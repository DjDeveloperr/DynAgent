import AppKit

/// A fully custom sidebar row with explicit clear/hover/selected states and right-click menu.
/// Avoids NSOutlineView's selection styling quirks (blue text, focus borders, multi-activation).
final class SidebarRow: NSView {
    private let onClick: () -> Void
    private let menuProvider: (() -> NSMenu)?
    private let onHoverChanged: ((Bool) -> Void)?
    private let showsHoverBackground: Bool
    var onHoverStart: ((SidebarRow) -> Void)?
    var selected = false { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }

    init(height: CGFloat, onClick: @escaping () -> Void, menu: (() -> NSMenu)? = nil, showsHoverBackground: Bool = true, onHoverChanged: ((Bool) -> Void)? = nil, build: (NSView) -> Void) {
        self.onClick = onClick; self.menuProvider = menu; self.onHoverChanged = onHoverChanged; self.showsHoverBackground = showsHoverBackground
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        build(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) {
        onHoverStart?(self)
        hovering = true
    }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { clearHover() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func mouseDown(with e: NSEvent) { onClick() }
    override func rightMouseDown(with e: NSEvent) {
        guard let m = menuProvider?() else { return super.rightMouseDown(with: e) }
        NSMenu.popUpContextMenu(m, with: e, for: self)
    }

    func clearHover() {
        if hovering { hovering = false }
    }

    private func refresh() {
        let color: NSColor = selected ? .secondaryLabelColor.withAlphaComponent(0.12)
            : (hovering && showsHoverBackground) ? .secondaryLabelColor.withAlphaComponent(0.06) : .clear
        layer?.backgroundColor = color.cgColor
        onHoverChanged?(hovering)
    }
}

final class SidebarScrollView: NSScrollView {
    var onScroll: (() -> Void)?
    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onScroll?()
    }
}

/// A smooth (non-stepped) indeterminate spinner: a rotating accent arc.
final class Spinner: NSView {
    private let ring = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        ring.strokeColor = NSColor.secondaryLabelColor.cgColor
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.lineCap = .round
        layer?.addSublayer(ring)
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0; anim.toValue = -2 * Double.pi
        anim.duration = 0.9; anim.repeatCount = .infinity
        ring.add(anim, forKey: "spin")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let r = bounds.insetBy(dx: 2, dy: 2)
        ring.frame = bounds
        let p = NSBezierPath()
        p.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: r.width / 2,
                    startAngle: 90, endAngle: -150, clockwise: true)
        ring.path = p.cgPath
    }
}

final class SidebarHoverTipWindow: NSPanel {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 52),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.transient, .ignoresCycle]
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.borderWidth = 0
        effect.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        for label in [titleLabel, detailLabel] { label.translatesAutoresizingMaskIntoConstraints = false }
        effect.addSubview(titleLabel)
        effect.addSubview(detailLabel)
        contentView = effect
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 7),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func show(title: String, detail: String, near row: NSView) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        guard let window = row.window else { return }
        let rectInWindow = row.convert(row.bounds, to: nil)
        let rect = window.convertToScreen(rectInWindow)
        let width = min(max((detail as NSString).size(withAttributes: [.font: detailLabel.font!]).width + 24, 220), 360)
        setFrame(NSRect(x: rect.minX + 8, y: rect.maxY + 4, width: width, height: 52), display: false)
        orderFront(nil)
    }
}

/// Left pane: a custom view-based list of workspaces and their conversations.
final class SidebarViewController: NSViewController {
    var workspaces: [Workspace] = []
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
    private var pendingArchiveId: String?
    private var archiveCancelWorkItem: DispatchWorkItem?
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

        var seenPinned = Set<String>()
        let pinned = (workspaces.flatMap(\.conversations) + projectlessConversations)
            .filter(\.pinned)
            .filter { seenPinned.insert($0.codexThreadId ?? $0.id).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !pinned.isEmpty {
            addSectionHeader("Pinned", expanded: pinnedExpanded) { [weak self] in
                guard let self else { return }
                self.pinnedExpanded.toggle()
                self.onPinnedCollapsedChanged?(!self.pinnedExpanded)
                self.reload()
            }
            if pinnedExpanded {
                for c in pinned { addConversationRow(c, indent: 8) }
            }
        }

        let looseChats = projectlessConversations
            .filter { !$0.pinned }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !looseChats.isEmpty {
            addSectionHeader("Chats", expanded: chatsExpanded) { [weak self] in
                guard let self else { return }
                self.chatsExpanded.toggle()
                self.onChatsCollapsedChanged?(!self.chatsExpanded)
                self.reload()
            }
            if chatsExpanded {
                for c in looseChats { addConversationRow(c, indent: 8) }
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
                let convs = w.conversations.filter { !$0.pinned }
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
        if pendingArchiveId != nil {
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
        var hoverViews: [NSView] = []
        var rowRef: SidebarRow?
        let row = SidebarRow(height: 34, onClick: { [weak self] in self?.toggleWorkspace(w) }, onHoverChanged: { [weak self] hovering in
            hoverViews.forEach { $0.isHidden = !hovering }
            guard let self, let row = rowRef else { return }
            if hovering { self.scheduleHoverTip(title: w.name, detail: w.path, row: row) }
            else { self.hideHoverTip() }
        }) { container in
            let icon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            let tf = singleLineLabel(w.name, size: 14.5, weight: .regular, color: .secondaryLabelColor)
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
        let working = (c.status == .thinking || c.status == .running)
        let isWorktree = c.workspace.contains("/worktrees/") || c.workspace.contains("/.worktrees/") || c.workspace.contains("/.codex/worktrees/")
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
            let confirming = self.pendingArchiveId == c.id
            pinButton?.isHidden = !hovering || confirming
            archiveButton?.isHidden = !hovering && !confirming
            timeLabel?.isHidden = working || hovering || confirming
            worktreeIcon?.isHidden = !isWorktree || working || hovering || confirming
            spinnerView?.isHidden = !working || hovering || confirming
            titleToTime?.isActive = !hovering && !confirming
            titleToActions?.isActive = hovering || confirming
            if !hovering, confirming { self.scheduleArchiveCancel(for: c.id) }
            if hovering, confirming { self.archiveCancelWorkItem?.cancel() }
            if let row = rowRef {
                if hovering { self.scheduleHoverTip(title: c.title, detail: c.workspace.nilIfEmpty ?? "No workspace", row: row) }
                else { self.hideHoverTip() }
            }
        }) { container in
            let tf = singleLineLabel(c.title, size: 14.5)
            let time = NSTextField(labelWithString: working ? (c.status == .thinking ? "thinking" : "running") : Self.relativeTime(c.updatedAt))
            time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            time.textColor = working ? .secondaryLabelColor : .tertiaryLabelColor
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
            branchIcon.isHidden = !isWorktree || working
            branchIcon.translatesAutoresizingMaskIntoConstraints = false
            let pin = SidebarActionButton(symbol: c.pinned ? "pin.slash" : "pin", tooltip: c.pinned ? "Unpin" : "Pin")
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
            titleToTime = tf.trailingAnchor.constraint(lessThanOrEqualTo: isWorktree ? branchIcon.leadingAnchor : time.leadingAnchor, constant: -8)
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
            if c.unread {
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
            if working {
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
        if pendingArchiveId == c.id {
            archiveCancelWorkItem?.cancel()
            archiveCancelWorkItem = nil
            pendingArchiveId = nil
            onArchive?(c)
            return
        }
        pendingArchiveId = c.id
        archiveCancelWorkItem?.cancel()
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
    }

    private func scheduleArchiveCancel(for id: String) {
        archiveCancelWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard self?.pendingArchiveId == id else { return }
            self?.cancelPendingArchive(immediate: true)
        }
        archiveCancelWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: item)
    }

    private func cancelPendingArchive(immediate: Bool) {
        let hadPending = pendingArchiveId != nil
        archiveCancelWorkItem?.cancel()
        archiveCancelWorkItem = nil
        pendingArchiveId = nil
        if immediate && hadPending { reload() }
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

    private static func statusColor(_ s: Conversation.Status) -> NSColor {
        switch s {
        case .idle: return .quaternaryLabelColor
        case .thinking: return .systemYellow
        case .running: return .systemBlue
        case .error: return .systemRed
        }
    }

    private static func relativeTime(_ epoch: Double) -> String {
        guard epoch > 0 else { return "" }
        let delta = max(0, Date().timeIntervalSince1970 - epoch)
        if delta < 45 { return "now" }
        if delta < 90 { return "1m" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 5400 { return "1h" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }
        if delta < 172_800 { return "1d" }
        if delta < 604_800 { return "\(Int(delta / 86_400))d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date(timeIntervalSince1970: epoch))
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
