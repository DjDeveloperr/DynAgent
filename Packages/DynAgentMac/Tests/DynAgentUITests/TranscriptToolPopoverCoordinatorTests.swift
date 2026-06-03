@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptToolPopoverCoordinatorTests: XCTestCase {
    func testPlansToolDetailFromAnchorBoundsAndClickPoint() {
        let coordinator = TranscriptToolPopoverCoordinator()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        let message = ChatMessage(role: .tool, toolName: "shell", toolDetail: "pwd")

        let plan = coordinator.plan(
            message: message,
            from: anchor,
            clickPoint: NSPoint(x: 30, y: 4)
        )

        XCTAssertEqual(plan.kind, .toolDetail)
        XCTAssertEqual(plan.anchorRect, NSRect(x: 26, y: 0, width: 8, height: 28))
        XCTAssertEqual(plan.content.size, NSSize(width: 440, height: 220))
    }

    func testPlansEditChangesFromFullAnchorBounds() {
        let coordinator = TranscriptToolPopoverCoordinator()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        let change = EditToolChange(path: "/repo/App.swift", added: 2, deleted: 1, diff: "@@\n-old\n+new")

        let plan = coordinator.planEditChanges([change], from: anchor)

        XCTAssertEqual(plan.kind, .editDiff)
        XCTAssertEqual(plan.anchorRect, NSRect(x: 0, y: 0, width: 180, height: 32))
        XCTAssertEqual(plan.content.size, NSSize(width: 760, height: 520))
    }
}
