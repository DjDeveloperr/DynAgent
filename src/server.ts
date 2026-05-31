import { join } from "node:path"
import { execFile } from "node:child_process"
import { promisify } from "node:util"
import type { ModelMessage } from "ai"
import { createKiroProvider } from "./provider/kiro"
import { ToolRegistry } from "./agent/tools"
import { builtins } from "./agent/builtins"
import { Agent } from "./agent/agent"

const cwd = process.env.AGENT_CWD ?? process.cwd()
const toolsDir = join(cwd, ".agent", "tools")
const port = Number(process.env.PORT ?? 4319)
const pexec = promisify(execFile)
const git = (dir: string, ...args: string[]) =>
  pexec("git", ["-C", dir, ...args], { maxBuffer: 1 << 24 }).then((r) => r.stdout.trim())

// Never let a stray streaming/IO error take down the server.
process.on("uncaughtException", (e) => console.error("uncaught:", e?.message ?? e))
process.on("unhandledRejection", (e) => console.error("unhandled:", e))

// Active working directory for tool execution; set per /chat request.
let activeCwd = cwd
let provider = createKiroProvider({ cwd })
const registry = new ToolRegistry(toolsDir, builtins(toolsDir, () => activeCwd))
await registry.init()

const toolSig = () => Object.keys(registry.tools()).sort().join(",")
let lastSig = toolSig()

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
}
const json = (data: unknown, status = 200) =>
  Response.json(data, { status, headers: CORS })

Bun.serve({
  port,
  idleTimeout: 255,
  async fetch(req) {
    const url = new URL(req.url)
    if (req.method === "OPTIONS") return new Response(null, { headers: CORS })

    if (url.pathname === "/models") return json(await provider.listModels())

    if (url.pathname === "/cwd") return json({ cwd, name: cwd.split("/").pop() || cwd })

    // Git status + diff for a workspace.
    if (url.pathname === "/git") {
      const dir = url.searchParams.get("cwd") || cwd
      try {
        const [branch, statusRaw, diff] = await Promise.all([
          git(dir, "rev-parse", "--abbrev-ref", "HEAD").catch(() => "—"),
          pexec("git", ["-C", dir, "status", "--porcelain"], { maxBuffer: 1 << 24 }).then((r) => r.stdout),
          git(dir, "diff"),
        ])
        const files = statusRaw.split("\n").filter(Boolean).map((l) => ({ x: l.slice(0, 2), path: l.slice(3) }))
        return json({ branch, files, diff })
      } catch (e: any) {
        return json({ error: e?.message ?? "not a git repo" }, 400)
      }
    }

    if (url.pathname === "/git/commit" && req.method === "POST") {
      const { cwd: dir, message } = (await req.json()) as { cwd: string; message: string }
      try {
        await git(dir, "add", "-A")
        const out = await git(dir, "commit", "-m", message)
        return json({ ok: true, out })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    // Create a git worktree (new branch) under <repo>/.worktrees/<branch>.
    if (url.pathname === "/worktree" && req.method === "POST") {
      const { cwd: dir, branch } = (await req.json()) as { cwd: string; branch: string }
      try {
        const root = await git(dir, "rev-parse", "--show-toplevel")
        const path = join(root, ".worktrees", branch)
        await git(root, "worktree", "add", "-b", branch, path)
        return json({ path, name: branch })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    if (url.pathname === "/quota") {
      try {
        return json(await provider.quota())
      } catch (e: any) {
        return json({ error: e?.message ?? "unavailable" }, 503)
      }
    }

    if (url.pathname === "/chat" && req.method === "POST") {
      const { model, messages, conversationId, cwd: reqCwd } = (await req.json()) as {
        model: string
        messages: ModelMessage[]
        conversationId?: string
        cwd?: string
      }
      if (!model || !messages?.length) return json({ error: "model and messages required" }, 400)
      activeCwd = reqCwd || cwd
      await registry.reload() // pick up tools authored on previous turns
      // kiro-cli enumerates its tool set per process; restart it when tools change
      // so newly authored tools become visible to the model.
      const sig = toolSig()
      if (sig !== lastSig) {
        await provider.shutdown().catch(() => {})
        provider = createKiroProvider({ cwd })
        lastSig = sig
      }
      const agent = new Agent(provider.languageModel(model), registry)
      const affinity = conversationId ?? crypto.randomUUID()
      const enc = new TextEncoder()
      const ac = new AbortController()
      let closed = false
      const stream = new ReadableStream({
        start(controller) {
          const send = (e: unknown) => {
            if (closed) return
            try {
              controller.enqueue(enc.encode(`data: ${JSON.stringify(e)}\n\n`))
            } catch {}
          }
          agent
            .run(messages, send, affinity, ac.signal)
            .catch((e) => send({ type: "error", error: String(e) }))
            .finally(() => {
              if (closed) return
              closed = true
              try {
                controller.close()
              } catch {}
            })
        },
        cancel() {
          closed = true
          ac.abort()
        },
      })
      return new Response(stream, {
        headers: { ...CORS, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
      })
    }

    return new Response("not found", { status: 404, headers: CORS })
  },
})

console.log(`agent server: http://127.0.0.1:${port}  (cwd=${cwd}, tools=${toolsDir})`)
