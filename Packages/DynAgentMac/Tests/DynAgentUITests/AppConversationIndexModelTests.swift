@testable import DynAgentUI
import XCTest

final class AppConversationIndexModelTests: XCTestCase {
    func testVisibleConversationsDedupeByCodexThreadIdBeforeLocalId() {
        let local = conversation(title: "Loaded", id: "local", threadId: "thread-1", updatedAt: 20)
        let duplicateStub = conversation(title: "Stub", id: "stub", threadId: "thread-1", updatedAt: 30)
        let other = conversation(title: "Other", id: "other", threadId: "thread-2", updatedAt: 10)

        let visible = AppConversationIndexModel.visibleConversations(
            local: [local],
            codexStubs: ["repo": [duplicateStub, other]]
        )

        XCTAssertEqual(visible.count, 2)
        XCTAssertTrue(visible[0] === local)
        XCTAssertTrue(visible[1] === other)
    }

    func testRestoredConversationPrefersSelectedIdOrThreadIdThenMostRecent() {
        let old = conversation(title: "Old", id: "old", updatedAt: 10)
        let recent = conversation(title: "Recent", id: "recent", updatedAt: 30)
        let selectedThread = conversation(title: "Selected", id: "selected-local", threadId: "thread-selected", updatedAt: 20)

        XCTAssertTrue(AppConversationIndexModel.restoredConversation(
            selectedId: "thread-selected",
            conversations: [old, selectedThread],
            codexStubs: ["repo": [recent]],
            draft: nil
        ) === selectedThread)

        XCTAssertTrue(AppConversationIndexModel.restoredConversation(
            selectedId: nil,
            conversations: [old],
            codexStubs: ["repo": [recent]],
            draft: selectedThread
        ) === recent)
    }

    func testDockRecentTrimsTitlesSortsAndRespectsLimit() {
        let blank = conversation(title: "   ", id: "blank", workspace: "/repo/blank", updatedAt: 30)
        let middle = conversation(title: "Middle", id: "middle", workspace: "/repo/middle", updatedAt: 20)
        let old = conversation(title: "Old", id: "old", workspace: "/repo/old", updatedAt: 10)

        let recent = AppConversationIndexModel.dockRecent(
            conversations: [old, blank, middle],
            limit: 2
        )

        XCTAssertEqual(recent.map(\.id), ["blank", "middle"])
        XCTAssertEqual(recent.map(\.title), ["New Chat", "Middle"])
        XCTAssertEqual(recent.map(\.workspace), ["/repo/blank", "/repo/middle"])
        XCTAssertEqual(recent.first?.dictionary["title"] as? String, "New Chat")
    }

    func testUnreadFinishedCountIgnoresRunningAndThinkingThreads() {
        let unreadIdle = conversation(title: "Idle")
        unreadIdle.unread = true
        unreadIdle.status = .idle
        let unreadRunning = conversation(title: "Running")
        unreadRunning.unread = true
        unreadRunning.status = .running
        let unreadThinking = conversation(title: "Thinking")
        unreadThinking.unread = true
        unreadThinking.status = .thinking
        let readIdle = conversation(title: "Read")
        readIdle.unread = false
        readIdle.status = .idle

        XCTAssertEqual(
            AppConversationIndexModel.unreadFinishedCount([unreadIdle, unreadRunning, unreadThinking, readIdle]),
            1
        )
    }

    private func conversation(
        title: String,
        id: String = UUID().uuidString,
        threadId: String? = nil,
        workspace: String = "/repo",
        updatedAt: Double = 0
    ) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", workspace: workspace, harness: .codex)
        conversation.id = id
        conversation.codexThreadId = threadId
        conversation.title = title
        conversation.updatedAt = updatedAt
        return conversation
    }
}
