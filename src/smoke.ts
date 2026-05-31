import { streamText } from "ai"
import { createKiroProvider } from "./provider/kiro"

const kiro = createKiroProvider()
try {
  const models = await kiro.listModels()
  console.log("models:", models.map((m) => m.id).join(", ") || "(none)")

  const modelId = models[0]?.id ?? "claude-opus-4.8"
  console.log(`\nstreaming via "${modelId}":`)
  const result = streamText({
    model: kiro.languageModel(modelId),
    prompt: 'Reply with exactly one word: "pong"',
  })
  for await (const chunk of result.textStream) process.stdout.write(chunk)
  process.stdout.write("\n")
} finally {
  await kiro.shutdown()
}
