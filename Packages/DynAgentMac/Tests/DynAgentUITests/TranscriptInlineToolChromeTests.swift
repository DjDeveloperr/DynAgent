@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptInlineToolChromeTests: XCTestCase {
    func testRunningEditShowsEditingFileAndReturnsStatsHandle() throws {
        let message = ChatMessage(
            role: .tool,
            text: "",
            toolName: "edit",
            toolDetail: #"{"path":"/repo/Sources/App.swift","added":2,"deleted":1,"diff":"+new"}"#
        )
        message.toolDone = false
        let label = MessageTextView()
        label.setRich(TranscriptToolFormatter.toolString(message))

        let chrome = TranscriptInlineToolChrome.make(label: label, message: message)

        XCTAssertNotNil(chrome.editStats)
        XCTAssertTrue(label.isHidden)
        let labels = findSubviews(of: NSTextField.self, in: chrome.view).map(\.stringValue)
        XCTAssertTrue(labels.contains("Editing App.swift"))
    }

    func testCompletedEditKeepsSummaryLabelAndStats() {
        let message = ChatMessage(
            role: .tool,
            text: "",
            toolName: "edit",
            toolDetail: #"{"path":"/repo/App.swift","added":3,"deleted":2,"diff":"+new"}"#
        )
        message.toolDone = true
        let label = MessageTextView()
        label.setRich(TranscriptToolFormatter.toolString(message))

        let chrome = TranscriptInlineToolChrome.make(label: label, message: message)

        XCTAssertNotNil(chrome.editStats)
        XCTAssertFalse(label.isHidden)
        XCTAssertTrue(findSubviews(of: EditStatsView.self, in: chrome.view).contains { !$0.isHidden })
    }

    func testRunningNonEditShowsStatusAndChevronWithoutEditStats() {
        let message = ChatMessage(
            role: .tool,
            text: "",
            toolName: "web_search",
            toolDetail: "query"
        )
        message.toolDone = false
        let label = MessageTextView()
        label.setRich(TranscriptToolFormatter.toolString(message))

        let chrome = TranscriptInlineToolChrome.make(label: label, message: message)

        XCTAssertNil(chrome.editStats)
        let labels = findSubviews(of: NSTextField.self, in: chrome.view).map(\.stringValue)
        XCTAssertTrue(labels.contains("Running"))
        XCTAssertFalse(findSubviews(of: NSImageView.self, in: chrome.view).isEmpty)
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
