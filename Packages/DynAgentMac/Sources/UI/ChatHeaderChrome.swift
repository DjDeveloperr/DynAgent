import AppKit

enum ChatHeaderChrome {
    static let titleFont = DesignSystem.Font.chatHeaderTitle
    static let menuButtonSize = NSSize(width: 24, height: 22)
    static let titleLeadingInset: CGFloat = 14
    static let titleTopInset: CGFloat = 15
    static let titleToButtonSpacing: CGFloat = 6
    static let titleTrailingSpacing: CGFloat = 4

    static func configureTitle(_ title: NSTextField) {
        DesignSystem.configureLabel(title, style: DesignSystem.Text.chatHeaderTitle)
        title.isHidden = true
    }

    static func configureMenuButton(_ button: NSButton, target: AnyObject, action: Selector) {
        button.image = DesignSystem.symbolImage(
            "ellipsis",
            accessibilityDescription: "Chat actions",
            pointSize: DesignSystem.Symbol.toolbarPointSize
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.isHidden = true
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    static func constraints(title: NSTextField, menuButton: NSButton, root: NSView) -> [NSLayoutConstraint] {
        [
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: titleLeadingInset),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: titleTopInset),
            title.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -titleTrailingSpacing),
            menuButton.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: titleToButtonSpacing),
            menuButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: menuButtonSize.width),
            menuButton.heightAnchor.constraint(equalToConstant: menuButtonSize.height),
        ]
    }
}
