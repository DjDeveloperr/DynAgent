/**
 * OpenAI Responses API-compatible server wrapping Kiro CLI's ACP provider.
 * Designed to be plugged into Codex CLI as a custom model provider.
 *
 * Usage:
 *   bun run src/codex-server.ts
 *   Then configure Codex: codex -c 'model_providers.kiro={base_url="http://localhost:4100/v1",env_key="KIRO_KEY",wire_api="responses"}' -c model_provider=kiro -m kiro/claude-opus-4.8
 */

import { streamText, generateText, type ToolSet } from "ai"
import { createKiroProvider } from "./provider/kiro"

const PORT = parseInt(process.env.KIRO_PORT || "4100")
const provider = createKiroProvider()

// --- Types for OpenAI Responses API ---

interface ResponsesRequest {
  model: string
  input: InputItem[]
  tools?: ToolDef[]
  stream?: boolean
  temperature?: number
  max_output_tokens?: number
  reasoning?: { effort?: string }
  instructions?: string
}

interface InputItem {
  type: string
  role?: string
  content?: string | ContentPart[]
  id?: string
  call_id?: string
  name?: string
  arguments?: string
  output?: string
  status?: string
}

interface ContentPart {
  type: string
  text?: string
}

interface ToolDef {
  type: string
  name?: string
  description?: string
  parameters?: Record<string, unknown>
  strict?: boolean
}

// --- Convert OpenAI Responses input to AI SDK messages ---

function inputToMessages(input: InputItem[]): Array<{ role: "user" | "assistant" | "tool"; content: string; toolCallId?: string; toolName?: string }> {
  const messages: Array<any> = []

  for (const item of input) {
    if (item.type === "message") {
      const text = typeof item.content === "string"
        ? item.content
        : (item.content as ContentPart[])?.map(p => p.text || "").join("") || ""

      if (item.role === "user" || item.role === "developer" || item.role === "system") {
        messages.push({ role: "user", content: text })
      } else if (item.role === "assistant") {
        messages.push({ role: "assistant", content: text })
      }
    } else if (item.type === "function_call") {
      // Assistant made a tool call
      messages.push({
        role: "assistant",
        content: [{ type: "tool-call", toolCallId: item.call_id || item.id || "", toolName: item.name || "", args: JSON.parse(item.arguments || "{}") }],
      })
    } else if (item.type === "function_call_output") {
      // Tool result
      messages.push({
        role: "tool",
        content: [{ type: "tool-result", toolCallId: item.call_id || "", result: item.output || "" }],
      })
    }
  }

  return messages
}

// --- Convert OpenAI tool defs to AI SDK tools ---

function convertTools(tools?: ToolDef[]): ToolSet | undefined {
  if (!tools?.length) return undefined
  const result: ToolSet = {}
  for (const t of tools) {
    if (t.type === "function" && t.name) {
      result[t.name] = {
        description: t.description || "",
        parameters: t.parameters as any,
      } as any
    }
  }
  return Object.keys(result).length ? result : undefined
}

// --- SSE helpers ---

function sseEvent(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`
}

// --- Request handler ---

async function handleResponses(req: Request): Promise<Response> {
  const body = await req.json() as ResponsesRequest
  const modelId = body.model.replace(/^kiro\//, "")

  const messages = inputToMessages(body.input)
  const tools = convertTools(body.tools)

  // Extract system/instructions
  const system = body.instructions || undefined

  const responseId = `resp_${crypto.randomUUID().replace(/-/g, "").slice(0, 24)}`

  if (!body.stream) {
    const result = await generateText({
      model: provider.languageModel(modelId),
      messages: messages as any,
      tools: tools as any,
      system,
    })

    const output: any[] = []
    if (result.text) {
      output.push({
        type: "message",
        id: `msg_${crypto.randomUUID().replace(/-/g, "").slice(0, 24)}`,
        role: "assistant",
        content: [{ type: "output_text", text: result.text }],
      })
    }
    for (const tc of result.toolCalls || []) {
      output.push({
        type: "function_call",
        id: `fc_${crypto.randomUUID().replace(/-/g, "").slice(0, 24)}`,
        call_id: tc.toolCallId,
        name: tc.toolName,
        arguments: JSON.stringify(tc.input),
      })
    }

    return Response.json({
      id: responseId,
      object: "response",
      status: "completed",
      output,
      usage: { input_tokens: 0, output_tokens: 0 },
    })
  }

  // --- Streaming ---
  const encoder = new TextEncoder()
  const stream = new ReadableStream({
    async start(controller) {
      const send = (event: string, data: unknown) => {
        controller.enqueue(encoder.encode(sseEvent(event, data)))
      }

      // response.created
      send("response.created", {
        type: "response.created",
        response: { id: responseId, object: "response", status: "in_progress", output: [] },
      })

      const outputItemId = `msg_${crypto.randomUUID().replace(/-/g, "").slice(0, 24)}`
      let outputIndex = 0
      let contentIndex = 0
      let currentText = ""
      const toolCalls: Array<{ id: string; callId: string; name: string; args: string }> = []
      let textStarted = false

      try {
        const result = streamText({
          model: provider.languageModel(modelId),
          messages: messages as any,
          tools: tools as any,
          system,
        })

        for await (const part of result.fullStream) {
          if (part.type === "text-delta") {
            if (!textStarted) {
              send("response.output_item.added", {
                type: "response.output_item.added",
                output_index: outputIndex,
                item: { type: "message", id: outputItemId, role: "assistant", content: [] },
              })
              send("response.content_part.added", {
                type: "response.content_part.added",
                output_index: outputIndex,
                content_index: contentIndex,
                part: { type: "output_text", text: "" },
              })
              textStarted = true
            }
            currentText += part.text
            send("response.output_text.delta", {
              type: "response.output_text.delta",
              output_index: outputIndex,
              content_index: contentIndex,
              delta: part.text,
            })
          } else if (part.type === "tool-call") {
            // If we had text, close it first
            if (textStarted) {
              send("response.output_text.done", {
                type: "response.output_text.done",
                output_index: outputIndex,
                content_index: contentIndex,
                text: currentText,
              })
              send("response.content_part.done", {
                type: "response.content_part.done",
                output_index: outputIndex,
                content_index: contentIndex,
                part: { type: "output_text", text: currentText },
              })
              send("response.output_item.done", {
                type: "response.output_item.done",
                output_index: outputIndex,
                item: { type: "message", id: outputItemId, role: "assistant", content: [{ type: "output_text", text: currentText }] },
              })
              outputIndex++
            }

            const fcId = `fc_${crypto.randomUUID().replace(/-/g, "").slice(0, 24)}`
            const argsStr = JSON.stringify(part.input)
            toolCalls.push({ id: fcId, callId: part.toolCallId, name: part.toolName, args: argsStr })

            // output_item.added for function_call
            send("response.output_item.added", {
              type: "response.output_item.added",
              output_index: outputIndex,
              item: { type: "function_call", id: fcId, call_id: part.toolCallId, name: part.toolName, arguments: "" },
            })
            send("response.function_call_arguments.delta", {
              type: "response.function_call_arguments.delta",
              output_index: outputIndex,
              delta: argsStr,
            })
            send("response.function_call_arguments.done", {
              type: "response.function_call_arguments.done",
              output_index: outputIndex,
              arguments: argsStr,
            })
            send("response.output_item.done", {
              type: "response.output_item.done",
              output_index: outputIndex,
              item: { type: "function_call", id: fcId, call_id: part.toolCallId, name: part.toolName, arguments: argsStr },
            })
            outputIndex++
          }
        }

        // If text was started but no tool call closed it
        if (textStarted && toolCalls.length === 0) {
          send("response.output_text.done", {
            type: "response.output_text.done",
            output_index: outputIndex,
            content_index: contentIndex,
            text: currentText,
          })
          send("response.content_part.done", {
            type: "response.content_part.done",
            output_index: outputIndex,
            content_index: contentIndex,
            part: { type: "output_text", text: currentText },
          })
          send("response.output_item.done", {
            type: "response.output_item.done",
            output_index: outputIndex,
            item: { type: "message", id: outputItemId, role: "assistant", content: [{ type: "output_text", text: currentText }] },
          })
        }

        // Build final output array
        const finalOutput: any[] = []
        if (currentText) {
          finalOutput.push({
            type: "message",
            id: outputItemId,
            role: "assistant",
            content: [{ type: "output_text", text: currentText }],
          })
        }
        for (const tc of toolCalls) {
          finalOutput.push({
            type: "function_call",
            id: tc.id,
            call_id: tc.callId,
            name: tc.name,
            arguments: tc.args,
          })
        }

        // response.completed
        send("response.completed", {
          type: "response.completed",
          response: {
            id: responseId,
            object: "response",
            status: "completed",
            output: finalOutput,
            usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 },
          },
        })
      } catch (err: any) {
        send("error", { type: "error", message: err.message || "Internal error" })
      } finally {
        controller.close()
      }
    },
  })

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  })
}

// --- HTTP Server ---

const server = Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url)

    // Health check
    if (url.pathname === "/health" || url.pathname === "/") {
      return Response.json({ status: "ok", provider: "kiro-acp" })
    }

    // Models endpoint (Codex may query this)
    if (url.pathname === "/v1/models") {
      const models = await provider.listModels()
      return Response.json({
        object: "list",
        data: models.map(m => ({ id: `kiro/${m.id}`, object: "model", owned_by: "kiro" })),
      })
    }

    // Responses API
    if (url.pathname === "/v1/responses" && req.method === "POST") {
      return handleResponses(req)
    }

    return new Response("Not Found", { status: 404 })
  },
})

console.log(`Kiro Codex bridge listening on http://localhost:${server.port}/v1`)
console.log(`Configure Codex:`)
console.log(`  codex -c 'model_providers.kiro={base_url="http://localhost:${server.port}/v1",env_key="KIRO_KEY",wire_api="responses"}' -c model_provider=kiro -m kiro/claude-opus-4.8`)

// Graceful shutdown
process.on("SIGINT", async () => {
  await provider.shutdown()
  process.exit(0)
})
process.on("SIGTERM", async () => {
  await provider.shutdown()
  process.exit(0)
})
