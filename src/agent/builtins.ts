import { tool, type ToolSet } from "ai"
import { z } from "zod"
import { exec } from "node:child_process"
import { promisify } from "node:util"
import { readFile, writeFile, mkdir } from "node:fs/promises"
import { dirname, join, resolve, isAbsolute } from "node:path"

const run = promisify(exec)
const cap = (s: string) => s.slice(0, 60_000)

/**
 * Built-in tools. `getCwd` returns the active workspace directory so shell and
 * file operations run where the chat lives; `create_tool` lets the agent author
 * new tools at runtime.
 */
export function builtins(toolsDir: string, getCwd: () => string): ToolSet {
  const at = (p: string) => (isAbsolute(p) ? p : resolve(getCwd(), p))
  const serverBase = `http://127.0.0.1:${process.env.PORT ?? 4319}`

  return {
    bash: tool({
      description: "Run a shell command in the workspace directory. Returns stdout+stderr.",
      inputSchema: z.object({ command: z.string() }),
      execute: async ({ command }) => {
        try {
          const { stdout, stderr } = await run(command, { timeout: 120_000, maxBuffer: 1 << 24, cwd: getCwd() })
          return cap(stdout + stderr) || "(no output)"
        } catch (e: any) {
          return cap(`error: ${e.message}\n${e.stdout ?? ""}${e.stderr ?? ""}`)
        }
      },
    }),
    read_file: tool({
      description: "Read a UTF-8 text file (relative to the workspace).",
      inputSchema: z.object({ path: z.string() }),
      execute: async ({ path }) => {
        try {
          return cap(await readFile(at(path), "utf8"))
        } catch (e: any) {
          return `error: ${e.message}`
        }
      },
    }),
    write_file: tool({
      description: "Write a UTF-8 text file (relative to the workspace), creating parent directories.",
      inputSchema: z.object({ path: z.string(), content: z.string() }),
      execute: async ({ path, content }) => {
        const p = at(path)
        await mkdir(dirname(p), { recursive: true })
        await writeFile(p, content)
        return `wrote ${p}`
      },
    }),
    create_tool: tool({
      description:
        "Create or replace one of your own tools at runtime. `code` must be a TypeScript module that " +
        "default-exports an AI SDK tool, e.g.\n" +
        "import { tool } from 'ai'\nimport { z } from 'zod'\n" +
        "export default tool({ description: '...', inputSchema: z.object({...}), execute: async (a) => '...' })\n" +
        "The tool becomes available on your next turn.",
      inputSchema: z.object({
        name: z.string().describe("tool name (filename), e.g. http_get"),
        code: z.string().describe("full TypeScript module source"),
      }),
      execute: async ({ name, code }) => {
        const path = join(toolsDir, `${name.replace(/[^a-zA-Z0-9_]/g, "_")}.ts`)
        await writeFile(path, code)
        return `created tool '${name}' at ${path} (available next turn)`
      },
    }),
    terminal_write: tool({
      description: "Write text to the terminal emulator panel in the app. Use this to run commands interactively (include \\n to execute). The terminal maintains state between calls (cd, env vars, etc persist).",
      inputSchema: z.object({
        text: z.string().describe("Text to send to the terminal (include \\n to press Enter)"),
        id: z.string().optional().describe("Terminal panel ID (omit for the first/default terminal)"),
      }),
      execute: async ({ text, id }) => {
        try {
          await fetch(`${serverBase}/terminal/write`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ text, id }),
          })
          // Wait a moment for output
          await new Promise((r) => setTimeout(r, 500))
          const res = await fetch(`${serverBase}/terminal/read?last=4000${id ? `&id=${id}` : ""}`)
          const { output } = await res.json() as { output: string }
          return cap(output || "(no output yet)")
        } catch (e: any) {
          return `error: ${e.message}`
        }
      },
    }),
    terminal_read: tool({
      description: "Read recent output from the terminal emulator panel. Returns the last N characters of terminal output.",
      inputSchema: z.object({
        last: z.number().optional().describe("Number of characters to read (default 4000)"),
        id: z.string().optional().describe("Terminal panel ID (omit for default)"),
      }),
      execute: async ({ last, id }) => {
        try {
          const res = await fetch(`${serverBase}/terminal/read?last=${last ?? 4000}${id ? `&id=${id}` : ""}`)
          const { output } = await res.json() as { output: string }
          return cap(output || "(terminal buffer empty)")
        } catch (e: any) {
          return `error: ${e.message}`
        }
      },
    }),
    browser_navigate: tool({
      description: "Navigate the browser panel to a URL. The browser is a full WebKit webview.",
      inputSchema: z.object({
        url: z.string().describe("URL to navigate to"),
        id: z.string().optional().describe("Browser panel ID (omit for default)"),
      }),
      execute: async ({ url, id }) => {
        try {
          await fetch(`${serverBase}/browser/navigate`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ url, id }),
          })
          return `navigating to ${url}`
        } catch (e: any) {
          return `error: ${e.message}`
        }
      },
    }),
    browser_eval: tool({
      description: "Execute JavaScript in the browser panel and return the result. Use for DOM inspection, scraping, or interaction.",
      inputSchema: z.object({
        script: z.string().describe("JavaScript code to evaluate in the page context"),
        id: z.string().optional().describe("Browser panel ID (omit for default)"),
      }),
      execute: async ({ script, id }) => {
        try {
          const res = await fetch(`${serverBase}/browser/eval`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ script, id }),
          })
          const { result } = await res.json() as { result: string }
          return cap(result || "(no result)")
        } catch (e: any) {
          return `error: ${e.message}`
        }
      },
    }),
    browser_state: tool({
      description: "Get the current state of the browser panel (URL and page title).",
      inputSchema: z.object({
        id: z.string().optional().describe("Browser panel ID (omit for default)"),
      }),
      execute: async ({ id }) => {
        try {
          const res = await fetch(`${serverBase}/browser/state${id ? `?id=${id}` : ""}`)
          const state = await res.json() as { url: string; title: string }
          return `URL: ${state.url}\nTitle: ${state.title}`
        } catch (e: any) {
          return `error: ${e.message}`
        }
      },
    }),
  }
}
