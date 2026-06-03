# DynAgent — Handoff

## Quick reference
- **macOS app**: `Packages/DynAgentMac/` (SwiftPM, targets macOS 26)
- **iOS app**: `Packages/DynAgentMobile/` (XcodeGen, iOS 17)
- **Server/agent**: `src/` (TypeScript, Bun runtime)
- **Server runs on**: `localhost:4319`
- **Codex app-server (pm2)**: `ws://127.0.0.1:4555` (managed by pm2 as `codex-appserver`)
- **Auth**: Kiro CLI (bearer token at `~/.aws/sso/cache/kiro-auth-token-cli.json`), Codex/OpenAI (OAuth tokens at `~/.codex/auth.json`)

## Architecture
```
DynAgent.app (macOS native, AppKit + SwiftTerm + WKWebView)
  │  HTTP/SSE (localhost:4319)
  ▼
Bun server (src/server.ts) — the central hub
  ├── /chat              → DynAgent agent (Kiro ACP, tool-calling loop)
  ├── /codex/*           → Codex app-server (WebSocket JSON-RPC, real OpenAI models)
  ├── /pi/*              → Pi CLI (spawns `pi -p --mode json`)
  ├── /git/*             → git CLI
  ├── /credits           → AWS CodeWhisperer GetUsageLimits (direct bearer call)
  ├── /terminal/*        → bridge to in-app SwiftTerm panels
  └── /browser/*         → bridge to in-app WKWebView panels
```

## What works (verified)
### App Kit (macOS)
- Sidebar with workspace groups (NSStackView-based, fully custom — no NSOutlineView blues)
- Per-workspace threads from Codex app-server, grouped under parent (including worktrees)
- Chat with streaming, markdown rendering, turn collapse ("Worked for Xs"), copy button + timestamp
- Steering (send while streaming — Codex uses `turn/steer`, DynAgent queues)
- Stop button (red stop.fill when empty composer, cancel stream + turn/interrupt)
- Tool-detail popover (click any tool row → shows cmd + output)
- Thinking shimmer stays at bottom during streaming
- Git panel (colored diff, commit, push, commit+push, PR info, branch/worktree buttons)
- Liquid Glass composer (`NSGlassEffectView` on macOS 26)
- Window-wide blur (`hudWindow` material)
- In-app Terminal panel (SwiftTerm PTY, native system colors)
- In-app Browser panel (WKWebView, headless always-available instance)
- Hot-reloadable macOS UI dylib (Cmd+R, or `kill -USR1 <pid>` for verification, rebuilds `DynAgentUI`, copies it to a unique temp dylib, and reattaches it without restarting the host process)
- Main menu bar (cmd+N new chat, cmd+W close, cmd+Q quit, Edit menu with copy/paste)
- Credits overlay (live account-level from GetUsageLimits)
- Context ring (circular progress for context %, shows on hover)
- Auto-detect git worktrees per workspace

### Server
- `/chat`: DynAgent (multi-step tool loop via `streamText`, `finish` control tool, self-verifying)
- `/codex/models`, `/codex/chat`, `/codex/threads`, `/codex/thread/:id`, `/codex/steer`
- `/pi/models`, `/pi/chat`
- `/git`, `/git/commit`, `/git/push`, `/git/commit-push`, `/git/create-branch`, `/git/create-pr`, `/git/pr-info`, `/worktrees`
- `/terminal/write`, `/terminal/read`, `/browser/navigate`, `/browser/eval`, `/browser/state`
- `/generate-title`, `/credits`, `/cwd`

### Harnesses (selectable in composer)
1. **DynAgent** — Kiro ACP, full autonomous tool loop (bash, read/write, create_tool, finish)
2. **Codex** — `codex app-server` over WebSocket (real GPT-5.x models, resume existing threads)
3. **Pi** — spawns `pi -p --mode json --session-id` per turn (kiro & openai-codex providers)

### Known issues (unfinished / partially working)
- **iOS companion app**: sources typecheck, XcodeGen project.yml exists, but building requires `xcodegen generate`. Not tested on device/sim.
- **Virtualization**: user asked, I deferred. `NSStackView` transcript is fine for typical thread sizes. Full `NSTableView` rewrite would be cleaner for 100+ message threads.
- **Browser panels per chat**: panels reset on conversation switch but don't persist/restore.

## Key files
| File | Purpose |
|------|---------|
| `src/server.ts` | Main server — all HTTP+SSE endpoints |
| `src/agent/agent.ts` | DynAgent loop (`streamText`, `finish` tool, re-prompt) |
| `src/agent/builtins.ts` | Tool definitions (bash, read/write, create_tool, terminal/browser) |
| `src/codex.ts` | WebSocket JSON-RPC client to `codex app-server` |
| `src/pi.ts` | Bridge to `pi` CLI |
| `src/provider/kiro.ts` | Kiro ACP provider wrapper |
| `src/provider/kiro-direct.ts` | Direct KRS event-stream client (proof of concept) |
| `Packages/DynAgentMac/Sources/Host/main.swift` | macOS host process, window owner, Cmd+R hot reload, `dlopen`/`dlsym` |
| `Packages/DynAgentMac/Sources/UI/AppController.swift` | Reloadable UI controller exported via `dynagent_attach` / `dynagent_detach` |
| `Packages/DynAgentMac/Sources/UI/ChatViewController.swift` | Chat transcript + composer + streaming |
| `Packages/DynAgentMac/Sources/UI/SidebarViewController.swift` | Fully custom sidebar (no NSOutlineView) |
| `Packages/DynAgentMac/Sources/UI/Panels.swift` | Tiling panel system, Terminal (SwiftTerm), Browser (WKWebView) |
| `Packages/DynAgentMac/Sources/UI/GitPanelViewController.swift` | Git diff + actions panel |
| `Packages/DynAgentMac/Sources/UI/AgentClient.swift` | HTTP client (all SSE streaming + polling) |
| `Packages/DynAgentMac/Sources/UI/Models.swift` | Data types + persistence |
| `Packages/DynAgentMac/Package.swift` | SwiftPM config (macOS 26, SwiftTerm dep) |
| `Packages/DynAgentMobile/Sources/App.swift` | iOS SwiftUI companion |
| `Packages/DynAgentMobile/project.yml` | XcodeGen config |

## How to run
```bash
# Start servers
bun src/server.ts                              # Main agent server (port 4319)
pm2 start codex app-server --listen ws://127.0.0.1:4555  # Codex (pm2 saved)
# Optional: bun src/codex-server.ts             # Old Kiro-backed bridge (UNUSED)

# Build + run macOS app as a real app bundle
./script/build_and_run.sh

# Same script from inside the package
cd Packages/DynAgentMac && ./script/build_and_run.sh

# Build only
cd Packages/DynAgentMac && swift build --disable-sandbox --product DynAgentUI && swift build --disable-sandbox --product DynAgent
```

## Persisted data
- **Chats**: `~/.dynagent/sessions.json` (Codable `[Conversation]`)
- **Workspace refs**: `~/.dynagent/workspaces.json`
- **Archived codex threads**: `UserDefaults["archivedCodexIds"]`
- **Last harness/model**: `UserDefaults["lastHarness"]` + `UserDefaults["lastModel"]`
- **Sidebar width**: `NSSplitView autosaveName = "dynagent.split"`

## Key decisions to honor
- No OpenAI API called directly. Codex access goes through `codex app-server` WebSocket (pm2 managed)
- No direct Kiro API reimplementation. The `kiro-direct.ts` file is a proof-of-concept text-stream client. The real integration uses `kiro-acp-ai-provider` / ACP subprocess
- Harness abstraction = enum + uniform `<harness>/models|chat` endpoints. No Swift protocol was added (user agreed to this)
- Sidebar is fully custom — no NSOutlineView (selection/hover/blue-text issues are non-reproducible with the current custom row approach)
- `Packages/` directory structure established (macapp → Packages/DynAgentMac, iosapp → Packages/DynAgentMobile)

## Next likely work
1. **Per-chat panel persistence** — store panel tree per conversation and restore on switch
2. **Virtualization** — NSTableView-based transcript for long threads
3. **iOS app** — build & test on device/simulator

## pm2 processes
- `codex-appserver` — `codex app-server --listen ws://127.0.0.1:4555` (saved, auto-starts)
- `kiro-codex` — old `bun run src/codex-server.ts` (legacy, can be deleted)

## Last verified state
- TS typechecks: ✅ (`bunx tsc --noEmit` clean)
- Swift builds: ✅ (`swift build` clean)
- Server runs: ✅ (port 4319, all endpoints responsive)
- App runs: ✅ (connects, streams chat, codex and pi harnesses work)
