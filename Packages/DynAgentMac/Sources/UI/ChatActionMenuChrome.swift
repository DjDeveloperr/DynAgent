import AppKit

struct ChatActionMenuSelectors {
    let pin: Selector
    let rename: Selector
    let archive: Selector
    let openInNewWindow: Selector
}

enum ChatActionMenuChrome {
    static func makeMenu(
        isPinned: Bool,
        target: AnyObject,
        selectors: ChatActionMenuSelectors
    ) -> NSMenu {
        let menu = NSMenu()
        let pin = item(
            title: isPinned ? "Unpin Chat" : "Pin Chat",
            action: selectors.pin,
            target: target
        )
        let rename = item(
            title: "Rename Chat",
            action: selectors.rename,
            target: target
        )
        let archive = item(
            title: "Archive Chat",
            action: selectors.archive,
            target: target
        )
        let open = item(
            title: "Open in a New Window",
            action: selectors.openInNewWindow,
            target: target
        )

        menu.addItem(pin)
        menu.addItem(rename)
        menu.addItem(archive)
        menu.addItem(.separator())
        menu.addItem(open)
        return menu
    }

    static func popUp(_ menu: NSMenu, from sender: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private static func item(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
