@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptRowFactoryTests: XCTestCase {
    func testAssistantRowBuildsMarkdownLabelWithoutToolMetadata() throws {
        let message = ChatMessage(role: .assistant, text: "Changed `App.swift`")

        let row = TranscriptRowFactory.makeRow(for: message) { text in
            NSAttributedString(string: text)
        }

        let label = try XCTUnwrap(row.label)
        XCTAssertEqual(label.string, "Changed `App.swift`")
        XCTAssertNil(row.clickableToolView)
        XCTAssertNil(row.editStats)
        XCTAssertNil(row.customSpacingAfter)
        XCTAssertTrue(row.container.subviews.contains(label))
    }

    func testShellToolRowUsesShellChromeWithoutClickableToolMetadata() {
        let message = ChatMessage(
            role: .tool,
            text: "",
            toolName: "shell",
            toolDetail: #"$ /bin/zsh -lc "sed -n '1,40p' App.swift"\#nexit 0\#n\#nfinal class App"#
        )
        message.toolDone = true

        let row = TranscriptRowFactory.makeRow(for: message) { NSAttributedString(string: $0) }

        XCTAssertNil(row.label)
        XCTAssertNil(row.clickableToolView)
        XCTAssertNil(row.editStats)
        XCTAssertEqual(row.customSpacingAfter, 6)
        XCTAssertFalse(findSubviews(of: ShellToolView.self, in: row.container).isEmpty)
    }

    func testEditToolRowReturnsClickableViewAndStatsHandle() throws {
        let message = ChatMessage(
            role: .tool,
            text: "",
            toolName: "edit",
            toolDetail: #"{"path":"/repo/App.swift","added":3,"deleted":1,"diff":"+new"}"#
        )
        message.toolDone = true

        let row = TranscriptRowFactory.makeRow(for: message) { NSAttributedString(string: $0) }

        let label = try XCTUnwrap(row.label)
        XCTAssertFalse(label.isSelectable)
        XCTAssertNotNil(row.clickableToolView)
        XCTAssertNotNil(row.editStats)
        XCTAssertEqual(row.customSpacingAfter, 6)
    }

    func testLargeThreadNoticeDelegatesToChrome() throws {
        let notice = TranscriptRowFactory.largeThreadNotice(maxRenderedMessages: 240, hiddenCount: 99)

        let label = try XCTUnwrap(findSubviews(of: NSTextField.self, in: notice).first)
        XCTAssertEqual(label.stringValue, "Showing latest 240 messages. 99 older messages skipped for performance.")
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
