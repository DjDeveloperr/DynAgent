@testable import DynAgentUI
import XCTest

final class AppDockStateCoordinatorTests: XCTestCase {
    func testUpdateWritesSortedRecentConversationsAndUnreadBadge() {
        var written: [DockRecentConversation] = []
        var badge: String?
        let coordinator = AppDockStateCoordinator(
            recentWriter: { written = $0 },
            badgeSetter: { badge = $0 }
        )
        let old = conversation(title: "Old", id: "old", updatedAt: 10)
        let recentUnread = conversation(title: "Recent", id: "recent", updatedAt: 30)
        recentUnread.unread = true
        recentUnread.status = .idle
        let runningUnread = conversation(title: "Running", id: "running", updatedAt: 20)
        runningUnread.unread = true
        runningUnread.status = .running

        coordinator.update(conversations: [old, runningUnread, recentUnread])

        XCTAssertEqual(written.map(\.id), ["recent", "running", "old"])
        XCTAssertEqual(written.map(\.title), ["Recent", "Running", "Old"])
        XCTAssertEqual(badge, "1")
    }

    func testUpdateClearsBadgeWhenNoFinishedUnreadConversationsRemain() {
        var badge: String? = "3"
        let coordinator = AppDockStateCoordinator(
            recentWriter: { _ in },
            badgeSetter: { badge = $0 }
        )
        let runningUnread = conversation(title: "Running", id: "running", updatedAt: 20)
        runningUnread.unread = true
        runningUnread.status = .thinking

        coordinator.update(conversations: [runningUnread])

        XCTAssertNil(badge)
    }

    func testWriteRecentDockConversationsWritesJsonPayload() throws {
        let dir = try temporaryDirectory()

        AppDockStateCoordinator.writeRecentDockConversations([
            DockRecentConversation(id: "one", title: "One", workspace: "/repo", updatedAt: 42)
        ], directory: dir)

        let data = try Data(contentsOf: dir.appendingPathComponent("dock-recent.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(json?.first?["id"] as? String, "one")
        XCTAssertEqual(json?.first?["title"] as? String, "One")
        XCTAssertEqual(json?.first?["workspace"] as? String, "/repo")
        XCTAssertEqual(json?.first?["updatedAt"] as? Double, 42)
    }

    private func conversation(
        title: String,
        id: String,
        workspace: String = "/repo",
        updatedAt: Double
    ) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", workspace: workspace, harness: .codex)
        conversation.id = id
        conversation.title = title
        conversation.updatedAt = updatedAt
        return conversation
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
