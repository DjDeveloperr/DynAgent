import AppKit

private struct SplitSpec {
    let sideBySide: Bool
    let kind: PanelKind
}

final class TilePanel: FlexibleContainerView {
    let content: NSView
    var splitHandler: ((TilePanel, Bool, PanelKind) -> Void)?
    var closeHandler: ((TilePanel) -> Void)?

    init(title: String, content: NSView, closable: Bool, showsHeader: Bool = true) {
        self.content = content
        super.init(frame: .zero)

        let titleLabel = DesignSystem.label(title, style: DesignSystem.Text.workspacePanelTitle)
        let add = iconButton("plus", #selector(showAddMenu(_:)))
        let close = iconButton("xmark", #selector(doClose))
        close.isHidden = !closable
        let header = NSStackView(views: [titleLabel, NSView(), add, close] as [NSView])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.clear.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(content)
        if showsHeader {
            addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: topAnchor),
                header.leadingAnchor.constraint(equalTo: leadingAnchor),
                header.trailingAnchor.constraint(equalTo: trailingAnchor),
                header.heightAnchor.constraint(equalToConstant: 26),
                content.topAnchor.constraint(equalTo: header.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func iconButton(_ symbol: String, _ action: Selector) -> NSButton {
        DesignSystem.iconButton(
            symbol: symbol,
            target: self,
            action: action
        )
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let specs: [(String, SplitSpec)] = [
            ("Browser  →", .init(sideBySide: true, kind: .browser)),
            ("Browser  ↓", .init(sideBySide: false, kind: .browser)),
            ("Terminal  →", .init(sideBySide: true, kind: .shell)),
            ("Terminal  ↓", .init(sideBySide: false, kind: .shell)),
        ]
        for (title, spec) in specs {
            let item = NSMenuItem(title: title, action: #selector(addItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spec
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addItem(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? SplitSpec else { return }
        splitHandler?(self, spec.sideBySide, spec.kind)
    }

    @objc private func doClose() {
        closeHandler?(self)
    }
}

final class WorkspaceAreaRootView: FlexibleContainerView {
    weak var pinnedSplitView: NSSplitView?

    override func layout() {
        super.layout()
        guard let pinnedSplitView else { return }
        pinnedSplitView.frame = bounds
        pinnedSplitView.adjustSubviews()
        if pinnedSplitView.arrangedSubviews.count == 1 {
            pinnedSplitView.arrangedSubviews.first?.frame = pinnedSplitView.bounds
        }
    }
}
