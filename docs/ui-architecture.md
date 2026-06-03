# DynAgent UI Architecture

## Current Shared Mac Components

- `DesignSystem.swift`: shared typography, colors, and paragraph tokens. Add visual constants here before introducing one-off styling in feature controllers.
- `ChromeControls.swift`: reusable AppKit chrome controls, currently `ChromeIconButton` and `ComposerMenuChrome`.
- `MarkdownRenderer.swift`: tested markdown rendering for chat text, links, inline code, bullets, code fences, and directive tokens.
- `GitDiffModel.swift`: tested pure parser for git diff sections, line numbers, metadata filtering, and hunk separator rows.
- `GitDiffLayoutModel.swift`: tested pure layout model for diff row heights, visible row lookup, file header lookup, and collapsed file sections.
- `ShellToolModel.swift`: tested command summarizer and command-title model for shell tool rows.
- `EditToolModel.swift`: tested edit-tool parser and title model for grouped editing rows and popout diff data.
- `TranscriptTurnModel.swift`: tested turn-planning model for prompt/steer boundaries, active-turn expansion, final-response collapse, timestamps, and large-thread trimming.
- `SidebarModel.swift`: tested pure grouping model for pinned chats, projectless chats, project workspaces, archived filtering, and recency ordering.
- `ComposerModel.swift`: tested composer behavior model for model/reasoning labels, draft keys, attachment message text, context state, and send/stop state.
- `WindowHosting.swift`: full-window host and split-view pinning used by the hot-reloadable macOS UI.

Feature controllers should keep behavior and orchestration, not reusable visual/parser logic. When a controller grows a reusable widget, parser, or display model, extract it into a small file and add a focused test before expanding behavior.

## Mac Layout Contract

- The macOS root is a full-window `NSSplitView` hosted directly by `FullWindowHostView`.
- The left sidebar is a custom AppKit stack-based surface with a fixed practical width band.
- The center chat/workspace surface owns transcript rendering, composer state, and panel layout.
- The right git panel is a collapsible split item; the git diff document uses `GitDiffModel` for all parsing.
- Hot reload must preserve the window size and keep the content split filling the visible window. Current verified invariant: content width, split width, and visible window width match after reload.

## iOS Adaptation Contract

The iOS app should share behavior and visual language, but not copy the desktop split layout directly:

- Left sidebar -> leading drawer containing New Chat, Search, pinned chats, projectless chats, and projects/workspaces.
- Center chat -> primary navigation destination with the composer pinned to the bottom and a max-width transcript only on regular-width iPad layouts.
- Right git panel -> trailing drawer or sheet with the same `GitDiffModel` sections and diff-row semantics.
- Settings/search/commit overlays -> native SwiftUI sheets or presentation detents, using the same labels and action order as macOS.
- Composer -> same model/reasoning/context/send ordering, with attachments previewed above the text field and keyboard-safe bottom padding.

Pure models should move toward platform-neutral Swift where possible (`MarkdownRenderer`, `GitDiffModel`, `GitDiffLayoutModel`, `ShellToolModel`, `EditToolModel`, `TranscriptTurnModel`, `SidebarModel`, `ComposerModel`). AppKit-only controls remain in macOS files; iOS should build SwiftUI equivalents using the same tokens and model outputs.

## Verification Gates

- `cd Packages/DynAgentMac && swift build --disable-sandbox --product DynAgentUI`
- `cd Packages/DynAgentMac && swift test --disable-sandbox`
- Hot reload the running app with `kill -USR1 $(pgrep -x DynAgent | head -1)` and verify layout metrics in `~/.dynagent/ui-layout-metrics.json`.
- For width safety, verify `windowWidth == splitViewWidth` and chat/workspace width remains the available center width when git is collapsed.

## Next Extraction Targets

- Transcript virtualization or reusable transcript row data source for large threads.
- Diff drawing component split from `GitPanelViewController` after the layout model is fully adopted.
- Composer visual component split from `ChatViewController`.
- Sidebar row view models and reusable row chrome for pinned, chats, projects, and workspaces.
