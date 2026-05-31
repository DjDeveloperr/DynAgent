import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    private let client = AgentClient()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
        backing: .buffered, defer: false)

    private let sidebar = SidebarViewController()
    private let chat = ChatViewController()
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
        gitPanel.client = client
        conversations = Store.load()
        workspaceRefs = Store.loadWorkspaces()
        sidebar.onSelect = { [weak self] c in self?.selectConversation(c) }
        sidebar.onSelectWorkspace = { [weak self] w in self?.selectWorkspace(w.path) }

        let split = NSSplitViewController()
        let side = NSSplitViewItem(sidebarWithViewController: sidebar)
        side.minimumThickness = 210; side.maximumThickness = 320; side.canCollapse = true
        split.addSplitViewItem(side)
        split.addSplitViewItem(NSSplitViewItem(viewController: chat))
        gitItem = NSSplitViewItem(inspectorWithViewController: gitPanel)
        gitItem.minimumThickness = 280; gitItem.canCollapse = true
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
        let c = Conversation(model: chat.selectedModel, workspace: active.path)
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
            guard let q = try? await client.quota() else { creditsLabel.stringValue = "credits —"; return }
            creditsLabel.stringValue = String(format: "credits %.3f", q.sessionCredits ?? 0)
            chat.setContext(q.contextUsagePercentage)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
