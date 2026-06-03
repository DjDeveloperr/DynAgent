import AppKit

enum SettingsOverlayChrome {
    static let pillHeight: CGFloat = 38
    static let pillHorizontalInset: CGFloat = 10
    static let buttonHorizontalInset: CGFloat = 12

    static func configurePill(
        _ pill: NSVisualEffectView,
        button: NSButton,
        target: AnyObject,
        menuAction: Selector
    ) {
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = DesignSystem.Radius.floatingPill
        pill.layer?.masksToBounds = true
        pill.layer?.zPosition = 50
        pill.translatesAutoresizingMaskIntoConstraints = false

        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.font = DesignSystem.Font.controlSmall
        button.alignment = .left
        button.target = target
        button.action = menuAction
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    static func install(_ pill: NSVisualEffectView, button: NSButton, over host: NSView) {
        if button.superview !== pill {
            pill.addSubview(button)
        }
        if pill.superview !== host {
            host.addSubview(pill, positioned: .above, relativeTo: nil)
        }
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pillHorizontalInset),
            pill.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -pillHorizontalInset),
            pill.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pillHorizontalInset),
            pill.heightAnchor.constraint(equalToConstant: pillHeight),
            button.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: buttonHorizontalInset),
            button.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -buttonHorizontalInset),
            button.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    static func makeMenu(usageTitle: String, target: AnyObject, settingsAction: Selector) -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings", action: settingsAction, keyEquivalent: "")
        settings.target = target
        let usage = NSMenuItem(title: usageTitle, action: nil, keyEquivalent: "")
        usage.isEnabled = false
        menu.addItem(settings)
        menu.addItem(usage)
        return menu
    }

    static func popUp(_ menu: NSMenu, from sender: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    static func makeSettingsAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "DynAgent settings will appear here as the native controls land."
        alert.addButton(withTitle: "Done")
        return alert
    }
}
