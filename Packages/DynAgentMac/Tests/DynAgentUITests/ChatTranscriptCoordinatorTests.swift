@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class ChatTranscriptCoordinatorTests: XCTestCase {
    func testLoadingShellAndClearRowsOwnTranscriptStackLifecycle() {
        let coordinator = ChatTranscriptCoordinator()
        let transcript = makeTranscript()

        coordinator.appendLoadingShell(text: "Loading latest thread...", to: transcript)

        XCTAssertEqual(transcript.arrangedSubviews.count, 1)
        XCTAssertTrue(findLabels(in: transcript).contains("Loading latest thread..."))

        coordinator.clearRows(from: transcript)

        XCTAssertEqual(transcript.arrangedSubviews.count, 0)
    }

    func testAppendRowAndRenderLiveAssistantUpdateRegisteredLabel() throws {
        let coordinator = ChatTranscriptCoordinator()
        let transcript = makeTranscript()
        let assistant = ChatMessage(role: .assistant, text: "first")

        _ = coordinator.appendRow(
            for: assistant,
            to: transcript,
            markdown: { NSAttributedString(string: $0.uppercased()) },
            bulkLoading: false
        )
        assistant.text = "updated"
        coordinator.renderLiveAssistant(
            assistant,
            markdown: { NSAttributedString(string: $0.uppercased()) },
            force: true,
            now: 10
        )

        let message = try XCTUnwrap(findSubviews(of: MessageTextView.self, in: transcript).first)
        XCTAssertEqual(message.attributedString().string, "UPDATED")
    }

    func testLiveDividerLifecycleAndThinkingRowsAreReusable() {
        let coordinator = ChatTranscriptCoordinator()
        let transcript = makeTranscript()

        XCTAssertEqual(transcript.arrangedSubviews.count, 0)
        coordinator.showThinking(in: transcript)
        coordinator.showThinking(in: transcript)
        XCTAssertEqual(transcript.arrangedSubviews.count, 1)

        let divider = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 10,
            now: 15,
            transcript: transcript
        )
        let same = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 10,
            now: 20,
            transcript: transcript
        )

        XCTAssertTrue(divider === same)
        XCTAssertEqual(transcript.arrangedSubviews.count, 2)

        coordinator.finishLiveDivider(for: "thread-1", duration: 9)
        let next = coordinator.ensureLiveDivider(
            for: "thread-1",
            startedAt: 30,
            now: 31,
            transcript: transcript
        )
        XCTAssertFalse(next === divider)

        coordinator.hideThinking()
        XCTAssertFalse(transcript.arrangedSubviews.contains { view in
            findLabels(in: view).contains("Thinking")
        })
    }

    private func makeTranscript() -> NSStackView {
        let transcript = NSStackView()
        transcript.orientation = .vertical
        transcript.translatesAutoresizingMaskIntoConstraints = false
        return transcript
    }

    private func findLabels(in root: NSView) -> [String] {
        findSubviews(of: NSTextField.self, in: root).map(\.stringValue)
    }

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var result: [T] = []
        if let match = root as? T {
            result.append(match)
        }
        for subview in root.subviews {
            result.append(contentsOf: findSubviews(of: type, in: subview))
        }
        return result
    }
}
