import { kiroDirectStream } from "./provider/kiro-direct"

const model = process.argv[2] ?? "claude-haiku-4.5"
process.stdout.write(`direct KRS via "${model}":\n`)
for await (const delta of kiroDirectStream({
  model,
  messages: [{ role: "user", content: 'Reply with exactly one word: "pong"' }],
})) {
  process.stdout.write(delta)
}
process.stdout.write("\n")
