@testable import DynAgentUI
import XCTest

final class SearchOverlayModelTests: XCTestCase {
    func testMatchesSortByRecencyAndRespectLimitForEmptyQuery() {
        let old = conversation(title: "Old", updatedAt: 10)
        let newest = conversation(title: "Newest", updatedAt: 30)
        let middle = conversation(title: "Middle", updatedAt: 20)

        let matches = SearchOverlayModel.matches(
            conversations: [old, newest, middle],
            query: "  ",
            limit: 2
        )

        XCTAssertTrue(matches[0] === newest)
        XCTAssertTrue(matches[1] === middle)
    }

    func testMatchesTitleWorkspaceAndRecentMessageText() {
        let title = conversation(title: "Storage Cleanup", workspace: "/repo/a", updatedAt: 1)
        let workspace = conversation(title: "Other", workspace: "/Users/dj/Developer/MediaHub", updatedAt: 2)
        let message = conversation(title: "Other", workspace: "/repo/b", updatedAt: 3)
        message.messages = [ChatMessage(role: .assistant, text: "Found the decoder bug")]
        let miss = conversation(title: "Other", workspace: "/repo/c", updatedAt: 4)

        XCTAssertEqual(
            SearchOverlayModel.matches(conversations: [title, workspace, message, miss], query: "storage").map(\.title),
            ["Storage Cleanup"]
        )
        XCTAssertEqual(
            SearchOverlayModel.matches(conversations: [title, workspace, message, miss], query: "mediahub").map(\.workspace),
            ["/Users/dj/Developer/MediaHub"]
        )
        XCTAssertTrue(SearchOverlayModel.matches(conversations: [title, workspace, message, miss], query: "decoder").first === message)
    }

    func testMessageSearchIsBoundedToRecentMessages() {
        let chat = conversation(title: "Thread", updatedAt: 1)
        chat.messages = [
            ChatMessage(role: .user, text: "needle is too old"),
            ChatMessage(role: .assistant, text: "recent plain text"),
        ]

        XCTAssertTrue(SearchOverlayModel.matches(
            conversations: [chat],
            query: "needle",
            messageSearchLimit: 1
        ).isEmpty)
        XCTAssertFalse(SearchOverlayModel.matches(
            conversations: [chat],
            query: "needle",
            messageSearchLimit: 2
        ).isEmpty)
    }

    func testRowModelUsesWorkspaceBasenameAndProjectlessFallback() {
        XCTAssertEqual(
            SearchOverlayModel.rowModel(for: conversation(title: "Chat", workspace: "/Users/dj/Developer/DynAgent")).detail,
            "DynAgent"
        )
        XCTAssertEqual(
            SearchOverlayModel.rowModel(for: conversation(title: "Chat", workspace: "")).detail,
            "Projectless"
        )
    }

    private func conversation(title: String, workspace: String = "/repo", updatedAt: Double = 0) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", workspace: workspace, harness: .codex)
        conversation.title = title
        conversation.updatedAt = updatedAt
        return conversation
    }
}
