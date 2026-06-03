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
    private var hoverTipWorkItem: DispatchWorkItem?

    override func loadView() {
        let scroll = SidebarScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
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
        view = scroll
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
        hoverTipWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak row] in
            guard let self, let row, row.window != nil else { return }
            self.hoverTip.show(title: title, detail: detail, near: row)
        }
        hoverTipWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func hideHoverTip() {
        hoverTipWorkItem?.cancel()
        hoverTipWorkItem = nil
        hoverTip.orderOut(nil)
    }

    private func clearHoverState() {
        hideHoverTip()
        hoveredRow?.clearHover()
        hoveredRow = nil
        if archiveConfirmation.hasPendingArchive {
            cancelPendingArchive(immediate: true)
        }
    }

    private func singleLineLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = .systemFont(ofSize: size, weight: weight)
        tf.textColor = color
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.cell?.usesSingleLineMode = true
        tf.cell?.truncatesLastVisibleLine = true
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }

    private func addTopActions() {
        let row = actionRow("square.and.pencil", "New Chat") { [weak self] in self?.onGlobalNewChat?() }
        row.selected = newChatSelected
        newChatRow = row
        fullWidth(row)
        fullWidth(actionRow("magnifyingglass", "Search") { [weak self] in self?.onSearch?() })
    }

    private func actionRow(_ symbol: String, _ title: String, trailingSymbol: String? = nil, trailingTooltip: String? = nil, trailingAction: (() -> Void)? = nil, action: @escaping () -> Void) -> SidebarRow {
        SidebarRow(height: 36, onClick: action) { container in
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage())
            icon.contentTintColor = .labelColor
            let tf = singleLineLabel(title, size: 15, weight: .regular)
            var trailing: NSButton?
            if let trailingSymbol, let trailingAction {
                let button = SidebarActionButton(symbol: trailingSymbol, tooltip: trailingTooltip)
                button.handler = { _ in trailingAction() }
                trailing = button
                container.addSubview(button)
            }
            for v in [icon, tf] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            if let trailing {
                NSLayoutConstraint.activate([
                    tf.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -8),
                    trailing.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                    trailing.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    trailing.widthAnchor.constraint(equalToConstant: 24),
                    trailing.heightAnchor.constraint(equalToConstant: 24),
                ])
            } else {
                tf.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8).isActive = true
            }
        }
    }

    private func addSectionHeader(_ title: String, expanded: Bool, addSymbol: String? = nil, addToolTip: String? = nil, addAction: (() -> Void)? = nil, action: @escaping () -> Void) {
        var hoverButtons: [NSView] = []
        let row = SidebarRow(height: 30, onClick: action, showsHoverBackground: false, onHoverChanged: { hovering in
            hoverButtons.forEach { $0.isHidden = !hovering }
        }) { container in
            let tf = singleLineLabel(title, size: 12.5, weight: .semibold, color: .tertiaryLabelColor)
            let chevron = NSImageView(image: NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) ?? NSImage())
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.isHidden = true
            hoverButtons.append(chevron)
            for v in [tf, chevron] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
            if let addSymbol, let addAction {
                let button = NSButton(image: NSImage(systemSymbolName: addSymbol, accessibilityDescription: addToolTip)!, target: nil, action: nil)
                button.isBordered = false
                button.contentTintColor = .tertiaryLabelColor
                button.toolTip = addToolTip
                button.isHidden = true
                button.translatesAutoresizingMaskIntoConstraints = false
                button.target = self
                button.action = #selector(sectionAddClicked(_:))
                sectionAddActions[ObjectIdentifier(button)] = addAction
                hoverButtons.append(button)
                container.addSubview(button)
                NSLayoutConstraint.activate([
                    button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                    button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                ])
            }
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                chevron.leadingAnchor.constraint(equalTo: tf.trailingAnchor, constant: 6),
                chevron.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
        fullWidth(row)
    }

    private func addWorkspaceHeader(_ w: Workspace) {
        let model = SidebarRowModel.workspace(w)
        var hoverViews: [NSView] = []
        var rowRef: SidebarRow?
        let row = SidebarRow(height: 34, onClick: { [weak self] in self?.toggleWorkspace(w) }, onHoverChanged: { [weak self] hovering in
            hoverViews.forEach { $0.isHidden = !hovering }
            guard let self, let row = rowRef else { return }
            if hovering { self.scheduleHoverTip(title: model.tooltip.title, detail: model.tooltip.detail, row: row) }
            else { self.hideHoverTip() }
        }) { container in
            let icon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            let tf = singleLineLabel(model.name, size: 14.5, weight: .regular, color: .secondaryLabelColor)
            let newChat = SidebarActionButton(symbol: "square.and.pencil", tooltip: "New chat")
            newChat.isHidden = true
            newChat.handler = { [weak self] _ in self?.onNewChat?(w) }
            hoverViews.append(newChat)
            for v in [icon, tf, newChat] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: newChat.leadingAnchor, constant: -6),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                newChat.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                newChat.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                newChat.widthAnchor.constraint(equalToConstant: 24),
                newChat.heightAnchor.constraint(equalToConstant: 24),
            ])
        }
        rowRef = row
        fullWidth(row)
    }

    private func addEmptyWorkspaceRow() {
        let row = SidebarRow(height: 26, onClick: {}, showsHoverBackground: false) { container in
            let tf = singleLineLabel("No chats", size: 13, weight: .regular, color: .tertiaryLabelColor)
            container.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 34),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
        fullWidth(row)
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
        weak var pinButton: SidebarActionButton?
        weak var archiveButton: SidebarActionButton?
        weak var timeLabel: NSTextField?
        weak var worktreeIcon: NSImageView?
        weak var spinnerView: Spinner?
        var titleToTime: NSLayoutConstraint?
        var titleToActions: NSLayoutConstraint?
        var rowRef: SidebarRow?
        let row = SidebarRow(height: 32, onClick: { [weak self] in self?.select(c) }, menu: { [weak self] in self?.menu(for: c) ?? NSMenu() }, onHoverChanged: { [weak self] hovering in
            guard let self else { return }
            let confirming = self.archiveConfirmation.isConfirming(conversationId: c.id)
            pinButton?.isHidden = !hovering || confirming
            archiveButton?.isHidden = !hovering && !confirming
            timeLabel?.isHidden = model.isWorking || hovering || confirming
            worktreeIcon?.isHidden = !model.isWorktree || model.isWorking || hovering || confirming
            spinnerView?.isHidden = !model.isWorking || hovering || confirming
            titleToTime?.isActive = !hovering && !confirming
            titleToActions?.isActive = hovering || confirming
            self.archiveConfirmation.updateHover(
                hovering: hovering,
                conversationId: c.id,
                cancelAndReload: { [weak self] in self?.reload() }
            )
            if let row = rowRef {
                if hovering { self.scheduleHoverTip(title: model.tooltip.title, detail: model.tooltip.detail, row: row) }
                else { self.hideHoverTip() }
            }
        }) { container in
            let tf = singleLineLabel(model.title, size: 14.5)
            let time = NSTextField(labelWithString: model.timeLabel)
            time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            time.textColor = model.isWorking ? .secondaryLabelColor : .tertiaryLabelColor
            time.lineBreakMode = .byTruncatingTail
            time.maximumNumberOfLines = 1
            time.cell?.usesSingleLineMode = true
            time.cell?.truncatesLastVisibleLine = true
            time.setContentCompressionResistancePriority(.required, for: .horizontal)
            time.setContentHuggingPriority(.required, for: .horizontal)
            time.translatesAutoresizingMaskIntoConstraints = false
            let branchIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Worktree")?
                .withSymbolConfiguration(.init(pointSize: 10.5, weight: .regular)) ?? NSImage())
            branchIcon.contentTintColor = .tertiaryLabelColor
            branchIcon.isHidden = !model.isWorktree || model.isWorking
            branchIcon.translatesAutoresizingMaskIntoConstraints = false
            let pin = SidebarActionButton(symbol: model.isPinned ? "pin.slash" : "pin", tooltip: model.isPinned ? "Unpin" : "Pin")
            pin.isHidden = true
            pin.handler = { [weak self, weak c] _ in
                guard let self, let c else { return }
                self.cancelPendingArchive(immediate: true)
                self.onPin?(c)
            }
            let archive = SidebarActionButton(symbol: "archivebox", tooltip: "Archive")
            archive.toolTip = "Archive"
            archive.isHidden = true
            archive.handler = { [weak self, weak c, weak pin] button in
                guard let self, let c else { return }
                self.archiveButtonClicked(button, conversation: c, pin: pin)
            }
            pinButton = pin
            archiveButton = archive
            timeLabel = time
            worktreeIcon = branchIcon
            container.addSubview(tf)
            container.addSubview(branchIcon)
            container.addSubview(time)
            container.addSubview(pin)
            container.addSubview(archive)
            titleToTime = tf.trailingAnchor.constraint(lessThanOrEqualTo: model.isWorktree ? branchIcon.leadingAnchor : time.leadingAnchor, constant: -8)
            titleToActions = tf.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -8)
            titleToActions?.isActive = false
            // Title left-padded to align with workspace labels.
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                archive.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                archive.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                archive.heightAnchor.constraint(equalToConstant: 24),
                archive.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
                pin.trailingAnchor.constraint(equalTo: archive.leadingAnchor, constant: -2),
                pin.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                pin.widthAnchor.constraint(equalToConstant: 24),
                pin.heightAnchor.constraint(equalToConstant: 24),
                time.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                time.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                branchIcon.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -4),
                branchIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                branchIcon.widthAnchor.constraint(equalToConstant: 12),
                branchIcon.heightAnchor.constraint(equalToConstant: 12),
                titleToTime!,
            ])
            // Blue unread dot in the left icon slot (only when unread).
            if model.isUnread {
                let dot = NSView()
                dot.wantsLayer = true; dot.layer?.cornerRadius = 3.5
                dot.layer?.backgroundColor = NSColor.systemBlue.cgColor
                dot.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(dot)
                NSLayoutConstraint.activate([
                    dot.centerXAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
                    dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    dot.widthAnchor.constraint(equalToConstant: 7), dot.heightAnchor.constraint(equalToConstant: 7),
                ])
            }
            // Smooth spinner on the right while the agent is working.
            if model.isWorking {
                let spinner = Spinner()
                spinnerView = spinner
                container.addSubview(spinner)
                time.isHidden = true
                NSLayoutConstraint.activate([
                    spinner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                    spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    spinner.widthAnchor.constraint(equalToConstant: 14), spinner.heightAnchor.constraint(equalToConstant: 14),
                    tf.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -6),
                ])
            }
        }
        rowRef = row
        row.selected = (c.id == selectedId)
        rowsById[c.id] = row
        fullWidth(row)
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
        let row = SidebarRow(height: 26, onClick: { [weak self] in
            guard let self else { return }
            if isOpen { self.expanded.remove(w.path) } else { self.expanded.insert(w.path) }
            self.reload()
        }) { container in
            let tf = singleLineLabel(isOpen ? "Show less" : "Show \(total - self.pageSize) more", size: 12, weight: .medium, color: .tertiaryLabelColor)
            container.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
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
