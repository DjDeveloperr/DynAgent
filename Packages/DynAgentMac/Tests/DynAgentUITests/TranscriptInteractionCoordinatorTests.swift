import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class TranscriptInteractionCoordinatorTests: XCTestCase {
    func testAppendRowRegistersToolStateAddsClickGestureAndPinsWhenNotBulkLoading() {
        let coordinator = TranscriptInteractionCoordinator()
        let transcript = NSStackView()
        let message = ChatMessage(role: .tool, text: "", toolName: "edit", toolDetail: "changed")
        var pinCount = 0

        let container = coordinator.appendRow(
            for: message,
            to: transcript,
            markdown: { NSAttributedString(string: $0) },
            bulkLoading: false,
            pinAfterAppend: { pinCount += 1 }
        )

        XCTAssertTrue(transcript.arrangedSubviews.contains(container))
        XCTAssertEqual(transcript.customSpacing(after: container), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertNotNil(coordinator.label(for: message))
        XCTAssertNotNil(coordinator.editStats(for: message))
        XCTAssertEqual(pinCount, 1)
        XCTAssertTrue(hasClickGesture(in: container))
    }

    func testAppendRowSkipsPinCallbackWhileBulkLoading() {
        let coordinator = TranscriptInteractionCoordinator()
        let transcript = NSStackView()
        let message = ChatMessage(role: .assistant, text: "streaming")
        var pinCount = 0

        _ = coordinator.appendRow(
            for: message,
            to: transcript,
            markdown: { NSAttributedString(string: $0) },
            bulkLoading: true,
            pinAfterAppend: { pinCount += 1 }
        )

        XCTAssertEqual(pinCount, 0)
        XCTAssertNotNil(coordinator.label(for: message))
    }

    func testAppendGroupedRowsBuildsShellGroupAndHonorsBulkPinning() {
        let coordinator = TranscriptInteractionCoordinator()
        let transcript = NSStackView()
        let first = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' A.swift"#)
        let second = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' B.swift"#)
        first.toolDone = true
        second.toolDone = true
        var pinCount = 0

        let rows = coordinator.appendRowsGrouped(
            [first, second],
            to: transcript,
            markdown: { NSAttributedString(string: $0) },
            bulkLoading: false,
            pinAfterAppend: { pinCount += 1 }
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(transcript.arrangedSubviews.contains(rows[0]))
        XCTAssertEqual(pinCount, 1)
        let labels = findSubviews(of: NSTextField.self, in: rows[0]).map(\.stringValue)
        XCTAssertTrue(labels.contains("Read 2 files  A.swift +1"))
    }

    func testInsertGroupedRowsPlacesGroupAtRequestedIndex() throws {
        let coordinator = TranscriptInteractionCoordinator()
        let transcript = NSStackView()
        let prefix = NSView()
        prefix.translatesAutoresizingMaskIntoConstraints = false
        let suffix = NSView()
        suffix.translatesAutoresizingMaskIntoConstraints = false
        TranscriptStackChrome.appendFullWidthRow(prefix, to: transcript)
        TranscriptStackChrome.appendFullWidthRow(suffix, to: transcript)
        let first = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' A.swift"#)
        let second = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' B.swift"#)
        first.toolDone = true
        second.toolDone = true

        let rows = coordinator.insertRowsGrouped(
            [first, second],
            at: 1,
            in: transcript,
            markdown: { NSAttributedString(string: $0) },
            bulkLoading: true,
            pinAfterAppend: {}
        )

        let inserted = try XCTUnwrap(rows.first)
        XCTAssertEqual(transcript.arrangedSubviews, [prefix, inserted, suffix])
        let labels = findSubviews(of: NSTextField.self, in: inserted).map(\.stringValue)
        XCTAssertTrue(labels.contains("Read 2 files  A.swift +1"))
    }

    func testAppendFinalFooterRegistersCopyTextAndOwnsCopyAction() throws {
        let coordinator = TranscriptInteractionCoordinator()
        let transcript = NSStackView()
        let message = ChatMessage(role: .assistant, text: "final answer")

        coordinator.appendFinalFooter(for: message, to: transcript)

        let button = try XCTUnwrap(findSubviews(of: NSButton.self, in: transcript).first)
        XCTAssertTrue((button.target as AnyObject?) === coordinator)
        XCTAssertEqual(coordinator.copyText(for: button), "final answer")
        XCTAssertEqual(button.action, NSSelectorFromString("copyFinal:"))
    }

    private func hasClickGesture(in root: NSView) -> Bool {
        if root.gestureRecognizers.contains(where: { $0 is NSClickGestureRecognizer }) {
            return true
        }
        return root.subviews.contains { hasClickGesture(in: $0) }
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
