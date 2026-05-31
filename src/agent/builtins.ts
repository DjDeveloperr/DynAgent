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
  }
}
