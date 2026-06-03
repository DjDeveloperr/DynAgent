import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class SidebarConversationRowChromeTests: XCTestCase {
    func testIdleWorktreeRowBuildsTitleTimeActionsAndHoverState() throws {
        var pinCount = 0
        var archivedButton: SidebarActionButton?
        var archivedPin: SidebarActionButton?
        let model = model(
            title: "Upload IR receiver code",
            timeLabel: "8h",
            isPinned: true,
            isUnread: true,
            isWorktree: true
        )

        let state = SidebarConversationRowChrome.make(
            model: model,
            indent: 32,
            onClick: {},
            menu: { NSMenu() },
            onPin: { pinCount += 1 },
            onArchive: { button, pin in
                archivedButton = button
                archivedPin = pin
            },
            onHoverChanged: { _, _ in }
        )

        XCTAssertEqual(state.row.constraints.first { $0.firstAnchor == state.row.heightAnchor }?.constant, 32)
        XCTAssertEqual(state.row.descendantTextFields().map(\.stringValue), ["Upload IR receiver code", "8h"])
        XCTAssertFalse(try XCTUnwrap(state.worktreeIcon).isHidden)
        XCTAssertTrue(try XCTUnwrap(state.pinButton).isHidden)
        XCTAssertTrue(try XCTUnwrap(state.archiveButton).isHidden)
        XCTAssertFalse(try XCTUnwrap(state.timeLabel).isHidden)
        XCTAssertTrue(state.titleToTime?.isActive ?? false)
        XCTAssertFalse(state.titleToActions?.isActive ?? true)

        state.applyHover(true, confirming: false)
        XCTAssertFalse(try XCTUnwrap(state.pinButton).isHidden)
        XCTAssertFalse(try XCTUnwrap(state.archiveButton).isHidden)
        XCTAssertTrue(try XCTUnwrap(state.timeLabel).isHidden)
        XCTAssertTrue(try XCTUnwrap(state.worktreeIcon).isHidden)
        XCTAssertFalse(state.titleToTime?.isActive ?? true)
        XCTAssertTrue(state.titleToActions?.isActive ?? false)

        try XCTUnwrap(state.pinButton).performClick(nil)
        try XCTUnwrap(state.archiveButton).performClick(nil)
        XCTAssertEqual(pinCount, 1)
        XCTAssertTrue(archivedButton === state.archiveButton)
        XCTAssertTrue(archivedPin === state.pinButton)
    }

    func testConfirmingArchiveKeepsArchiveVisibleAndPinHidden() throws {
        let state = SidebarConversationRowChrome.make(
            model: model(title: "Confirm me", timeLabel: "1d"),
            indent: 8,
            onClick: {},
            menu: { NSMenu() },
            onPin: {},
            onArchive: { _, _ in },
            onHoverChanged: { _, _ in }
        )

        state.applyHover(false, confirming: true)

        XCTAssertTrue(try XCTUnwrap(state.pinButton).isHidden)
        XCTAssertFalse(try XCTUnwrap(state.archiveButton).isHidden)
        XCTAssertTrue(try XCTUnwrap(state.timeLabel).isHidden)
        XCTAssertFalse(state.titleToTime?.isActive ?? true)
        XCTAssertTrue(state.titleToActions?.isActive ?? false)
    }

    func testWorkingRowShowsSpinnerInsteadOfTimeUntilHover() throws {
        let state = SidebarConversationRowChrome.make(
            model: model(title: "Still running", timeLabel: "running", isWorking: true),
            indent: 32,
            onClick: {},
            menu: { NSMenu() },
            onPin: {},
            onArchive: { _, _ in },
            onHoverChanged: { _, _ in }
        )

        XCTAssertNotNil(state.spinnerView)
        XCTAssertTrue(try XCTUnwrap(state.timeLabel).isHidden)
        XCTAssertFalse(try XCTUnwrap(state.spinnerView).isHidden)

        state.applyHover(true, confirming: false)

        XCTAssertTrue(try XCTUnwrap(state.spinnerView).isHidden)
        XCTAssertFalse(try XCTUnwrap(state.archiveButton).isHidden)
    }

    private func model(
        title: String,
        timeLabel: String,
        isWorking: Bool = false,
        isPinned: Bool = false,
        isUnread: Bool = false,
        isWorktree: Bool = false
    ) -> SidebarConversationRowModel {
        SidebarConversationRowModel(
            id: "thread-1",
            title: title,
            workspaceDetail: "/repo",
            timeLabel: timeLabel,
            isWorking: isWorking,
            isThinking: false,
            isPinned: isPinned,
            isUnread: isUnread,
            isWorktree: isWorktree,
            tooltip: SidebarTooltipModel(title: title, detail: "/repo")
        )
    }
}

private extension NSView {
    func descendantTextFields() -> [NSTextField] {
        var result: [NSTextField] = []
        if let field = self as? NSTextField {
            result.append(field)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendantTextFields())
        }
        return result
    }
}
