@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptRowChromeTests: XCTestCase {
    func testThinkingRowBuildsPinnedShimmerContainer() {
        let row = TranscriptRowChrome.thinkingRow(text: "Thinking")

        XCTAssertFalse(row.container.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(row.shimmer.superview === row.container)
        XCTAssertFalse(row.shimmer.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(row.container.constraints.contains {
            $0.firstAnchor == row.shimmer.leadingAnchor && $0.secondAnchor == row.container.leadingAnchor
        })
        XCTAssertTrue(row.container.constraints.contains {
            $0.firstAnchor == row.shimmer.topAnchor && $0.secondAnchor == row.container.topAnchor
        })
        XCTAssertTrue(row.container.constraints.contains {
            $0.firstAnchor == row.shimmer.bottomAnchor && $0.secondAnchor == row.container.bottomAnchor
        })
    }

    func testUserBubbleBuildsSelectableWrappingTextWithoutFixedWidth() throws {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        TranscriptRowChrome.installUserBubble(text: "hello\nthere", in: container)

        let label = try XCTUnwrap(findSubviews(of: NSTextField.self, in: container).first)
        XCTAssertEqual(label.stringValue, "hello\nthere")
        XCTAssertTrue(label.isSelectable)
        XCTAssertEqual(label.lineBreakMode, .byWordWrapping)
        XCTAssertFalse(container.constraints.contains { $0.firstAttribute == .width && $0.relation == .equal })
    }

    func testMessageTextViewIntrinsicHeightTracksAssignedWidth() {
        let text = """
        This is a long markdown row that must wrap inside the readable chat column instead of painting across subsequent transcript rows.
        This second line makes the regression easier to catch because the height should grow when the view gets narrower.
        """
        let view = MessageTextView()
        view.setRich(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 15)
        ]))

        view.setFrameSize(NSSize(width: 760, height: 1))
        let wideHeight = view.intrinsicContentSize.height

        view.setFrameSize(NSSize(width: 260, height: 1))
        let narrowHeight = view.intrinsicContentSize.height

        XCTAssertGreaterThan(wideHeight, 1)
        XCTAssertGreaterThan(narrowHeight, wideHeight)
    }

    func testSteerBubbleLabelsPendingAndCompletedStates() throws {
        let pending = NSView()
        TranscriptRowChrome.installSteerBubble(text: "adjust this", pending: true, in: pending)
        XCTAssertTrue(findSubviews(of: NSTextField.self, in: pending).contains { $0.stringValue == "Steering conversation…" })

        let completed = NSView()
        TranscriptRowChrome.installSteerBubble(text: "adjust this", pending: false, in: completed)
        XCTAssertTrue(findSubviews(of: NSTextField.self, in: completed).contains { $0.stringValue == "Steered conversation" })
        XCTAssertFalse(completed.constraints.contains {
            $0.firstAttribute == .width && $0.relation == .equal
        })
    }

    func testSteerNoticeCombinesStatusAndDetail() throws {
        let container = NSView()
        TranscriptRowChrome.installSteerNotice(detail: "Use smaller padding", pending: false, in: container)

        let label = try XCTUnwrap(findSubviews(of: NSTextField.self, in: container).first)
        XCTAssertEqual(label.stringValue, "Steered conversation\nUse smaller padding")
        XCTAssertEqual(label.textColor, .secondaryLabelColor)
    }

    func testFinalFooterBuildsCopyButtonAndTimestamp() throws {
        let target = DummyTarget()
        let footer = TranscriptRowChrome.finalFooter(
            text: "final",
            timestamp: 1_785_600_000,
            target: target,
            copyAction: #selector(DummyTarget.copy(_:))
        )

        XCTAssertEqual(footer.copyButton.toolTip, "Copy")
        XCTAssertTrue(footer.copyButton.target === target)
        let labels = findSubviews(of: NSTextField.self, in: footer.view)
        XCTAssertFalse(labels.map(\.stringValue).joined().isEmpty)
    }

    func testLargeThreadNoticeUsesProvidedCounts() throws {
        let notice = TranscriptRowChrome.largeThreadNotice(maxRenderedMessages: 240, hiddenCount: 1200)

        let label = try XCTUnwrap(findSubviews(of: NSTextField.self, in: notice).first)
        XCTAssertEqual(label.stringValue, "Showing latest 240 messages. 1200 older messages skipped for performance.")
        XCTAssertEqual(label.textColor, .tertiaryLabelColor)
    }

    func testLoadingShellRowCentersLabelAndTracksTranscriptWidth() throws {
        let transcript = NSStackView()
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let row = TranscriptLoadingShellChrome.makeRow(text: "Loading latest thread...")

        transcript.addArrangedSubview(row)
        let widthConstraint = TranscriptLoadingShellChrome.pinRowToTranscriptWidth(row, transcript: transcript)

        let label = try XCTUnwrap(findSubviews(of: NSTextField.self, in: row).first)
        XCTAssertEqual(label.stringValue, "Loading latest thread...")
        XCTAssertEqual(label.textColor, .tertiaryLabelColor)
        XCTAssertFalse(row.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(row.constraints.contains {
            $0.firstAnchor == label.centerXAnchor && $0.secondAnchor == row.centerXAnchor
        })
        XCTAssertTrue(row.constraints.contains {
            $0.firstAnchor == label.topAnchor && $0.constant == TranscriptLoadingShellChrome.verticalPadding
        })
        XCTAssertTrue(row.constraints.contains {
            $0.firstAnchor == label.bottomAnchor && $0.constant == -TranscriptLoadingShellChrome.verticalPadding
        })
        XCTAssertEqual(widthConstraint.firstAnchor, row.widthAnchor)
        XCTAssertEqual(widthConstraint.secondAnchor, transcript.widthAnchor)
        XCTAssertTrue(widthConstraint.isActive)
        XCTAssertFalse(row.constraints.contains {
            $0.firstAttribute == .width && $0.relation == .equal && $0.secondItem == nil
        })
    }

    func testTranscriptStackContainerPinsContentEdgesWithoutFixedWidth() throws {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = TranscriptStackChrome.makeFullWidthContainer(containing: content)

        XCTAssertFalse(container.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(content.superview === container)
        XCTAssertTrue(container.constraints.contains {
            $0.firstAnchor == content.topAnchor && $0.secondAnchor == container.topAnchor
        })
        XCTAssertTrue(container.constraints.contains {
            $0.firstAnchor == content.bottomAnchor && $0.secondAnchor == container.bottomAnchor
        })
        XCTAssertTrue(container.constraints.contains {
            $0.firstAnchor == content.leadingAnchor && $0.secondAnchor == container.leadingAnchor
        })
        XCTAssertTrue(container.constraints.contains {
            $0.firstAnchor == content.trailingAnchor && $0.secondAnchor == container.trailingAnchor
        })
        XCTAssertFalse(container.constraints.contains {
            $0.firstAttribute == .width && $0.relation == .equal && $0.secondItem == nil
        })
    }

    func testTranscriptStackPinnerTracksTranscriptWidth() {
        let transcript = NSStackView()
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        transcript.addArrangedSubview(row)

        let constraint = TranscriptStackChrome.pinRowToTranscriptWidth(row, transcript: transcript)

        XCTAssertEqual(constraint.firstAnchor, row.widthAnchor)
        XCTAssertEqual(constraint.secondAnchor, transcript.widthAnchor)
        XCTAssertTrue(constraint.isActive)
        XCTAssertFalse(row.constraints.contains {
            $0.firstAttribute == .width && $0.relation == .equal && $0.secondItem == nil
        })
    }

    func testTranscriptStackAppendAddsFullWidthRowAndCustomSpacing() {
        let transcript = NSStackView()
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let constraint = TranscriptStackChrome.appendFullWidthRow(row, to: transcript, customSpacingAfter: TranscriptStackChrome.toolSpacingAfter)

        XCTAssertTrue(transcript.arrangedSubviews.contains(row))
        XCTAssertEqual(transcript.customSpacing(after: row), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertEqual(constraint.firstAnchor, row.widthAnchor)
        XCTAssertEqual(constraint.secondAnchor, transcript.widthAnchor)
        XCTAssertTrue(constraint.isActive)
    }

    func testTranscriptStackInsertClampsIndexAndPinsWidth() {
        let transcript = NSStackView()
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let first = NSView()
        first.translatesAutoresizingMaskIntoConstraints = false
        let second = NSView()
        second.translatesAutoresizingMaskIntoConstraints = false
        let inserted = NSView()
        inserted.translatesAutoresizingMaskIntoConstraints = false
        transcript.addArrangedSubview(first)
        transcript.addArrangedSubview(second)

        let constraint = TranscriptStackChrome.insertFullWidthRow(
            inserted,
            at: 1,
            in: transcript,
            customSpacingAfter: TranscriptStackChrome.toolSpacingAfter
        )

        XCTAssertEqual(transcript.arrangedSubviews, [first, inserted, second])
        XCTAssertEqual(transcript.customSpacing(after: inserted), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertEqual(constraint.firstAnchor, inserted.widthAnchor)
        XCTAssertEqual(constraint.secondAnchor, transcript.widthAnchor)
        XCTAssertTrue(constraint.isActive)
    }

    func testTranscriptStackInsertContainerAddsPinnedWrappedContent() {
        let transcript = NSStackView()
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let before = NSView()
        let after = NSView()
        let content = NSTextField(labelWithString: "group")
        transcript.addArrangedSubview(before)
        transcript.addArrangedSubview(after)

        let container = TranscriptStackChrome.insertFullWidthContainer(
            containing: content,
            at: 1,
            in: transcript
        )

        XCTAssertEqual(transcript.arrangedSubviews, [before, container, after])
        XCTAssertTrue(content.superview === container)
        XCTAssertTrue(transcript.constraints.contains {
            $0.firstAnchor == container.widthAnchor && $0.secondAnchor == transcript.widthAnchor
        })
    }

    func testTranscriptStackAppendContainerAddsPinnedWrappedContent() throws {
        let transcript = NSStackView()
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let content = NSTextField(labelWithString: "tool group")
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = TranscriptStackChrome.appendFullWidthContainer(containing: content, to: transcript)

        XCTAssertTrue(transcript.arrangedSubviews.contains(container))
        XCTAssertTrue(content.superview === container)
        XCTAssertTrue(container.constraints.contains {
            $0.firstAnchor == content.leadingAnchor && $0.secondAnchor == container.leadingAnchor
        })
        XCTAssertTrue(container.constraints.contains {
            $0.firstAnchor == content.trailingAnchor && $0.secondAnchor == container.trailingAnchor
        })
        XCTAssertTrue(transcript.constraints.contains {
            $0.firstAnchor == container.widthAnchor && $0.secondAnchor == transcript.widthAnchor
        })
    }

    func testTranscriptStackRemoveAllRowsClearsArrangedSubviewsAndSuperview() {
        let transcript = NSStackView()
        let first = NSView()
        let second = NSView()
        transcript.addArrangedSubview(first)
        transcript.addArrangedSubview(second)

        TranscriptStackChrome.removeAllRows(from: transcript)

        XCTAssertTrue(transcript.arrangedSubviews.isEmpty)
        XCTAssertNil(first.superview)
        XCTAssertNil(second.superview)
    }

    func testTranscriptStackMoveRowToBottomReordersExistingRow() {
        let transcript = NSStackView()
        let first = NSView()
        let second = NSView()
        let third = NSView()
        transcript.addArrangedSubview(first)
        transcript.addArrangedSubview(second)
        transcript.addArrangedSubview(third)

        TranscriptStackChrome.moveRowToBottom(first, in: transcript)

        XCTAssertEqual(transcript.arrangedSubviews, [second, third, first])
        XCTAssertTrue(first.superview === transcript)
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

private final class DummyTarget: NSObject {
    @objc func copy(_ sender: Any?) {}
}
