import { join } from "node:path"
import { execFile } from "node:child_process"
import { promisify } from "node:util"
import type { ModelMessage } from "ai"
import { generateText } from "ai"
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

// Terminal/browser control state
const terminalWriteQueue: { text: string; id?: string }[] = []
const terminalBuffers = new Map<string, string>()
const browserActions: { type: string; url?: string; script?: string; id?: string; resultId?: string }[] = []
const browserStates = new Map<string, { url: string; title: string }>()
const browserResultCallbacks = new Map<string, (result: string) => void>()

function waitForBrowserResult(resultId: string, timeout = 10000): Promise<string> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      browserResultCallbacks.delete(resultId)
      resolve("timeout: no response from browser")
    }, timeout)
    browserResultCallbacks.set(resultId, (result) => {
      clearTimeout(timer)
      resolve(result)
    })
  })
}

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

    // Codex harness: models from codex-server (port 4100)
    if (url.pathname === "/codex/models") {
      try {
        const res = await fetch("http://127.0.0.1:4100/v1/models")
        const data = await res.json() as { data?: Array<{ id: string }> }
        return json((data.data || []).map((m: { id: string }) => ({ id: m.id, name: m.id })))
      } catch {
        return json({ error: "codex-server not running (start with: bun src/codex-server.ts)" }, 503)
      }
    }

    // Codex harness: stream chat completions through codex-server
    if (url.pathname === "/codex/chat" && req.method === "POST") {
      const { model, messages } = (await req.json()) as { model: string; messages: Array<{ role: string; content: string }> }
      try {
        const res = await fetch("http://127.0.0.1:4100/v1/chat/completions", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": "Bearer dummy" },
          body: JSON.stringify({ model, messages, stream: true }),
        })
        if (!res.ok || !res.body) return json({ error: `codex-server: ${res.status}` }, 502)
        // Transform OpenAI SSE stream to our event format
        const enc = new TextEncoder()
        let closed = false
        const stream = new ReadableStream({
          async start(controller) {
            const send = (e: unknown) => {
              if (closed) return
              try { controller.enqueue(enc.encode(`data: ${JSON.stringify(e)}\n\n`)) } catch {}
            }
            try {
              const reader = res.body!.getReader()
              const decoder = new TextDecoder()
              let buf = ""
              while (true) {
                const { done, value } = await reader.read()
                if (done) break
                buf += decoder.decode(value, { stream: true })
                const lines = buf.split("\n")
                buf = lines.pop() || ""
                for (const line of lines) {
                  if (!line.startsWith("data: ")) continue
                  const payload = line.slice(6).trim()
                  if (payload === "[DONE]") { send({ type: "done" }); break }
                  try {
                    const chunk = JSON.parse(payload)
                    const delta = chunk.choices?.[0]?.delta
                    if (delta?.content) send({ type: "text", text: delta.content })
                    if (delta?.tool_calls) {
                      for (const tc of delta.tool_calls) {
                        if (tc.function?.name) send({ type: "tool", name: tc.function.name })
                      }
                    }
                    if (chunk.choices?.[0]?.finish_reason) send({ type: "done" })
                  } catch {}
                }
              }
            } catch (e: any) {
              send({ type: "error", error: e.message })
            } finally {
              if (!closed) { closed = true; try { controller.close() } catch {} }
            }
          },
          cancel() { closed = true }
        })
        return new Response(stream, {
          headers: { ...CORS, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
        })
      } catch (e: any) {
        return json({ error: "codex-server not running" }, 503)
      }
    }

    if (url.pathname === "/cwd") return json({ cwd, name: cwd.split("/").pop() || cwd })

    // Real Kiro account credits (calls AWS CodeWhisperer GetUsageLimits)
    if (url.pathname === "/credits") {
      try {
        const tokenPath = join(process.env.HOME || "~", ".aws/sso/cache/kiro-auth-token-cli.json")
        const tokenData = JSON.parse(await Bun.file(tokenPath).text())
        const res = await fetch("https://codewhisperer.us-east-1.amazonaws.com", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${tokenData.accessToken}`,
            "Content-Type": "application/x-amz-json-1.0",
            "X-Amz-Target": "AmazonCodeWhispererService.GetUsageLimits",
          },
          body: "{}",
        })
        const data = await res.json() as any
        const usage = data.usageBreakdownList?.[0]
        if (usage) {
          return json({
            used: usage.currentUsageWithPrecision ?? usage.currentUsage ?? 0,
            limit: usage.usageLimit ?? 10000,
            plan: data.subscriptionInfo?.subscriptionTitle ?? "Kiro",
            daysUntilReset: data.daysUntilReset ?? 0,
          })
        }
        return json({ used: 0, limit: 10000, plan: "Kiro", daysUntilReset: 0 })
      } catch (e: any) {
        return json({ error: e.message }, 500)
      }
    }

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
        const msg = e?.stderr || e?.message || ""
        return json({ error: /not a git repository/i.test(msg) ? "Not a git repository" : msg.trim() })
      }
    }

    if (url.pathname === "/git/commit" && req.method === "POST") {
      const { cwd: dir, message } = (await req.json()) as { cwd: string; message?: string }
      try {
        await git(dir, "add", "-A")
        let msg = message?.trim() || ""
        if (!msg) {
          // Auto-generate commit message from diff
          const diff = await git(dir, "diff", "--cached", "--stat").catch(() => "")
          const diffFull = await git(dir, "diff", "--cached").catch(() => "")
          const summary = diffFull.slice(0, 4000)
          const agent = new Agent(provider.languageModel("auto"), registry)
          const enc2 = new TextEncoder()
          let generated = ""
          await agent.run(
            [{ role: "user", content: [{ type: "text", text: `Generate a concise git commit message (one line, no quotes, no prefix like "feat:" unless obvious) for these changes:\n\n${diff}\n\n${summary}` }] }],
            (e: any) => { if (e?.type === "text") generated += e.text },
            crypto.randomUUID(),
            new AbortController().signal
          )
          msg = generated.trim().replace(/^["']|["']$/g, "") || "update"
        }
        const out = await git(dir, "commit", "-m", msg)
        return json({ ok: true, out, message: msg })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    if (url.pathname === "/git/push" && req.method === "POST") {
      const { cwd: dir } = (await req.json()) as { cwd: string }
      try {
        const branch = await git(dir, "rev-parse", "--abbrev-ref", "HEAD")
        const out = await git(dir, "push", "-u", "origin", branch)
        return json({ ok: true, out })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    if (url.pathname === "/git/commit-push" && req.method === "POST") {
      const { cwd: dir, message } = (await req.json()) as { cwd: string; message?: string }
      try {
        await git(dir, "add", "-A")
        let msg = message?.trim() || ""
        if (!msg) {
          const diff = await git(dir, "diff", "--cached", "--stat").catch(() => "")
          const diffFull = await git(dir, "diff", "--cached").catch(() => "")
          const summary = diffFull.slice(0, 4000)
          const agent = new Agent(provider.languageModel("auto"), registry)
          let generated = ""
          await agent.run(
            [{ role: "user", content: [{ type: "text", text: `Generate a concise git commit message (one line, no quotes, no prefix like "feat:" unless obvious) for these changes:\n\n${diff}\n\n${summary}` }] }],
            (e: any) => { if (e?.type === "text") generated += e.text },
            crypto.randomUUID(),
            new AbortController().signal
          )
          msg = generated.trim().replace(/^["']|["']$/g, "") || "update"
        }
        await git(dir, "commit", "-m", msg)
        const branch = await git(dir, "rev-parse", "--abbrev-ref", "HEAD")
        const out = await git(dir, "push", "-u", "origin", branch)
        return json({ ok: true, out, message: msg })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    if (url.pathname === "/git/create-branch" && req.method === "POST") {
      const { cwd: dir, branch } = (await req.json()) as { cwd: string; branch: string }
      try {
        await git(dir, "checkout", "-b", branch)
        return json({ ok: true, branch })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    if (url.pathname === "/git/create-pr" && req.method === "POST") {
      const { cwd: dir, title, body } = (await req.json()) as { cwd: string; title?: string; body?: string }
      try {
        const args = ["pr", "create", "--fill"]
        if (title) { args.push("--title", title) }
        if (body) { args.push("--body", body) }
        const out = await pexec("gh", args, { cwd: dir, maxBuffer: 1 << 24 }).then(r => r.stdout.trim())
        return json({ ok: true, url: out })
      } catch (e: any) {
        return json({ error: e?.stderr || e?.message }, 400)
      }
    }

    if (url.pathname === "/git/pr-info") {
      const dir = url.searchParams.get("cwd") || cwd
      try {
        const out = await pexec("gh", ["pr", "view", "--json", "number,title,state,url,headRefName,additions,deletions,reviewDecision"], { cwd: dir, maxBuffer: 1 << 24 }).then(r => r.stdout.trim())
        return json(JSON.parse(out))
      } catch (e: any) {
        const msg = e?.stderr || e?.message || ""
        if (/no pull requests found|no open pull request/i.test(msg)) return json({ none: true })
        return json({ error: msg.trim() }, 400)
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

    // Generate a short title for a conversation from the first prompt.
    if (url.pathname === "/generate-title" && req.method === "POST") {
      const { prompt, model } = (await req.json()) as { prompt: string; model?: string }
      try {
        const result = await generateText({
          model: provider.languageModel(model || "auto"),
          messages: [{ role: "user", content: `Generate a very short title (3-5 words, no quotes, no punctuation) for a conversation starting with: ${prompt.slice(0, 300)}` }],
        })
        const title = result.text.trim().replace(/^["']|["']$/g, "").slice(0, 50)
        return json({ title: title || "New Chat" })
      } catch {
        return json({ title: "New Chat" })
      }
    }

    // Terminal control: write to the terminal
    if (url.pathname === "/terminal/write" && req.method === "POST") {
      const { text, id } = (await req.json()) as { text: string; id?: string }
      // Forward to the app's terminal panel via a pending callback
      terminalWriteQueue.push({ text, id })
      return json({ ok: true })
    }

    // Terminal control: read recent output
    if (url.pathname === "/terminal/read") {
      const id = url.searchParams.get("id") || undefined
      const last = Number(url.searchParams.get("last") || 4000)
      // Return from the terminal output buffer
      const buf = terminalBuffers.get(id || "_default") || ""
      const out = buf.length <= last ? buf : buf.slice(-last)
      return json({ output: out, id: id || "_default" })
    }

    // Terminal control: list active terminals
    if (url.pathname === "/terminal/list") {
      return json({ terminals: Array.from(terminalBuffers.keys()) })
    }

    // Browser control: navigate
    if (url.pathname === "/browser/navigate" && req.method === "POST") {
      const { url: targetUrl, id } = (await req.json()) as { url: string; id?: string }
      browserActions.push({ type: "navigate", url: targetUrl, id })
      return json({ ok: true })
    }

    // Browser control: evaluate JavaScript
    if (url.pathname === "/browser/eval" && req.method === "POST") {
      const { script, id } = (await req.json()) as { script: string; id?: string }
      const resultId = crypto.randomUUID()
      browserActions.push({ type: "eval", script, id, resultId })
      // Wait for result (the app posts it back)
      const result = await waitForBrowserResult(resultId)
      return json({ result })
    }

    // Browser control: get current state
    if (url.pathname === "/browser/state") {
      const id = url.searchParams.get("id") || undefined
      const state = browserStates.get(id || "_default") || { url: "", title: "" }
      return json(state)
    }

    // App reports terminal output (called by the macOS app)
    if (url.pathname === "/terminal/report" && req.method === "POST") {
      const { id, output } = (await req.json()) as { id: string; output: string }
      const key = id || "_default"
      const existing = terminalBuffers.get(key) || ""
      const combined = existing + output
      terminalBuffers.set(key, combined.length > 64000 ? combined.slice(-64000) : combined)
      return json({ ok: true })
    }

    // App reports browser result (called by the macOS app)
    if (url.pathname === "/browser/result" && req.method === "POST") {
      const { resultId, result } = (await req.json()) as { resultId: string; result: string }
      browserResultCallbacks.get(resultId)?.(result)
      browserResultCallbacks.delete(resultId)
      return json({ ok: true })
    }

    // App reports browser state (called by the macOS app)
    if (url.pathname === "/browser/report" && req.method === "POST") {
      const { id, url: pageUrl, title } = (await req.json()) as { id: string; url: string; title: string }
      browserStates.set(id || "_default", { url: pageUrl, title })
      return json({ ok: true })
    }

    // App polls for pending terminal writes
    if (url.pathname === "/terminal/pending") {
      const items = [...terminalWriteQueue]
      terminalWriteQueue.length = 0
      return json({ actions: items })
    }

    // App polls for pending browser actions
    if (url.pathname === "/browser/pending") {
      const items = [...browserActions]
      browserActions.length = 0
      return json({ actions: items })
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
