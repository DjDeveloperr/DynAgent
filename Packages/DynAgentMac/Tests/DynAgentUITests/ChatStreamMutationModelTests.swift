@testable import DynAgentUI
import XCTest

final class ChatStreamMutationModelTests: XCTestCase {
    func testAppendUserPromptMarksRunningTurn() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)

        let prompt = ChatStreamMutationModel.appendUserPrompt("Fix layout", to: conversation, startedAt: 100)

        XCTAssertTrue(prompt === conversation.messages[0])
        XCTAssertEqual(prompt.role, .user)
        XCTAssertEqual(prompt.text, "Fix layout")
        XCTAssertEqual(prompt.turnStartedAt, 100)
        XCTAssertEqual(prompt.turnStatus, "running")
    }

    func testAppendAssistantTextCreatesOnceThenAccumulatesExistingMessage() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)

        let first = ChatStreamMutationModel.appendAssistantText("hello", to: conversation, existing: nil)
        let second = ChatStreamMutationModel.appendAssistantText(" world", to: conversation, existing: first.message)

        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
        XCTAssertTrue(first.message === second.message)
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages[0].text, "hello world")
    }

    func testAppendErrorCreatesOrAppendsWarningText() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)

        let first = ChatStreamMutationModel.appendErrorText("failed", to: conversation, existing: nil, startedAt: 10)
        let second = ChatStreamMutationModel.appendErrorText("again", to: conversation, existing: first.message, startedAt: 20)

        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
        XCTAssertEqual(first.message.turnStartedAt, 10)
        XCTAssertEqual(first.message.turnStatus, "running")
        XCTAssertEqual(first.message.text, "\u{26A0}\u{FE0E} failed\n\u{26A0}\u{FE0E} again")
    }

    func testAppendAndCompleteToolResultMutatesLatestOpenMatchingTool() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)
        let first = ChatStreamMutationModel.appendTool(name: "shell", detail: "$ swift test", to: conversation, startedAt: 1)
        let second = ChatStreamMutationModel.appendTool(name: "shell", detail: "$ swift build", to: conversation, startedAt: 2)

        let completed = ChatStreamMutationModel.completeToolResult(name: "shell", detail: "ok", in: conversation)

        XCTAssertTrue(completed === second)
        XCTAssertFalse(first.toolDone)
        XCTAssertTrue(second.toolDone)
        XCTAssertEqual(second.turnStatus, "completed")
        XCTAssertEqual(second.toolDetail, "$ swift build\n\nok")
    }

    func testFinishAssistantTurnMarksFinalAndCompletesLatestPromptTurn() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)
        let oldPrompt = ChatStreamMutationModel.appendUserPrompt("old", to: conversation, startedAt: 1)
        oldPrompt.turnStatus = "running"
        let prompt = ChatStreamMutationModel.appendUserPrompt("new", to: conversation, startedAt: 10)
        let tool = ChatStreamMutationModel.appendTool(name: "shell", detail: "$ pwd", to: conversation, startedAt: 11)
        let assistant = ChatStreamMutationModel.appendAssistantText("done", to: conversation, existing: nil).message

        let final = ChatStreamMutationModel.finishAssistantTurn(in: conversation, assistant: assistant, startedAt: 10, now: 14)

        XCTAssertTrue(final === assistant)
        XCTAssertEqual(assistant.timestamp, 14)
        XCTAssertEqual(assistant.turnDuration, 4)
        XCTAssertEqual(assistant.turnStatus, "completed")
        XCTAssertTrue(assistant.isFinal ?? false)
        XCTAssertEqual(oldPrompt.turnStatus, "running")
        XCTAssertEqual(prompt.turnStatus, "completed")
        XCTAssertTrue(tool.toolDone)
        XCTAssertEqual(tool.turnStatus, "completed")
    }
}
