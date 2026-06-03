import AppKit

final class ChromeIconButton: NSButton {
    var handler: ((ChromeIconButton) -> Void)?

    init(symbol: String, tooltip: String? = nil, pointSize: CGFloat = 12, weight: NSFont.Weight = .semibold) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .tertiaryLabelColor
        toolTip = tooltip
        target = self
        action = #selector(run)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func run() {
        handler?(self)
    }
}

typealias SidebarActionButton = ChromeIconButton

final class ComposerMenuChrome: NSView {
    let popup: NSPopUpButton
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold)) ?? NSImage())
    private let minWidth: CGFloat
    var displayProvider: (() -> NSAttributedString?)?

    init(popup: NSPopUpButton, minWidth: CGFloat) {
        self.popup = popup
        self.minWidth = minWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        popup.alphaValue = 0.01
        popup.translatesAutoresizingMaskIntoConstraints = false
        label.font = DesignSystem.Font.controlLabel
        label.textColor = DesignSystem.Color.primaryText
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        chevron.contentTintColor = .secondaryLabelColor
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(popup)
        addSubview(label)
        chevron.isHidden = true
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            popup.leadingAnchor.constraint(equalTo: leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: trailingAnchor),
            popup.topAnchor.constraint(equalTo: topAnchor),
            popup.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let labelWidth = max(label.intrinsicContentSize.width, 1)
        return NSSize(width: max(minWidth, labelWidth + 4), height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        popup.performClick(self)
    }

    func refresh() {
        if let display = displayProvider?() {
            label.attributedStringValue = display
        } else {
            label.stringValue = popup.titleOfSelectedItem ?? ""
        }
        invalidateIntrinsicContentSize()
    }
}
