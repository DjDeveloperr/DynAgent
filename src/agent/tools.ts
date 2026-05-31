import type { Tool, ToolSet } from "ai"
import { watch } from "node:fs"
import { readdir, mkdir } from "node:fs/promises"
import { join, extname, basename } from "node:path"
import { pathToFileURL } from "node:url"

/**
 * Registry of agent tools = fixed builtins + hot-reloaded user tools.
 *
 * User tools are `.ts` modules in `dir`, each default-exporting an AI SDK
 * `tool({...})`. The directory is watched; changes reload immediately so the
 * agent can author its own tools at runtime (picked up on the next run).
 */
export class ToolRegistry {
  private dynamic: Record<string, Tool> = {}

  constructor(
    private readonly dir: string,
    private readonly builtins: ToolSet = {},
  ) {}

  async init(): Promise<void> {
    await mkdir(this.dir, { recursive: true })
    await this.reload()
    watch(this.dir, () => void this.reload().catch(() => {}))
  }

  tools(): ToolSet {
    return { ...this.builtins, ...this.dynamic }
  }

  async reload(): Promise<void> {
    const out: Record<string, Tool> = {}
    for (const f of await readdir(this.dir)) {
      if (extname(f) !== ".ts") continue
      try {
        // Cache-bust so edits re-evaluate on every reload.
        const mod = await import(pathToFileURL(join(this.dir, f)).href + "?t=" + Date.now())
        if (mod.default) out[basename(f, ".ts")] = mod.default as Tool
      } catch {
        // Skip modules that fail to import; a later edit can fix them.
      }
    }
    this.dynamic = out
  }
}
