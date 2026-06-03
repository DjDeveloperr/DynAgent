import AppKit

final class AppController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    private struct HotState: Codable {
        var conversations: [Conversation]
        var draft: Conversation?
        var codexStubs: [String: [Conversation]]
        var workspaceRefs: [WorkspaceRef]
        var worktreesByPath: [String: [String]]
        var modelCache: [String: [String]]
        var primaryPath: String
        var active: WorkspaceRef
        var archivedCodexIds: [String]
        var selectedConversationId: String?
        var savedAt: Double
    }

    private let client = AgentClient()
    private let window: NSWindow
    private let hotState: NSMutableDictionary?
    private let hotStateKey = "DynAgentUIHotState"

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
    private var pendingHotStateSave: DispatchWorkItem?
    private var detachedChatWindows: [DetachedChatWindowController] = []
    private let projectlessCodexKey = "__codex_projectless__"
    private var navigationBackStack: [Conversation] = []
    private var navigationForwardStack: [Conversation] = []
    private let maximumWindowSize = NSSize(width: 20_000, height: 20_000)
    private var lastRequestedMainFrame: NSRect = .zero
    private var lastAppliedMainFrame: NSRect = .zero
    private var isUserLiveResizing = false

    init(window: NSWindow, hotState: NSMutableDictionary? = nil) {
        self.window = window
        self.hotState = hotState
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
        side.minimumThickness = 260; side.maximumThickness = 380; side.canCollapse = true
        side.holdingPriority = NSLayoutConstraint.Priority(251)
        side.preferredThicknessFraction = 0
        split.addSplitViewItem(side)
        workspaceArea.cwdProvider = { [weak self] in self?.active.path ?? FileManager.default.currentDirectoryPath }
        workspaceArea.setPrimary(chat.view, title: "")
        let mainItem = NSSplitViewItem(viewController: workspaceArea)
        mainItem.minimumThickness = 360
        mainItem.maximumThickness = maximumWindowSize.width
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
                    applied: self.lastAppliedMainFrame
                ) {
                    self.setMainWindowFrame(self.lastAppliedMainFrame)
                }
                self.forceRootSplitToContentSize()
                self.workspaceArea.forceLayoutToBounds()
                self.rebalanceMainSplitIfNeeded()
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

    private func processTerminalActions() async {
        let actions = await client.pollTerminalActions()
        for action in actions {
            guard let terminal = PanelRegistry.shared.terminal(action.id) else { continue }
            terminal.write(action.text)
            // Report output back after a short delay
            let termId = action.id ?? terminal.panelId
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                let output = terminal.readBuffer(last: 8000)
                Task { await self.client.reportTerminalOutput(id: termId, output: output) }
            }
        }
    }

    private func processBrowserActions() async {
        let actions = await client.pollBrowserActions()
        for action in actions {
            guard let browser = PanelRegistry.shared.browser(action.id) else { continue }
            switch action.type {
            case "navigate":
                if let url = action.url {
                    browser.load(url)
                    // Report state after navigation settles
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self else { return }
                        let id = action.id ?? browser.panelId
                        Task { await self.client.reportBrowserState(id: id, url: browser.currentURL, title: browser.pageTitle()) }
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
        guard let c = chat.conversation,
              c.harness == .codex,
              c.status == .thinking || c.status == .running else { return }
        guard !chat.hasLocalStream(for: c) else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastActiveHistoryRefresh > 2.0 else { return }
        lastActiveHistoryRefresh = now
        refreshCodexHistoryIfNeeded(c, force: true)
    }

    // MARK: Menu bar

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let top = NSMenuItem(); let sub = NSMenu(title: title)
            items.forEach { sub.addItem($0) }; top.submenu = sub; return top
        }
        func item(_ title: String, _ sel: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key); it.keyEquivalentModifierMask = mods; it.target = target; return it
        }
        // App menu
        main.addItem(menu("DynAgent", [
            item("Hide DynAgent", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit DynAgent", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        // File
        main.addItem(menu("File", [
            item("New Chat", #selector(newChat), "n", target: self),
            item("Search Chats", #selector(showSearchFromMenu), "k", target: self),
            item("Reload UI", Selector(("dynagentReloadUI:")), "r"),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        // Edit (standard responder-chain selectors enable copy/paste/select-all everywhere)
        main.addItem(menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        // Window
        main.addItem(menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]))
        return main
    }

    // MARK: Toolbar

    private func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "main"); t.delegate = self; t.displayMode = .iconOnly
        return t
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .init("navBack"), .init("navForward"), .flexibleSpace, .init("addWorkspace"), .sidebarTrackingSeparator, .init("chatTitle"), .flexibleSpace, .init("gitScope"), .init("gitCommit"), .init("git")]
    }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(t) }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id.rawValue {
        case "navBack":
            item.view = navigationButton(navBackButton, symbol: "chevron.left", action: #selector(goBack), tip: "Back")
        case "navForward":
            item.view = navigationButton(navForwardButton, symbol: "chevron.right", action: #selector(goForward), tip: "Forward")
        case "new": item.view = button("square.and.pencil", #selector(newChat), "New Chat")
        case "add": item.view = button("folder.badge.plus", #selector(showAddMenu(_:)), "Add Workspace / Worktree")
        case "addWorkspace":
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Workspace")
            item.label = "Add Workspace"
            item.paletteLabel = "Add Workspace"
            item.toolTip = "Add Workspace"
            item.target = self
            item.action = #selector(addWorkspace)
        case "gitCommit":
            item.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Commit")
            item.label = "Commit"
            item.paletteLabel = "Commit"
            item.toolTip = "Commit and push"
            item.target = gitPanel
            item.action = #selector(GitPanelViewController.showGitActions)
        case "gitScope":
            let control = gitPanel.scopeToolbarView
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                control.widthAnchor.constraint(equalToConstant: 112),
                control.heightAnchor.constraint(equalToConstant: 24),
            ])
            item.view = control
            item.label = "Diff Scope"
            item.paletteLabel = "Diff Scope"
            item.toolTip = "Show all or staged changes"
        case "git": item.view = button("arrow.triangle.branch", #selector(toggleGit), "Toggle Git")
        case "chatTitle":
            chatTitleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
            chatTitleLabel.lineBreakMode = .byTruncatingTail
            chatTitleLabel.maximumNumberOfLines = 1
            chatTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            chatMenuButton.isBordered = false
            chatMenuButton.contentTintColor = .secondaryLabelColor
            chatMenuButton.target = self
            chatMenuButton.action = #selector(showChatTitleMenu(_:))
            chatMenuButton.toolTip = "Chat actions"
            chatMenuButton.translatesAutoresizingMaskIntoConstraints = false
            let stack = NSStackView(views: [chatTitleLabel, chatMenuButton])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 11, bottom: 0, right: 8)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.heightAnchor.constraint(equalToConstant: 28),
                chatTitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
                chatMenuButton.widthAnchor.constraint(equalToConstant: 24),
                chatMenuButton.heightAnchor.constraint(equalToConstant: 22),
            ])
            item.view = stack
        default: return nil
        }
        item.label = id.rawValue
        return item
    }

    private func navigationButton(_ button: NSButton, symbol: String, action: Selector, tip: String) -> NSButton {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func currentNavigableConversation() -> Conversation? {
        guard let c = chat.conversation else { return nil }
        if conversations.contains(where: { $0 === c }) { return c }
        if codexStubs.values.flatMap({ $0 }).contains(where: { $0 === c }) { return c }
        return nil
    }

    private func recordNavigationAwayFromCurrent(to next: Conversation?) {
        guard let current = currentNavigableConversation(), current !== next else { return }
        navigationBackStack.removeAll { $0 === current }
        navigationBackStack.append(current)
        if navigationBackStack.count > 50 { navigationBackStack.removeFirst(navigationBackStack.count - 50) }
        navigationForwardStack.removeAll()
        updateNavigationControls()
    }

    private func updateNavigationControls() {
        navBackButton.isEnabled = !navigationBackStack.isEmpty
        navForwardButton.isEnabled = !navigationForwardStack.isEmpty
        navBackButton.contentTintColor = navBackButton.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        navForwardButton.contentTintColor = navForwardButton.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @objc private func goBack() {
        guard let target = navigationBackStack.popLast() else { return }
        if let current = currentNavigableConversation(), current !== target {
            navigationForwardStack.append(current)
        }
        selectConversation(target, recordHistory: false)
        rebuildGroups(select: target)
        updateNavigationControls()
    }

    @objc private func goForward() {
        guard let target = navigationForwardStack.popLast() else { return }
        if let current = currentNavigableConversation(), current !== target {
            navigationBackStack.append(current)
        }
        selectConversation(target, recordHistory: false)
        rebuildGroups(select: target)
        updateNavigationControls()
    }

    @objc private func showChatTitleMenu(_ sender: NSButton) {
        guard let c = chat.conversation else { return }
        let menu = NSMenu()
        let pin = NSMenuItem(title: c.pinned ? "Unpin Chat" : "Pin Chat", action: #selector(pinCurrentChat), keyEquivalent: "")
        let rename = NSMenuItem(title: "Rename Chat", action: #selector(renameCurrentChat), keyEquivalent: "")
        let archive = NSMenuItem(title: "Archive Chat", action: #selector(archiveCurrentChat), keyEquivalent: "")
        let open = NSMenuItem(title: "Open in a New Window", action: #selector(openCurrentChatInNewWindow), keyEquivalent: "")
        for item in [pin, rename, archive, open] { item.target = self }
        menu.addItem(pin)
        menu.addItem(rename)
        menu.addItem(archive)
        menu.addItem(.separator())
        menu.addItem(open)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
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
        let capped = max(sidebarItem.minimumThickness, min(width, sidebarItem.maximumThickness))
        guard abs(capped - lastSyncedSidebarWidth) > 1 else { return }
        lastSyncedSidebarWidth = capped
        Task { [client] in
            await client.codexSetSidebarState(["sidebarWidth": Double(capped)])
        }
    }

    private func stabilizeMainLayout(reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.unlockWindowSizing()
            self.forceRootSplitToContentSize()
            self.workspaceArea.forceLayoutToBounds()
            self.rebalanceMainSplitIfNeeded()
            self.writeLayoutMetrics(reason: reason)
        }
    }

    private func rebalanceMainSplitIfNeeded() {
        guard let splitView, splitView.subviews.count >= 2 else { return }
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: splitView.bounds.width,
            sidebarCurrentWidth: splitView.subviews.first?.frame.width ?? 0,
            sidebarMinimumWidth: sidebarItem.minimumThickness,
            sidebarMaximumWidth: sidebarItem.maximumThickness,
            sidebarCollapsed: sidebarItem.isCollapsed,
            gitCurrentWidth: splitView.subviews.count >= 3 ? splitView.subviews[2].frame.width : 0,
            gitMinimumWidth: gitItem.minimumThickness,
            gitMaximumWidth: gitItem.maximumThickness,
            gitCollapsed: gitItem.isCollapsed
        ))
        if let first = plan.firstDividerPosition {
            splitView.setPosition(first, ofDividerAt: 0)
        }
        if splitView.subviews.count >= 3, let second = plan.secondDividerPosition {
            splitView.setPosition(second, ofDividerAt: 1)
        }
        splitView.adjustSubviews()
        workspaceArea.forceLayoutToBounds()
    }

    private func forceRootSplitToContentSize() {
        let contentBounds = window.contentView?.bounds ?? .zero
        let width = max(contentBounds.width, window.frame.width, window.contentLayoutRect.width)
        let height = max(contentBounds.height, window.contentLayoutRect.height)
        let bounds = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        if rootContentController?.view.frame != bounds {
            rootContentController?.view.frame = bounds
        }
        if splitView?.frame != bounds {
            splitView?.frame = bounds
        }
    }

    private func writeLayoutMetrics(reason: String = "startup") {
        let splitFrames = splitView?.subviews.enumerated().map { index, view in
            [
                "index": index,
                "class": String(describing: type(of: view)),
                "x": Double(view.frame.minX),
                "width": Double(view.frame.width),
                "height": Double(view.frame.height),
            ] as [String: Any]
        } ?? []
        let rootSubviews = window.contentView?.subviews.enumerated().map { index, view in
            [
                "index": index,
                "class": String(describing: type(of: view)),
                "x": Double(view.frame.minX),
                "width": Double(view.frame.width),
                "height": Double(view.frame.height),
            ] as [String: Any]
        } ?? []
        var payload: [String: Any] = [
            "reason": reason,
            "windowWidth": Double(window.frame.width),
            "windowHeight": Double(window.frame.height),
            "contentViewWidth": Double(window.contentView?.bounds.width ?? -1),
            "contentViewHeight": Double(window.contentView?.bounds.height ?? -1),
            "contentControllerWidth": Double(rootContentController?.view.frame.width ?? -1),
            "contentControllerHeight": Double(rootContentController?.view.frame.height ?? -1),
            "contentLayoutWidth": Double(window.contentLayoutRect.width),
            "contentLayoutHeight": Double(window.contentLayoutRect.height),
            "rootSplitViewWidth": Double(rootSplitController?.view.frame.width ?? -1),
            "rootSplitViewHeight": Double(rootSplitController?.view.frame.height ?? -1),
            "splitViewWidth": Double(splitView?.frame.width ?? -1),
            "splitViewHeight": Double(splitView?.frame.height ?? -1),
            "splitViewX": Double(splitView?.frame.minX ?? -1),
            "splitViewClass": String(describing: type(of: splitView ?? NSSplitView())),
            "rootSubviews": rootSubviews,
            "requestedFrameWidth": Double(lastRequestedMainFrame.width),
            "requestedFrameHeight": Double(lastRequestedMainFrame.height),
            "appliedFrameWidth": Double(lastAppliedMainFrame.width),
            "appliedFrameHeight": Double(lastAppliedMainFrame.height),
            "screenVisibleWidth": Double((window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero).width),
            "screenVisibleHeight": Double((window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero).height),
            "sidebarCollapsed": sidebarItem.isCollapsed,
            "gitCollapsed": gitItem.isCollapsed,
            "splitFrames": splitFrames,
            "chatViewWidth": Double(chat.view.frame.width),
            "chatViewHeight": Double(chat.view.frame.height),
            "workspaceWidth": Double(workspaceArea.view.frame.width),
            "workspaceHeight": Double(workspaceArea.view.frame.height),
            "mainSplitItemWidth": Double(mainSplitItemWidth()),
            "workspaceWidthSlack": Double(mainSplitItemWidth() - workspaceArea.view.frame.width),
        ]
        payload["chat"] = chat.layoutMetrics
        payload["workspace"] = workspaceArea.layoutMetrics
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("ui-layout-metrics.json"))
        }
    }

    private func button(_ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        return b
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
        guard c.harness == .codex, let tid = c.codexThreadId else { return }
        guard force || c.needsLoad else { return }
        guard force || (c.status != .thinking && c.status != .running) else { return }
        guard !codexRefreshInFlight.contains(tid) else { return }
        codexRefreshInFlight.insert(tid)
        Task { @MainActor in
            defer {
                codexRefreshInFlight.remove(tid)
                c.needsLoad = false
            }
            guard let hist = try? await client.codexThread(id: tid) else { return }
            let previousUpdatedAt = c.updatedAt
            c.messages = hist.map { item in
                let role = Role(rawValue: item.role) ?? .assistant
                let m = ChatMessage(role: role, text: item.content, toolName: item.toolName, toolDetail: item.toolDetail)
                m.toolDone = item.toolDone ?? false
                m.timestamp = item.timestamp
                m.turnDuration = item.turnDuration
                m.turnStartedAt = item.turnStartedAt
                m.turnStatus = item.turnStatus
                m.isFinal = item.isFinal
                m.isSteer = item.isSteer
                return m
            }
            c.status = latestCodexTurnLooksActive(c) ? .running : .idle
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
        let lastSidebar = lastActivitySidebarRefresh[c.id] ?? 0
        if !active || now - lastSidebar > 1.0 {
            lastActivitySidebarRefresh[c.id] = now
            rebuildGroups(select: chat.conversation)
        } else {
            updateDockState()
        }

        if !active || now - lastActiveHistoryRefresh > 8.0 {
            lastActiveHistoryRefresh = now
            loadQuota()
        }

        if !active {
            lastActivityGitReload[c.id] = now
            gitPanel.reload()
        }

        if !active { persist() }
    }

    private func updateWindowTitle(_ c: Conversation?) {
        let title = c?.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "New Chat"
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
        guard let data = hotState?[hotStateKey] as? Data,
              let state = try? JSONDecoder().decode(HotState.self, from: data) else { return false }
        conversations = state.conversations
        draft = state.draft
        codexStubs = state.codexStubs
        for c in conversations + codexStubs.values.flatMap({ $0 }) where c.harness == .codex {
            if latestCodexTurnLooksActive(c) {
                c.status = .running
                c.needsLoad = true
            } else if c.status == .thinking || c.status == .running {
                c.status = .idle
                c.needsLoad = false
            }
        }
        workspaceRefs = state.workspaceRefs.filter { !$0.path.contains("/worktrees/") }
        worktreesByPath = state.worktreesByPath
        modelCache = Dictionary(uniqueKeysWithValues: state.modelCache.compactMap { key, value in
            guard let harness = Harness(rawValue: key) else { return nil }
            return (harness, value)
        })
        primaryPath = state.primaryPath
        active = state.active
        archivedCodexIds = Set(state.archivedCodexIds)
        if let selected = state.selectedConversationId {
            UserDefaults.standard.set(selected, forKey: selectedConversationKey)
        }
        return true
    }

    private func saveHotState() {
        guard let hotState else { return }
        pendingHotStateSave?.cancel()
        pendingHotStateSave = nil
        let selected = chat.conversation?.id ?? UserDefaults.standard.string(forKey: selectedConversationKey)
        let cache = Dictionary(uniqueKeysWithValues: modelCache.map { ($0.key.rawValue, $0.value) })
        let state = HotState(
            conversations: conversations,
            draft: draft,
            codexStubs: codexStubs,
            workspaceRefs: workspaceRefs,
            worktreesByPath: worktreesByPath,
            modelCache: cache,
            primaryPath: primaryPath,
            active: active,
            archivedCodexIds: Array(archivedCodexIds),
            selectedConversationId: selected,
            savedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(state) {
            hotState[hotStateKey] = data
        }
    }

    private func scheduleHotStateSave() {
        guard hotState != nil else { return }
        pendingHotStateSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveHotState() }
        pendingHotStateSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    private func latestCodexTurnLooksActive(_ c: Conversation) -> Bool {
        let recentCutoff = Date().timeIntervalSince1970 - 20 * 60
        guard c.updatedAt >= recentCutoff else { return false }
        guard let promptIndex = c.messages.lastIndex(where: { $0.role == .user && !($0.isSteer ?? false) }) else { return false }
        let latestTurn = c.messages[promptIndex...]
        if latestTurn.contains(where: { ($0.isFinal ?? false) || $0.turnStatus == "completed" }) { return false }
        return latestTurn.contains { $0.turnStatus != nil && $0.turnStatus != "completed" }
    }

    private func allVisibleConversations() -> [Conversation] {
        var seen = Set<String>()
        var out: [Conversation] = []
        for c in conversations + codexStubs.values.flatMap({ $0 }) {
            guard !seen.contains(c.id) else { continue }
            seen.insert(c.id)
            out.append(c)
        }
        return out
    }

    private func updateDockState() {
        let recent = allVisibleConversations()
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { c in
                [
                    "id": c.id,
                    "title": c.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "New Chat",
                    "workspace": c.workspace,
                    "updatedAt": c.updatedAt,
                ] as [String: Any]
            }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: Array(recent), options: []) {
            try? data.write(to: dir.appendingPathComponent("dock-recent.json"))
        }
        let unread = allVisibleConversations().filter { $0.unread && $0.status != .thinking && $0.status != .running }.count
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
        let candidates = conversations + codexStubs.values.flatMap { $0 } + (draft.map { [$0] } ?? [])
        if let id = UserDefaults.standard.string(forKey: selectedConversationKey),
           let selected = candidates.first(where: { $0.id == id }) {
            return selected
        }
        return candidates.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    // MARK: Workspaces & worktrees

    @MainActor private func syncCodexWorkspaceIndex() async {
        guard let indexed = try? await client.codexWorkspaces(), !indexed.isEmpty else { return }
        let existing = workspaceRefs
        var merged: [WorkspaceRef] = []
        var seen = Set<String>()

        func append(_ ref: WorkspaceRef) {
            guard !ref.path.isEmpty, !ref.path.contains("/.codex/worktrees/") else { return }
            guard seen.insert(ref.path).inserted else { return }
            merged.append(ref)
        }

        for workspace in indexed {
            append(WorkspaceRef(name: workspace.name, path: workspace.path))
        }
        for ref in existing {
            append(ref)
        }
        guard merged != workspaceRefs else { return }
        workspaceRefs = merged
        if !workspaceRefs.contains(where: { $0.path == active.path }), let first = workspaceRefs.first {
            active = first
            primaryPath = first.path
        }
        Store.saveWorkspaces(workspaceRefs)
        rebuildGroups(select: chat.conversation)
    }

    @MainActor private func syncCodexSidebarState() async {
        guard let state = try? await client.codexSidebarState() else { return }
        sidebar.applyCodexSidebarState(collapsedGroups: state.collapsedGroups, collapsedSections: state.collapsedSections)
        if let width = state.sidebarWidth, let splitView, splitView.subviews.count > 1 {
            let capped = max(sidebarItem.minimumThickness, min(CGFloat(width), sidebarItem.maximumThickness))
            lastSyncedSidebarWidth = capped
            splitView.setPosition(capped, ofDividerAt: 0)
            if abs(CGFloat(width) - capped) > 1 {
                Task { [client] in
                    await client.codexSetSidebarState(["sidebarWidth": Double(capped)])
                }
            }
        }
        rebuildGroups(select: chat.conversation)
    }

    private func setCodexSection(_ section: String, collapsed: Bool) {
        Task { [client] in
            await client.codexSetSidebarState(["section": section, "sectionCollapsed": collapsed])
        }
    }

    private func setCodexWorkspace(_ path: String, collapsed: Bool) {
        Task { [client] in
            await client.codexSetSidebarState(["groupPath": path, "groupCollapsed": collapsed])
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
        window.styleMask.insert(.resizable)
        window.minSize = NSSize(width: 820, height: 480)
        window.maxSize = maximumWindowSize
        window.contentMinSize = NSSize(width: 820, height: 480)
        window.contentMaxSize = maximumWindowSize
    }

    private func wideWindowFrame() -> NSRect {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 900)
        return WindowLayoutModel.wideFrame(visibleFrame: visible)
    }

    private func setMainWindowFrame(_ frame: NSRect) {
        lastRequestedMainFrame = frame
        window.setFrame(frame, display: true)
        lastAppliedMainFrame = window.frame
        saveMainWindowFrame(window.frame)
    }

    private func restoredMainWindowFrame() -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: mainWindowFrameKey) else { return nil }
        let rect = NSRectFromString(value)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return WindowLayoutModel.restoredFrame(rect, minSize: window.minSize, visibleFrame: visible)
    }

    private func initialMainWindowFrame() -> NSRect {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if let current = WindowLayoutModel.restoredFrame(window.frame, minSize: window.minSize, visibleFrame: visible) {
            return current
        }
        return restoredMainWindowFrame() ?? wideWindowFrame()
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
        if WindowLayoutModel.shouldRestoreUnexpectedShrink(
            current: window.frame,
            applied: lastAppliedMainFrame,
            isUserLiveResizing: isUserLiveResizing
        ) {
            window.setFrame(lastAppliedMainFrame, display: true)
            forceRootSplitToContentSize()
            workspaceArea.forceLayoutToBounds()
            rebalanceMainSplitIfNeeded()
            writeLayoutMetrics(reason: "restored-unexpected-shrink")
            return
        }
        lastAppliedMainFrame = window.frame
        saveMainWindowFrame(window.frame)
        forceRootSplitToContentSize()
        rebalanceMainSplitIfNeeded()
        writeLayoutMetrics(reason: "window-resize")
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isUserLiveResizing = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isUserLiveResizing = false
        unlockWindowSizing()
        lastAppliedMainFrame = window.frame
        saveMainWindowFrame(window.frame)
        forceRootSplitToContentSize()
        rebalanceMainSplitIfNeeded()
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
                }
                self.forceRootSplitToContentSize()
                self.workspaceArea.forceLayoutToBounds()
                self.rebalanceMainSplitIfNeeded()
                self.writeLayoutMetrics(reason: "git-toggle")
            }
        }
    }

    // MARK: Settings overlay

    private func installSettingsOverlay(over host: NSView) {
        settingsPill.material = .hudWindow; settingsPill.blendingMode = .withinWindow; settingsPill.state = .active
        settingsPill.wantsLayer = true; settingsPill.layer?.cornerRadius = 14; settingsPill.layer?.masksToBounds = true
        settingsPill.layer?.zPosition = 50
        settingsPill.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.imagePosition = .imageLeading
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .labelColor
        settingsButton.font = .systemFont(ofSize: 13.5, weight: .medium)
        settingsButton.alignment = .left
        settingsButton.target = self
        settingsButton.action = #selector(showSettingsMenu(_:))
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsPill.addSubview(settingsButton)
        host.addSubview(settingsPill, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            settingsPill.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            settingsPill.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
            settingsPill.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -10),
            settingsPill.heightAnchor.constraint(equalToConstant: 38),
            settingsButton.leadingAnchor.constraint(equalTo: settingsPill.leadingAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: settingsPill.trailingAnchor, constant: -12),
            settingsButton.centerYAnchor.constraint(equalTo: settingsPill.centerYAnchor),
        ])
    }

    @objc private func showSettingsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings", action: #selector(openSettingsOverlay), keyEquivalent: "")
        settings.target = self
        let usage = NSMenuItem(title: usageRemainingTitle, action: nil, keyEquivalent: "")
        usage.isEnabled = false
        menu.addItem(settings)
        menu.addItem(usage)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    @objc private func openSettingsOverlay() {
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "DynAgent settings will appear here as the native controls land."
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window)
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
                var stubs: [Conversation] = []
                var existingById: [String: Conversation] = [:]
                for c in codexStubs[ref.path] ?? [] {
                    if let id = c.codexThreadId { existingById[id] = c }
                }
                for c in conversations {
                    if let id = c.codexThreadId { existingById[id] = c }
                }
                for cwd in cwds {
                    guard let threads = try? await client.codexThreads(cwd: cwd) else { continue }
                    stubs += threads.filter { !archivedCodexIds.contains($0.id) && $0.projectless != true }.map { t in
                        let c = existingById[t.id] ?? Conversation(model: modelCache[.codex]?.first ?? "gpt-5.5", workspace: cwd, harness: .codex)
                        if c.codexThreadId == nil { c.id = "codex:" + t.id }
                        let previousUpdatedAt = c.updatedAt
                        c.title = t.title
                        c.workspace = cwd
                        c.harness = .codex
                        c.codexThreadId = t.id
                        c.pinned = t.pinned == true
                        c.updatedAt = t.updatedAt
                        if c.messages.isEmpty || t.updatedAt > previousUpdatedAt + 1 {
                            c.needsLoad = true
                        }
                        return c
                    }
                }
                codexStubs[ref.path] = Array(stubs.prefix(60))
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
        var existingById: [String: Conversation] = [:]
        for c in codexStubs[projectlessCodexKey] ?? [] {
            if let id = c.codexThreadId { existingById[id] = c }
        }
        let stubs = threads
            .filter { !archivedCodexIds.contains($0.id) && ($0.projectless == true || $0.pinned == true) }
            .map { t in
                let c = existingById[t.id] ?? Conversation(model: modelCache[.codex]?.first ?? "gpt-5.5", workspace: t.workspace ?? primaryPath, harness: .codex)
                if c.codexThreadId == nil { c.id = "codex:" + t.id }
                let previousUpdatedAt = c.updatedAt
                c.title = t.title
                c.workspace = t.workspace ?? primaryPath
                c.harness = .codex
                c.codexThreadId = t.id
                c.pinned = t.pinned == true
                c.updatedAt = t.updatedAt
                if c.messages.isEmpty || t.updatedAt > previousUpdatedAt + 1 {
                    c.needsLoad = true
                }
                return c
            }
        codexStubs[projectlessCodexKey] = Array(stubs.prefix(80))
    }

}

final class DetachedChatWindowController: NSObject, NSWindowDelegate {
    let conversation: Conversation
    private let window: NSWindow
    private let chat = ChatViewController()
    private let onClose: (DetachedChatWindowController) -> Void

    init(client: AgentClient,
         conversation: Conversation,
         models: [String],
         onActivity: @escaping (Conversation) -> Void,
         onTitleGenerated: @escaping (Conversation, String) -> Void,
         onClose: @escaping (DetachedChatWindowController) -> Void) {
        self.conversation = conversation
        self.onClose = onClose
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered,
                               defer: false)
        super.init()
        chat.client = client
        chat.onActivity = onActivity
        chat.onTitleGenerated = onTitleGenerated
        chat.setHarness(conversation.harness, preferredModel: conversation.model)
        if !models.isEmpty { chat.setModels(models) }
        chat.show(conversation)

        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "New Chat"
        window.title = title
        chat.setHeaderTitle(title)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 560, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = chat
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        refreshTitle()
        chat.show(conversation)
    }

    func refreshTitle() {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "New Chat"
        window.title = title
        chat.setHeaderTitle(title)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
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
