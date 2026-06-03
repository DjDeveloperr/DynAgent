import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class WindowLayoutChromeTests: XCTestCase {
    func testApplyUsableSizingMakesWindowResizableAndSetsContentBounds() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        let sizing = WindowLayoutChrome.applyUsableSizing(to: window)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(sizing.minSize, WindowLayoutChrome.defaultMinimumWindowSize)
        XCTAssertEqual(sizing.maxSize, WindowLayoutChrome.defaultMaximumWindowSize)
        XCTAssertEqual(window.minSize, WindowLayoutChrome.defaultMinimumWindowSize)
        XCTAssertEqual(window.maxSize, WindowLayoutChrome.defaultMaximumWindowSize)
        XCTAssertEqual(window.contentMinSize.width, WindowLayoutChrome.defaultMinimumWindowSize.width, accuracy: 0.5)
        XCTAssertGreaterThan(window.contentMinSize.height, 0)
        XCTAssertEqual(window.contentMaxSize.width, WindowLayoutChrome.defaultMaximumWindowSize.width, accuracy: 0.5)
        XCTAssertGreaterThan(window.contentMaxSize.height, window.contentMinSize.height)
    }

    func testPinRootToContentBoundsUsesContentViewSize() {
        let root = NSViewController()
        root.view = NSView(frame: .zero)
        let split = NSSplitView(frame: .zero)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )

        let bounds = WindowLayoutChrome.pinRootToContentBounds(
            window: window,
            rootContentController: root,
            splitView: split
        )

        XCTAssertEqual(bounds.origin, .zero)
        XCTAssertEqual(bounds.size.width, window.contentView?.bounds.width ?? -1, accuracy: 0.5)
        XCTAssertEqual(root.view.frame, bounds)
        XCTAssertEqual(split.frame, bounds)
    }

    func testFrameMetricsCaptureClassAndGeometry() {
        let first = NSView(frame: NSRect(x: 3, y: 0, width: 120, height: 40))
        let second = NSButton(frame: NSRect(x: 124, y: 0, width: 32, height: 28))

        let metrics = WindowLayoutChrome.frameMetrics(for: [first, second])

        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].index, 0)
        XCTAssertEqual(metrics[0].className, "NSView")
        XCTAssertEqual(metrics[0].x, 3)
        XCTAssertEqual(metrics[0].width, 120)
        XCTAssertEqual(metrics[0].height, 40)
        XCTAssertEqual(metrics[1].index, 1)
        XCTAssertEqual(metrics[1].className, "NSButton")
        XCTAssertEqual(metrics[1].x, 124)
        XCTAssertEqual(metrics[1].width, 32)
        XCTAssertEqual(metrics[1].height, 28)
    }

    func testSplitItemWidthUsesContainingWrapperInsteadOfSubviewOrder() {
        let wrapper = NSView(frame: NSRect(x: 268, y: 0, width: 1_204, height: 798))
        let workspace = NSView(frame: wrapper.bounds)
        wrapper.addSubview(workspace)

        XCTAssertEqual(WindowLayoutChrome.splitItemWidth(containing: workspace), 1_204, accuracy: 0.5)
        XCTAssertEqual(WindowLayoutChrome.splitItemWidth(containing: NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))), 900, accuracy: 0.5)
    }
}
