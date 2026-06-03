# DynAgent UI Architecture

## Current Shared Mac Components

- `DesignSystem.swift`: shared typography, colors, and paragraph tokens. Add visual constants here before introducing one-off styling in feature controllers.
- `ChromeControls.swift`: reusable AppKit chrome controls, currently `ChromeIconButton` and `ComposerMenuChrome`.
- `MarkdownRenderer.swift`: tested markdown rendering for chat text, links, inline code, bullets, code fences, and directive tokens.
- `GitDiffModel.swift`: tested pure parser for git diff sections, line numbers, metadata filtering, and hunk separator rows.
- `GitDiffLayoutModel.swift`: tested pure layout model for diff row heights, visible row lookup, file header lookup, and collapsed file sections.
- `GitDiffViews.swift`: reusable AppKit diff document/header/gutter views that consume the diff parser and layout model.
- `ShellToolModel.swift`: tested command summarizer and command-title model for shell tool rows.
- `EditToolModel.swift`: tested edit-tool parser and title model for grouped editing rows and popout diff data.
- `TranscriptTurnModel.swift`: tested turn-planning model for prompt/steer boundaries, active-turn expansion, final-response collapse, timestamps, and large-thread trimming.
- `TranscriptRenderModel.swift`: tested row data-source model for turn batching, shell tool grouping, and completed edit grouping.
- `WorkDividerModel.swift`: tested label/duration model for active and completed Codex-style work dividers.
- `TranscriptChrome.swift`: reusable AppKit transcript text, shimmer, work-divider, and edit-stat views.
- `TranscriptToolChrome.swift`: reusable AppKit shell/edit tool rows, grouped tool collapse controls, and inline edit diff popover blocks.
- `TranscriptPopoverChrome.swift`: reusable selectable popover content for shell/tool output and edit diff details.
- `SidebarModel.swift`: tested pure grouping model for pinned chats, projectless chats, project workspaces, archived filtering, and recency ordering.
- `SidebarRowModel.swift`: tested pure row-presentation model for short relative timestamps, workspace/chat tooltip content, worktree indicators, and working/pinned/unread state.
- `SidebarChrome.swift`: reusable AppKit sidebar row, scroll-hover clearing, spinner, and liquid tooltip chrome.
- `ComposerModel.swift`: tested composer behavior model for model/reasoning labels, draft keys, attachment message text, draft snapshots, attachment normalization, context state, and send/stop state.
- `ComposerChrome.swift`: reusable AppKit composer text input, context ring, and attachment chip views.
- `WindowLayoutModel.swift`: tested pure layout model for main window frame restoration, wide fallback sizing, split divider planning, and post-load width invariants.
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

Pure models should move toward platform-neutral Swift where possible (`MarkdownRenderer`, `GitDiffModel`, `GitDiffLayoutModel`, `ShellToolModel`, `EditToolModel`, `TranscriptTurnModel`, `TranscriptRenderModel`, `WorkDividerModel`, `SidebarModel`, `SidebarRowModel`, `ComposerModel`, `WindowLayoutModel`). AppKit-only controls remain in macOS files; iOS should build SwiftUI equivalents using the same tokens and model outputs.

## Verification Gates

- `cd Packages/DynAgentMac && swift build --disable-sandbox --product DynAgentUI`
- `cd Packages/DynAgentMac && swift test --disable-sandbox`
- Hot reload the running app with `kill -USR1 $(pgrep -x DynAgent | head -1)` and verify layout metrics in `~/.dynagent/ui-layout-metrics.json`.
- For width safety, verify `windowWidth == splitViewWidth` and chat/workspace width remains the available center width when git is collapsed.

## Next Extraction Targets

- Continue shrinking `ChatViewController.swift` by extracting composer orchestration, transcript data-source glue, and popover presentation helpers.
- Native iOS adaptation using the shared pure models and platform-specific SwiftUI chrome.
