import { createKiroAcp, verifyAuth, listModels, getQuota } from "kiro-acp-ai-provider"
import type { LanguageModelV3 } from "@ai-sdk/provider"
import type { InferenceProvider, ModelInfo } from "./types"

export interface QuotaInfo {
  sessionCredits: number
  contextUsagePercentage?: number
  metering?: Array<{ unit: string; unitPlural: string; value: number }>
}

export interface KiroProvider extends InferenceProvider {
  /** Per-session Kiro credit usage (from kiro-cli `_kiro.dev/metadata`). */
  quota(): Promise<QuotaInfo>
}

export interface KiroOptions {
  /** Working directory the kiro-cli ACP session runs in. Default: process.cwd(). */
  cwd?: string
  /** Agent config name written under `.kiro/agents`. Default: "dynamic_agent". */
  agent?: string
}

/**
 * Kiro inference provider, backed by the locally-authenticated `kiro-cli`.
 *
 * Mirrors opencode: spawns `kiro-cli acp` (Agent Client Protocol over stdio)
 * and exposes it as an AI SDK provider. Auth is delegated to kiro-cli — no
 * tokens or endpoints are handled here.
 */
export function createKiroProvider(opts: KiroOptions = {}): KiroProvider {
  const status = verifyAuth()
  if (!status.installed) throw new Error("kiro-cli is not installed. See https://kiro.dev/docs/cli/")
  if (!status.authenticated) throw new Error("kiro-cli is not authenticated. Run `kiro-cli login`.")

  const cwd = opts.cwd ?? process.cwd()
  const sdk = createKiroAcp({ cwd, agent: opts.agent ?? "dynamic_agent", trustAllTools: true })

  return {
    id: "kiro",
    languageModel: (modelId): LanguageModelV3 => sdk.languageModel(modelId),
    listModels: async (): Promise<ModelInfo[]> =>
      (await listModels({ cwd })).map((m) => ({ id: m.modelId, name: m.name })),
    quota: () => getQuota({ client: sdk.getClient() }),
    shutdown: () => sdk.shutdown(),
  }
}
