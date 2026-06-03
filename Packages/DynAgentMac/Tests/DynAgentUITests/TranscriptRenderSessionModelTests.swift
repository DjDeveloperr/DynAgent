@testable import DynAgentUI
import XCTest

final class TranscriptRenderSessionModelTests: XCTestCase {
    func testBeginShowStartsNewGenerationAndMarksBulkLoadingForFreshRender() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)
        conversation.id = "thread"
        conversation.messages = [ChatMessage(role: .user, text: "hello")]

        let start = TranscriptRenderSessionModel.beginShow(
            state: TranscriptRenderSessionState(),
            conversation: conversation,
            wasShowingSameConversation: false,
            isActive: false,
            maxRenderedMessages: 240
        )

        XCTAssertEqual(start.generation, 1)
        XCTAssertFalse(start.shouldReuse)
        XCTAssertEqual(start.state.generation, 1)
        XCTAssertEqual(start.state.renderedConversationId, "thread")
        XCTAssertEqual(start.state.renderedFingerprint, start.fingerprint)
        XCTAssertTrue(start.state.bulkLoading)
    }

    func testBeginShowReusesInactiveSameConversationWithSameFingerprint() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)
        conversation.id = "thread"
        conversation.messages = [ChatMessage(role: .assistant, text: "done")]
        let fingerprint = TranscriptRenderModel.fingerprint(for: conversation, maxRenderedMessages: 240)
        let state = TranscriptRenderSessionState(
            generation: 3,
            renderedConversationId: "thread",
            renderedFingerprint: fingerprint,
            bulkLoading: false
        )

        let start = TranscriptRenderSessionModel.beginShow(
            state: state,
            conversation: conversation,
            wasShowingSameConversation: true,
            isActive: false,
            maxRenderedMessages: 240
        )

        XCTAssertTrue(start.shouldReuse)
        XCTAssertEqual(start.generation, 4)
        XCTAssertEqual(start.state.generation, 4)
        XCTAssertEqual(start.state.renderedConversationId, "thread")
        XCTAssertEqual(start.state.renderedFingerprint, fingerprint)
        XCTAssertFalse(start.state.bulkLoading)
    }

    func testBeginShowDoesNotReuseActiveConversationEvenWithSameFingerprint() {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)
        conversation.id = "thread"
        let fingerprint = TranscriptRenderModel.fingerprint(for: conversation, maxRenderedMessages: 240)
        let state = TranscriptRenderSessionState(
            generation: 1,
            renderedConversationId: "thread",
            renderedFingerprint: fingerprint,
            bulkLoading: false
        )

        let start = TranscriptRenderSessionModel.beginShow(
            state: state,
            conversation: conversation,
            wasShowingSameConversation: true,
            isActive: true,
            maxRenderedMessages: 240
        )

        XCTAssertFalse(start.shouldReuse)
        XCTAssertTrue(start.state.bulkLoading)
    }

    func testBeginLoadingShellInvalidatesRenderedCacheAndStopsBulkLoading() {
        let state = TranscriptRenderSessionState(
            generation: 9,
            renderedConversationId: "thread",
            renderedFingerprint: 42,
            bulkLoading: true
        )

        let shell = TranscriptRenderSessionModel.beginLoadingShell(state: state)

        XCTAssertEqual(shell.generation, 10)
        XCTAssertNil(shell.renderedConversationId)
        XCTAssertNil(shell.renderedFingerprint)
        XCTAssertFalse(shell.bulkLoading)
    }

    func testShouldContinueRequiresGenerationAndVisibleConversationIdentity() {
        let visible = Conversation(model: "gpt-5.5", harness: .codex)
        let other = Conversation(model: "gpt-5.5", harness: .codex)
        let state = TranscriptRenderSessionState(generation: 2)

        XCTAssertTrue(TranscriptRenderSessionModel.shouldContinue(
            state: state,
            generation: 2,
            visibleConversation: visible,
            expectedConversation: visible
        ))
        XCTAssertFalse(TranscriptRenderSessionModel.shouldContinue(
            state: state,
            generation: 1,
            visibleConversation: visible,
            expectedConversation: visible
        ))
        XCTAssertFalse(TranscriptRenderSessionModel.shouldContinue(
            state: state,
            generation: 2,
            visibleConversation: other,
            expectedConversation: visible
        ))
    }

    func testBatchRangeAndFinishBulkLoadingDelegateRenderProgress() {
        XCTAssertEqual(TranscriptRenderSessionModel.batchRange(totalCount: 8, startIndex: 0), 0..<6)
        XCTAssertEqual(TranscriptRenderSessionModel.batchRange(totalCount: 8, startIndex: 6), 6..<8)

        let finished = TranscriptRenderSessionModel.finishBulkLoading(
            state: TranscriptRenderSessionState(generation: 1, bulkLoading: true)
        )
        XCTAssertFalse(finished.bulkLoading)
        XCTAssertEqual(finished.generation, 1)
    }
}
