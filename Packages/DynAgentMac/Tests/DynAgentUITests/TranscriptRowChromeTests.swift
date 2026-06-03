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

    func testSteerBubbleLabelsPendingAndCompletedStates() throws {
        let pending = NSView()
        TranscriptRowChrome.installSteerBubble(text: "adjust this", pending: true, in: pending)
        XCTAssertTrue(findSubviews(of: NSTextField.self, in: pending).contains { $0.stringValue == "Steering conversation…" })

        let completed = NSView()
        TranscriptRowChrome.installSteerBubble(text: "adjust this", pending: false, in: completed)
        XCTAssertTrue(findSubviews(of: NSTextField.self, in: completed).contains { $0.stringValue == "Steered conversation" })
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
