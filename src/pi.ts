/**
 * Bridge to the `pi` CLI coding agent (https://pi.dev). Spawns `pi -p --mode json`
 * per turn, keyed by a stable session id for multi-turn continuity, and maps Pi's
 * NDJSON event stream to the app's ChatEvent format. No API key needed for the
 * preconfigured `kiro` / `openai-codex` providers.
 */

import { spawn } from "node:child_process"
import { promisify } from "node:util"
import { execFile } from "node:child_process"

const pexec = promisify(execFile)

export type PiEvent =
  | { type: "text"; text: string }
  | { type: "tool"; name: string; detail?: string }
  | { type: "tool-result"; name: string; detail?: string }
  | { type: "done" }
  | { type: "error"; error: string }

/** List available Pi models as `provider::model` ids. */
export async function piModels(): Promise<Array<{ id: string; name: string }>> {
  const { stdout, stderr } = await pexec("pi", ["--mode", "json", "--list-models"], { maxBuffer: 1 << 20 })
  const out: Array<{ id: string; name: string }> = []
  for (const line of (stdout + stderr).split("\n").slice(1)) {
    const m = line.trim().match(/^(\S+)\s+(\S+)/)
    if (m && m[1] !== "provider") out.push({ id: `${m[1]}::${m[2]}`, name: m[2] })
  }
  return out
}

/** Run one Pi turn, streaming events. `model` is a `provider::model` id. */
export function piChat(opts: {
  model: string
  text: string
  cwd: string
  sessionId: string
  onEvent: (e: PiEvent) => void
  signal?: AbortSignal
}): Promise<void> {
  const [provider, model] = opts.model.includes("::") ? opts.model.split("::") : ["kiro", opts.model]
  const args = ["-p", "--mode", "json", "--session-id", opts.sessionId, "--provider", provider, "--model", model, opts.text]
  return new Promise((resolve) => {
    const child = spawn("pi", args, { cwd: opts.cwd, stdio: ["ignore", "pipe", "pipe"] })
    opts.signal?.addEventListener("abort", () => child.kill())
    let buf = ""
    const handle = (line: string) => {
      let m: any
      try { m = JSON.parse(line) } catch { return }
      if (m.type === "message_update") {
        const ev = m.assistantMessageEvent
        if (ev?.type === "text_delta" && ev.delta) opts.onEvent({ type: "text", text: ev.delta })
        else if (ev?.type === "tool_start") opts.onEvent({ type: "tool", name: ev.toolName || ev.name || "tool", detail: ev.input ? JSON.stringify(ev.input).slice(0, 400) : undefined })
        else if (ev?.type === "tool_end") opts.onEvent({ type: "tool-result", name: ev.toolName || ev.name || "tool", detail: typeof ev.result === "string" ? ev.result.slice(0, 4000) : undefined })
      } else if (m.type === "agent_end" && m.willRetry !== true) {
        const err = m.messages?.find?.((x: any) => x.errorMessage)?.errorMessage
        if (err) opts.onEvent({ type: "error", error: err })
        opts.onEvent({ type: "done" })
      }
    }
    child.stdout.on("data", (d) => {
      buf += d.toString()
      const lines = buf.split("\n")
      buf = lines.pop() || ""
      for (const l of lines) if (l.trim()) handle(l)
    })
    child.stderr.on("data", () => {})
    child.on("close", () => { if (buf.trim()) handle(buf); resolve() })
    child.on("error", (e) => { opts.onEvent({ type: "error", error: e.message }); resolve() })
  })
}
