import AppKit

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

        let panel = SearchOverlayChrome.makePanel()
        super.init(window: panel)
        panel.onEscape = { [weak self] in self?.close() }

        let root = SearchOverlayChrome.makeBackdrop { [weak self] in self?.close() }

        let card = SearchOverlayChrome.makeCard()
        root.card = card

        SearchOverlayChrome.configureField(field, delegate: self) { [weak self] in self?.close() }
        let scroll = SearchOverlayChrome.makeScroll { [weak self] in self?.rows.forEach { $0.clearHover() } }
        let doc = FlippedView()
        SearchOverlayChrome.configureStack(stack, in: doc)
        scroll.documentView = doc

        card.addSubview(field)
        card.addSubview(scroll)
        root.addSubview(card)
        NSLayoutConstraint.activate(SearchOverlayChrome.rootConstraints(
            root: root,
            card: card,
            field: field,
            scroll: scroll,
            document: doc,
            stack: stack
        ))
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
        let matches = SearchOverlayModel.matches(
            conversations: allConversations(),
            query: field.stringValue
        )
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        for c in matches {
            let rowModel = SearchOverlayModel.rowModel(for: c)
            let row = SearchOverlayChrome.makeRow(model: rowModel) { [weak self, weak c] in
                guard let self, let c else { return }
                self.close()
                self.onSelect(c)
            }
            stack.addArrangedSubview(row)
            rows.append(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}
