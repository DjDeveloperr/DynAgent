import AppKit

/// Left pane: workspaces (group rows) with their conversations, plus a credits
/// overlay pinned to the bottom.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var workspaces: [Workspace] = []
    var onSelect: ((Conversation) -> Void)?
    var onSelectWorkspace: ((Workspace) -> Void)?

    private let outline = NSOutlineView()

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.rowHeight = 28
        outline.indentationPerLevel = 8
        outline.style = .sourceList
        outline.floatsGroupRows = false
        let col = NSTableColumn(identifier: .init("c"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.dataSource = self
        outline.delegate = self
        scroll.documentView = outline
        view = scroll
    }

    func reload(selecting: Conversation? = nil) {
        outline.reloadData()
        workspaces.forEach { outline.expandItem($0) }
        if let c = selecting {
            let r = outline.row(forItem: c)
            if r >= 0 { outline.selectRowIndexes([r], byExtendingSelection: false) }
        }
    }

    // MARK: Data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Workspace)?.conversations.count ?? workspaces.count
    }
    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Workspace)?.conversations[index] ?? workspaces[index]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { item is Workspace }

    // MARK: Delegate

    func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool { item is Workspace }
    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

    func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
        if let w = item as? Workspace {
            let l = NSTextField(labelWithString: w.name.uppercased())
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingTail
            l.toolTip = w.path
            return l
        }
        let c = item as! Conversation
        let dot = NSTextField(labelWithString: "●")
        dot.font = .systemFont(ofSize: 9)
        dot.textColor = statusColor(c.status)
        let title = NSTextField(labelWithString: c.title)
        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: 13)
        let row = NSStackView(views: [dot, title] as [NSView])
        row.orientation = .horizontal
        row.spacing = 7
        return row
    }

    func outlineViewSelectionDidChange(_ note: Notification) {
        let item = outline.item(atRow: outline.selectedRow)
        if let c = item as? Conversation { onSelect?(c) }
        else if let w = item as? Workspace { onSelectWorkspace?(w) }
    }

    private func statusColor(_ s: Conversation.Status) -> NSColor {
        switch s {
        case .idle: return .tertiaryLabelColor
        case .thinking: return .systemBlue
        case .running: return .systemOrange
        case .error: return .systemRed
        }
    }
}
