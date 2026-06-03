import AppKit
@testable import DynAgentUI
import XCTest

final class SidebarChromeTests: XCTestCase {
    func testNativeRootUsesSidebarMaterialAndPinsScrollView() {
        let scroll = SidebarScrollView()

        let root = SidebarChrome.makeNativeRoot(containing: scroll)
        root.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(root.material, .sidebar)
        XCTAssertEqual(root.blendingMode, .behindWindow)
        XCTAssertEqual(root.state, .active)
        XCTAssertEqual(scroll.borderType, .noBorder)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertIdentical(scroll.superview, root)
        XCTAssertEqual(scroll.frame.width, 300, accuracy: 0.5)
        XCTAssertEqual(scroll.frame.height, 700, accuracy: 0.5)
    }
}
