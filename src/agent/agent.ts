import { streamText, stepCountIs, hasToolCall, tool, type LanguageModel, type ModelMessage } from "ai"
import { z } from "zod"
import type { ToolRegistry } from "./tools"

export type AgentEvent =
  | { type: "text"; text: string }
  | { type: "tool"; name: string; input: unknown }
  | { type: "tool-result"; name: string }
  | { type: "done"; status?: "complete" | "impossible"; summary?: string }
  | { type: "error"; error: string }

export const SYSTEM =
  "You are a self-extending coding agent. You have bash, read_file, write_file, and create_tool. " +
  "When a capability is missing, author it with create_tool (a TypeScript AI SDK tool) and use it on your next turn.\n" +
  "You run autonomously and DO NOT end your turn until the goal is fully achieved AND verified (build/run/test or read the result back). " +
  "End the turn ONLY by calling the `finish` tool: status 'complete' once the goal is verified done, or status 'impossible' if it is physically impossible to proceed. " +
  "Never stop for any other reason — if you are unsure, keep working."

/** Control tool the agent must call to deterministically end its turn. */
const finishTool = tool({
  description:
    "End the turn. Call ONLY when the goal is fully achieved and verified (status 'complete'), " +
    "or when it is physically impossible to proceed (status 'impossible').",
  inputSchema: z.object({
    status: z.enum(["complete", "impossible"]),
    summary: z.string().describe("what was accomplished, or why it is impossible"),
  }),
  execute: async ({ status, summary }) => `turn ended (${status}): ${summary}`,
})

const MAX_ROUNDS = 100

/** Multi-step tool-calling agent that controls its own end-of-turn via `finish`. */
export class Agent {
  constructor(
    private readonly model: LanguageModel,
    private readonly registry: ToolRegistry,
  ) {}

  /**
   * Run a turn to completion. Loops until the agent calls `finish` (complete /
   * impossible), the caller aborts, or a hard safety cap is hit. `affinity`
   * keeps the Kiro ACP session alive across steps.
   */
  async run(messages: ModelMessage[], onEvent: (e: AgentEvent) => void, affinity?: string, signal?: AbortSignal): Promise<void> {
    const convo: ModelMessage[] = [...messages]
    let done: { status: "complete" | "impossible"; summary: string } | undefined
    try {
      for (let round = 0; round < MAX_ROUNDS && !done && !signal?.aborted; round++) {
        const result = streamText({
          model: this.model,
          system: SYSTEM,
          messages: convo,
          tools: { ...this.registry.tools(), finish: finishTool },
          stopWhen: [hasToolCall("finish"), stepCountIs(100)],
          abortSignal: signal,
          headers: affinity ? { "x-session-affinity": affinity } : undefined,
        })
        for await (const part of result.fullStream) {
          if (part.type === "text-delta") onEvent({ type: "text", text: part.text })
          else if (part.type === "tool-call") {
            if (part.toolName === "finish") done = part.input as typeof done
            else onEvent({ type: "tool", name: part.toolName, input: part.input })
          } else if (part.type === "tool-result") {
            if (part.toolName !== "finish") onEvent({ type: "tool-result", name: part.toolName })
          } else if (part.type === "error") onEvent({ type: "error", error: String(part.error) })
        }
        convo.push(...(await result.response).messages)
        if (done || signal?.aborted) break
        // Stopped without finishing: re-prompt to continue until the goal is verified.
        convo.push({
          role: "user",
          content:
            "You stopped without calling `finish`. If the goal is verified complete, call finish(status:'complete'). " +
            "If it is truly physically impossible, call finish(status:'impossible'). Otherwise keep working.",
        })
      }
      onEvent({ type: "done", status: done?.status, summary: done?.summary })
    } catch (e: any) {
      onEvent({ type: "error", error: e?.message ?? String(e) })
    }
  }
}
