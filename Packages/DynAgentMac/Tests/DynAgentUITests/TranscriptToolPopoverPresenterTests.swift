@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptToolPopoverPresenterTests: XCTestCase {
    func testEditMessagePlansExpandedDiffPopoverWithStableAnchor() throws {
        let message = ChatMessage(
            role: .tool,
            toolName: "edit",
            toolDetail: #"{"changes":[{"path":"/repo/App.swift","added":2,"deleted":1,"diff":"@@\n-old\n+new"}]}"#
        )

        let plan = TranscriptToolPopoverPresenter.plan(
            for: message,
            clickPoint: NSPoint(x: 25, y: 3),
            anchorBounds: NSRect(x: 0, y: 0, width: 120, height: 28)
        )

        XCTAssertEqual(plan.kind, .editDiff)
        XCTAssertEqual(plan.anchorRect, NSRect(x: 0, y: 0, width: 120, height: 28))
        XCTAssertEqual(plan.content.size, NSSize(width: 760, height: 520))
        let scroll = try XCTUnwrap(plan.content.controller.view as? NSScrollView)
        let doc = try XCTUnwrap(scroll.documentView)
        XCTAssertFalse(findSubviews(of: DiffFileBlock.self, in: doc).isEmpty)
    }

    func testToolDetailPlansClickSizedAnchorAndSelectableText() throws {
        let message = ChatMessage(role: .tool, toolName: "shell", toolDetail: "$ pwd")
        message.toolDone = true

        let plan = TranscriptToolPopoverPresenter.plan(
            for: message,
            clickPoint: NSPoint(x: 25, y: 3),
            anchorBounds: NSRect(x: 0, y: 0, width: 120, height: 28)
        )

        XCTAssertEqual(plan.kind, .toolDetail)
        XCTAssertEqual(plan.anchorRect, NSRect(x: 21, y: 0, width: 8, height: 28))
        let scroll = try XCTUnwrap(plan.content.controller.view as? NSScrollView)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertTrue(text.isSelectable)
        XCTAssertEqual(text.string, "shell  \u{2713}\n\n$ pwd")
    }

    func testEmptyAnchorBoundsFallbackToOnePointRect() {
        let edit = ChatMessage(role: .tool, toolName: "edit", toolDetail: nil)
        let detail = ChatMessage(role: .tool, toolName: "shell", toolDetail: nil)

        let editPlan = TranscriptToolPopoverPresenter.plan(for: edit, clickPoint: nil, anchorBounds: .zero)
        let detailPlan = TranscriptToolPopoverPresenter.plan(for: detail, clickPoint: nil, anchorBounds: .zero)

        XCTAssertEqual(editPlan.anchorRect, NSRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(detailPlan.anchorRect, NSRect(x: 0, y: 0, width: 8, height: 1))
    }

    func testDirectEditChangesPlanUsesDiffContentAndAnchorBounds() {
        let change = EditToolChange(path: "/repo/App.swift", added: 1, deleted: 0, diff: "@@\n+new")

        let plan = TranscriptToolPopoverPresenter.editPlan(
            changes: [change],
            anchorBounds: NSRect(x: 2, y: 3, width: 80, height: 22)
        )

        XCTAssertEqual(plan.kind, .editDiff)
        XCTAssertEqual(plan.anchorRect, NSRect(x: 2, y: 3, width: 80, height: 22))
        XCTAssertEqual(plan.content.size, NSSize(width: 760, height: 520))
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
