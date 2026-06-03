import AppKit

struct AppMenuSelectors {
    let newChat: Selector
    let searchChats: Selector
}

enum AppMenuChrome {
    static func makeMainMenu(target: AnyObject, selectors: AppMenuSelectors) -> NSMenu {
        let main = NSMenu()
        main.addItem(menu("DynAgent", [
            item("Hide DynAgent", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit DynAgent", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(menu("File", [
            item("New Chat", selectors.newChat, "n", target: target),
            item("Search Chats", selectors.searchChats, "k", target: target),
            item("Reload UI", Selector(("dynagentReloadUI:")), "r"),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        main.addItem(menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]))
        return main
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let top = NSMenuItem()
        let sub = NSMenu(title: title)
        items.forEach { sub.addItem($0) }
        top.submenu = sub
        return top
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
