@testable import DynAgentUI
import XCTest

final class ChatPresentationModelTests: XCTestCase {
    func testRenderedTranscriptReuseRequiresSameInactiveConversationAndFingerprint() {
        XCTAssertTrue(ChatPresentationModel.shouldReuseRenderedTranscript(
            wasShowingSameConversation: true,
            isActive: false,
            renderedConversationId: "chat-1",
            renderedFingerprint: 42,
            conversationId: "chat-1",
            fingerprint: 42
        ))
        XCTAssertFalse(ChatPresentationModel.shouldReuseRenderedTranscript(
            wasShowingSameConversation: true,
            isActive: true,
            renderedConversationId: "chat-1",
            renderedFingerprint: 42,
            conversationId: "chat-1",
            fingerprint: 42
        ))
        XCTAssertFalse(ChatPresentationModel.shouldReuseRenderedTranscript(
            wasShowingSameConversation: false,
            isActive: false,
            renderedConversationId: "chat-1",
            renderedFingerprint: 42,
            conversationId: "chat-1",
            fingerprint: 42
        ))
        XCTAssertFalse(ChatPresentationModel.shouldReuseRenderedTranscript(
            wasShowingSameConversation: true,
            isActive: false,
            renderedConversationId: "chat-1",
            renderedFingerprint: 41,
            conversationId: "chat-1",
            fingerprint: 42
        ))
    }

    func testLoadingTextDistinguishesLatestThreadFetchFromGenericShell() {
        XCTAssertEqual(ChatPresentationModel.loadingText(needsLoad: true), "Loading latest thread...")
        XCTAssertEqual(ChatPresentationModel.loadingText(needsLoad: false), "Loading conversation...")
    }

    func testEmptyStateUsesWorkspaceLeafAndVisibility() {
        let empty = ChatPresentationModel.emptyState(messages: [], workspace: "/Users/dj/Developer/dynamic_agent")
        let populated = ChatPresentationModel.emptyState(messages: [ChatMessage(role: .user, text: "hi")], workspace: "")

        XCTAssertFalse(empty.isHidden)
        XCTAssertEqual(empty.subtitle, "dynamic_agent")
        XCTAssertTrue(populated.isHidden)
        XCTAssertEqual(populated.subtitle, "Workspace")
    }
}
