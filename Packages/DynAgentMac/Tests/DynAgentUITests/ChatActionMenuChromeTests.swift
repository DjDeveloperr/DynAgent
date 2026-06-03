import AppKit
import XCTest
@testable import DynAgentUI

final class ChatActionMenuChromeTests: XCTestCase {
    func testMenuUsesPinnedStateForPinTitleAndPreservesOrder() throws {
        let target = Target()
        let menu = ChatActionMenuChrome.makeMenu(
            isPinned: false,
            target: target,
            selectors: selectors
        )

        XCTAssertEqual(menu.items.map(\.title), [
            "Pin Chat",
            "Rename Chat",
            "Archive Chat",
            "",
            "Open in a New Window",
        ])
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        try assertTargets(menu, target: target)

        let pinnedMenu = ChatActionMenuChrome.makeMenu(
            isPinned: true,
            target: target,
            selectors: selectors
        )
        XCTAssertEqual(pinnedMenu.items.first?.title, "Unpin Chat")
    }

    func testMenuItemsUseExpectedSelectors() {
        let menu = ChatActionMenuChrome.makeMenu(
            isPinned: false,
            target: Target(),
            selectors: selectors
        )

        XCTAssertEqual(menu.items[0].action, #selector(Target.pin))
        XCTAssertEqual(menu.items[1].action, #selector(Target.rename))
        XCTAssertEqual(menu.items[2].action, #selector(Target.archive))
        XCTAssertEqual(menu.items[4].action, #selector(Target.open))
    }

    private var selectors: ChatActionMenuSelectors {
        ChatActionMenuSelectors(
            pin: #selector(Target.pin),
            rename: #selector(Target.rename),
            archive: #selector(Target.archive),
            openInNewWindow: #selector(Target.open)
        )
    }

    private func assertTargets(
        _ menu: NSMenu,
        target: Target,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.target === target, file: file, line: line)
            XCTAssertEqual(item.keyEquivalent, "", file: file, line: line)
        }
    }

    private final class Target: NSObject {
        @objc func pin() {}
        @objc func rename() {}
        @objc func archive() {}
        @objc func open() {}
    }
}
