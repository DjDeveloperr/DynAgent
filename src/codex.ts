/**
 * Bridge to the real `codex app-server` running over WebSocket (managed by pm2:
 *   codex app-server --listen ws://127.0.0.1:4555
 * Speaks the app-server JSON-RPC protocol. No OpenAI API is used directly.
 */

import { basename } from "node:path"
import { stat } from "node:fs/promises"

const CODEX_WS = process.env.CODEX_WS ?? "ws://127.0.0.1:4555"
const CODEX_HOME = (process.env.HOME ?? "~") + "/.codex"
const INDEX_PATH = CODEX_HOME + "/session_index.jsonl"
const GLOBAL_STATE_PATH = CODEX_HOME + "/.codex-global-state.json"
const CONFIG_PATH = CODEX_HOME + "/config.toml"

export type CodexWorkspace = { name: string; path: string; source: "desktop" | "config" }
export type CodexSidebarState = {
  collapsedGroups: Record<string, boolean>
  collapsedSections: Record<string, boolean>
  sidebarWidth?: number
}

/** Map of thread id -> human title stored in Codex's session index. */
async function indexTitles(): Promise<Map<string, string>> {
  const m = new Map<string, string>()
  try {
    const text = await Bun.file(INDEX_PATH).text()
    for (const line of text.split("\n")) {
      if (!line.trim()) continue
      try { const o = JSON.parse(line); if (o.id && o.thread_name) m.set(o.id, o.thread_name) } catch {}
    }
  } catch {}
  return m
}

function uniquePaths(paths: string[]): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const path of paths) {
    if (!path || !path.startsWith("/") || path.includes("/.codex/worktrees/")) continue
    if (seen.has(path)) continue
    seen.add(path)
    out.push(path)
  }
  return out
}

function decodeTomlString(raw: string): string {
  try { return JSON.parse(`"${raw}"`) } catch {
    return raw.replace(/\\"/g, "\"").replace(/\\\\/g, "\\")
  }
}

async function existingDirectories(paths: string[]): Promise<string[]> {
  const checks = await Promise.all(paths.map(async (path) => {
    try {
      return (await stat(path)).isDirectory() ? path : undefined
    } catch {
      return undefined
    }
  }))
  return checks.filter((path): path is string => Boolean(path))
}

async function readGlobalState(): Promise<any> {
  try { return JSON.parse(await Bun.file(GLOBAL_STATE_PATH).text()) } catch { return {} }
}

async function writeGlobalState(state: any): Promise<void> {
  await Bun.write(GLOBAL_STATE_PATH, JSON.stringify(state, null, 2))
}

function atomState(globalState: any): any {
  if (!globalState["electron-persisted-atom-state"] || typeof globalState["electron-persisted-atom-state"] !== "object") {
    globalState["electron-persisted-atom-state"] = {}
  }
  return globalState["electron-persisted-atom-state"]
}

export type ChatEvent =
  | { type: "thread"; id: string }
  | { type: "text"; text: string }
  | { type: "reasoning"; text: string }
  | { type: "steer" }
  | { type: "tool"; name: string; detail?: string }
  | { type: "tool-result"; name: string; detail?: string }
  | { type: "done"; status?: string }
  | { type: "error"; error: string }

function diffStats(diff?: string): { added: number; deleted: number } {
  let added = 0
  let deleted = 0
  for (const line of (diff || "").split("\n")) {
    if (line.startsWith("+++") || line.startsWith("---")) continue
    if (line.startsWith("+")) added++
    else if (line.startsWith("-")) deleted++
  }
  return { added, deleted }
}

function fileChangeDetail(it: any, status?: string): string {
  return JSON.stringify({
    status: status || it.status || "completed",
    changes: (it.changes || []).map((c: any) => ({
      path: c.path,
      kind: c.kind?.type || c.kind || "update",
      diff: typeof c.diff === "string" ? c.diff.slice(0, 8_000) : "",
      ...diffStats(c.diff),
    })),
  })
}

function codexErrorMessage(value: any): string {
  if (!value) return "codex error"
  if (typeof value === "string") return value
  const message = value.message
    ?? value.error?.message
    ?? value.error
    ?? value.data?.message
    ?? value.data?.error?.message
  if (typeof message === "string" && message.trim()) return message
  try { return JSON.stringify(value) } catch { return "codex error" }
}

type Pending = { resolve: (v: any) => void; reject: (e: any) => void }

export class CodexClient {
  private ws?: WebSocket
  private ready?: Promise<void>
  private nextId = 1
  private pending = new Map<number, Pending>()
  // notification subscribers keyed by threadId
  private subs = new Map<string, (msg: any) => void>()
  // currently running turn id per thread (for turn/steer)
  private activeTurns = new Map<string, string>()

  private connect(): Promise<void> {
    if (this.ready) return this.ready
    this.ready = new Promise((resolve, reject) => {
      const ws = new WebSocket(CODEX_WS)
      this.ws = ws
      ws.onopen = async () => {
        try {
          await this.call("initialize", {
            clientInfo: { name: "dynagent", title: "DynAgent", version: "0.1" },
            capabilities: null,
          })
          resolve()
        } catch (e) { reject(e) }
      }
      ws.onmessage = (e) => this.onMessage(JSON.parse(e.data as string))
      ws.onclose = () => { this.ready = undefined; this.ws = undefined }
      ws.onerror = () => { reject(new Error("codex app-server unreachable")); this.ready = undefined }
    })
    return this.ready
  }

  private onMessage(m: any) {
    // Response to a client request
    if (typeof m.id !== "undefined" && !m.method) {
      const p = this.pending.get(m.id)
      if (p) { this.pending.delete(m.id); m.error ? p.reject(new Error(codexErrorMessage(m.error))) : p.resolve(m.result) }
      return
    }
    // Server->client request (approvals): auto-approve to keep streaming
    if (typeof m.id !== "undefined" && m.method) {
      this.respondApproval(m)
      return
    }
    // Notification
    if (m.method) {
      const tid = m.params?.threadId ?? m.params?.thread?.id
      if (tid && this.subs.has(tid)) this.subs.get(tid)!(m)
    }
  }

  private respondApproval(m: any) {
    let result: any = { decision: "approved" }
    if (m.method === "item/commandExecution/requestApproval") result = { decision: "accept" }
    else if (m.method === "item/fileChange/requestApproval") result = { decision: "accept" }
    else if (m.method === "item/permissions/requestApproval") result = { decision: "accept" }
    this.ws?.send(JSON.stringify({ jsonrpc: "2.0", id: m.id, result }))
  }

  private async call(method: string, params: any): Promise<any> {
    const ws = this.ws!
    const id = this.nextId++
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject })
      ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }))
    })
  }

  private async rpc(method: string, params: any): Promise<any> {
    await this.connect()
    return this.call(method, params)
  }

  async listModels(): Promise<Array<{ id: string; name: string }>> {
    const r = await this.rpc("model/list", { limit: 100 })
    return (r.data || []).map((m: any) => ({ id: m.id, name: m.displayName || m.id }))
  }

  private async supportedModelOrDefault(model: string): Promise<string> {
    const models = await this.listModels()
    if (models.some((m) => m.id === model)) return model
    return models[0]?.id ?? model
  }

  async listThreads(cwd?: string): Promise<Array<{ id: string; title: string; preview: string; updatedAt: number; pinned: boolean; projectless: boolean; workspace?: string }>> {
    const r = await this.rpc("thread/list", { limit: 100, ...(cwd ? { cwd } : {}) })
    const titles = await indexTitles()
    const state = await readGlobalState()
    const pinned = new Set((Array.isArray(state["pinned-thread-ids"]) ? state["pinned-thread-ids"] : []).filter((id: unknown) => typeof id === "string"))
    const projectless = new Set((Array.isArray(state["projectless-thread-ids"]) ? state["projectless-thread-ids"] : []).filter((id: unknown) => typeof id === "string"))
    const hints = state["thread-workspace-root-hints"] && typeof state["thread-workspace-root-hints"] === "object" ? state["thread-workspace-root-hints"] : {}
    return (r.data || []).map((t: any) => ({
      id: t.id,
      title: titles.get(t.id) || t.name || t.preview || "Untitled",
      preview: t.preview || "",
      updatedAt: t.updatedAt || 0,
      pinned: pinned.has(t.id),
      projectless: projectless.has(t.id),
      workspace: typeof hints[t.id] === "string" ? hints[t.id] : undefined,
    }))
  }

  /**
   * Workspaces as Codex Desktop knows them. Desktop keeps the user-facing
   * workspace index in global state; config.toml projects are a fallback for
   * trusted roots that may not be in the visible sidebar state yet.
   */
  async listWorkspaces(): Promise<CodexWorkspace[]> {
    let desktopPaths: string[] = []
    let labels: Record<string, string> = {}
    try {
      const state = await readGlobalState()
      const saved = Array.isArray(state["electron-saved-workspace-roots"]) ? state["electron-saved-workspace-roots"] : []
      const active = Array.isArray(state["active-workspace-roots"]) ? state["active-workspace-roots"] : []
      const order = Array.isArray(state["project-order"]) ? state["project-order"] : []
      labels = state["electron-workspace-root-labels"] || {}
      const savedSet = new Set([...saved, ...active].filter((p) => typeof p === "string"))
      desktopPaths = uniquePaths([
        ...order.filter((p: unknown) => typeof p === "string" && savedSet.has(p as string)),
        ...saved,
        ...active,
      ] as string[])
    } catch {}

    const configPaths: string[] = []
    try {
      const text = await Bun.file(CONFIG_PATH).text()
      const re = /^\[projects\."((?:\\.|[^"\\])*)"\]\s*$/gm
      let match: RegExpExecArray | null
      while ((match = re.exec(text))) configPaths.push(decodeTomlString(match[1]))
    } catch {}

    const desktopExisting = await existingDirectories(desktopPaths)
    if (desktopExisting.length > 0) {
      return desktopExisting.map((path) => ({ name: labels[path] || basename(path), path, source: "desktop" as const }))
    }

    const configExisting = await existingDirectories(
      uniquePaths(configPaths).filter((path) => !path.includes("/Documents/Codex/"))
    )
    return configExisting.map((path) => ({ name: labels[path] || basename(path), path, source: "config" as const }))
  }

  async sidebarState(): Promise<CodexSidebarState> {
    const atom = atomState(await readGlobalState())
    return {
      collapsedGroups: atom["sidebar-collapsed-groups"] || {},
      collapsedSections: atom["sidebar-collapsed-sections-v1"] || {},
      sidebarWidth: typeof atom["sidebar-width"] === "number" ? atom["sidebar-width"] : undefined,
    }
  }

  async setSidebarState(patch: {
    groupPath?: string
    groupCollapsed?: boolean
    section?: string
    sectionCollapsed?: boolean
    sidebarWidth?: number
  }): Promise<CodexSidebarState> {
    const state = await readGlobalState()
    const atom = atomState(state)
    if (!atom["sidebar-collapsed-groups"] || typeof atom["sidebar-collapsed-groups"] !== "object") atom["sidebar-collapsed-groups"] = {}
    if (!atom["sidebar-collapsed-sections-v1"] || typeof atom["sidebar-collapsed-sections-v1"] !== "object") {
      atom["sidebar-collapsed-sections-v1"] = { chats: false, cloud: false, pinned: false, threads: false }
    }

    if (patch.groupPath && typeof patch.groupCollapsed === "boolean") {
      if (patch.groupCollapsed) atom["sidebar-collapsed-groups"][patch.groupPath] = true
      else delete atom["sidebar-collapsed-groups"][patch.groupPath]
    }
    if (patch.section && typeof patch.sectionCollapsed === "boolean") {
      atom["sidebar-collapsed-sections-v1"][patch.section] = patch.sectionCollapsed
    }
    if (typeof patch.sidebarWidth === "number" && Number.isFinite(patch.sidebarWidth)) {
      atom["sidebar-width"] = patch.sidebarWidth
    }
    await writeGlobalState(state)
    return this.sidebarState()
  }

  /** Read a thread's full history as flat chat/tool messages for rendering. */
  async readThread(id: string): Promise<Array<{
    role: string
    content: string
    toolName?: string
    toolDetail?: string
    toolDone?: boolean
    timestamp?: number
    turnDuration?: number
    turnStartedAt?: number
    turnStatus?: string
    isFinal?: boolean
    isSteer?: boolean
  }>> {
    const r = await this.rpc("thread/read", { threadId: id, includeTurns: true })
    const out: Array<{ role: string; content: string; toolName?: string; toolDetail?: string; toolDone?: boolean; timestamp?: number; turnDuration?: number; turnStartedAt?: number; turnStatus?: string; isFinal?: boolean; isSteer?: boolean }> = []
    const epoch = (...values: any[]) => {
      for (const value of values) {
        if (typeof value === "number" && Number.isFinite(value)) return value > 10_000_000_000 ? value / 1000 : value
        if (typeof value === "string") {
          const parsed = Date.parse(value)
          if (Number.isFinite(parsed)) return parsed / 1000
        }
      }
      return undefined
    }
    for (const turn of r.thread?.turns || []) {
      const started = epoch(turn.startedAt, turn.createdAt, turn.startTime, turn.created_at)
      const completed = epoch(turn.completedAt, turn.finishedAt, turn.updatedAt, turn.endTime, turn.completed_at)
      const duration = typeof turn.durationMs === "number" ? Math.max(0, turn.durationMs / 1000) : (started && completed ? Math.max(0, completed - started) : undefined)
      const turnStatus = turn.status || (completed ? "completed" : "running")
      const items = turn.items || []
      const finalAgentIndex = turnStatus === "completed" ? items.findLastIndex((it: any) => it.type === "agentMessage" && it.text) : -1
      let sawPrompt = false
      for (const [index, it] of items.entries()) {
        const timestamp = epoch(it.completedAt, it.finishedAt, it.updatedAt, it.createdAt, it.timestamp, completed)
        if (it.type === "userMessage") {
          const text = (it.content || []).map((c: any) => c.text || "").join("")
          if (text) {
            out.push({ role: "user", content: text, timestamp, turnStartedAt: started, turnStatus, isSteer: sawPrompt })
            sawPrompt = true
          }
        } else if (it.type === "agentMessage" && it.text) {
          out.push({ role: "assistant", content: it.text, timestamp, turnDuration: duration, turnStartedAt: started, turnStatus, isFinal: index === finalAgentIndex })
        } else if (it.type === "commandExecution") {
          const outText = (it.aggregatedOutput || it.output || "").slice(0, 4000)
          out.push({
            role: "tool",
            content: "",
            toolName: "shell",
            toolDetail: `$ ${it.command || ""}\nexit ${it.exitCode ?? "?"}\n\n${outText}`,
            toolDone: true,
            timestamp,
            turnStartedAt: started,
            turnStatus,
          })
        } else if (it.type === "fileChange") {
          out.push({
            role: "tool",
            content: "",
            toolName: "edit",
            toolDetail: fileChangeDetail(it),
            toolDone: true,
            timestamp,
            turnStartedAt: started,
            turnStatus,
          })
        } else if (it.type === "mcpToolCall") {
          out.push({
            role: "tool",
            content: "",
            toolName: it.tool || "mcp",
            toolDetail: JSON.stringify(it.result ?? it.error ?? it.server ?? "").slice(0, 4000),
            toolDone: true,
            timestamp,
            turnStartedAt: started,
            turnStatus,
          })
        } else if (it.type === "webSearch") {
          out.push({ role: "tool", content: "", toolName: "web_search", toolDetail: it.query || "", toolDone: true, timestamp, turnStartedAt: started, turnStatus })
        }
      }
    }
    return out
  }

  async archiveThread(threadId: string): Promise<void> {
    await this.rpc("thread/archive", { threadId })
  }

  async renameThread(threadId: string, name: string): Promise<void> {
    await this.rpc("thread/name/set", { threadId, name })
  }

  async setThreadPinned(threadId: string, pinned: boolean): Promise<void> {
    try {
      await this.rpc("set-thread-pinned", { threadId, pinned })
    } catch {}
    const state = await readGlobalState()
    const ids = new Set(
      (Array.isArray(state["pinned-thread-ids"]) ? state["pinned-thread-ids"] : [])
        .filter((id: unknown) => typeof id === "string")
    )
    if (pinned) ids.add(threadId)
    else ids.delete(threadId)
    state["pinned-thread-ids"] = Array.from(ids)
    await writeGlobalState(state)
  }

  /**
   * Start (or resume) a thread and run one turn, streaming events.
   * Returns nothing; events flow through onEvent. Resolves when the turn completes.
   */
  async chat(opts: {
    cwd: string
    model: string
    effort?: string
    threadId?: string
    text: string
    onEvent: (e: ChatEvent) => void
    signal?: AbortSignal
  }): Promise<void> {
    await this.connect()
    const model = await this.supportedModelOrDefault(opts.model)
    let threadId = opts.threadId
    if (threadId) {
      try { await this.call("thread/resume", { threadId }) } catch { threadId = undefined }
    }
    if (!threadId) {
      const started = await this.call("thread/start", {
        cwd: opts.cwd, model, approvalPolicy: "never", sandbox: "workspace-write",
      })
      threadId = started.thread.id
    }
    opts.onEvent({ type: "thread", id: threadId! })

    return new Promise<void>((resolve) => {
      const finish = () => { this.subs.delete(threadId!); resolve() }
      if (opts.signal) opts.signal.addEventListener("abort", () => {
        this.call("turn/interrupt", { threadId }).catch(() => {})
        finish()
      })
      this.subs.set(threadId!, (m: any) => {
        const p = m.params
        if (p?.turnId) this.activeTurns.set(threadId!, p.turnId)
        switch (m.method) {
          case "item/agentMessage/delta": opts.onEvent({ type: "text", text: p.delta }); break
          case "item/reasoning/textDelta":
          case "item/reasoning/summaryTextDelta": opts.onEvent({ type: "reasoning", text: p.delta }); break
          case "turn/steered": opts.onEvent({ type: "steer" }); break
          case "item/started": {
            const it = p.item
            if (it?.type === "commandExecution") opts.onEvent({ type: "tool", name: "shell", detail: it.command })
            else if (it?.type === "fileChange") opts.onEvent({ type: "tool", name: "edit", detail: fileChangeDetail(it, "running") })
            else if (it?.type === "mcpToolCall") opts.onEvent({ type: "tool", name: it.tool, detail: it.server })
            else if (it?.type === "webSearch") opts.onEvent({ type: "tool", name: "web_search", detail: it.query })
            break
          }
          case "item/completed": {
            const it = p.item
            if (it?.type === "commandExecution") {
              const out = (it.aggregatedOutput || "").slice(0, 4000)
              opts.onEvent({ type: "tool-result", name: "shell", detail: `$ ${it.command}\nexit ${it.exitCode ?? "?"}\n\n${out}` })
            }
            else if (it?.type === "fileChange") opts.onEvent({ type: "tool-result", name: "edit", detail: fileChangeDetail(it) })
            else if (it?.type === "mcpToolCall") opts.onEvent({ type: "tool-result", name: it.tool, detail: JSON.stringify(it.result ?? it.error ?? "").slice(0, 4000) })
            break
          }
          case "turn/completed": opts.onEvent({ type: "done", status: p.turn?.status }); this.activeTurns.delete(threadId!); finish(); break
      case "error": {
            const message = codexErrorMessage(p || m.error || m)
            opts.onEvent({ type: "error", error: message || "codex error" })
            finish()
            break
          }
        }
      })
      this.call("turn/start", {
        threadId,
        input: [{ type: "text", text: opts.text, text_elements: [] }],
        model,
        ...(opts.effort ? { effort: opts.effort } : {}),
      }).then((r) => { if (r?.turn?.id) this.activeTurns.set(threadId!, r.turn.id) })
        .catch((e) => { opts.onEvent({ type: "error", error: e.message }); finish() })
    })
  }

  /** Inject a message into the currently running turn via turn/steer. */
  async steer(threadId: string, text: string): Promise<void> {
    await this.connect()
    const expectedTurnId = this.activeTurns.get(threadId) ?? await this.findActiveTurnId(threadId)
    if (!expectedTurnId) throw new Error("no active turn to steer")
    this.activeTurns.set(threadId, expectedTurnId)
    await this.call("turn/steer", {
      threadId,
      input: [{ type: "text", text, text_elements: [] }],
      expectedTurnId,
    })
    this.subs.get(threadId)?.({ method: "turn/steered", params: { threadId } })
  }

  async cancel(threadId: string): Promise<void> {
    await this.connect()
    await this.call("turn/interrupt", { threadId })
    this.activeTurns.delete(threadId)
    this.subs.get(threadId)?.({ method: "turn/completed", params: { threadId, turn: { status: "interrupted" } } })
  }

  private async findActiveTurnId(threadId: string): Promise<string | undefined> {
    const r = await this.rpc("thread/read", { threadId, includeTurns: true })
    const turns = r.thread?.turns || []
    for (let i = turns.length - 1; i >= 0; i--) {
      const turn = turns[i]
      const status = turn?.status
      if (turn?.id && status !== "completed" && status !== "failed" && status !== "cancelled" && status !== "interrupted") {
        return turn.id
      }
    }
    return undefined
  }
}

export const codex = new CodexClient()
