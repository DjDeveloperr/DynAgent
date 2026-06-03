import AppKit
import XCTest
@testable import DynAgentUI

final class WorkspacePanelChromeTests: XCTestCase {
    func testHeaderlessTilePinsContentToFullBounds() {
        let content = NSView()
        let panel = TilePanel(title: "Chat", content: content, closable: false, showsHeader: false)

        panel.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(content.superview === panel)
        XCTAssertEqual(content.frame.width, 640, accuracy: 0.5)
        XCTAssertEqual(content.frame.height, 420, accuracy: 0.5)
        XCTAssertEqual(panel.subviews.count, 1)
    }

    func testHeaderTileInstallsHeaderAndOffsetsContent() throws {
        let content = NSView()
        let panel = TilePanel(title: "Terminal", content: content, closable: true, showsHeader: true)

        panel.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        panel.layoutSubtreeIfNeeded()

        let header = try XCTUnwrap(panel.subviews.compactMap { $0 as? NSStackView }.first)
        XCTAssertEqual(header.orientation, .horizontal)
        XCTAssertEqual(header.edgeInsets.left, 10)
        XCTAssertEqual(header.frame.height, 26, accuracy: 0.5)
        XCTAssertEqual(content.frame.height, 394, accuracy: 0.5)
    }

    func testRootViewPinsSplitViewToBounds() {
        let rootView = WorkspaceAreaRootView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let splitView = NSSplitView(frame: .zero)
        let child = NSView()

        splitView.addArrangedSubview(child)
        rootView.pinnedSplitView = splitView
        rootView.addSubview(splitView)
        rootView.layoutSubtreeIfNeeded()

        XCTAssertEqual(splitView.frame.width, 800, accuracy: 0.5)
        XCTAssertEqual(splitView.frame.height, 600, accuracy: 0.5)
        XCTAssertEqual(child.frame.width, 800, accuracy: 0.5)
        XCTAssertEqual(child.frame.height, 600, accuracy: 0.5)
    }
}
