import type { LanguageModelV3 } from "@ai-sdk/provider"

export interface ModelInfo {
  id: string
  name: string
}

/**
 * Provider-agnostic inference interface.
 *
 * Each provider yields AI SDK `LanguageModelV3` instances so the harness can
 * drive them with the standard `ai` SDK (streamText/generateText) and its own
 * dynamically-built tools, independent of which backend serves the request.
 */
export interface InferenceProvider {
  readonly id: string
  /** Resolve a model id into an AI SDK language model. */
  languageModel(modelId: string): LanguageModelV3
  /** Models offered by this provider. */
  listModels(): Promise<ModelInfo[]>
  /** Release underlying resources (child processes, sockets, etc.). */
  shutdown(): Promise<void>
}
