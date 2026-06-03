@testable import DynAgentUI
import XCTest

final class AppCodexHistoryModelTests: XCTestCase {
    func testRefreshThreadIdRequiresCodexThreadAndNeedUnlessForced() {
        let codex = conversation(threadId: "thread", harness: .codex, needsLoad: true, status: .idle)
        XCTAssertEqual(AppCodexHistoryModel.refreshThreadId(for: codex, force: false, inFlight: []), "thread")

        codex.needsLoad = false
        XCTAssertNil(AppCodexHistoryModel.refreshThreadId(for: codex, force: false, inFlight: []))
        XCTAssertEqual(AppCodexHistoryModel.refreshThreadId(for: codex, force: true, inFlight: []), "thread")

        let dynagent = conversation(threadId: "thread", harness: .dynagent, needsLoad: true, status: .idle)
        XCTAssertNil(AppCodexHistoryModel.refreshThreadId(for: dynagent, force: true, inFlight: []))

        let missingThread = conversation(threadId: nil, harness: .codex, needsLoad: true, status: .idle)
        XCTAssertNil(AppCodexHistoryModel.refreshThreadId(for: missingThread, force: true, inFlight: []))
    }

    func testRefreshThreadIdSuppressesActiveAndInFlightUnlessForcedForActive() {
        let active = conversation(threadId: "thread", harness: .codex, needsLoad: true, status: .running)

        XCTAssertNil(AppCodexHistoryModel.refreshThreadId(for: active, force: false, inFlight: []))
        XCTAssertEqual(AppCodexHistoryModel.refreshThreadId(for: active, force: true, inFlight: []), "thread")
        XCTAssertNil(AppCodexHistoryModel.refreshThreadId(for: active, force: true, inFlight: ["thread"]))
    }

    func testMessagesMapHistoryFieldsAndFallbackUnknownRolesToAssistant() {
        let messages = AppCodexHistoryModel.messages(from: [
            hist(
                role: "tool",
                content: "ran",
                toolName: "shell",
                toolDetail: "$ pwd",
                toolDone: true,
                timestamp: 10,
                turnDuration: 2,
                turnStartedAt: 8,
                turnStatus: "completed",
                isFinal: false,
                isSteer: true
            ),
            hist(role: "weird", content: "fallback")
        ])

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .tool)
        XCTAssertEqual(messages[0].text, "ran")
        XCTAssertEqual(messages[0].toolName, "shell")
        XCTAssertEqual(messages[0].toolDetail, "$ pwd")
        XCTAssertTrue(messages[0].toolDone)
        XCTAssertEqual(messages[0].timestamp, 10)
        XCTAssertEqual(messages[0].turnDuration, 2)
        XCTAssertEqual(messages[0].turnStartedAt, 8)
        XCTAssertEqual(messages[0].turnStatus, "completed")
        XCTAssertEqual(messages[0].isFinal, false)
        XCTAssertEqual(messages[0].isSteer, true)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testStatusAfterLoadingReflectsLatestTurnActivity() {
        let final = ChatMessage(role: .assistant, text: "done")
        final.isFinal = true
        XCTAssertEqual(AppCodexHistoryModel.status(afterLoading: [final]), .idle)

        let prompt = ChatMessage(role: .user, text: "run tests")
        prompt.turnStartedAt = 1_000
        prompt.turnStatus = "running"
        let tool = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: "$ swift test")
        tool.turnStartedAt = 1_005
        tool.turnStatus = "running"
        XCTAssertEqual(AppCodexHistoryModel.status(afterLoading: [prompt, tool], now: 1_010), .running)
    }

    private func conversation(
        threadId: String?,
        harness: Harness,
        needsLoad: Bool,
        status: Conversation.Status
    ) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", harness: harness)
        conversation.codexThreadId = threadId
        conversation.needsLoad = needsLoad
        conversation.status = status
        return conversation
    }

    private func hist(
        role: String,
        content: String,
        toolName: String? = nil,
        toolDetail: String? = nil,
        toolDone: Bool? = nil,
        timestamp: Double? = nil,
        turnDuration: Double? = nil,
        turnStartedAt: Double? = nil,
        turnStatus: String? = nil,
        isFinal: Bool? = nil,
        isSteer: Bool? = nil
    ) -> AgentClient.HistMsg {
        AgentClient.HistMsg(
            role: role,
            content: content,
            toolName: toolName,
            toolDetail: toolDetail,
            toolDone: toolDone,
            timestamp: timestamp,
            turnDuration: turnDuration,
            turnStartedAt: turnStartedAt,
            turnStatus: turnStatus,
            isFinal: isFinal,
            isSteer: isSteer
        )
    }
}
