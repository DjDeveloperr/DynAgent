import AppKit

enum AppToolbarID {
    static let navBack = NSToolbarItem.Identifier("navBack")
    static let navForward = NSToolbarItem.Identifier("navForward")
    static let addWorkspace = NSToolbarItem.Identifier("addWorkspace")
    static let gitScope = NSToolbarItem.Identifier("gitScope")
    static let gitCommit = NSToolbarItem.Identifier("gitCommit")
    static let git = NSToolbarItem.Identifier("git")
    static let chatTitle = NSToolbarItem.Identifier("chatTitle")

    static let defaultIdentifiers: [NSToolbarItem.Identifier] = [
        .toggleSidebar,
        navBack,
        navForward,
        .flexibleSpace,
        addWorkspace,
        .sidebarTrackingSeparator,
        chatTitle,
        .flexibleSpace,
        gitScope,
        gitCommit,
        git,
    ]
}

enum AppToolbarChrome {
    static func makeMainToolbar(delegate: NSToolbarDelegate) -> NSToolbar {
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    static func configureNavigationButton(
        _ button: NSButton,
        symbol: String,
        target: AnyObject,
        action: Selector,
        tooltip: String
    ) -> NSButton {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = target
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    static func texturedIconButton(
        symbol: String,
        target: AnyObject,
        action: Selector,
        tooltip: String
    ) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
            target: target,
            action: action
        )
        button.bezelStyle = .texturedRounded
        button.toolTip = tooltip
        return button
    }

    static func configureNativeActionItem(
        _ item: NSToolbarItem,
        symbol: String,
        label: String,
        tooltip: String,
        target: AnyObject,
        action: Selector
    ) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tooltip
        item.target = target
        item.action = action
    }

    static func configureScopeItem(_ item: NSToolbarItem, control: NSControl) {
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: 112),
            control.heightAnchor.constraint(equalToConstant: 24),
        ])
        item.view = control
        item.label = "Diff Scope"
        item.paletteLabel = "Diff Scope"
        item.toolTip = "Show all or staged changes"
    }

    static func makeChatTitleView(
        titleLabel: NSTextField,
        menuButton: NSButton,
        target: AnyObject,
        menuAction: Selector
    ) -> NSView {
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        menuButton.isBordered = false
        menuButton.contentTintColor = .secondaryLabelColor
        menuButton.target = target
        menuButton.action = menuAction
        menuButton.toolTip = "Chat actions"
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, menuButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 11, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            menuButton.widthAnchor.constraint(equalToConstant: 24),
            menuButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        return stack
    }
}
