@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class ChatThinkingCoordinatorTests: XCTestCase {
    func testThinkingRowIsIdempotentAndHideRemovesIt() {
        let transcript = makeTranscript()
        let coordinator = ChatThinkingCoordinator()

        XCTAssertTrue(coordinator.showThinking(in: transcript))
        XCTAssertFalse(coordinator.showThinking(in: transcript))
        XCTAssertEqual(transcript.arrangedSubviews.count, 1)

        XCTAssertTrue(coordinator.hideThinking())
        XCTAssertFalse(coordinator.hideThinking())
        XCTAssertEqual(transcript.arrangedSubviews.count, 0)
    }

    func testPinThinkingMovesItsContainerToBottom() {
        let transcript = makeTranscript()
        let coordinator = ChatThinkingCoordinator()
        let first = NSView()
        first.translatesAutoresizingMaskIntoConstraints = false

        XCTAssertTrue(coordinator.showThinking(in: transcript))
        let thinkingContainer = transcript.arrangedSubviews.last
        TranscriptStackChrome.appendFullWidthRow(first, to: transcript)
        XCTAssertTrue(transcript.arrangedSubviews.last === first)

        coordinator.pinThinkingToBottom(in: transcript)

        XCTAssertTrue(transcript.arrangedSubviews.last === thinkingContainer)
    }

    func testLiveDividerLifecycleReusesThenFinishesDivider() {
        let transcript = makeTranscript()
        let coordinator = ChatThinkingCoordinator()

        let first = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 10,
            now: 15,
            transcript: transcript
        )
        let second = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 10,
            now: 25,
            transcript: transcript
        )

        XCTAssertTrue(first === second)
        XCTAssertEqual(transcript.arrangedSubviews.count, 1)
        XCTAssertTrue(coordinator.finishLiveDivider(for: "thread-1", duration: 7) === first)
        XCTAssertNil(coordinator.finishLiveDivider(for: "thread-1", duration: 7))

        let third = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 30,
            now: 32,
            transcript: transcript
        )
        XCTAssertFalse(third === first)
    }

    func testResetClearsLiveDividerReferencesWithoutMutatingRows() {
        let transcript = makeTranscript()
        let coordinator = ChatThinkingCoordinator()

        let first = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 10,
            now: 15,
            transcript: transcript
        )
        coordinator.reset()
        let second = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 10,
            now: 16,
            transcript: transcript
        )

        XCTAssertFalse(first === second)
        XCTAssertEqual(transcript.arrangedSubviews.count, 2)
    }

    private func makeTranscript() -> NSStackView {
        let transcript = NSStackView()
        transcript.orientation = .vertical
        transcript.translatesAutoresizingMaskIntoConstraints = false
        return transcript
    }
}
