import XCTest
@testable import DynAgentUI

final class SidebarRowModelTests: XCTestCase {
    func testRelativeTimeUsesShortLabelsWithoutAgo() {
        let now: Double = 1_000_000

        XCTAssertEqual(SidebarRowModel.relativeTime(now - 10, now: now), "now")
        XCTAssertEqual(SidebarRowModel.relativeTime(now - 60, now: now), "1m")
        XCTAssertEqual(SidebarRowModel.relativeTime(now - 8 * 60, now: now), "8m")
        XCTAssertEqual(SidebarRowModel.relativeTime(now - 60 * 60, now: now), "1h")
        XCTAssertEqual(SidebarRowModel.relativeTime(now - 8 * 60 * 60, now: now), "8h")
        XCTAssertEqual(SidebarRowModel.relativeTime(now - 24 * 60 * 60, now: now), "1d")
        XCTAssertEqual(SidebarRowModel.relativeTime(now - 3 * 24 * 60 * 60, now: now), "3d")
    }

    func testConversationRowCapturesWorkingPinnedUnreadAndTooltipState() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo/.codex/worktrees/branch", harness: .codex)
        conversation.id = "thread-1"
        conversation.title = "Upload IR receiver code"
        conversation.status = .running
        conversation.pinned = true
        conversation.unread = true
        conversation.updatedAt = 100

        let row = SidebarRowModel.conversation(conversation, now: 200)

        XCTAssertEqual(row.id, "thread-1")
        XCTAssertEqual(row.title, "Upload IR receiver code")
        XCTAssertEqual(row.workspaceDetail, "/repo/.codex/worktrees/branch")
        XCTAssertEqual(row.timeLabel, "running")
        XCTAssertTrue(row.isWorking)
        XCTAssertFalse(row.isThinking)
        XCTAssertTrue(row.isPinned)
        XCTAssertTrue(row.isUnread)
        XCTAssertTrue(row.isWorktree)
        XCTAssertEqual(row.tooltip, SidebarTooltipModel(title: "Upload IR receiver code", detail: "/repo/.codex/worktrees/branch"))
    }

    func testConversationRowFallsBackForProjectlessChats() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "", harness: .codex)
        conversation.title = "Projectless"
        conversation.updatedAt = 100

        let row = SidebarRowModel.conversation(conversation, now: 160)

        XCTAssertEqual(row.workspaceDetail, "No workspace")
        XCTAssertEqual(row.tooltip.detail, "No workspace")
        XCTAssertEqual(row.timeLabel, "1m")
        XCTAssertFalse(row.isWorktree)
    }

    func testWorkspaceRowIncludesTooltipAndEmptyStateInput() {
        let workspace = Workspace(name: "dynamic_agent", path: "/repo/dynamic_agent", conversations: [])

        let row = SidebarRowModel.workspace(workspace)

        XCTAssertEqual(row.name, "dynamic_agent")
        XCTAssertEqual(row.path, "/repo/dynamic_agent")
        XCTAssertFalse(row.hasChats)
        XCTAssertEqual(row.tooltip, SidebarTooltipModel(title: "dynamic_agent", detail: "/repo/dynamic_agent"))
    }
}
