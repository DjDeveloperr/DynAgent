import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    private let client = AgentClient()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
        backing: .buffered, defer: false)

    private let sidebar = SidebarViewController()
    private let chat = ChatViewController()
    private let workspaceArea = WorkspaceAreaViewController()
    private let gitPanel = GitPanelViewController()
    private var gitItem: NSSplitViewItem!
    private let creditsPill = NSVisualEffectView()
    private let creditsLabel = NSTextField(labelWithString: "credits —")

    private var conversations: [Conversation] = []
    private var draft: Conversation?
    private var workspaceRefs: [WorkspaceRef] = []
    private var primaryPath = FileManager.default.currentDirectoryPath
    private var active = WorkspaceRef(name: "Workspace", path: FileManager.default.currentDirectoryPath)

    func applicationDidFinishLaunching(_ note: Notification) {
        chat.client = client
        chat.onActivity = { [weak self] in self?.refreshActivity() }
        chat.onTitleGenerated = { [weak self] c, title in
            self?.rebuildGroups(select: c)
            self?.persist()
        }
        chat.onHarnessChanged = { [weak self] harness in
            self?.loadModelsForHarness(harness)
        }
        gitPanel.client = client
        conversations = Store.load()
        workspaceRefs = Store.loadWorkspaces()
        sidebar.onSelect = { [weak self] c in self?.selectConversation(c) }
        sidebar.onSelectWorkspace = { [weak self] w in self?.selectWorkspace(w.path) }
        sidebar.onRename = { [weak self] c in self?.rebuildGroups(select: c); self?.persist() }
        sidebar.onFork = { [weak self] c in self?.forkConversation(c) }
        sidebar.onArchive = { [weak self] c in self?.archiveConversation(c) }

        let split = NSSplitViewController()
        let side = NSSplitViewItem(sidebarWithViewController: sidebar)
        side.minimumThickness = 210; side.maximumThickness = 320; side.canCollapse = true
        split.addSplitViewItem(side)
        workspaceArea.cwdProvider = { [weak self] in self?.active.path ?? FileManager.default.currentDirectoryPath }
        workspaceArea.setPrimary(chat.view, title: "Chat")
        split.addSplitViewItem(NSSplitViewItem(viewController: workspaceArea))
        gitItem = NSSplitViewItem(inspectorWithViewController: gitPanel)
        gitItem.minimumThickness = 320; gitItem.maximumThickness = 800; gitItem.canCollapse = true
        split.addSplitViewItem(gitItem)

        window.title = "DynAgent"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 820, height: 480)
        window.contentViewController = split
        window.setFrameAutosaveName("main")
        window.toolbar = makeToolbar()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installCreditsOverlay(over: split.view)

        Task { @MainActor in
            if let info = try? await client.cwd() {
                primaryPath = info.cwd
                active = WorkspaceRef(name: info.name, path: info.cwd)
            }
            if !workspaceRefs.contains(where: { $0.path == primaryPath }) {
                workspaceRefs.insert(active, at: 0)
            }
            chat.setModels((try? await client.models())?.map(\.id) ?? ["auto"])
            if let first = conversations.first { selectConversation(first) } else { newChat() }
            loadQuota()
        }

        // Start polling for agent-driven terminal/browser commands
        startControlPolling()
    }

    // MARK: Agent control polling

    private func startControlPolling() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.processTerminalActions()
                await self.processBrowserActions()
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

    // MARK: Toolbar

    private func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "main"); t.delegate = self; t.displayMode = .iconOnly
        return t
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .init("new"), .init("add"), .sidebarTrackingSeparator, .flexibleSpace, .init("git")]
    }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(t) }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id.rawValue {
        case "new": item.view = button("square.and.pencil", #selector(newChat), "New Chat")
        case "add": item.view = button("folder.badge.plus", #selector(showAddMenu(_:)), "Add Workspace / Worktree")
        case "git": item.view = button("arrow.triangle.branch", #selector(toggleGit), "Toggle Git")
        default: return nil
        }
        item.label = id.rawValue
        return item
    }
    private func button(_ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        return b
    }

    // MARK: Chats & drafts

    @objc private func newChat() {
        let c = Conversation(model: chat.selectedModel, workspace: active.path, harness: chat.selectedHarness)
        draft = c
        chat.show(c)
        gitPanel.show(workspace: active.path)
        rebuildGroups()
    }

    private func selectConversation(_ c: Conversation) {
        draft = nil
        let path = c.workspace.isEmpty ? primaryPath : c.workspace
        active = workspaceRefs.first { $0.path == path } ?? active
        chat.show(c)
        gitPanel.show(workspace: path)
    }

    private func selectWorkspace(_ path: String) {
        active = workspaceRefs.first { $0.path == path } ?? active
        newChat()
    }

    private func forkConversation(_ c: Conversation) {
        let fork = Conversation(model: c.model, workspace: c.workspace, harness: c.harness)
        fork.title = c.title + " (fork)"
        fork.messages = c.messages.map { ChatMessage(role: $0.role, text: $0.text, toolName: $0.toolName) }
        conversations.insert(fork, at: 0)
        selectConversation(fork)
        rebuildGroups(select: fork)
        persist()
    }

    private func archiveConversation(_ c: Conversation) {
        conversations.removeAll { $0 === c }
        if chat.conversation === c { newChat() }
        rebuildGroups()
        persist()
    }

    private func refreshActivity() {
        if let d = draft, d === chat.conversation, !d.messages.isEmpty {
            conversations.insert(d, at: 0); draft = nil
        }
        rebuildGroups(select: chat.conversation)
        loadQuota()
        persist()
        gitPanel.reload()
    }

    private func rebuildGroups(select: Conversation? = nil) {
        for c in conversations where !c.workspace.isEmpty && !workspaceRefs.contains(where: { $0.path == c.workspace }) {
            workspaceRefs.append(WorkspaceRef(name: (c.workspace as NSString).lastPathComponent, path: c.workspace))
        }
        sidebar.workspaces = workspaceRefs.map { ref in
            Workspace(name: ref.name, path: ref.path,
                      conversations: conversations.filter { ($0.workspace.isEmpty ? primaryPath : $0.workspace) == ref.path })
        }
        sidebar.reload(selecting: select)
    }

    private func persist() { Store.save(conversations) }

    // MARK: Workspaces & worktrees

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

    @objc private func toggleGit() { gitItem.animator().isCollapsed.toggle() }

    // MARK: Credits overlay

    private func installCreditsOverlay(over host: NSView) {
        creditsPill.material = .hudWindow; creditsPill.blendingMode = .withinWindow; creditsPill.state = .active
        creditsPill.wantsLayer = true; creditsPill.layer?.cornerRadius = 13; creditsPill.layer?.masksToBounds = true
        creditsPill.translatesAutoresizingMaskIntoConstraints = false
        creditsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        creditsLabel.textColor = .secondaryLabelColor
        creditsLabel.translatesAutoresizingMaskIntoConstraints = false
        creditsPill.addSubview(creditsLabel)
        host.addSubview(creditsPill)
        NSLayoutConstraint.activate([
            creditsPill.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            creditsPill.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
            creditsPill.heightAnchor.constraint(equalToConstant: 26),
            creditsLabel.leadingAnchor.constraint(equalTo: creditsPill.leadingAnchor, constant: 12),
            creditsLabel.trailingAnchor.constraint(equalTo: creditsPill.trailingAnchor, constant: -12),
            creditsLabel.centerYAnchor.constraint(equalTo: creditsPill.centerYAnchor),
        ])
    }

    private func loadQuota() {
        Task { @MainActor in
            if let c = try? await client.credits() {
                creditsLabel.stringValue = String(format: "%.0f / %.0f credits", c.used, c.limit)
            } else {
                creditsLabel.stringValue = "—"
            }
            if let q = try? await client.quota() {
                chat.setContext(q.contextUsagePercentage)
            }
        }
    }

    private func loadModelsForHarness(_ harness: Harness) {
        Task { @MainActor in
            switch harness {
            case .dynagent:
                chat.setModels((try? await client.models())?.map(\.id) ?? ["auto"])
            case .codex:
                // Real Codex/OpenAI models available through the bridge
                let codexModels = ["o3", "o4-mini", "gpt-5.5", "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "claude-opus-4.8", "claude-sonnet-4.6"]
                chat.setModels(codexModels)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        persist()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
