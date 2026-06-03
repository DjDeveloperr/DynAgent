import AppKit

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class PaddedSearchFieldCell: NSSearchFieldCell {
    private let leftInset: CGFloat = 12
    private let rightInset: CGFloat = 12

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect).insetBy(dx: 0, dy: 2)
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        super.searchButtonRect(forBounds: rect).offsetBy(dx: leftInset - 2, dy: 0)
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        super.cancelButtonRect(forBounds: rect).offsetBy(dx: -rightInset + 2, dy: 0)
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var text = super.searchTextRect(forBounds: rect)
        text.origin.x += leftInset
        text.size.width -= leftInset + rightInset
        return text
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

private final class PaddedSearchField: NSSearchField {
    var onEscape: (() -> Void)?
    override class var cellClass: AnyClass? {
        get { PaddedSearchFieldCell.self }
        set {}
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class SearchBackdropView: NSView {
    weak var card: NSView?
    var onOutsideClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let card, card.frame.contains(point) {
            super.mouseDown(with: event)
        } else {
            onOutsideClick?()
        }
    }
}

final class SearchOverlayController: NSWindowController, NSSearchFieldDelegate {
    private let allConversations: () -> [Conversation]
    private let onSelect: (Conversation) -> Void
    private let field = PaddedSearchField()
    private let stack = NSStackView()
    private weak var parentWindow: NSWindow?
    private var rows: [SidebarRow] = []

    init(allConversations: @escaping () -> [Conversation], onSelect: @escaping (Conversation) -> Void) {
        self.allConversations = allConversations
        self.onSelect = onSelect

        let panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                                styleMask: [.borderless, .fullSizeContentView],
                                backing: .buffered,
                                defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        super.init(window: panel)
        panel.onEscape = { [weak self] in self?.close() }

        let root = SearchBackdropView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
        root.onOutsideClick = { [weak self] in self?.close() }

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        root.card = card

        field.placeholderString = "Search chats"
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.cell = PaddedSearchFieldCell(textCell: "")
        field.cell?.font = field.font
        field.focusRingType = .none
        field.delegate = self
        field.onEscape = { [weak self] in self?.close() }
        field.translatesAutoresizingMaskIntoConstraints = false

        let scroll = SidebarScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.onScroll = { [weak self] in self?.rows.forEach { $0.clearHover() } }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        card.addSubview(field)
        card.addSubview(scroll)
        root.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: 86),
            card.widthAnchor.constraint(equalToConstant: 620),
            card.heightAnchor.constraint(equalToConstant: 430),

            field.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            field.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            field.heightAnchor.constraint(equalToConstant: 42),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        panel.contentView = root
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(over parent: NSWindow) {
        guard let window else { return }
        parentWindow = parent
        window.setFrame(parent.frame, display: true)
        parent.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    override func close() {
        if let window { parentWindow?.removeChildWindow(window) }
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() }
        else { super.keyDown(with: event) }
    }

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    private func reload() {
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = allConversations()
            .filter { query.isEmpty || $0.title.lowercased().contains(query) || $0.messages.contains { $0.text.lowercased().contains(query) } }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(14)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        for c in matches {
            let row = SidebarRow(height: 46, onClick: { [weak self, weak c] in
                guard let self, let c else { return }
                self.close()
                self.onSelect(c)
            }) { container in
                let title = NSTextField(labelWithString: c.title)
                title.font = .systemFont(ofSize: 14, weight: .medium)
                title.lineBreakMode = .byTruncatingTail
                title.maximumNumberOfLines = 1
                title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                let detail = NSTextField(labelWithString: (c.workspace as NSString).lastPathComponent)
                detail.font = .systemFont(ofSize: 11.5)
                detail.textColor = .tertiaryLabelColor
                detail.lineBreakMode = .byTruncatingTail
                detail.maximumNumberOfLines = 1
                detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                for v in [title, detail] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
                NSLayoutConstraint.activate([
                    title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                    title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                    title.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
                    detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                    detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
                    detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
                ])
            }
            stack.addArrangedSubview(row)
            rows.append(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}
