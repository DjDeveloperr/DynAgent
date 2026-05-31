import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

/**
 * Direct client for the underlying Kiro Runtime Service (KRS) — the
 * CodeWhisperer streaming API that kiro-cli itself calls, bypassing the ACP
 * subprocess. Auth is the bearer token kiro-cli already stored on disk.
 *
 * Endpoint/schema reverse-engineered from `kiro-cli-chat`:
 *   POST {KRS}  X-Amz-Target: AmazonCodeWhispererStreamingService.GenerateAssistantResponse
 *   Authorization: Bearer <accessToken>;  Content-Type: application/x-amz-json-1.0
 *   body: { conversationState{...}, profileArn }
 *   response: AWS event-stream framing; assistantResponseEvent → { content }
 */
const KRS = process.env.KIRO_CLI_KRS_ENDPOINTS?.split(",")[0] ?? "https://runtime.us-east-1.kiro.dev"
const TOKEN_PATH = join(homedir(), ".aws/sso/cache/kiro-auth-token-cli.json")

function loadToken(): { accessToken: string; profileArn?: string } {
  const t = JSON.parse(readFileSync(TOKEN_PATH, "utf8"))
  if (t.expiresAt && new Date(t.expiresAt) <= new Date())
    throw new Error("Kiro token expired — run `kiro-cli login`")
  return t
}

export interface DirectMessage { role: "user" | "assistant"; content: string }

/** Stream assistant text directly from KRS. Yields text deltas. */
export async function* kiroDirectStream(opts: {
  model?: string
  messages: DirectMessage[]
  signal?: AbortSignal
}): AsyncGenerator<string> {
  const tok = loadToken()
  const modelId = opts.model && opts.model !== "auto" ? opts.model : undefined
  const msg = (m: DirectMessage) =>
    m.role === "user"
      ? { userInputMessage: { content: m.content, origin: "CLI", ...(modelId ? { modelId } : {}) } }
      : { assistantResponseMessage: { content: m.content } }
  const last = opts.messages.at(-1)
  if (last?.role !== "user") throw new Error("last message must be from the user")

  const body = {
    conversationState: {
      chatTriggerType: "MANUAL",
      conversationId: crypto.randomUUID(),
      currentMessage: msg(last),
      history: opts.messages.slice(0, -1).map(msg),
    },
    ...(tok.profileArn ? { profileArn: tok.profileArn } : {}),
  }

  const res = await fetch(KRS, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.0",
      "X-Amz-Target": "AmazonCodeWhispererStreamingService.GenerateAssistantResponse",
      Authorization: `Bearer ${tok.accessToken}`,
    },
    body: JSON.stringify(body),
    signal: opts.signal,
  })
  if (!res.ok || !res.body) throw new Error(`KRS ${res.status}: ${await res.text()}`)

  for await (const ev of decodeEventStream(res.body)) {
    if (ev.type === "assistantResponseEvent" && typeof ev.payload?.content === "string")
      yield ev.payload.content
    else if (ev.type?.endsWith("Exception") || ev.type === "error")
      throw new Error(`KRS event ${ev.type}: ${JSON.stringify(ev.payload)}`)
  }
}

/** Decode AWS `vnd.amazon.eventstream` framing into {type, payload} events. */
async function* decodeEventStream(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<{ type?: string; payload: any }> {
  const td = new TextDecoder()
  let buf = new Uint8Array(0)
  // Header value byte-size by type tag (after the 1-byte tag).
  const skip: Record<number, (dv: DataView, o: number) => number> = {
    0: () => 0, 1: () => 0, 2: () => 1, 3: () => 2, 4: () => 4, 5: () => 8, 8: () => 8, 9: () => 16,
    6: (dv, o) => 2 + dv.getUint16(o), 7: (dv, o) => 2 + dv.getUint16(o),
  }

  for await (const chunk of body as any as AsyncIterable<Uint8Array>) {
    const next = new Uint8Array(buf.length + chunk.length)
    next.set(buf); next.set(chunk, buf.length); buf = next

    while (buf.length >= 12) {
      const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
      const total = dv.getUint32(0)
      if (buf.length < total) break
      const headersLen = dv.getUint32(4)
      const headers: Record<string, string> = {}
      let o = 12
      const hEnd = 12 + headersLen
      while (o < hEnd) {
        const nameLen = buf[o]; o += 1
        const name = td.decode(buf.subarray(o, o + nameLen)); o += nameLen
        const type = buf[o]; o += 1
        if (type === 7) { const vl = dv.getUint16(o); headers[name] = td.decode(buf.subarray(o + 2, o + 2 + vl)) }
        o += skip[type]?.(dv, o) ?? 0
      }
      let payload: any = {}
      try { payload = JSON.parse(td.decode(buf.subarray(hEnd, total - 4))) } catch {}
      yield { type: headers[":event-type"], payload }
      buf = buf.subarray(total)
    }
  }
}
