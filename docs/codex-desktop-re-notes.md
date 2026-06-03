# Codex Desktop Reverse-Engineering Notes

Source inspected: `/Applications/Codex.app`

## Bundle Shape

- App bundle id: `com.openai.codex`
- Version observed: `26.527.31326`
- Runtime: Electron/Chromium (`NSPrincipalClass = BrowserCrApplication`)
- Main executable: `Contents/MacOS/Codex`
- Main UI bundle: `Contents/Resources/app.asar`
- Extracted analysis copy: `/private/tmp/codex-asar`
- Bundled binaries:
  - `Contents/Resources/codex` (`codex-cli 0.135.0-alpha.1`)
  - `Contents/Resources/node`
  - `Contents/Resources/node_repl`
  - `Contents/Resources/rg`
  - `Contents/Resources/codex_chronicle`
- Native helpers/modules:
  - `native/sparkle.node`
  - `native/devicecheck.node`
  - `native/browser-use-peer-authorization.node`
  - `native/sky.node`
  - `native/input-monitoring-permission.node`
  - `native/remote-control-device-key.node`
  - `native/launch-services-helper`
  - `native/bare-modifier-monitor`

## App-Server Protocol Signals

The bundled CLI/app-server binary exposes these useful JSON-RPC methods/events:

- Thread lifecycle: `thread/start`, `thread/resume`, `thread/fork`, `thread/archive`, `thread/read`, `thread/list`, `thread/search`
- Turn lifecycle: `turn/start`, `turn/steer`, `turn/interrupt`
- Notifications: `thread/started`, `thread/status/changed`, `thread/archived`, `thread/name/updated`, `turn/started`, `turn/completed`
- Items: `item/started`, `item/completed`, `item/agentMessage/delta`, `item/reasoning/textDelta`, `item/reasoning/summaryTextDelta`, command/file/MCP output deltas

## UI Assets / Modules Worth Mining

Extracted web assets include readable module names even after bundling. High-value references:

- `sidebar-thread-list-signals-*.js`: sidebar grouping, pinned/unpinned ordering, active/running state derivation.
- `thread-actions-*.js`: archive and other row actions.
- `local-task-row-*.js`: thread row rendering patterns.
- `header-*.js`: title/header composition and command wiring.
- `right-panel-composer-overlay-scroll-reserve-*.js`: composer overlay spacing strategy.
- `queued-message-list-*.js`: queued/steered message UI.
- `review-runtime-bridge-*.js`: right panel and review pane state bridge.

## Porting Notes For DynAgent

- Codex keeps thread identity separate from currently visible route state. DynAgent should do the same: streaming callbacks mutate the target thread model first, and only render when that thread is selected.
- Codex app-server already supports `thread/archive`; DynAgent should call it instead of only locally hiding Codex threads.
- `thread/read` with `includeTurns: true` contains tool items (`fileChange`, `commandExecution`, `mcpToolCall`, `webSearch`) that can be reconstructed into DynAgent tool rows.
- Sidebar should use cached local state immediately and then reconcile with app-server lists, matching Codex's signal/query pattern rather than blanking while fresh data loads.
