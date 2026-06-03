import AppKit

final class SearchPanel: NSPanel {
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

final class PaddedSearchFieldCell: NSSearchFieldCell {
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

final class PaddedSearchField: NSSearchField {
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

final class SearchBackdropView: NSView {
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

enum SearchOverlayChrome {
    static let panelSize = NSSize(width: 800, height: 620)
    static let backdropAlpha: CGFloat = 0.34
    static let cardTop: CGFloat = 86
    static let cardSize = NSSize(width: 620, height: 430)
    static let fieldHeight: CGFloat = 42
    static let rowHeight: CGFloat = 46

    static func makePanel() -> SearchPanel {
        let panel = SearchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        return panel
    }

    static func makeBackdrop(onOutsideClick: @escaping () -> Void) -> SearchBackdropView {
        let root = SearchBackdropView()
        root.wantsLayer = true
        root.layer?.backgroundColor = DesignSystem.Color.backdrop(alpha: backdropAlpha).cgColor
        root.onOutsideClick = onOutsideClick
        return root
    }

    static func makeCard() -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = DesignSystem.Radius.overlayCard
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    static func configureField(_ field: PaddedSearchField, delegate: NSSearchFieldDelegate, onEscape: @escaping () -> Void) {
        field.cell = PaddedSearchFieldCell(textCell: "")
        field.placeholderString = "Search chats"
        field.font = DesignSystem.Font.overlaySearch
        field.cell?.font = field.font
        field.focusRingType = .none
        field.delegate = delegate
        field.onEscape = onEscape
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    static func makeScroll(onScroll: @escaping () -> Void) -> SidebarScrollView {
        let scroll = SidebarScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.onScroll = onScroll
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }

    static func configureStack(_ stack: NSStackView, in document: NSView) {
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignSystem.Spacing.xSmall
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
    }

    static func rootConstraints(
        root: NSView,
        card: NSView,
        field: NSView,
        scroll: NSScrollView,
        document: NSView,
        stack: NSStackView
    ) -> [NSLayoutConstraint] {
        [
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: cardTop),
            card.widthAnchor.constraint(equalToConstant: cardSize.width),
            card.heightAnchor.constraint(equalToConstant: cardSize.height),
            field.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            field.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            field.heightAnchor.constraint(equalToConstant: fieldHeight),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ]
    }

    static func makeRow(model: SearchOverlayRowModel, onClick: @escaping () -> Void) -> SidebarRow {
        SidebarRow(height: rowHeight, onClick: onClick) { container in
            let title = NSTextField(labelWithString: model.title)
            title.font = DesignSystem.Font.overlayRowTitle
            title.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 1
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let detail = NSTextField(labelWithString: model.detail)
            detail.font = DesignSystem.Font.overlayRowDetail
            detail.textColor = .tertiaryLabelColor
            detail.lineBreakMode = .byTruncatingTail
            detail.maximumNumberOfLines = 1
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            for view in [title, detail] {
                view.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(view)
            }
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                title.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
                detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
                detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            ])
        }
    }
}
