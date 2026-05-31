import { streamText, stepCountIs, type LanguageModel, type ModelMessage } from "ai"
import type { ToolRegistry } from "./tools"

export type AgentEvent =
  | { type: "text"; text: string }
  | { type: "tool"; name: string; input: unknown }
  | { type: "tool-result"; name: string }
  | { type: "done" }
  | { type: "error"; error: string }

export const SYSTEM =
  "You are a self-extending coding agent. You have bash, read_file, write_file, and create_tool. " +
  "When a capability is missing, author it with create_tool (a TypeScript AI SDK tool) and use it on your next turn. " +
  "Work autonomously and concisely."

/** Multi-step tool-calling agent over a single inference model. */
export class Agent {
  constructor(
    private readonly model: LanguageModel,
    private readonly registry: ToolRegistry,
  ) {}

  /**
   * Run one turn over the full conversation history. `affinity` keeps the Kiro
   * ACP session alive across the internal tool-calling steps.
   */
  async run(messages: ModelMessage[], onEvent: (e: AgentEvent) => void, affinity?: string, signal?: AbortSignal): Promise<void> {
    const result = streamText({
      model: this.model,
      system: SYSTEM,
      messages,
      tools: this.registry.tools(),
      stopWhen: stepCountIs(50),
      abortSignal: signal,
      headers: affinity ? { "x-session-affinity": affinity } : undefined,
    })
    try {
      for await (const part of result.fullStream) {
        if (part.type === "text-delta") onEvent({ type: "text", text: part.text })
        else if (part.type === "tool-call") onEvent({ type: "tool", name: part.toolName, input: part.input })
        else if (part.type === "tool-result") onEvent({ type: "tool-result", name: part.toolName })
        else if (part.type === "error") onEvent({ type: "error", error: String(part.error) })
      }
      onEvent({ type: "done" })
    } catch (e: any) {
      onEvent({ type: "error", error: e?.message ?? String(e) })
    }
  }
}
