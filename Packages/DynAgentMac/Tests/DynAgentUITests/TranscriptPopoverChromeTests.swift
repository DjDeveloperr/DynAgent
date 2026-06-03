@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptPopoverChromeTests: XCTestCase {
    func testToolDetailBuildsSelectablePopoverContent() throws {
        let content = TranscriptPopoverChrome.toolDetail(name: "shell", done: true, detail: "$ pwd")

        XCTAssertEqual(content.size, NSSize(width: 440, height: 220))
        let scroll = try XCTUnwrap(content.controller.view as? NSScrollView)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertTrue(text.isSelectable)
        XCTAssertFalse(text.isEditable)
        XCTAssertEqual(text.string, "shell  \u{2713}\n\n$ pwd")
    }

    func testShellOutputUsesHorizontalScrollingWithoutWrapping() throws {
        let content = TranscriptPopoverChrome.shellOutput("very long output")

        XCTAssertEqual(content.size, NSSize(width: 620, height: 360))
        let scroll = try XCTUnwrap(content.controller.view as? NSScrollView)
        XCTAssertTrue(scroll.hasHorizontalScroller)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertTrue(text.isHorizontallyResizable)
        XCTAssertFalse(text.textContainer?.widthTracksTextView ?? true)
        XCTAssertEqual(text.string, "very long output")
    }

    func testEditDiffBuildsDiffBlockOrEmptyState() throws {
        let change = EditToolChange(path: "/repo/App.swift", added: 2, deleted: 1, diff: "@@ -1 +1 @@\n-old\n+new")
        let content = TranscriptPopoverChrome.editDiff(changes: [change])

        XCTAssertEqual(content.size, NSSize(width: 760, height: 520))
        let scroll = try XCTUnwrap(content.controller.view as? NSScrollView)
        XCTAssertTrue(scroll.hasHorizontalScroller)
        let doc = try XCTUnwrap(scroll.documentView)
        XCTAssertFalse(findSubviews(of: DiffFileBlock.self, in: doc).isEmpty)

        let empty = TranscriptPopoverChrome.editDiff(changes: [])
        let emptyScroll = try XCTUnwrap(empty.controller.view as? NSScrollView)
        let emptyDoc = try XCTUnwrap(emptyScroll.documentView)
        let labels = findSubviews(of: NSTextField.self, in: emptyDoc).map(\.stringValue)
        XCTAssertTrue(labels.contains("No diff details available."))
    }

    func testContentInstallsIntoPopover() {
        let popover = NSPopover()
        let content = TranscriptPopoverChrome.shellOutput("output")

        content.install(in: popover)

        XCTAssertTrue(popover.contentViewController === content.controller)
        XCTAssertEqual(popover.contentSize, content.size)
        XCTAssertEqual(popover.behavior, .transient)
    }

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var result: [T] = []
        if let match = root as? T {
            result.append(match)
        }
        for subview in root.subviews {
            result.append(contentsOf: findSubviews(of: type, in: subview))
        }
        return result
    }
}
