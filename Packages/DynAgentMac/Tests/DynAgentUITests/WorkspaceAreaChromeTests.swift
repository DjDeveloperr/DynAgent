import AppKit
@testable import DynAgentUI
import XCTest

final class WorkspaceAreaChromeTests: XCTestCase {
    func testMakeRootViewConfiguresAndPinsSplitView() {
        let split = NSSplitView()

        let root = WorkspaceAreaChrome.makeRootView(pinning: split)
        root.frame = NSRect(x: 0, y: 0, width: 960, height: 640)
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(split.isVertical)
        XCTAssertEqual(split.dividerStyle, .thin)
        XCTAssertTrue(split.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(split.autoresizingMask.contains(.width))
        XCTAssertTrue(split.autoresizingMask.contains(.height))
        XCTAssertIdentical(split.superview, root)
        XCTAssertEqual(split.frame.width, 960, accuracy: 0.5)
        XCTAssertEqual(split.frame.height, 640, accuracy: 0.5)
    }

    func testForceLayoutPinsWorkspaceAndSinglePrimarySubviewToBounds() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1_188, height: 798))
        let split = NSSplitView()
        let root = WorkspaceAreaChrome.makeRootView(pinning: split)
        let child = NSView()

        host.addSubview(root)
        root.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        split.addArrangedSubview(child)

        WorkspaceAreaChrome.forceLayout(view: root, rootSplit: split)

        XCTAssertEqual(root.frame.width, 1_188, accuracy: 0.5)
        XCTAssertEqual(root.frame.height, 798, accuracy: 0.5)
        XCTAssertEqual(split.frame.width, 1_188, accuracy: 0.5)
        XCTAssertEqual(split.frame.height, 798, accuracy: 0.5)
        XCTAssertEqual(child.frame.width, 1_188, accuracy: 0.5)
        XCTAssertEqual(child.frame.height, 798, accuracy: 0.5)
    }

    func testMetricsExposeWorkspaceAndSubviewWidths() throws {
        let split = NSSplitView()
        let root = WorkspaceAreaChrome.makeRootView(pinning: split)
        let child = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        root.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        split.addArrangedSubview(child)
        WorkspaceAreaChrome.forceLayout(view: root, rootSplit: split)

        let metrics = WorkspaceAreaChrome.metrics(view: root, rootSplit: split)
        let frames = try XCTUnwrap(metrics["workspaceRootSubviewFrames"] as? [[String: Any]])
        let first = try XCTUnwrap(frames.first)

        XCTAssertEqual(try XCTUnwrap(metrics["workspaceViewWidth"] as? Double), 900, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(metrics["workspaceRootWidth"] as? Double), 900, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(first["width"] as? Double), 900, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(first["height"] as? Double), 640, accuracy: 0.5)
    }
}
