import AppKit
import XCTest
@testable import DynAgentUI

final class AppMenuChromeTests: XCTestCase {
    func testMainMenuPreservesTopLevelSections() {
        let menu = AppMenuChrome.makeMainMenu(target: Target(), selectors: selectors)

        XCTAssertEqual(menu.items.compactMap { $0.submenu?.title }, [
            "DynAgent",
            "File",
            "Edit",
            "Window",
        ])
    }

    func testFileMenuUsesAppTargetForChatActionsAndResponderChainForWindowCommands() throws {
        let target = Target()
        let menu = AppMenuChrome.makeMainMenu(target: target, selectors: selectors)
        let file = try submenu("File", in: menu)

        let newChat = try item("New Chat", in: file)
        XCTAssertTrue(newChat.target === target)
        XCTAssertEqual(newChat.action, #selector(Target.newChat))
        XCTAssertEqual(newChat.keyEquivalent, "n")
        XCTAssertEqual(newChat.keyEquivalentModifierMask, .command)

        let search = try item("Search Chats", in: file)
        XCTAssertTrue(search.target === target)
        XCTAssertEqual(search.action, #selector(Target.search))
        XCTAssertEqual(search.keyEquivalent, "k")

        let reload = try item("Reload UI", in: file)
        XCTAssertNil(reload.target)
        XCTAssertEqual(reload.action, Selector(("dynagentReloadUI:")))

        let close = try item("Close Window", in: file)
        XCTAssertNil(close.target)
        XCTAssertEqual(close.action, #selector(NSWindow.performClose(_:)))
    }

    func testEditMenuKeepsStandardResponderChainItems() throws {
        let menu = AppMenuChrome.makeMainMenu(target: Target(), selectors: selectors)
        let edit = try submenu("Edit", in: menu)

        XCTAssertEqual(edit.items.map(\.title), [
            "Undo",
            "Redo",
            "",
            "Cut",
            "Copy",
            "Paste",
            "Select All",
        ])
        XCTAssertEqual(try item("Redo", in: edit).keyEquivalentModifierMask, [.command, .shift])
        XCTAssertNil(try item("Copy", in: edit).target)
        XCTAssertEqual(try item("Paste", in: edit).action, #selector(NSText.paste(_:)))
    }

    func testAppAndWindowMenusUseSystemSelectors() throws {
        let menu = AppMenuChrome.makeMainMenu(target: Target(), selectors: selectors)

        let app = try submenu("DynAgent", in: menu)
        XCTAssertEqual(try item("Hide DynAgent", in: app).action, #selector(NSApplication.hide(_:)))
        XCTAssertEqual(try item("Quit DynAgent", in: app).action, #selector(NSApplication.terminate(_:)))

        let window = try submenu("Window", in: menu)
        XCTAssertEqual(try item("Minimize", in: window).action, #selector(NSWindow.performMiniaturize(_:)))
    }

    private var selectors: AppMenuSelectors {
        AppMenuSelectors(
            newChat: #selector(Target.newChat),
            searchChats: #selector(Target.search)
        )
    }

    private func submenu(_ title: String, in menu: NSMenu, file: StaticString = #filePath, line: UInt = #line) throws -> NSMenu {
        try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == title }, file: file, line: line)
    }

    private func item(_ title: String, in menu: NSMenu, file: StaticString = #filePath, line: UInt = #line) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.title == title }, file: file, line: line)
    }

    private final class Target: NSObject {
        @objc func newChat() {}
        @objc func search() {}
    }
}
