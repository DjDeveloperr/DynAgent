# DynAgent UI Architecture

## Current Shared Mac Components

- `DesignSystem.swift`: shared typography, colors, and paragraph tokens. Add visual constants here before introducing one-off styling in feature controllers.
- `ChromeControls.swift`: reusable AppKit chrome controls, currently `ChromeIconButton` and `ComposerMenuChrome`.
- `AppMenuChrome.swift`: tested AppKit main-menu command chrome for app, file, edit, and window menus.
- `AppToolbarChrome.swift`: tested AppKit toolbar identifiers and chrome builders for navigation, native actions, Git scope, and chat-title controls.
- `ChatActionMenuChrome.swift`: tested AppKit chat-title action menu construction for pin, rename, archive, and detached-window actions.
- `ChatEmptyStateChrome.swift`: tested AppKit new-chat empty-state title/subtitle/action chrome and liquid-glass action wrappers.
- `ChatHeaderChrome.swift`: tested AppKit in-chat title and ellipsis action-button styling/placement.
- `ChatPresentationModel.swift`: tested pure chat presentation decisions for transcript render-cache reuse, loading shell labels, and empty-state visibility/subtitles.
- `SettingsOverlayChrome.swift`: tested AppKit settings pill, settings/usage menu, and settings sheet chrome.
- `MarkdownRenderer.swift`: tested markdown rendering for chat text, links, inline code, bullets, code fences, and directive tokens.
- `GitDiffModel.swift`: tested pure parser for git diff sections, line numbers, metadata filtering, and hunk separator rows.
- `GitDiffLayoutModel.swift`: tested pure layout model for diff row heights, visible row lookup, file header lookup, and collapsed file sections.
- `GitDiffViews.swift`: reusable AppKit diff document/header/gutter views that consume the diff parser and layout model.
- `GitActionModel.swift`: tested git action labels, modal sizing, pending-status text, and commit request payload helpers.
- `GitActionChrome.swift`: reusable AppKit git action sheet/panel chrome for commit, push, branch, and PR actions.
- `GitPanelModel.swift`: tested git status and pull-request presentation model for branch labels, diff text, changed-file counts, and PR summaries.
- `ShellToolModel.swift`: tested command summarizer and command-title model for shell tool rows.
- `EditToolModel.swift`: tested edit-tool parser and title model for grouped editing rows and popout diff data.
- `TranscriptTurnModel.swift`: tested turn-planning model for prompt/steer boundaries, active-turn detection, active-turn expansion, final-response collapse, timestamps, and large-thread trimming.
- `TranscriptRenderModel.swift`: tested row data-source model for render-cache fingerprints, turn batching, shell tool grouping, and completed edit grouping.
- `TranscriptLiveUpdateModel.swift`: tested streaming update policy for markdown render throttling and autoscroll throttling.
- `ConversationTurnMutationModel.swift`: tested pure mutation model for completing the latest prompt turn, closing open tool rows, and reconciling pending/completed steer notices.
- `WorkDividerModel.swift`: tested label/duration model for active and completed Codex-style work dividers.
- `TranscriptChrome.swift`: reusable AppKit transcript text, shimmer/thinking rows, work-divider, edit-stat, and transcript row views.
- `TranscriptRowFactory.swift`: tested row factory that maps chat messages to AppKit row chrome and returns controller metadata for labels, clickable tool views, and edit stats.
- `TranscriptToolChrome.swift`: reusable AppKit shell/edit/inline tool rows, grouped tool collapse controls, and inline edit diff popover blocks.
- `TranscriptToolFormatter.swift`: tested attributed title, preview, grouping, and icon-name formatting for transcript tool rows.
- `TranscriptPopoverChrome.swift`: reusable AppKit popover content and presenter for tool details, shell output, and edit diffs.
- `TranscriptToolPopoverPresenter.swift`: tested transcript tool popover planner for edit-vs-detail content selection and stable click anchors.
- `SidebarModel.swift`: tested pure grouping model for pinned chats, projectless chats, project workspaces, archived filtering, and recency ordering.
- `SidebarRowModel.swift`: tested pure row-presentation model for short relative timestamps, workspace/chat tooltip content, worktree indicators, and working/pinned/unread state.
- `SidebarChrome.swift`: reusable AppKit sidebar row, scroll-hover clearing, spinner, and liquid tooltip chrome.
- `SearchOverlayModel.swift`: tested pure search overlay model for bounded chat/message matching, recency sorting, result limiting, and row detail labels.
- `ComposerModel.swift`: tested composer behavior model for model/reasoning menu data, picker selection, draft keys, attachment message text, draft snapshots, attachment normalization, context state, and send/stop state.
- `ComposerDraftStore.swift`: tested draft persistence store for preserving composer text and attachments across chat switches and hot reloads.
- `ComposerChrome.swift`: reusable AppKit composer text input, context ring, attachment chips/strip rendering, Codex nested model/reasoning menus, menu label styling, send/attachment buttons, and stable footer sizing.
- `MobilePresentationModel.swift`: tested shared iOS presentation bridge for mobile composer labels/send state and mobile tool rows.
- `NavigationHistoryModel.swift`: tested identity-based back/forward stack behavior for chat navigation.
- `AppConversationIndexModel.swift`: tested visible-conversation de-duping, restored-selection lookup, dock recent payloads, and unread finished-thread counts.
- `AppWorkspaceIndexModel.swift`: tested Codex workspace index merge/filter model for preserving local workspaces and stable active workspace selection.
- `AppSidebarSyncModel.swift`: tested Codex sidebar-state bridge for width clamping/correction payloads and collapsed section/workspace payloads.
- `AppHotStateModel.swift`: tested hot-reload state serializer/restorer for conversations, active Codex thread status, workspace refs, model cache, and selection.
- `ChatLayoutModel.swift`: shared chat-column constants and inspector-aware split sizing.
- `WindowLayoutModel.swift`: tested pure layout model for main window frame restoration, root content bounds, wide fallback sizing, split divider planning, metrics payloads, and post-load width invariants.
- `WindowLayoutChrome.swift`: tested AppKit bridge for applying usable window limits, pinning root/split frames to content bounds, applying split plans, and capturing frame metrics.
- `WindowHosting.swift`: full-window host and split-view pinning used by the hot-reloadable macOS UI.
- `WorkspacePanelChrome.swift`: reusable AppKit workspace tile chrome and root split pinning for chat, terminal, and browser panels.

Feature controllers should keep behavior and orchestration, not reusable visual/parser logic. When a controller grows a reusable widget, parser, or display model, extract it into a small file and add a focused test before expanding behavior.

## Mac Layout Contract

- The macOS root is a full-window `NSSplitView` hosted directly by `FullWindowHostView`.
- The left sidebar is a custom AppKit stack-based surface with a fixed practical width band.
- The center chat/workspace surface owns transcript rendering, composer state, and panel layout. Transcript and composer content fill the center split item without advertising a fitted width back to the window.
- The right git panel is a collapsible split item; opening it preserves a readable center width before growing the inspector. The git diff document uses `GitDiffModel` for all parsing.
- Hot reload must preserve the window size and keep the content split filling the visible window. Current verified invariant: content width, split width, and visible window width match after reload.

## iOS Adaptation Contract

The iOS app should share behavior and visual language, but not copy the desktop split layout directly:

- Left sidebar -> leading drawer containing New Chat, Search, pinned chats, projectless chats, and projects/workspaces.
- Center chat -> primary navigation destination with the composer pinned to the bottom and a max-width transcript only on regular-width iPad layouts.
- Right git panel -> trailing drawer or sheet with the same `GitDiffModel` sections and diff-row semantics.
- Settings/search/commit overlays -> native SwiftUI sheets or presentation detents, using the same labels and action order as macOS.
- Composer -> same model/reasoning/context/send ordering, with attachments previewed above the text field and keyboard-safe bottom padding.

Pure models should move toward platform-neutral Swift where possible (`MarkdownRenderer`, `GitDiffModel`, `GitDiffLayoutModel`, `GitActionModel`, `GitPanelModel`, `ShellToolModel`, `EditToolModel`, `TranscriptTurnModel`, `TranscriptRenderModel`, `TranscriptLiveUpdateModel`, `ConversationTurnMutationModel`, `WorkDividerModel`, `SidebarModel`, `SidebarRowModel`, `SearchOverlayModel`, `ComposerModel`, `ComposerDraftStore`, `MobilePresentationModel`, `NavigationHistoryModel`, `AppConversationIndexModel`, `AppWorkspaceIndexModel`, `AppSidebarSyncModel`, `AppHotStateModel`, `ChatLayoutModel`, `ChatPresentationModel`, `WindowLayoutModel`). AppKit-only controls remain in macOS files; iOS should build SwiftUI equivalents using the same tokens and model outputs.

## Verification Gates

- `cd Packages/DynAgentMac && swift build --disable-sandbox --product DynAgentUI`
- `cd Packages/DynAgentMac && swift test --disable-sandbox`
- Hot reload the running app with `kill -USR1 $(pgrep -x DynAgent | head -1)` and verify layout metrics in `~/.dynagent/ui-layout-metrics.json`.
- For width safety, verify `windowWidth == splitViewWidth` and chat/workspace width remains the available center width when git is collapsed.

## Next Extraction Targets

- Continue shrinking `ChatViewController.swift` by extracting composer orchestration, transcript data-source glue, and popover presentation helpers.
- Native iOS adaptation using the shared pure models and platform-specific SwiftUI chrome.
