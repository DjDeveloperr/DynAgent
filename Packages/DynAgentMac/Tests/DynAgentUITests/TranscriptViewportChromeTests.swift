@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptViewportChromeTests: XCTestCase {
    func testConfiguresTranscriptForWidthTrackingVerticalRows() {
        let transcript = NSStackView()

        TranscriptViewportChrome.configureTranscript(transcript)

        XCTAssertEqual(transcript.orientation, .vertical)
        XCTAssertEqual(transcript.alignment, .leading)
        XCTAssertEqual(transcript.spacing, TranscriptViewportChrome.transcriptSpacing)
        XCTAssertFalse(transcript.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(transcript.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        XCTAssertEqual(transcript.contentHuggingPriority(for: .horizontal), .defaultLow)
    }

    func testDocumentOwnsTranscriptAndKeepsLowHorizontalPriorities() {
        let transcript = NSStackView()

        let document = TranscriptViewportChrome.makeDocument(containing: transcript)

        XCTAssertTrue(document.isFlipped)
        XCTAssertTrue(transcript.superview === document)
        XCTAssertFalse(document.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(document.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        XCTAssertEqual(document.contentHuggingPriority(for: .horizontal), .defaultLow)
    }

    func testConfiguresScrollViewForManualBottomInsetAndDocumentTracking() {
        let scroll = NSScrollView()
        let document = NSView()

        TranscriptViewportChrome.configureScroll(scroll, document: document)

        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertFalse(scroll.automaticallyAdjustsContentInsets)
        XCTAssertEqual(scroll.contentInsets.bottom, TranscriptViewportChrome.initialBottomInset)
        XCTAssertTrue(scroll.documentView === document)
        XCTAssertFalse(scroll.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(scroll.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        XCTAssertEqual(scroll.contentHuggingPriority(for: .horizontal), .defaultLow)
    }

    func testViewportConstraintsKeepDocumentAndTranscriptTrackingRootWidth() {
        let root = NSView()
        let scroll = NSScrollView()
        let document = NSView()
        let transcript = NSStackView()

        let constraints = TranscriptViewportChrome.constraints(
            scroll: scroll,
            root: root,
            document: document,
            transcript: transcript,
            horizontalInset: 17
        )

        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == scroll.leadingAnchor && $0.secondAnchor == root.leadingAnchor
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == scroll.trailingAnchor && $0.secondAnchor == root.trailingAnchor
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == document.leadingAnchor && $0.secondAnchor == scroll.contentView.leadingAnchor
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == document.trailingAnchor && $0.secondAnchor == scroll.contentView.trailingAnchor
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == transcript.leadingAnchor && $0.secondAnchor == document.leadingAnchor && $0.constant == 17
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == transcript.trailingAnchor && $0.secondAnchor == document.trailingAnchor && $0.constant == -17
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == transcript.topAnchor && $0.constant == TranscriptViewportChrome.topPadding
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == transcript.bottomAnchor && $0.constant == -TranscriptViewportChrome.bottomPadding
        })
    }
}
