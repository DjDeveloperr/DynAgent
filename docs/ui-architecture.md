# DynAgent UI Architecture

## Current Shared Mac Components

- `DesignSystem.swift`: shared typography, colors, radius, spacing, and paragraph tokens. Add visual constants here before introducing one-off styling in feature controllers.
- `ChromeControls.swift`: reusable AppKit chrome controls, currently `ChromeIconButton` and `ComposerMenuChrome`.
- `AppMenuChrome.swift`: tested AppKit main-menu command chrome for app, file, edit, and window menus.
- `AppToolbarChrome.swift`: tested AppKit toolbar identifiers and chrome builders for navigation, native actions, Git scope, and chat-title controls.
- `DetachedChatWindowController.swift`: reusable AppKit controller for secondary chat windows that share chat rendering and title updates without the sidebar/git chrome.
- `ChatActionMenuChrome.swift`: tested AppKit chat-title action menu construction for pin, rename, archive, and detached-window actions.
- `ChatEmptyStateChrome.swift`: tested AppKit new-chat empty-state title/subtitle/action chrome and liquid-glass action wrappers.
- `ChatHeaderChrome.swift`: tested AppKit in-chat title and ellipsis action-button styling/placement.
- `ChatViewChrome.swift`: tested AppKit root canvas, top border, composer readable-width positioning, and empty-state placement constraints.
- `ChatTitleModel.swift`: tested shared chat title trimming/fallback and generated-title acceptance policy for window titles, toolbar labels, chat headers, and dock recent entries.
- `ChatTitleGenerationCoordinator.swift`: tested async title-generation bridge for accepted-title filtering, conversation title mutation, and callback delivery.
- `ChatPresentationModel.swift`: tested pure chat presentation decisions for transcript render-cache reuse, loading shell labels, and empty-state visibility/subtitles.
- `SettingsOverlayChrome.swift`: tested AppKit settings pill, settings/usage menu, and settings sheet chrome.
- `MarkdownRenderer.swift`: tested markdown rendering for chat text, links, inline code, bullets, code fences, and directive tokens.
- `GitDiffModel.swift`: tested pure parser for git diff sections, line numbers, metadata filtering, and hunk separator rows.
- `GitDiffLayoutModel.swift`: tested pure layout model for diff row heights, visible row lookup, file header lookup, and collapsed file sections.
- `GitDiffViews.swift`: reusable AppKit diff document/header/gutter views that consume the diff parser and layout model.
- `GitActionModel.swift`: tested git action labels, modal sizing, pending-status text, and commit request payload helpers.
- `GitActionChrome.swift`: reusable AppKit git action sheet/panel chrome for commit, push, branch, and PR actions.
- `GitPanelChrome.swift`: tested AppKit Git panel header, scope control, diff scroll, PR/status, and root layout chrome.
- `GitPanelModel.swift`: tested git status and pull-request presentation model for branch labels, diff text, changed-file counts, and PR summaries.
- `ShellToolModel.swift`: tested command summarizer and command-title model for shell tool rows.
- `EditToolModel.swift`: tested edit-tool parser and title model for grouped editing rows and popout diff data.
- `TranscriptTurnModel.swift`: tested turn-planning model for prompt/steer boundaries, active-turn detection, active-turn expansion, final-response collapse, timestamps, and large-thread trimming.
- `TranscriptTurnRenderModel.swift`: tested turn-render decision model for active, collapsed, and expanded transcript turn row plans.
- `TranscriptTurnRenderer.swift`: tested AppKit bridge that applies turn-render plans to transcript rows, grouped tool rows, work dividers, and final footers.
- `TranscriptRenderModel.swift`: tested row data-source model for render-cache fingerprints, turn batching, shell tool grouping, and completed edit grouping.
- `TranscriptRenderSessionModel.swift`: tested render-session state for transcript cache reuse, generation invalidation, shell loading, async batch guards, and bulk-loading completion.
- `TranscriptLiveUpdateModel.swift`: tested streaming update policy for markdown render throttling and stateful autoscroll scheduling.
- `TranscriptScrollCoordinator.swift`: tested AppKit bridge for throttled transcript autoscroll, pending-scroll scheduling, layout-before-idle-scroll, and bottom-offset math.
- `ConversationTurnMutationModel.swift`: tested pure mutation model for completing the latest prompt turn, closing open tool rows, and reconciling pending/completed steer notices.
- `ChatStreamMutationModel.swift`: tested streaming prompt, assistant, error, tool, and final-response mutations used by chat event handling.
- `ChatStreamStartModel.swift`: tested turn-start mutation model for harness/model locking, prompt insertion, thinking status, timestamps, and title-generation decisions.
- `ChatStreamEventCoordinator.swift`: tested stream-event coordinator for assistant cache reuse, tool completion refreshes, deterministic finalization, and stop-error suppression.
- `ChatAssistantStreamCache.swift`: tested live assistant-message cache for per-conversation streaming, visible-chat adoption, and stale fallback clearing.
- `ChatStreamRegistry.swift`: tested stream lifecycle registry for active conversation ids, cancellable tasks, and per-thread stop-error suppression.
- `ChatActivityThrottleModel.swift`: tested per-conversation activity emit reducer that limits noisy streaming refreshes while allowing forced updates.
- `ChatToolRefreshModel.swift`: tested completed-tool and stream-done refresh policy for debounced grouped tool re-renders.
- `ChatActivityCoordinator.swift`: tested streaming-path coordinator for throttled activity emits and cancellable delayed grouped-tool refreshes.
- `WorkDividerModel.swift`: tested label/duration model for active and completed Codex-style work dividers.
- `TranscriptChrome.swift`: reusable AppKit transcript text, full-width row lifecycle/stack helpers, loading shell rows, shimmer/thinking rows, work-divider, edit-stat, and transcript row views.
- `TranscriptViewportChrome.swift`: tested AppKit transcript scroll/document/stack setup and width-tracking constraints for the loaded-thread layout invariant.
- `ChatViewportMetricsChrome.swift`: tested AppKit runtime metrics payload for chat viewport, scroll/document, transcript, composer, and root subview geometry.
- `ChatViewportLayoutChrome.swift`: tested AppKit bridge that applies width-critical scroll frame, document width, and composer bottom-inset corrections during chat layout.
- `TranscriptRowFactory.swift`: tested row factory that maps chat messages to AppKit row chrome and returns controller metadata for labels, clickable tool views, and edit stats.
- `TranscriptRowRegistry.swift`: tested transcript interaction registry for message labels, clickable tool rows, edit stats, copy text, and live markdown render throttling.
- `TranscriptInteractionCoordinator.swift`: tested AppKit bridge for transcript row registration, clickable tool popovers, grouped edit popovers, final-footer copy actions, and shimmer pin callbacks.
- `TranscriptToolChrome.swift`: reusable AppKit shell/edit/inline tool rows, grouped tool collapse controls, and inline edit diff popover blocks.
- `TranscriptGroupedToolRowChrome.swift`: tested AppKit helper for appending grouped shell and edit tool rows into the transcript while preserving edit-file popover callbacks.
- `TranscriptToolFormatter.swift`: tested attributed title, preview, grouping, and icon-name formatting for transcript tool rows.
- `TranscriptPopoverChrome.swift`: reusable AppKit popover content and presenter for tool details, shell output, and edit diffs.
- `TranscriptToolPopoverPresenter.swift`: tested transcript tool popover planner for edit-vs-detail content selection and stable click anchors.
- `TranscriptToolPopoverCoordinator.swift`: tested AppKit coordinator that owns the tool popover and bridges transcript tool/edit clicks to popover plans.
- `SidebarModel.swift`: tested pure grouping model for pinned chats, projectless chats, project workspaces, archived filtering, and recency ordering.
- `SidebarRowModel.swift`: tested pure row-presentation model for short relative timestamps, workspace/chat tooltip content, worktree indicators, and working/pinned/unread state.
- `SidebarLayoutModel.swift`: tested sidebar width band used by the macOS split view.
- `SidebarArchiveConfirmationModel.swift`: tested archive confirmation reducer for first-click confirmation, second-click archive, hover-out cancellation, and reload decisions.
- `SidebarArchiveConfirmationCoordinator.swift`: tested AppKit-timer bridge for sidebar archive confirmation, hover-out debounce cancellation, and reload triggering.
- `SidebarHoverTipCoordinator.swift`: tested AppKit-timer bridge for delayed sidebar hover tooltips, cancellation, and stale-row suppression.
- `DesignSystem.swift`: shared AppKit design tokens for chrome fonts, radii, spacing, and semantic fill/backdrop colors used by reusable UI components.
- `SidebarChrome.swift`: reusable AppKit sidebar row, scroll-hover clearing, spinner, and liquid tooltip chrome.
- `SidebarRowsChrome.swift`: tested AppKit builders for reusable sidebar action rows, section headers, workspace rows, empty workspace labels, and show-more rows.
- `SidebarConversationRowChrome.swift`: tested AppKit conversation-row builder for title/time/worktree/spinner affordances, hover action state, and pin/archive callbacks.
- `SearchOverlayModel.swift`: tested pure search overlay model for bounded chat/message matching, recency sorting, result limiting, and row detail labels.
- `SearchOverlayChrome.swift`: tested AppKit search overlay panel, backdrop, padded search field, scroll/stack layout, and result-row chrome.
- `ComposerModel.swift`: tested composer behavior model for model/reasoning menu data, picker selection, draft keys, attachment message text, draft snapshots, attachment normalization, context state, and send/stop state.
- `ComposerSelectionModel.swift`: tested composer model/reasoning selection state for Codex availability, harness sync plans, model-list sync plans, conversation adoption actions, desired-model adoption, fallback selection, and picker updates.
- `ComposerMenuCoordinator.swift`: tested AppKit bridge for composer harness/model/reasoning popup orchestration, Codex nested menus, thread model adoption, and locked existing-thread menu state.
- `ComposerSessionModel.swift`: tested composer session state transitions for attachment add/remove, draft restoration, placeholder visibility, and send clearing.
- `ComposerDraftCoordinator.swift`: tested AppKit-free coordinator for composer attachment state, draft save/restore/clear, and debounced draft persistence.
- `ComposerAttachmentCoordinator.swift`: tested AppKit bridge that combines composer draft persistence, attachment strip rendering, and remove-button identity mapping.
- `ChatSendModel.swift`: tested prompt/stop/steer send-action routing, attachment-only sends, native Codex steering, and queued steer prompt joining.
- `ComposerDraftStore.swift`: tested draft persistence store for preserving composer text and attachments across chat switches and hot reloads.
- `ComposerChrome.swift`: reusable AppKit composer text input, context ring, attachment chips/strip rendering, Codex nested model/reasoning menus, menu label styling/state application, send/attachment buttons, composer card surface layout, send-state application, and stable footer sizing.
- `ChatComposerChrome.swift`: tested chat-specific composer assembly for text input callbacks, harness/model/reasoning menu wiring, footer controls, and composer surface installation.
- `MobilePresentationModel.swift`: tested shared iOS presentation bridge for mobile composer labels/send state and mobile tool rows.
- `NavigationHistoryModel.swift`: tested identity-based back/forward stack behavior for chat navigation.
- `AppNavigationCoordinator.swift`: tested AppKit-free app navigation bridge for visible-conversation gating, draft/new-chat transitions, and back/forward state.
- `AppDetachedChatWindowCoordinator.swift`: tested detached-window lifecycle bridge for creation, close callbacks, per-conversation refresh, and archive cleanup.
- `AppSearchOverlayCoordinator.swift`: tested search-overlay presentation bridge for overlay creation, retention, and repeat presentation.
- `AppControlPollingCoordinator.swift`: tested agent-control polling bridge for terminal writes/output reports, browser navigation state reports, eval results, missing-target skips, and active Codex refresh hooks.
- `AppUsageCoordinator.swift`: tested usage/context loader for settings-menu credit labels, unavailable-credit fallback, context-ring updates, and iOS-reusable usage snapshots.
- `AppModelCatalogCoordinator.swift`: tested model-list cache and loader for harness fallback ids, hot-reload restoration, startup defaults, and async model refreshes.
- `AppChatActionCoordinator.swift`: tested chat action bridge for rename/pin/archive mutation, Codex app-server sync scheduling, archive id storage, and Codex stub cleanup.
- `AppConversationIndexModel.swift`: tested visible-conversation de-duping, restored-selection lookup, dock recent payloads, and unread finished-thread counts.
- `AppDockStateCoordinator.swift`: tested Dock-state bridge for recent-thread JSON payloads and unread badge labels.
- `AppActivityRefreshModel.swift`: tested app activity throttling policy for sidebar rebuilds, dock updates, quota refreshes, git reloads, persistence, and remote Codex history polling.
- `AppCodexHistoryModel.swift`: tested Codex history refresh eligibility, history-message mapping, metadata preservation, and loaded-thread status detection.
- `AppCodexHistoryRefreshCoordinator.swift`: tested Codex history loading bridge for synchronous in-flight gating, history mutation, stale-update preservation, and failed-load cleanup.
- `AppCodexThreadListCoordinator.swift`: tested Codex thread-list loader for projectless threads, workspace/worktree grouping, local conversation reuse, archived filtering, and unavailable endpoint preservation.
- `AppCodexThreadStubModel.swift`: tested Codex thread stub builder for workspace/projectless threads, archive filtering, pinned state, reuse, limits, and latest-history reload markers.
- `AppWorkspaceIndexModel.swift`: tested Codex workspace index merge/filter model for preserving local workspaces and stable active workspace selection.
- `AppWorktreeCoordinator.swift`: tested worktree bridge for workspace path detection, branch-name normalization, create-result parsing, and create failure handling.
- `AppSidebarSyncModel.swift`: tested Codex sidebar-state bridge for width clamping/correction payloads, resize tolerance, and collapsed section/workspace payloads.
- `AppLayoutMetricsCoordinator.swift`: tested layout metrics persistence bridge for live width-regression diagnostics and hot-reload verification payloads.
- `AppSplitLayoutChrome.swift`: tested AppKit builder for the top-level sidebar/main/git split, split item sizing priorities, collapsed git inspector default, frame-managed root hosting, and autoresizing installation.
- `AppHotStateModel.swift`: tested hot-reload state serializer/restorer for conversations, active Codex thread status, workspace refs, model cache, and selection.
- `AppHotStateCoordinator.swift`: tested hot-reload dictionary bridge for restore, immediate saves, debounced saves, and pending-save cancellation.
- `MainWindowFrameModel.swift`: tested main-window frame state model for initial saved-frame restoration, requested/applied frame tracking, live-resize state, non-user shrink proposals, and startup requested-frame retry suppression after manual resize.
- `ChatLayoutModel.swift`: shared chat-column constants, readable-width cap, and inspector-aware split sizing.
- `ChatViewportLayoutModel.swift`: tested chat viewport layout policy for scroll frame pinning, document-width correction, and composer bottom inset updates.
- `WindowLayoutModel.swift`: tested pure layout model for main window frame restoration, root content bounds, wide fallback sizing, split divider planning, metrics payloads, and post-load width invariants.
- `WindowLayoutChrome.swift`: tested AppKit bridge for applying usable window limits, pinning root/split frames to content bounds, applying split plans, and capturing frame metrics.
- `MainLayoutStabilizer.swift`: tested AppKit orchestration for the post-load/resize/git-toggle layout pass that keeps the root split, workspace tile, and chat view tracking the real window width.
- `WindowHosting.swift`: non-fitting full-window host and split-view pinning used by the hot-reloadable macOS UI.
- `WorkspaceAreaChrome.swift`: tested workspace root split setup, forced frame layout, and width metrics for center-pane fill invariants.
- `WorkspacePanelChrome.swift`: reusable AppKit workspace tile chrome and root split pinning for chat, terminal, and browser panels.

Feature controllers should keep behavior and orchestration, not reusable visual/parser logic. When a controller grows a reusable widget, parser, or display model, extract it into a small file and add a focused test before expanding behavior.

## Mac Layout Contract

- The macOS root is a full-window `NSSplitView` hosted directly by `FullWindowHostView`.
- The left sidebar is a custom AppKit stack-based surface with a fixed practical width band capped tightly enough that restored Codex sidebar state cannot steal the readable chat column.
- The center chat/workspace surface owns transcript rendering, composer state, and panel layout. The workspace canvas fills the split item; transcript and composer use a centered readable column without advertising a fitted width back to the window.
- The right git panel is a collapsible split item; opening it preserves a readable center width before growing the inspector. The git diff document uses `GitDiffModel` for all parsing.
- Hot reload must preserve the window size and keep the content split filling the visible window. Current verified invariant: after a fresh relaunch and Codex history render on a 1512px-wide visible screen, `windowWidth == contentViewWidth == splitViewWidth == 1452`, `mainSplitItemWidth == workspaceWidth == chatViewWidth == 1128`, and `workspaceWidthSlack == 0`.

## iOS Adaptation Contract

The iOS app should share behavior and visual language, but not copy the desktop split layout directly:

- Left sidebar -> leading drawer containing New Chat, Search, pinned chats, projectless chats, and projects/workspaces.
- Center chat -> primary navigation destination with the composer pinned to the bottom and a max-width transcript only on regular-width iPad layouts.
- Right git panel -> trailing drawer or sheet with the same `GitDiffModel` sections and diff-row semantics.
- Settings/search/commit overlays -> native SwiftUI sheets or presentation detents, using the same labels and action order as macOS.
- Composer -> same model/reasoning/context/send ordering, with attachments previewed above the text field and keyboard-safe bottom padding.

Pure models should move toward platform-neutral Swift where possible (`MarkdownRenderer`, `GitDiffModel`, `GitDiffLayoutModel`, `GitActionModel`, `GitPanelModel`, `ShellToolModel`, `EditToolModel`, `TranscriptTurnModel`, `TranscriptTurnRenderModel`, `TranscriptRenderModel`, `TranscriptRenderSessionModel`, `TranscriptLiveUpdateModel`, `ConversationTurnMutationModel`, `ChatStreamMutationModel`, `ChatStreamStartModel`, `ChatStreamRegistry`, `ChatActivityThrottleModel`, `ChatToolRefreshModel`, `WorkDividerModel`, `SidebarModel`, `SidebarRowModel`, `SidebarArchiveConfirmationModel`, `SearchOverlayModel`, `ComposerModel`, `ComposerSelectionModel`, `ComposerMenuCoordinator`, `ComposerSessionModel`, `ComposerDraftCoordinator`, `ChatSendModel`, `ComposerDraftStore`, `MobilePresentationModel`, `NavigationHistoryModel`, `AppNavigationCoordinator`, `AppUsageCoordinator`, `AppModelCatalogCoordinator`, `AppChatActionCoordinator`, `AppConversationIndexModel`, `AppActivityRefreshModel`, `AppCodexHistoryModel`, `AppCodexHistoryRefreshCoordinator`, `AppCodexThreadListCoordinator`, `AppCodexThreadStubModel`, `AppWorkspaceIndexModel`, `AppWorktreeCoordinator`, `AppSidebarSyncModel`, `AppLayoutMetricsCoordinator`, `AppHotStateModel`, `MainWindowFrameModel`, `ChatLayoutModel`, `ChatTitleModel`, `ChatTitleGenerationCoordinator`, `ChatPresentationModel`, `WindowLayoutModel`). AppKit-only controls such as `TranscriptRowRegistry` remain in macOS files; iOS should build SwiftUI equivalents using the same tokens and model outputs.

## Verification Gates

- `cd Packages/DynAgentMac && swift build --disable-sandbox --product DynAgentUI`
- `cd Packages/DynAgentMac && swift test --disable-sandbox`
- Hot reload the running app with `kill -USR1 $(pgrep -x DynAgent | head -1)` and verify layout metrics in `~/.dynagent/ui-layout-metrics.json`.
- For width safety, verify `windowWidth == splitViewWidth` and chat/workspace width remains the available center width when git is collapsed.

## Next Extraction Targets

- Continue shrinking `ChatViewController.swift` by extracting composer orchestration, transcript data-source glue, and popover presentation helpers.
- Native iOS adaptation using the shared pure models and platform-specific SwiftUI chrome.
