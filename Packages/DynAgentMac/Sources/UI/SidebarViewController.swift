import AppKit

/// Left pane: a custom view-based list of workspaces and their conversations.
final class SidebarViewController: NSViewController {
    var workspaces: [Workspace] = []
    var pinnedConversations: [Conversation] = []
    var projectlessConversations: [Conversation] = []
    var onSelect: ((Conversation) -> Void)?
    var onSelectWorkspace: ((Workspace) -> Void)?
    var onNewChat: ((Workspace) -> Void)?
    var onGlobalNewChat: (() -> Void)?
    var onAddWorkspace: (() -> Void)?
    var onSearch: (() -> Void)?
    var onRename: ((Conversation) -> Void)?
    var onFork: ((Conversation) -> Void)?
    var onPin: ((Conversation) -> Void)?
    var onArchive: ((Conversation) -> Void)?
    var onProjectsCollapsedChanged: ((Bool) -> Void)?
    var onPinnedCollapsedChanged: ((Bool) -> Void)?
    var onChatsCollapsedChanged: ((Bool) -> Void)?
    var onWorkspaceCollapsedChanged: ((String, Bool) -> Void)?

    private let list = NSStackView()
    private let pageSize = 5
    private var expanded = Set<String>()
    private var projectsExpanded = true
    private var pinnedExpanded = true
    private var chatsExpanded = true
    private var collapsedWorkspacePaths = Set<String>()
    private var selectedId: String?
    private var newChatSelected = false
    private weak var newChatRow: SidebarRow?
    private var rowsById: [String: SidebarRow] = [:]
    private var allRows: [SidebarRow] = []
    private weak var hoveredRow: SidebarRow?
    private var sectionAddActions: [ObjectIdentifier: () -> Void] = [:]
    private let archiveConfirmation = SidebarArchiveConfirmationCoordinator()
    private let hoverTip = SidebarHoverTipWindow()
    private let hoverTipCoordinator = SidebarHoverTipCoordinator()

    override func loadView() {
        let scroll = SidebarScrollView()
        scroll.hasVerticalScroller = true
        scroll.onScroll = { [weak self] in self?.clearHoverState() }
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            list.topAnchor.constraint(equalTo: doc.topAnchor, constant: 2),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8),
        ])
        view = SidebarChrome.makeNativeRoot(containing: scroll)
    }

    func reload(selecting: Conversation? = nil) {
        if let s = selecting {
            selectedId = s.id
            newChatSelected = false
        }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowsById.removeAll()
        allRows.removeAll()
        sectionAddActions.removeAll()
        addTopActions()

        if !pinnedConversations.isEmpty {
            addSectionHeader("Pinned", expanded: pinnedExpanded) { [weak self] in
                guard let self else { return }
                self.pinnedExpanded.toggle()
                self.onPinnedCollapsedChanged?(!self.pinnedExpanded)
                self.reload()
            }
            if pinnedExpanded {
                for c in pinnedConversations { addConversationRow(c, indent: 8) }
            }
        }

        if !projectlessConversations.isEmpty {
            addSectionHeader("Chats", expanded: chatsExpanded) { [weak self] in
                guard let self else { return }
                self.chatsExpanded.toggle()
                self.onChatsCollapsedChanged?(!self.chatsExpanded)
                self.reload()
            }
            if chatsExpanded {
                for c in projectlessConversations { addConversationRow(c, indent: 8) }
            }
        }

        addSectionHeader("Projects", expanded: projectsExpanded, addSymbol: "folder.badge.plus", addToolTip: "Add workspace", addAction: { [weak self] in
            self?.onAddWorkspace?()
        }) { [weak self] in
            guard let self else { return }
            self.projectsExpanded.toggle()
            self.onProjectsCollapsedChanged?(!self.projectsExpanded)
            self.reload()
        }
        if projectsExpanded {
            for w in workspaces {
                addWorkspaceHeader(w)
                if collapsedWorkspacePaths.contains(w.path) { continue }
                let convs = w.conversations
                let shown = (expanded.contains(w.path) || convs.count <= pageSize) ? convs : Array(convs.prefix(pageSize))
                if convs.isEmpty {
                    addEmptyWorkspaceRow()
                } else {
                    for c in shown { addConversationRow(c) }
                }
                if convs.count > pageSize { addMoreToggle(w, total: convs.count) }
            }
        }
    }

    func selectNewChat() {
        selectedId = nil
        newChatSelected = true
        newChatRow?.selected = true
        rowsById.values.forEach { $0.selected = false }
    }

    func selectConversation(_ c: Conversation) {
        selectedId = c.id
        newChatSelected = false
        newChatRow?.selected = false
        rowsById.forEach { $0.value.selected = ($0.key == c.id) }
    }

    func applyCodexSidebarState(collapsedGroups: [String: Bool], collapsedSections: [String: Bool]) {
        collapsedWorkspacePaths = Set(collapsedGroups.compactMap { $0.value ? $0.key : nil })
        projectsExpanded = !(collapsedSections["threads"] ?? false)
        pinnedExpanded = !(collapsedSections["pinned"] ?? false)
        chatsExpanded = !(collapsedSections["chats"] ?? false)
    }

    private func fullWidth(_ row: SidebarRow) {
        allRows.append(row)
        row.onHoverStart = { [weak self] row in
            guard let self else { return }
            if self.hoveredRow !== row { self.hoveredRow?.clearHover() }
            self.hoveredRow = row
        }
        list.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
    }

    private func scheduleHoverTip(title: String, detail: String, row: SidebarRow) {
        hoverTipCoordinator.schedule(title: title, detail: detail, row: row) { [weak self] title, detail, row in
            self?.hoverTip.show(title: title, detail: detail, near: row)
        }
    }

    private func hideHoverTip() {
        hoverTipCoordinator.hide { [weak self] in
            self?.hoverTip.orderOut(nil)
        }
    }

    private func clearHoverState() {
        hideHoverTip()
        hoveredRow?.clearHover()
        hoveredRow = nil
        if archiveConfirmation.hasPendingArchive {
            cancelPendingArchive(immediate: true)
        }
    }

    private func addTopActions() {
        let row = SidebarRowsChrome.actionRow(symbol: "square.and.pencil", title: "New Chat") { [weak self] in self?.onGlobalNewChat?() }
        row.selected = newChatSelected
        newChatRow = row
        fullWidth(row)
        fullWidth(SidebarRowsChrome.actionRow(symbol: "magnifyingglass", title: "Search") { [weak self] in self?.onSearch?() })
    }

    private func addSectionHeader(_ title: String, expanded: Bool, addSymbol: String? = nil, addToolTip: String? = nil, addAction: (() -> Void)? = nil, action: @escaping () -> Void) {
        let section = SidebarRowsChrome.sectionHeader(
            title: title,
            expanded: expanded,
            addSymbol: addSymbol,
            addToolTip: addToolTip,
            addTarget: self,
            addAction: #selector(sectionAddClicked(_:)),
            toggle: action
        )
        if let button = section.addButton, let addAction {
            sectionAddActions[ObjectIdentifier(button)] = addAction
        }
        fullWidth(section.row)
    }

    private func addWorkspaceHeader(_ w: Workspace) {
        let model = SidebarRowModel.workspace(w)
        let row = SidebarRowsChrome.workspaceHeader(
            model: model,
            onClick: { [weak self] in self?.toggleWorkspace(w) },
            onNewChat: { [weak self] in self?.onNewChat?(w) },
            onHoverChanged: { [weak self] hovering, row in
                guard let self else { return }
                if hovering { self.scheduleHoverTip(title: model.tooltip.title, detail: model.tooltip.detail, row: row) }
                else { self.hideHoverTip() }
            })
        fullWidth(row)
    }

    private func addEmptyWorkspaceRow() {
        fullWidth(SidebarRowsChrome.emptyWorkspaceRow())
    }

    private func toggleWorkspace(_ w: Workspace) {
        let collapsed: Bool
        if collapsedWorkspacePaths.contains(w.path) {
            collapsedWorkspacePaths.remove(w.path)
            collapsed = false
        } else {
            collapsedWorkspacePaths.insert(w.path)
            collapsed = true
        }
        onWorkspaceCollapsedChanged?(w.path, collapsed)
        reload()
    }

    @objc private func sectionAddClicked(_ sender: NSButton) {
        sectionAddActions[ObjectIdentifier(sender)]?()
    }

    private func addConversationRow(_ c: Conversation, indent: CGFloat = 32) {
        let model = SidebarRowModel.conversation(c)
        let state = SidebarConversationRowChrome.make(
            model: model,
            indent: indent,
            onClick: { [weak self] in self?.select(c) },
            menu: { [weak self] in self?.menu(for: c) ?? NSMenu() },
            onPin: { [weak self, weak c] in
                guard let self, let c else { return }
                self.cancelPendingArchive(immediate: true)
                self.onPin?(c)
            },
            onArchive: { [weak self, weak c] button, pin in
                guard let self, let c else { return }
                self.archiveButtonClicked(button, conversation: c, pin: pin)
            },
            onHoverChanged: { [weak self, weak c] hovering, state in
                guard let self, let c else { return }
                let confirming = self.archiveConfirmation.isConfirming(conversationId: c.id)
                state.applyHover(hovering, confirming: confirming)
                self.archiveConfirmation.updateHover(
                    hovering: hovering,
                    conversationId: c.id,
                    cancelAndReload: { [weak self] in self?.reload() }
                )
                if hovering { self.scheduleHoverTip(title: model.tooltip.title, detail: model.tooltip.detail, row: state.row) }
                else { self.hideHoverTip() }
            }
        )
        state.row.selected = (c.id == selectedId)
        rowsById[c.id] = state.row
        fullWidth(state.row)
    }

    private func archiveButtonClicked(_ sender: SidebarActionButton, conversation c: Conversation, pin: SidebarActionButton?) {
        archiveConfirmation.clickArchive(conversationId: c.id) { [weak sender, weak pin] in
            guard let sender else { return }
            sender.attributedTitle = NSAttributedString(
                string: "Confirm",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            )
            sender.image = nil
            sender.imagePosition = .noImage
            sender.toolTip = "Click again to archive"
            sender.invalidateIntrinsicContentSize()
            sender.superview?.needsLayout = true
            pin?.isHidden = true
        } confirmArchive: { [weak self, weak c] in
            guard let self, let c else { return }
            onArchive?(c)
        }
    }

    private func cancelPendingArchive(immediate: Bool) {
        archiveConfirmation.cancelPending(immediate: immediate) { [weak self] in
            self?.reload()
        }
    }

    private func addMoreToggle(_ w: Workspace, total: Int) {
        let isOpen = expanded.contains(w.path)
        let title = isOpen ? "Show less" : "Show \(total - pageSize) more"
        let row = SidebarRowsChrome.moreToggleRow(title: title) { [weak self] in
            guard let self else { return }
            if isOpen { self.expanded.remove(w.path) } else { self.expanded.insert(w.path) }
            self.reload()
        }
        fullWidth(row)
    }

    private func select(_ c: Conversation) {
        c.unread = false
        selectConversation(c)
        onSelect?(c)
    }

    // MARK: Context menu

    private func menu(for c: Conversation) -> NSMenu {
        let m = NSMenu()
        let rename = NSMenuItem(title: "Rename", action: #selector(doRename(_:)), keyEquivalent: "")
        let pin = NSMenuItem(title: c.pinned ? "Unpin" : "Pin", action: #selector(doPin(_:)), keyEquivalent: "")
        let fork = NSMenuItem(title: "Fork", action: #selector(doFork(_:)), keyEquivalent: "")
        let archive = NSMenuItem(title: "Archive", action: #selector(doArchive(_:)), keyEquivalent: "")
        for it in [rename, pin, fork, archive] { it.target = self; it.representedObject = c }
        m.addItem(rename); m.addItem(pin); m.addItem(fork); m.addItem(.separator()); m.addItem(archive)
        return m
    }

    @objc private func doRename(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? Conversation else { return }
        let a = NSAlert(); a.messageText = "Rename Chat"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = c.title; a.accessoryView = tf
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { c.title = name; onRename?(c) }
    }
    @objc private func doPin(_ sender: NSMenuItem) { (sender.representedObject as? Conversation).map { onPin?($0) } }
    @objc private func doFork(_ sender: NSMenuItem) { (sender.representedObject as? Conversation).map { onFork?($0) } }
    @objc private func doArchive(_ sender: NSMenuItem) { (sender.representedObject as? Conversation).map { onArchive?($0) } }
}
