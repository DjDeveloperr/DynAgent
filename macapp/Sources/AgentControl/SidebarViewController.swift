import AppKit

/// Left pane: workspaces (group rows) with their conversations.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var workspaces: [Workspace] = []
    var onSelect: ((Conversation) -> Void)?
    var onSelectWorkspace: ((Workspace) -> Void)?
    var onRename: ((Conversation) -> Void)?
    var onFork: ((Conversation) -> Void)?
    var onArchive: ((Conversation) -> Void)?

    private let outline = NSOutlineView()

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.rowHeight = 32
        outline.indentationPerLevel = 12
        outline.style = .sourceList
        outline.floatsGroupRows = false
        let col = NSTableColumn(identifier: .init("c"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.dataSource = self
        outline.delegate = self
        outline.menu = makeContextMenu()
        scroll.documentView = outline
        view = scroll
    }

    func reload(selecting: Conversation? = nil) {
        outline.reloadData()
        for w in workspaces { outline.expandItem(w) }
        if let c = selecting {
            let r = outline.row(forItem: c)
            if r >= 0 { outline.selectRowIndexes([r], byExtendingSelection: false) }
        }
    }

    // MARK: Data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return workspaces.count }
        if let w = item as? Workspace { return w.conversations.count }
        return 0
    }
    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return workspaces[index] }
        return (item as! Workspace).conversations[index]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { item is Workspace }

    // MARK: Delegate

    func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool { item is Workspace }
    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

    func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
        if let w = item as? Workspace {
            let cell = NSTableCellView()
            let img = NSImageView(image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)!)
            img.contentTintColor = .secondaryLabelColor
            let tf = NSTextField(labelWithString: w.name)
            tf.font = .systemFont(ofSize: 12, weight: .semibold)
            tf.textColor = .secondaryLabelColor
            tf.lineBreakMode = .byTruncatingTail
            cell.addSubview(img)
            cell.addSubview(tf)
            cell.imageView = img
            cell.textField = tf
            img.translatesAutoresizingMaskIntoConstraints = false
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 16),
                img.heightAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        let c = item as! Conversation
        let cell = NSTableCellView()
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = statusColor(c.status).cgColor
        let tf = NSTextField(labelWithString: c.title)
        tf.font = .systemFont(ofSize: 13)
        tf.lineBreakMode = .byTruncatingTail
        cell.addSubview(dot)
        cell.addSubview(tf)
        cell.textField = tf
        dot.translatesAutoresizingMaskIntoConstraints = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            tf.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ note: Notification) {
        let item = outline.item(atRow: outline.selectedRow)
        if let c = item as? Conversation { onSelect?(c) }
        else if let w = item as? Workspace { onSelectWorkspace?(w) }
    }

    // MARK: Context menu

    private func makeContextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Rename", action: #selector(contextRename), keyEquivalent: "")
        m.addItem(withTitle: "Fork", action: #selector(contextFork), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Archive", action: #selector(contextArchive), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }

    private func clickedConversation() -> Conversation? {
        let row = outline.clickedRow
        guard row >= 0 else { return nil }
        return outline.item(atRow: row) as? Conversation
    }

    @objc private func contextRename() {
        guard let c = clickedConversation() else { return }
        let a = NSAlert(); a.messageText = "Rename Chat"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = c.title; a.accessoryView = tf
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { c.title = name; onRename?(c) }
    }

    @objc private func contextFork() { guard let c = clickedConversation() else { return }; onFork?(c) }
    @objc private func contextArchive() { guard let c = clickedConversation() else { return }; onArchive?(c) }

    private func statusColor(_ s: Conversation.Status) -> NSColor {
        switch s {
        case .idle: return .tertiaryLabelColor
        case .thinking: return .systemBlue
        case .running: return .systemOrange
        case .error: return .systemRed
        }
    }
}
