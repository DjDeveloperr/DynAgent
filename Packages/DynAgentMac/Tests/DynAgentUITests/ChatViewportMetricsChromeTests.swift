@testable import DynAgentUI
import AppKit
import XCTest

final class ChatViewportMetricsChromeTests: XCTestCase {
    func testPayloadCapturesChatViewportWidthsAndVisibleRows() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 420))
        scroll.documentView = document

        let transcript = NSStackView(frame: NSRect(x: 14, y: 0, width: 872, height: 360))
        transcript.addArrangedSubview(NSView())
        transcript.addArrangedSubview(NSView())

        let composer = NSView(frame: NSRect(x: 14, y: 16, width: 872, height: 144))
        root.addSubview(scroll)
        root.addSubview(composer)

        let payload = ChatViewportMetricsChrome.payload(
            root: root,
            scroll: scroll,
            transcript: transcript,
            composer: composer
        )

        XCTAssertEqual(payload["chatViewWidth"] as? Double, 900)
        XCTAssertEqual(payload["chatViewHeight"] as? Double, 700)
        XCTAssertEqual(payload["scrollWidth"] as? Double, 900)
        XCTAssertEqual(payload["scrollHeight"] as? Double, 700)
        XCTAssertEqual(payload["documentWidth"] as? Double, 900)
        XCTAssertEqual(payload["documentHeight"] as? Double, 420)
        XCTAssertEqual(payload["transcriptWidth"] as? Double, 872)
        XCTAssertEqual(payload["composerWidth"] as? Double, 872)
        XCTAssertEqual(payload["composerHeight"] as? Double, 144)
        XCTAssertEqual(payload["visibleRows"] as? Int, 2)
    }

    func testFrameMetricsPreserveSubviewOrderClassAndGeometry() throws {
        let first = NSView(frame: NSRect(x: 3, y: 4, width: 120, height: 40))
        let second = NSButton(frame: NSRect(x: 11, y: 12, width: 24, height: 18))

        let frames = ChatViewportMetricsChrome.frameMetrics(for: [first, second])

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0]["index"] as? Int, 0)
        XCTAssertEqual(frames[0]["class"] as? String, "NSView")
        XCTAssertEqual(frames[0]["x"] as? Double, 3)
        XCTAssertEqual(frames[0]["y"] as? Double, 4)
        XCTAssertEqual(frames[0]["width"] as? Double, 120)
        XCTAssertEqual(frames[0]["height"] as? Double, 40)
        XCTAssertEqual(frames[1]["index"] as? Int, 1)
        XCTAssertEqual(frames[1]["class"] as? String, "NSButton")
        XCTAssertEqual(frames[1]["x"] as? Double, 11)
        XCTAssertEqual(frames[1]["y"] as? Double, 12)
        XCTAssertEqual(frames[1]["width"] as? Double, 24)
        XCTAssertEqual(frames[1]["height"] as? Double, 18)
    }
}
