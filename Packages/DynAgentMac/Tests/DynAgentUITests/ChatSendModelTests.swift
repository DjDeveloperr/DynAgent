@testable import DynAgentUI
import XCTest

final class ChatSendModelTests: XCTestCase {
    func testEmptyInputDoesNothingWhenIdleAndStopsWhenStreaming() {
        XCTAssertEqual(
            ChatSendModel.action(
                typedText: "  \n ",
                attachmentPaths: [],
                streaming: false,
                harness: .codex,
                codexThreadId: "thread"
            ),
            .none
        )
        XCTAssertEqual(
            ChatSendModel.action(
                typedText: "",
                attachmentPaths: [],
                streaming: true,
                harness: .codex,
                codexThreadId: "thread"
            ),
            .stop
        )
        XCTAssertFalse(ChatSendAction.none.clearsComposer)
        XCTAssertFalse(ChatSendAction.stop.clearsComposer)
    }

    func testIdleNonEmptyInputStartsPromptTurnWithAttachments() {
        let action = ChatSendModel.action(
            typedText: "  inspect this  ",
            attachmentPaths: ["/tmp/App.swift"],
            streaming: false,
            harness: .codex,
            codexThreadId: "thread"
        )

        XCTAssertEqual(action, .startTurn(text: "inspect this\n\nAttached files:\n- /tmp/App.swift"))
        XCTAssertTrue(action.clearsComposer)
    }

    func testStreamingCodexThreadSendsNativeSteer() {
        let action = ChatSendModel.action(
            typedText: "keep going",
            attachmentPaths: [],
            streaming: true,
            harness: .codex,
            codexThreadId: "thread-1"
        )

        XCTAssertEqual(action, .sendCodexSteer(threadId: "thread-1", text: "keep going"))
        XCTAssertTrue(action.clearsComposer)
    }

    func testStreamingWithoutCodexThreadQueuesSteerForNextTurn() {
        XCTAssertEqual(
            ChatSendModel.action(
                typedText: "adjust",
                attachmentPaths: [],
                streaming: true,
                harness: .codex,
                codexThreadId: nil
            ),
            .queueSteer(text: "adjust")
        )
        XCTAssertEqual(
            ChatSendModel.action(
                typedText: "adjust",
                attachmentPaths: [],
                streaming: true,
                harness: .dynagent,
                codexThreadId: "ignored"
            ),
            .queueSteer(text: "adjust")
        )
    }

    func testAttachmentOnlyInputIsSendableAndQueuedSteersJoinAsNextPrompt() {
        XCTAssertEqual(
            ChatSendModel.action(
                typedText: "",
                attachmentPaths: ["/tmp/a.png", "/tmp/b.swift"],
                streaming: false,
                harness: .codex,
                codexThreadId: nil
            ),
            .startTurn(text: "Attached files:\n- /tmp/a.png\n- /tmp/b.swift")
        )
        XCTAssertEqual(ChatSendModel.queuedSteerTurnText(["one", "two"]), "one\n\ntwo")
        XCTAssertNil(ChatSendModel.queuedSteerTurnText([]))
    }
}
