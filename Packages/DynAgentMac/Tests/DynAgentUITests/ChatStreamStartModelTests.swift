@testable import DynAgentUI
import XCTest

final class ChatStreamStartModelTests: XCTestCase {
    func testPrepareTurnLocksHarnessModelAppendsPromptAndMarksThinking() {
        let conversation = Conversation(model: "old", workspace: "/repo", harness: .dynagent)

        let result = ChatStreamStartModel.prepareTurn(
            text: "build this",
            conversation: conversation,
            harness: .codex,
            model: "gpt-5.5-codex",
            appendUser: true,
            now: 100
        )

        XCTAssertEqual(conversation.harness, .codex)
        XCTAssertEqual(conversation.model, "gpt-5.5-codex")
        XCTAssertEqual(conversation.status, .thinking)
        XCTAssertEqual(conversation.updatedAt, 100)
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertTrue(result.userMessage === conversation.messages.first)
        XCTAssertEqual(result.userMessage?.text, "build this")
        XCTAssertEqual(result.userMessage?.turnStartedAt, 100)
        XCTAssertEqual(result.userMessage?.turnStatus, "running")
        XCTAssertEqual(result.startedAt, 100)
        XCTAssertTrue(result.shouldGenerateTitle)
    }

    func testPrepareTurnDoesNotAppendUserForQueuedSteerContinuation() {
        let conversation = Conversation(model: "old", harness: .codex)
        conversation.messages.append(ChatMessage(role: .user, text: "original"))

        let result = ChatStreamStartModel.prepareTurn(
            text: "queued steer",
            conversation: conversation,
            harness: .codex,
            model: "gpt-5.5",
            appendUser: false,
            now: 200
        )

        XCTAssertNil(result.userMessage)
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.status, .thinking)
        XCTAssertEqual(conversation.updatedAt, 200)
        XCTAssertFalse(result.shouldGenerateTitle)
    }

    func testSteerMessagesDoNotCountAsTitlePrompt() {
        let conversation = Conversation(model: "gpt", harness: .codex)
        let steer = ChatMessage(role: .user, text: "steer")
        steer.isSteer = true
        conversation.messages.append(steer)

        let result = ChatStreamStartModel.prepareTurn(
            text: "first real prompt",
            conversation: conversation,
            harness: .codex,
            model: "gpt-5.5",
            appendUser: true,
            now: 300
        )

        XCTAssertTrue(result.shouldGenerateTitle)
        XCTAssertEqual(conversation.messages.filter { $0.role == .user && $0.isSteer != true }.count, 1)
    }
}
