import AppKit

enum ChatEmptyStateChrome {
    static let titleFont = DesignSystem.Font.emptyStateTitle
    static let subtitleFont = DesignSystem.Font.emptyStateSubtitle
    static let subtitleMaxWidth: CGFloat = 420
    static let stackSpacing = DesignSystem.Spacing.large
    static let actionSpacing = DesignSystem.Spacing.large
    static let actionHeight: CGFloat = 30
    static let actionCornerRadius = DesignSystem.Radius.compactGlassControl
    static let actionLeadingInset = DesignSystem.Spacing.large
    static let actionTrailingInset = DesignSystem.Spacing.medium
    static let newWorktreeWidth: CGFloat = 142
    static let addWorkspaceWidth: CGFloat = 150

    static func configureTitle(_ title: NSTextField) {
        title.font = titleFont
        title.alignment = .center
    }

    static func configureSubtitle(_ subtitle: NSTextField) {
        subtitle.font = subtitleFont
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 3
        subtitle.preferredMaxLayoutWidth = subtitleMaxWidth
    }

    static func configureStack(_ stack: NSStackView, title: NSTextField, subtitle: NSTextField, actions: NSStackView) {
        stack.orientation = .vertical
        stack.spacing = stackSpacing
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(actions)
        stack.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configureActions(_ actions: NSStackView) {
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = actionSpacing
    }

    static func makeAction(title: String, symbol: String, target: AnyObject, action: Selector) -> NSView {
        let button = NSButton(title: title, target: target, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.controlSize = .large
        button.font = DesignSystem.Font.actionButton
        button.translatesAutoresizingMaskIntoConstraints = false
        return glassControl(button, minWidth: minWidth(for: title))
    }

    static func minWidth(for title: String) -> CGFloat {
        title == "New Worktree" ? newWorktreeWidth : addWorkspaceWidth
    }

    static func glassControl(_ control: NSView, minWidth: CGFloat) -> NSView {
        let shell = NSVisualEffectView()
        shell.material = .menu
        shell.blendingMode = .withinWindow
        shell.state = .active
        shell.wantsLayer = true
        shell.layer?.cornerRadius = actionCornerRadius
        shell.layer?.masksToBounds = true
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(control)
        NSLayoutConstraint.activate([
            shell.heightAnchor.constraint(equalToConstant: actionHeight),
            shell.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            control.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: actionLeadingInset),
            control.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -actionTrailingInset),
            control.centerYAnchor.constraint(equalTo: shell.centerYAnchor),
        ])
        return shell
    }
}
