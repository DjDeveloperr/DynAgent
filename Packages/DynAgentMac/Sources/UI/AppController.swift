import AppKit

final class AppController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    private let client = AgentClient()
    private let window: NSWindow
    private let hotStateCoordinator: AppHotStateCoordinator

    private let sidebar = SidebarViewController()
    private let chat = ChatViewController()
    private let workspaceArea = WorkspaceAreaViewController()
    private let gitPanel = GitPanelViewController()
    /// Always-available offscreen browser so the agent can navigate/eval without an open panel.
    private let headlessBrowser = BrowserPanel()
    private weak var splitView: NSSplitView?
    private var rootContentController: NSViewController?
    private var rootSplitController: NSSplitViewController?
    private var sidebarItem: NSSplitViewItem!
    private var gitItem: NSSplitViewItem!
    private let settingsPill = NSVisualEffectView()
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let chatTitleLabel = NSTextField(labelWithString: "New Chat")
    private let chatMenuButton = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Chat actions")!, target: nil, action: nil)
    private let navBackButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!, target: nil, action: nil)
    private let navForwardButton = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!, target: nil, action: nil)
    private var usageRemainingTitle = "Usage remaining"

    private var conversations: [Conversation] = []
    private var draft: Conversation?
    /// Codex's existing threads per workspace path (resumable, not persisted locally).
    private var codexStubs: [String: [Conversation]] = [:]
    private var archivedCodexIds = Set(UserDefaults.standard.stringArray(forKey: "archivedCodexIds") ?? [])
    /// Worktree cwds belonging to each top-level workspace path (threads grouped under the parent).
    private var worktreesByPath: [String: [String]] = [:]
    /// Cached model id lists per harness for instant switching.
    private var modelCache: [Harness: [String]] = [:]
    private var codexRefreshInFlight = Set<String>()
    private var pendingRenderConversationId: String?
    private var workspaceRefs: [WorkspaceRef] = []
    private var primaryPath = FileManager.default.currentDirectoryPath
    private var active = WorkspaceRef(name: "Workspace", path: FileManager.default.currentDirectoryPath)
    private var controlTimer: Timer?
    private var attached = false
    private let selectedConversationKey = "selectedConversationId"
    private let mainWindowFrameKey = "DynAgentMainWindowFrame"
    private var searchOverlay: SearchOverlayController?
    private var dockObserver: NSObjectProtocol?
    private var splitResizeObserver: NSObjectProtocol?
    private var lastSyncedSidebarWidth: CGFloat = 0
    private var lastActiveHistoryRefresh: Double = 0
    private var lastActivitySidebarRefresh: [String: Double] = [:]
    private var lastActivityGitReload: [String: Double] = [:]
    private var detachedChatWindows: [DetachedChatWindowController] = []
    private let projectlessCodexKey = "__codex_projectless__"
    private var navigationHistory = NavigationHistoryModel<Conversation>()
    private var mainWindowFrameState = MainWindowFrameState()
    private var pendingWindowFrameRestore = false

    init(window: NSWindow, hotState: NSMutableDictionary? = nil) {
        self.window = window
        hotStateCoordinator = AppHotStateCoordinator(hotState: hotState)
        super.init()
    }

    func attach() {
        guard !attached else { return }
        attached = true
        UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames dynagent.split")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame main")
        NSApp.mainMenu = buildMenu()
        chat.client = client
        chat.onActivity = { [weak self] c in self?.refreshActivity(c) }
        chat.onTitleGenerated = { [weak self] c, title in
            self?.rebuildGroups(select: c)
            self?.updateWindowTitle(c)
            self?.persist()
        }
        chat.onLayoutChanged = { [weak self] in
            self?.stabilizeMainLayout(reason: "chat-layout")
        }
        chat.onHarnessChanged = { [weak self] harness in
            self?.loadModelsForHarness(harness)
        }
        chat.onAddWorkspace = { [weak self] in self?.addWorkspace() }
        chat.onNewWorktree = { [weak self] in self?.addWorktree() }
        chat.onChatMenu = { [weak self] sender in self?.showChatTitleMenu(sender) }
        gitPanel.client = client
        if !restoreHotState() {
            conversations = Store.load()
            codexStubs = Store.loadCodexStubs()
            for stubs in codexStubs.values {
                for c in stubs { c.needsLoad = true }
            }
            // Drop legacy per-worktree workspace entries; worktrees now group under their parent.
            workspaceRefs = Store.loadWorkspaces().filter { !$0.path.contains("/worktrees/") }
        }
        sidebar.onSelect = { [weak self] c in self?.selectConversation(c) }
        sidebar.onSelectWorkspace = { [weak self] w in self?.selectWorkspace(w.path) }
        sidebar.onNewChat = { [weak self] w in self?.selectWorkspace(w.path) }
        sidebar.onGlobalNewChat = { [weak self] in self?.newChat() }
        sidebar.onAddWorkspace = { [weak self] in self?.addWorkspace() }
        sidebar.onSearch = { [weak self] in self?.showSearchOverlay() }
        sidebar.onRename = { [weak self] c in self?.renameConversation(c) }
        sidebar.onFork = { [weak self] c in self?.forkConversation(c) }
        sidebar.onPin = { [weak self] c in self?.togglePin(c) }
        sidebar.onArchive = { [weak self] c in self?.archiveConversation(c) }
        sidebar.onProjectsCollapsedChanged = { [weak self] collapsed in self?.setCodexSection("threads", collapsed: collapsed) }
        sidebar.onPinnedCollapsedChanged = { [weak self] collapsed in self?.setCodexSection("pinned", collapsed: collapsed) }
        sidebar.onChatsCollapsedChanged = { [weak self] collapsed in self?.setCodexSection("chats", collapsed: collapsed) }
        sidebar.onWorkspaceCollapsedChanged = { [weak self] path, collapsed in self?.setCodexWorkspace(path, collapsed: collapsed) }
        dockObserver = NotificationCenter.default.addObserver(forName: Notification.Name("DynAgentOpenConversation"), object: nil, queue: .main) { [weak self] note in
            guard let id = note.object as? String else { return }
            self?.openConversationFromDock(id: id)
        }

        let split = RootSplitViewController()
        rootSplitController = split
        splitView = split.splitView
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = nil
        splitResizeObserver = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split.splitView, queue: .main) { [weak self] note in
            self?.splitViewDidResizeSubviews(note)
        }
        let side = NSSplitViewItem(viewController: sidebar)
        sidebarItem = side
        side.minimumThickness = SidebarLayoutModel.minimumWidth
        side.maximumThickness = SidebarLayoutModel.maximumWidth
        side.canCollapse = true
        side.holdingPriority = NSLayoutConstraint.Priority(251)
        side.preferredThicknessFraction = 0
        split.addSplitViewItem(side)
        workspaceArea.cwdProvider = { [weak self] in self?.active.path ?? FileManager.default.currentDirectoryPath }
        workspaceArea.setPrimary(chat.view, title: "")
        let mainItem = NSSplitViewItem(viewController: workspaceArea)
        mainItem.minimumThickness = 360
        mainItem.maximumThickness = WindowLayoutChrome.defaultMaximumWindowSize.width
        mainItem.holdingPriority = NSLayoutConstraint.Priority(1)
        split.addSplitViewItem(mainItem)
        gitItem = NSSplitViewItem(viewController: gitPanel)
        gitItem.minimumThickness = 300; gitItem.maximumThickness = 520; gitItem.canCollapse = true
        gitItem.preferredThicknessFraction = 0.30
        gitItem.holdingPriority = NSLayoutConstraint.Priority(249)
        split.addSplitViewItem(gitItem)
        gitItem.isCollapsed = true

        window.title = "DynAgent"
        DispatchQueue.main.async { [weak self] in self?.window.subtitle = "" }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        unlockWindowSizing()
        let desiredFrame = initialMainWindowFrame()
        window.delegate = self
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        setMainWindowFrame(desiredFrame)
        split.splitView.translatesAutoresizingMaskIntoConstraints = true
        split.view.frame = NSRect(origin: .zero, size: desiredFrame.size)
        split.view.autoresizingMask = [.width, .height]
        split.splitView.frame = split.view.bounds
        split.splitView.autoresizingMask = [.width, .height]
        rootContentController = split
        window.contentViewController = split
        split.deactivateInternalSplitSizingConstraints()
        window.toolbar = makeToolbar()
        updateNavigationControls()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installSettingsOverlay(over: sidebar.view)
        for delay in [0.0, 0.75, 1.6, 3.0, 4.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                if WindowLayoutModel.shouldRestoreAppliedFrame(
                    current: self.window.frame,
                    applied: self.mainWindowFrameState.appliedFrame
                ) {
                    self.setMainWindowFrame(self.mainWindowFrameState.appliedFrame)
                }
                self.applyMainLayoutStabilization()
                self.writeLayoutMetrics()
            }
        }

        if let firstWorkspace = workspaceRefs.first {
            primaryPath = firstWorkspace.path
            active = firstWorkspace
        }
        let initialSelection = restoredConversation()
        rebuildGroups(select: initialSelection)
        if let initialSelection {
            selectConversation(initialSelection)
        }

        Task { @MainActor in
            if let info = try? await client.cwd() {
                primaryPath = info.cwd
                active = WorkspaceRef(name: info.name, path: info.cwd)
            }
            if !workspaceRefs.contains(where: { $0.path == primaryPath }) {
                workspaceRefs.insert(active, at: 0)
                Store.saveWorkspaces(workspaceRefs)
            }
            await syncCodexWorkspaceIndex()
            await syncCodexSidebarState()
            let codexModels = (try? await client.codexModels())?.map(\.id) ?? ["gpt-5.5"]
            modelCache[.codex] = codexModels
            chat.applyDefaults(harness: .codex, model: codexModels.first ?? "gpt-5.5")
            chat.setModels(codexModels)
            let dynModels = (try? await client.models())?.map(\.id) ?? ["auto"]
            modelCache[.dynagent] = dynModels
            rebuildGroups(select: chat.conversation)
            if chat.conversation == nil {
                if let initial = restoredConversation() { selectConversation(initial) } else { newChat() }
            }
            loadQuota()
            detectWorktrees()
            saveHotState()
        }

        // Start polling for agent-driven terminal/browser commands
        startControlPolling()
    }

    func detach() {
        guard attached else { return }
        attached = false
        controlTimer?.invalidate()
        controlTimer = nil
        if let dockObserver {
            NotificationCenter.default.removeObserver(dockObserver)
            self.dockObserver = nil
        }
        if let splitResizeObserver {
            NotificationCenter.default.removeObserver(splitResizeObserver)
            self.splitResizeObserver = nil
        }
        persist()
        workspaceArea.resetPanels()
        PanelRegistry.shared.removeAll()
        NSApp.mainMenu = nil
        window.toolbar = nil
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        rootContentController = nil
        rootSplitController = nil
    }

    deinit {
        detach()
    }

    // MARK: Agent control polling

    private func startControlPolling() {
        controlTimer?.invalidate()
        controlTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.processTerminalActions()
                await self.processBrowserActions()
                self.refreshSelectedActiveCodexThreadIfNeeded()
            }
        }
    }

    @MainActor private func processTerminalActions() async {
        let actions = await client.pollTerminalActions()
        for action in actions {
            guard let terminal = PanelRegistry.shared.terminal(action.id) else { continue }
            terminal.write(action.text)
            // Report output back after a short delay
            let termId = action.id ?? terminal.panelId
            let client = client
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak terminal, client] in
                guard let terminal else { return }
                let output = terminal.readBuffer(last: 8000)
                Task { await client.reportTerminalOutput(id: termId, output: output) }
            }
        }
    }

    @MainActor private func processBrowserActions() async {
        let actions = await client.pollBrowserActions()
        for action in actions {
            guard let browser = PanelRegistry.shared.browser(action.id) else { continue }
            switch action.type {
            case "navigate":
                if let url = action.url {
                    browser.load(url)
                    // Report state after navigation settles
                    let client = client
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak browser, client] in
                        guard let browser else { return }
                        let id = action.id ?? browser.panelId
                        Task { await client.reportBrowserState(id: id, url: browser.currentURL, title: browser.pageTitle()) }
                    }
                }
            case "eval":
                if let script = action.script, let resultId = action.resultId {
                    let result = await browser.evaluateJS(script)
                    await client.reportBrowserResult(resultId: resultId, result: result)
                }
            default: break
            }
        }
    }

    private func refreshSelectedActiveCodexThreadIfNeeded() {
        let now = Date().timeIntervalSince1970
        guard let c = chat.conversation,
              AppActivityRefreshModel.shouldRefreshSelectedActiveCodexThread(
                  harness: c.harness,
                  status: c.status,
                  hasLocalStream: chat.hasLocalStream(for: c),
                  now: now,
                  lastRefresh: lastActiveHistoryRefresh
              ) else { return }
        lastActiveHistoryRefresh = now
        refreshCodexHistoryIfNeeded(c, force: true)
    }

    // MARK: Menu bar

    private func buildMenu() -> NSMenu {
        AppMenuChrome.makeMainMenu(
            target: self,
            selectors: AppMenuSelectors(
                newChat: #selector(newChat),
                searchChats: #selector(showSearchFromMenu)
            )
        )
    }

    // MARK: Toolbar

    private func makeToolbar() -> NSToolbar {
        AppToolbarChrome.makeMainToolbar(delegate: self)
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        AppToolbarID.defaultIdentifiers
    }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(t) }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id.rawValue {
        case "navBack":
            item.view = AppToolbarChrome.configureNavigationButton(navBackButton, symbol: "chevron.left", target: self, action: #selector(goBack), tooltip: "Back")
        case "navForward":
            item.view = AppToolbarChrome.configureNavigationButton(navForwardButton, symbol: "chevron.right", target: self, action: #selector(goForward), tooltip: "Forward")
        case "new": item.view = AppToolbarChrome.texturedIconButton(symbol: "square.and.pencil", target: self, action: #selector(newChat), tooltip: "New Chat")
        case "add": item.view = AppToolbarChrome.texturedIconButton(symbol: "folder.badge.plus", target: self, action: #selector(showAddMenu(_:)), tooltip: "Add Workspace / Worktree")
        case "addWorkspace":
            AppToolbarChrome.configureNativeActionItem(item, symbol: "folder.badge.plus", label: "Add Workspace", tooltip: "Add Workspace", target: self, action: #selector(addWorkspace))
        case "gitCommit":
            AppToolbarChrome.configureNativeActionItem(item, symbol: "checkmark", label: "Commit", tooltip: "Commit and push", target: gitPanel, action: #selector(GitPanelViewController.showGitActions))
        case "gitScope":
            AppToolbarChrome.configureScopeItem(item, control: gitPanel.scopeToolbarView)
        case "git": item.view = AppToolbarChrome.texturedIconButton(symbol: "arrow.triangle.branch", target: self, action: #selector(toggleGit), tooltip: "Toggle Git")
        case "chatTitle":
            item.view = AppToolbarChrome.makeChatTitleView(titleLabel: chatTitleLabel, menuButton: chatMenuButton, target: self, menuAction: #selector(showChatTitleMenu(_:)))
        default: return nil
        }
        item.label = id.rawValue
        return item
    }

    private func currentNavigableConversation() -> Conversation? {
        guard let c = chat.conversation else { return nil }
        if conversations.contains(where: { $0 === c }) { return c }
        if codexStubs.values.flatMap({ $0 }).contains(where: { $0 === c }) { return c }
        return nil
    }

    private func recordNavigationAwayFromCurrent(to next: Conversation?) {
        navigationHistory.recordLeaving(current: currentNavigableConversation(), to: next)
        updateNavigationControls()
    }

    private func updateNavigationControls() {
        navBackButton.isEnabled = navigationHistory.canGoBack
        navForwardButton.isEnabled = navigationHistory.canGoForward
        navBackButton.contentTintColor = navBackButton.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        navForwardButton.contentTintColor = navForwardButton.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @objc private func goBack() {
        guard let target = navigationHistory.goBack(from: currentNavigableConversation()) else { return }
        selectConversation(target, recordHistory: false)
        rebuildGroups(select: target)
        updateNavigationControls()
    }

    @objc private func goForward() {
        guard let target = navigationHistory.goForward(from: currentNavigableConversation()) else { return }
        selectConversation(target, recordHistory: false)
        rebuildGroups(select: target)
        updateNavigationControls()
    }

    @objc private func showChatTitleMenu(_ sender: NSButton) {
        guard let c = chat.conversation else { return }
        let menu = ChatActionMenuChrome.makeMenu(
            isPinned: c.pinned,
            target: self,
            selectors: ChatActionMenuSelectors(
                pin: #selector(pinCurrentChat),
                rename: #selector(renameCurrentChat),
                archive: #selector(archiveCurrentChat),
                openInNewWindow: #selector(openCurrentChatInNewWindow)
            )
        )
        ChatActionMenuChrome.popUp(menu, from: sender)
    }

    @objc private func pinCurrentChat() {
        guard let c = chat.conversation else { return }
        togglePin(c)
    }

    @objc private func renameCurrentChat() {
        guard let c = chat.conversation else { return }
        promptRename(c)
    }

    @objc private func archiveCurrentChat() {
        guard let c = chat.conversation else { return }
        archiveConversation(c)
    }

    @objc private func openCurrentChatInNewWindow() {
        guard let c = chat.conversation else { return }
        openDetachedChat(c)
    }

    private func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let width = splitView?.subviews.first?.frame.width, width > 0 else { return }
        let capped = SidebarLayoutModel.clampedWidth(width)
        guard abs(capped - lastSyncedSidebarWidth) > 1 else { return }
        lastSyncedSidebarWidth = capped
        Task { [client] in
            await client.codexSetSidebarState(["sidebarWidth": Double(capped)])
        }
    }

    private func stabilizeMainLayout(reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduleUnexpectedMainWindowRestoreIfNeeded(reason: "restored-unexpected-shrink")
            self.applyMainLayoutStabilization()
            self.writeLayoutMetrics(reason: reason)
        }
    }

    private func scheduleUnexpectedMainWindowRestoreIfNeeded(reason: String) {
        guard case .restore(let frame) = MainWindowFrameModel.resizeDecision(
            current: window.frame,
            state: mainWindowFrameState
        ) else { return }
        applyRestoredMainWindowFrame(frame, reason: reason)
        guard !pendingWindowFrameRestore else { return }
        pendingWindowFrameRestore = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.pendingWindowFrameRestore = false
            guard case .restore(let frame) = MainWindowFrameModel.resizeDecision(
                current: self.window.frame,
                state: self.mainWindowFrameState
            ) else { return }
            self.applyRestoredMainWindowFrame(frame, reason: reason)
        }
    }

    private func applyRestoredMainWindowFrame(_ frame: NSRect, reason: String) {
        unlockWindowSizing()
        window.setFrame(frame, display: true)
        mainWindowFrameState = MainWindowFrameModel.recordingApplied(window.frame, in: mainWindowFrameState)
        applyMainLayoutStabilization()
        writeLayoutMetrics(reason: reason)
    }

    private func applyMainLayoutStabilization() {
        MainLayoutStabilizer.stabilize(
            window: window,
            rootContentController: rootContentController,
            splitView: splitView,
            rootSplitController: rootSplitController as? RootSplitViewController,
            workspaceArea: workspaceArea,
            sidebarItem: sidebarItem,
            gitItem: gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        )
    }

    private func writeLayoutMetrics(reason: String = "startup") {
        let mainWidth = mainSplitItemWidth()
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let snapshot = WindowLayoutMetricsSnapshot(
            reason: reason,
            windowWidth: Double(window.frame.width),
            windowHeight: Double(window.frame.height),
            contentViewWidth: Double(window.contentView?.bounds.width ?? -1),
            contentViewHeight: Double(window.contentView?.bounds.height ?? -1),
            contentControllerWidth: Double(rootContentController?.view.frame.width ?? -1),
            contentControllerHeight: Double(rootContentController?.view.frame.height ?? -1),
            contentLayoutWidth: Double(window.contentLayoutRect.width),
            contentLayoutHeight: Double(window.contentLayoutRect.height),
            rootSplitViewWidth: Double(rootSplitController?.view.frame.width ?? -1),
            rootSplitViewHeight: Double(rootSplitController?.view.frame.height ?? -1),
            splitViewWidth: Double(splitView?.frame.width ?? -1),
            splitViewHeight: Double(splitView?.frame.height ?? -1),
            splitViewX: Double(splitView?.frame.minX ?? -1),
            splitViewClass: String(describing: type(of: splitView ?? NSSplitView())),
            rootSubviews: WindowLayoutChrome.frameMetrics(for: window.contentView?.subviews ?? []),
            requestedFrameWidth: Double(mainWindowFrameState.requestedFrame.width),
            requestedFrameHeight: Double(mainWindowFrameState.requestedFrame.height),
            appliedFrameWidth: Double(mainWindowFrameState.appliedFrame.width),
            appliedFrameHeight: Double(mainWindowFrameState.appliedFrame.height),
            screenVisibleWidth: Double(visible.width),
            screenVisibleHeight: Double(visible.height),
            sidebarCollapsed: sidebarItem.isCollapsed,
            gitCollapsed: gitItem.isCollapsed,
            splitFrames: WindowLayoutChrome.frameMetrics(for: splitView?.subviews ?? []),
            chatViewWidth: Double(chat.view.frame.width),
            chatViewHeight: Double(chat.view.frame.height),
            workspaceWidth: Double(workspaceArea.view.frame.width),
            workspaceHeight: Double(workspaceArea.view.frame.height),
            mainSplitItemWidth: Double(mainWidth),
            chatMetrics: chat.layoutMetrics,
            workspaceMetrics: workspaceArea.layoutMetrics
        )
        let payload = WindowLayoutModel.metricsPayload(from: snapshot)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("ui-layout-metrics.json"))
        }
    }

    // MARK: Chats & drafts

    @objc private func newChat() {
        recordNavigationAwayFromCurrent(to: nil)
        chat.setHarness(.codex, preferredModel: modelCache[.codex]?.first ?? "gpt-5.5")
        let c: Conversation
        if let existing = draft, existing.workspace == active.path, existing.messages.isEmpty {
            c = existing
            c.model = chat.selectedModel
            c.harness = .codex
        } else {
            c = Conversation(model: chat.selectedModel, workspace: active.path, harness: .codex)
        }
        draft = c
        workspaceArea.resetPanels()
        chat.show(c)
        stabilizeMainLayout(reason: "new-chat")
        updateWindowTitle(c)
        gitPanel.show(workspace: active.path)
        rebuildGroups()
        sidebar.selectNewChat()
        updateNavigationControls()
    }

    private func selectConversation(_ c: Conversation, recordHistory: Bool = true) {
        if recordHistory { recordNavigationAwayFromCurrent(to: c) }
        draft = nil
        UserDefaults.standard.set(c.id, forKey: selectedConversationKey)
        let path = c.workspace.isEmpty ? primaryPath : c.workspace
        active = workspaceRefs.first { $0.path == path } ?? active
        chat.setHarness(c.harness, preferredModel: c.model)
        workspaceArea.resetPanels()   // isolate panels per chat
        chat.showShell(c)
        stabilizeMainLayout(reason: "thread-loading-shell")
        updateWindowTitle(c)
        gitPanel.show(workspace: path)
        sidebar.selectConversation(c)
        updateNavigationControls()
        if c.needsLoad {
            refreshCodexHistoryIfNeeded(c, force: c.status == .thinking || c.status == .running)
        } else {
            pendingRenderConversationId = c.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard self.pendingRenderConversationId == c.id, self.chat.conversation === c else { return }
                self.chat.show(c)
                self.stabilizeMainLayout(reason: "thread-render")
            }
        }
    }

    private func refreshCodexHistoryIfNeeded(_ c: Conversation, force: Bool = false) {
        guard let tid = AppCodexHistoryModel.refreshThreadId(for: c, force: force, inFlight: codexRefreshInFlight) else { return }
        codexRefreshInFlight.insert(tid)
        Task { @MainActor in
            defer {
                codexRefreshInFlight.remove(tid)
                c.needsLoad = false
            }
            guard let hist = try? await client.codexThread(id: tid) else { return }
            let previousUpdatedAt = c.updatedAt
            c.messages = AppCodexHistoryModel.messages(from: hist)
            c.status = AppCodexHistoryModel.status(afterLoading: c.messages)
            c.updatedAt = previousUpdatedAt
            if chat.conversation === c {
                chat.show(c)
                stabilizeMainLayout(reason: "codex-history-render")
            }
            rebuildGroups(select: chat.conversation)
            persist()
            Store.saveCodexStubs(codexStubs)
        }
    }

    private func selectWorkspace(_ path: String) {
        active = workspaceRefs.first { $0.path == path } ?? active
        newChat()
    }

    private func forkConversation(_ c: Conversation) {
        let fork = Conversation(model: c.model, workspace: c.workspace, harness: c.harness)
        fork.title = c.title + " (fork)"
        fork.messages = c.messages.map {
            let m = ChatMessage(role: $0.role, text: $0.text, toolName: $0.toolName, toolDetail: $0.toolDetail)
            m.toolDone = $0.toolDone
            m.timestamp = $0.timestamp
            m.turnDuration = $0.turnDuration
            m.turnStartedAt = $0.turnStartedAt
            m.turnStatus = $0.turnStatus
            m.isFinal = $0.isFinal
            m.isSteer = $0.isSteer
            return m
        }
        conversations.insert(fork, at: 0)
        selectConversation(fork)
        rebuildGroups(select: fork)
        persist()
    }

    private func renameConversation(_ c: Conversation) {
        rebuildGroups(select: c)
        updateWindowTitle(c)
        refreshDetachedWindows(for: c, rerender: true)
        persist()
        if let tid = c.codexThreadId {
            Task { [client] in
                try? await client.codexRename(threadId: tid, name: c.title)
            }
        }
    }

    private func promptRename(_ c: Conversation) {
        let alert = NSAlert()
        alert.messageText = "Rename Chat"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = c.title
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        c.title = name
        renameConversation(c)
    }

    private func togglePin(_ c: Conversation) {
        c.pinned.toggle()
        if let tid = c.codexThreadId {
            let pinned = c.pinned
            Task { [client] in
                try? await client.codexPin(threadId: tid, pinned: pinned)
            }
        }
        rebuildGroups(select: chat.conversation ?? c)
        persist()
        Store.saveCodexStubs(codexStubs)
    }

    private func archiveConversation(_ c: Conversation) {
        conversations.removeAll { $0 === c }
        // Codex thread stubs aren't in `conversations`; archive them so they don't reappear on reload.
        if let tid = c.codexThreadId {
            archivedCodexIds.insert(tid)
            UserDefaults.standard.set(Array(archivedCodexIds), forKey: "archivedCodexIds")
            for k in codexStubs.keys { codexStubs[k]?.removeAll { $0.codexThreadId == tid } }
            Store.saveCodexStubs(codexStubs)
            Task { try? await client.codexArchive(threadId: tid) }
        }
        if chat.conversation === c { newChat() }
        detachedChatWindows.removeAll { $0.conversation === c }
        rebuildGroups()
        persist()
    }

    private func refreshActivity(_ c: Conversation) {
        c.updatedAt = Date().timeIntervalSince1970
        if let d = draft, d === c, !d.messages.isEmpty {
            conversations.insert(d, at: 0); draft = nil
        }
        if chat.conversation === c { updateWindowTitle(c) }
        refreshDetachedWindows(for: c, rerender: false)
        scheduleHotStateSave()

        let now = Date().timeIntervalSince1970
        let active = c.status == .thinking || c.status == .running || chat.hasLocalStream(for: c)
        let plan = AppActivityRefreshModel.activityPlan(
            isActive: active,
            now: now,
            lastSidebarRefresh: lastActivitySidebarRefresh[c.id],
            lastHistoryRefresh: lastActiveHistoryRefresh
        )
        if let next = plan.nextSidebarRefresh {
            lastActivitySidebarRefresh[c.id] = next
        }
        if plan.refreshSidebar {
            rebuildGroups(select: chat.conversation)
        } else {
            updateDockState()
        }

        if let next = plan.nextHistoryRefresh {
            lastActiveHistoryRefresh = next
        }
        if plan.refreshQuota {
            loadQuota()
        }

        if let next = plan.nextGitReload {
            lastActivityGitReload[c.id] = next
            gitPanel.reload()
        }

        if plan.persist { persist() }
    }

    private func updateWindowTitle(_ c: Conversation?) {
        let title = ChatTitleModel.displayTitle(for: c)
        window.title = title
        chatTitleLabel.stringValue = title
        chat.setHeaderTitle(title)
    }

    private func openDetachedChat(_ c: Conversation) {
        let detached = DetachedChatWindowController(
            client: client,
            conversation: c,
            models: modelCache[c.harness] ?? [],
            onActivity: { [weak self] conversation in
                self?.refreshActivity(conversation)
            },
            onTitleGenerated: { [weak self] conversation, _ in
                self?.renameConversation(conversation)
            },
            onClose: { [weak self] controller in
                self?.detachedChatWindows.removeAll { $0 === controller }
            }
        )
        detachedChatWindows.append(detached)
        detached.show()
    }

    private func refreshDetachedWindows(for c: Conversation, rerender: Bool) {
        detachedChatWindows.forEach { controller in
            guard controller.conversation === c else { return }
            if rerender { controller.refresh() }
            else { controller.refreshTitle() }
        }
    }

    private func rebuildGroups(select: Conversation? = nil) {
        let content = SidebarModel.build(
            conversations: conversations,
            codexStubs: codexStubs,
            workspaceRefs: workspaceRefs,
            primaryPath: primaryPath,
            projectlessKey: projectlessCodexKey,
            archivedCodexIds: archivedCodexIds
        )
        workspaceRefs = content.workspaceRefs
        Store.saveWorkspaces(workspaceRefs)
        sidebar.pinnedConversations = content.pinnedConversations
        sidebar.projectlessConversations = content.projectlessConversations
        sidebar.workspaces = content.workspaces
        if let select, !(select === draft) {
            sidebar.reload(selecting: select)
        } else {
            sidebar.reload()
            if chat.conversation === draft {
                sidebar.selectNewChat()
            }
        }
        updateDockState()
    }

    private func persist() {
        chat.saveComposerDraft()
        Store.save(conversations)
        Store.saveWorkspaces(workspaceRefs)
        Store.saveCodexStubs(codexStubs)
        saveHotState()
    }

    private func restoreHotState() -> Bool {
        guard let restored = hotStateCoordinator.restore() else { return false }
        conversations = restored.conversations
        draft = restored.draft
        codexStubs = restored.codexStubs
        workspaceRefs = restored.workspaceRefs
        worktreesByPath = restored.worktreesByPath
        modelCache = restored.modelCache
        primaryPath = restored.primaryPath
        active = restored.active
        archivedCodexIds = restored.archivedCodexIds
        if let selected = restored.selectedConversationId {
            UserDefaults.standard.set(selected, forKey: selectedConversationKey)
        }
        return true
    }

    private func saveHotState() {
        let selected = chat.conversation?.id ?? UserDefaults.standard.string(forKey: selectedConversationKey)
        hotStateCoordinator.save(
            conversations: conversations,
            draft: draft,
            codexStubs: codexStubs,
            workspaceRefs: workspaceRefs,
            worktreesByPath: worktreesByPath,
            modelCache: modelCache,
            primaryPath: primaryPath,
            active: active,
            archivedCodexIds: archivedCodexIds,
            selectedConversationId: selected
        )
    }

    private func scheduleHotStateSave() {
        hotStateCoordinator.scheduleSave { [weak self] in self?.saveHotState() }
    }

    private func allVisibleConversations() -> [Conversation] {
        AppConversationIndexModel.visibleConversations(local: conversations, codexStubs: codexStubs)
    }

    private func updateDockState() {
        let visible = allVisibleConversations()
        let recent = AppConversationIndexModel.dockRecent(conversations: visible).map(\.dictionary)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: Array(recent), options: []) {
            try? data.write(to: dir.appendingPathComponent("dock-recent.json"))
        }
        let unread = AppConversationIndexModel.unreadFinishedCount(visible)
        NSApp.dockTile.badgeLabel = unread > 0 ? "\(unread)" : nil
    }

    private func openConversationFromDock(id: String) {
        guard let conversation = allVisibleConversations().first(where: { $0.id == id || $0.codexThreadId == id }) else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        selectConversation(conversation)
        rebuildGroups(select: conversation)
    }

    private func showSearchOverlay() {
        let overlay = SearchOverlayController(allConversations: { [weak self] in
            self?.allVisibleConversations() ?? []
        }, onSelect: { [weak self] c in
            self?.selectConversation(c)
            self?.rebuildGroups(select: c)
        })
        searchOverlay = overlay
        overlay.show(over: window)
    }

    @objc private func showSearchFromMenu() {
        showSearchOverlay()
    }

    private func restoredConversation() -> Conversation? {
        AppConversationIndexModel.restoredConversation(
            selectedId: UserDefaults.standard.string(forKey: selectedConversationKey),
            conversations: conversations,
            codexStubs: codexStubs,
            draft: draft
        )
    }

    // MARK: Workspaces & worktrees

    @MainActor private func syncCodexWorkspaceIndex() async {
        guard let indexed = try? await client.codexWorkspaces(), !indexed.isEmpty else { return }
        let result = AppWorkspaceIndexModel.sync(
            indexed: indexed,
            existing: workspaceRefs,
            active: active,
            primaryPath: primaryPath
        )
        guard result.didChange else { return }
        workspaceRefs = result.workspaceRefs
        active = result.active
        primaryPath = result.primaryPath
        Store.saveWorkspaces(workspaceRefs)
        rebuildGroups(select: chat.conversation)
    }

    @MainActor private func syncCodexSidebarState() async {
        guard let state = try? await client.codexSidebarState() else { return }
        sidebar.applyCodexSidebarState(collapsedGroups: state.collapsedGroups, collapsedSections: state.collapsedSections)
        if let width = state.sidebarWidth, let splitView, splitView.subviews.count > 1 {
            let plan = SidebarLayoutModel.syncPlan(receivedWidth: width)
            let capped = CGFloat(plan.appliedWidth ?? width)
            lastSyncedSidebarWidth = capped
            splitView.setPosition(capped, ofDividerAt: 0)
            stabilizeMainLayout(reason: "codex-sidebar-state")
            if let payload = plan.correctionPayload {
                Task { [client] in
                    await client.codexSetSidebarState(payload)
                }
            }
        }
        rebuildGroups(select: chat.conversation)
    }

    private func setCodexSection(_ section: String, collapsed: Bool) {
        Task { [client] in
            await client.codexSetSidebarState(AppSidebarSyncModel.sectionPayload(section: section, collapsed: collapsed))
        }
    }

    private func setCodexWorkspace(_ path: String, collapsed: Bool) {
        Task { [client] in
            await client.codexSetSidebarState(AppSidebarSyncModel.workspacePayload(path: path, collapsed: collapsed))
        }
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        let m = NSMenu()
        m.addItem(withTitle: "Add Workspace…", action: #selector(addWorkspace), keyEquivalent: "")
        m.addItem(withTitle: "New Worktree of \(active.name)…", action: #selector(addWorktree), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addWorkspace() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        guard p.runModal() == .OK, let url = p.url else { return }
        let ref = WorkspaceRef(name: url.lastPathComponent, path: url.path)
        if !workspaceRefs.contains(ref) { workspaceRefs.append(ref); Store.saveWorkspaces(workspaceRefs) }
        active = ref
        newChat()
        detectWorktrees()
    }

    /// Map each top-level workspace to its existing git worktrees, then load Codex threads.
    private func detectWorktrees() {
        Task { @MainActor in
            for ref in workspaceRefs {
                worktreesByPath[ref.path] = (await client.worktrees(cwd: ref.path)).map(\.path)
            }
            loadCodexThreads()
        }
    }

    @objc private func addWorktree() {
        let a = NSAlert()
        a.messageText = "New Worktree"
        a.informativeText = "Create a git worktree (new branch) of \(active.name):"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        tf.placeholderString = "branch-name"
        a.accessoryView = tf
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let branch = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }
        Task { @MainActor in
            let r = try? await client.post("worktree", ["cwd": active.path, "branch": branch])
            if let path = r?["path"] as? String, let name = r?["name"] as? String {
                let ref = WorkspaceRef(name: name, path: path)
                workspaceRefs.append(ref); Store.saveWorkspaces(workspaceRefs)
                active = ref
                newChat()
            } else {
                let err = NSAlert(); err.messageText = "Worktree failed"
                err.informativeText = (r?["error"] as? String) ?? "Is this a git repository?"
                err.runModal()
            }
        }
    }

    private func unlockWindowSizing() {
        WindowLayoutChrome.applyUsableSizing(to: window)
    }

    private func setMainWindowFrame(_ frame: NSRect) {
        mainWindowFrameState = MainWindowFrameModel.recordingRequest(frame, in: mainWindowFrameState)
        window.setFrame(frame, display: true)
        mainWindowFrameState = MainWindowFrameModel.recordingApplied(window.frame, in: mainWindowFrameState)
        saveMainWindowFrame(window.frame)
    }

    private func initialMainWindowFrame() -> NSRect {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let saved = UserDefaults.standard.string(forKey: mainWindowFrameKey).map(NSRectFromString)
        return MainWindowFrameModel.initialFrame(
            savedFrame: saved,
            minSize: window.minSize,
            visibleFrame: visible
        )
    }

    private func saveMainWindowFrame(_ frame: NSRect) {
        guard WindowLayoutModel.shouldPersistFrame(frame, minSize: window.minSize) else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: mainWindowFrameKey)
    }

    private func mainSplitItemWidth() -> CGFloat {
        guard let splitView, splitView.subviews.count >= 2 else { return -1 }
        return splitView.subviews[1].frame.width
    }

    func windowDidResize(_ notification: Notification) {
        unlockWindowSizing()
        switch MainWindowFrameModel.resizeDecision(current: window.frame, state: mainWindowFrameState) {
        case .restore:
            scheduleUnexpectedMainWindowRestoreIfNeeded(reason: "restored-unexpected-shrink")
            applyMainLayoutStabilization()
            writeLayoutMetrics(reason: "restored-unexpected-shrink")
            return
        case .accept(let frame):
            mainWindowFrameState = MainWindowFrameModel.recordingApplied(frame, in: mainWindowFrameState)
            saveMainWindowFrame(frame)
        }
        applyMainLayoutStabilization()
        writeLayoutMetrics(reason: "window-resize")
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        mainWindowFrameState = MainWindowFrameModel.recordingLiveResize(true, in: mainWindowFrameState)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        mainWindowFrameState = MainWindowFrameModel.recordingLiveResize(false, in: mainWindowFrameState)
        unlockWindowSizing()
        mainWindowFrameState = MainWindowFrameModel.recordingApplied(window.frame, in: mainWindowFrameState)
        saveMainWindowFrame(window.frame)
        applyMainLayoutStabilization()
        writeLayoutMetrics(reason: "window-live-resize")
    }

    @objc private func toggleGit() {
        let frame = window.frame
        unlockWindowSizing()
        gitItem.animator().isCollapsed.toggle()
        for delay in [0.05, 0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.unlockWindowSizing()
                if self.window.frame.width < frame.width - 1 {
                    self.window.setFrame(frame, display: true)
                    self.mainWindowFrameState = MainWindowFrameModel.recordingApplied(self.window.frame, in: self.mainWindowFrameState)
                }
                self.applyMainLayoutStabilization()
                self.writeLayoutMetrics(reason: "git-toggle")
            }
        }
    }

    // MARK: Settings overlay

    private func installSettingsOverlay(over host: NSView) {
        SettingsOverlayChrome.configurePill(
            settingsPill,
            button: settingsButton,
            target: self,
            menuAction: #selector(showSettingsMenu(_:))
        )
        SettingsOverlayChrome.install(settingsPill, button: settingsButton, over: host)
    }

    @objc private func showSettingsMenu(_ sender: NSButton) {
        let menu = SettingsOverlayChrome.makeMenu(
            usageTitle: usageRemainingTitle,
            target: self,
            settingsAction: #selector(openSettingsOverlay)
        )
        SettingsOverlayChrome.popUp(menu, from: sender)
    }

    @objc private func openSettingsOverlay() {
        SettingsOverlayChrome.makeSettingsAlert().beginSheetModal(for: window)
    }

    private func loadQuota() {
        Task { @MainActor in
            if let c = try? await client.credits() {
                usageRemainingTitle = String(format: "Usage remaining: %.0f / %.0f credits", max(0, c.limit - c.used), c.limit)
            } else {
                usageRemainingTitle = "Usage remaining"
            }
            if let q = try? await client.quota() {
                chat.setContext(q.contextUsagePercentage)
            }
        }
    }

    private func loadModelsForHarness(_ harness: Harness) {
        if let cached = modelCache[harness] { chat.setModels(cached) }  // instant swap
        Task { @MainActor in
            let ids: [String]
            switch harness {
            case .dynagent: ids = (try? await client.models())?.map(\.id) ?? ["auto"]
            case .codex: ids = (try? await client.codexModels())?.map(\.id) ?? ["gpt-5.5"]
            case .pi: ids = (try? await client.piModels())?.map(\.id) ?? ["kiro::kiro/claude-opus-4.8"]
            }
            modelCache[harness] = ids
            chat.setModels(ids)
            saveHotState()
        }
    }

    /// Fetch Codex's existing threads per workspace (and its worktrees), grouped under the parent.
    private func loadCodexThreads() {
        Task { @MainActor in
            await loadProjectlessCodexThreads()
            for ref in workspaceRefs {
                let cwds = [ref.path] + (worktreesByPath[ref.path] ?? [])
                var batches: [(cwd: String, threads: [AgentClient.CodexThread])] = []
                for cwd in cwds {
                    guard let threads = try? await client.codexThreads(cwd: cwd) else { continue }
                    batches.append((cwd: cwd, threads: threads))
                }
                codexStubs[ref.path] = AppCodexThreadStubModel.workspaceStubs(
                    threadBatches: batches,
                    existingStubs: codexStubs[ref.path] ?? [],
                    localConversations: conversations,
                    archivedIds: archivedCodexIds,
                    defaultModel: modelCache[.codex]?.first ?? "gpt-5.5"
                )
            }
            Store.saveCodexStubs(codexStubs)
            rebuildGroups(select: chat.conversation)
            if let selected = chat.conversation {
                refreshCodexHistoryIfNeeded(selected)
            }
        }
    }

    @MainActor private func loadProjectlessCodexThreads() async {
        guard let threads = try? await client.codexThreads() else { return }
        codexStubs[projectlessCodexKey] = AppCodexThreadStubModel.projectlessStubs(
            threads: threads,
            existingStubs: codexStubs[projectlessCodexKey] ?? [],
            archivedIds: archivedCodexIds,
            defaultModel: modelCache[.codex]?.first ?? "gpt-5.5",
            fallbackWorkspace: primaryPath
        )
    }

}

@_cdecl("dynagent_attach")
public func dynagentAttach(_ rawWindow: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let rawWindow else { return nil }
    let window = Unmanaged<NSWindow>.fromOpaque(rawWindow).takeUnretainedValue()
    let controller = AppController(window: window)
    controller.attach()
    return Unmanaged.passRetained(controller).toOpaque()
}

@_cdecl("dynagent_attach_with_state")
public func dynagentAttachWithState(_ rawWindow: UnsafeMutableRawPointer?, _ rawState: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let rawWindow else { return nil }
    let window = Unmanaged<NSWindow>.fromOpaque(rawWindow).takeUnretainedValue()
    let state = rawState.map { Unmanaged<NSMutableDictionary>.fromOpaque($0).takeUnretainedValue() }
    let controller = AppController(window: window, hotState: state)
    controller.attach()
    return Unmanaged.passRetained(controller).toOpaque()
}

@_cdecl("dynagent_detach")
public func dynagentDetach(_ rawController: UnsafeMutableRawPointer?) {
    guard let rawController else { return }
    let controller = Unmanaged<AppController>.fromOpaque(rawController).takeRetainedValue()
    controller.detach()
}
