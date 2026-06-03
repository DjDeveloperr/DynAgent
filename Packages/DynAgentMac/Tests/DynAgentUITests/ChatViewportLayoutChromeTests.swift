@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class ChatViewportLayoutChromeTests: XCTestCase {
    func testApplyPinsScrollAndDocumentWidthToRootBounds() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1188, height: 740))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 420))
        let composer = NSView(frame: NSRect(x: 0, y: 0, width: 1160, height: 144))
        scroll.documentView = document

        let inset = ChatViewportLayoutChrome.apply(
            root: root,
            scroll: scroll,
            composer: composer,
            bottomInsetCache: 0
        )

        XCTAssertEqual(scroll.frame, root.bounds)
        XCTAssertEqual(document.frame.width, 1188)
        XCTAssertEqual(document.frame.height, 420)
        XCTAssertEqual(inset, 172)
        XCTAssertEqual(scroll.contentInsets.bottom, 172)
    }

    func testApplyKeepsExistingBottomInsetWhenWithinTolerance() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let scroll = NSScrollView(frame: root.bounds)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 900.2, height: 300))
        let composer = NSView(frame: NSRect(x: 0, y: 0, width: 872, height: 144))
        scroll.documentView = document
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 171.5, right: 0)

        let inset = ChatViewportLayoutChrome.apply(
            root: root,
            scroll: scroll,
            composer: composer,
            bottomInsetCache: 171.5
        )

        XCTAssertEqual(scroll.frame, root.bounds)
        XCTAssertEqual(document.frame.width, 900.2)
        XCTAssertEqual(inset, 171.5)
        XCTAssertEqual(scroll.contentInsets.bottom, 171.5)
    }
}
