@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptGroupedToolRowChromeTests: XCTestCase {
    func testAppendShellGroupBuildsGroupedRowAndAppendsContainer() {
        let transcript = NSStackView()
        let first = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' A.swift"#)
        first.toolDone = true
        let second = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' B.swift"#)
        second.toolDone = true

        let row = TranscriptGroupedToolRowChrome.appendShellGroup(messages: [first, second], to: transcript)

        XCTAssertTrue(transcript.arrangedSubviews.contains(row.container))
        XCTAssertEqual(transcript.customSpacing(after: row.container), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertTrue(row.content is ShellGroupView)
        XCTAssertEqual(findSubviews(of: ShellToolView.self, in: row.container).count, 2)
        let labels = findSubviews(of: NSTextField.self, in: row.container).map(\.stringValue)
        XCTAssertTrue(labels.contains("Read 2 files  A.swift +1"))
    }

    func testInsertShellGroupPlacesContainerAtRequestedIndex() {
        let transcript = NSStackView()
        let before = NSView()
        let after = NSView()
        transcript.addArrangedSubview(before)
        transcript.addArrangedSubview(after)
        let first = ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ ls"#)
        first.toolDone = true

        let row = TranscriptGroupedToolRowChrome.insertShellGroup(
            messages: [first],
            at: 1,
            in: transcript
        )

        XCTAssertEqual(transcript.arrangedSubviews, [before, row.container, after])
        XCTAssertEqual(transcript.customSpacing(after: row.container), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertTrue(row.content is ShellGroupView)
    }

    func testAppendEditGroupBuildsExpandableFileRowsAndOpenCallback() throws {
        let transcript = NSStackView()
        let change = EditToolChange(path: "/repo/Sources/App.swift", added: 3, deleted: 1, diff: "+new")
        var opened: EditToolChange?
        var anchor: NSView?

        let row = TranscriptGroupedToolRowChrome.appendEditGroup(changes: [change], to: transcript) { change, view in
            opened = change
            anchor = view
        }

        XCTAssertTrue(transcript.arrangedSubviews.contains(row.container))
        XCTAssertEqual(transcript.customSpacing(after: row.container), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertTrue(row.content is EditGroupView)
        let headerLabels = findSubviews(of: NSTextField.self, in: row.container).map(\.stringValue)
        XCTAssertTrue(headerLabels.contains("Edited 1 file"))

        row.content.perform(NSSelectorFromString("toggle"))
        let fileRow = try XCTUnwrap(findSubviews(of: EditFileSummaryRow.self, in: row.container).first)
        fileRow.perform(NSSelectorFromString("open"))

        XCTAssertEqual(opened, change)
        XCTAssertTrue(anchor === fileRow)
    }

    func testInsertEditGroupPlacesContainerAtRequestedIndex() {
        let transcript = NSStackView()
        let before = NSView()
        let after = NSView()
        transcript.addArrangedSubview(before)
        transcript.addArrangedSubview(after)
        let change = EditToolChange(path: "/repo/Sources/App.swift", added: 2, deleted: 0, diff: "+new")

        let row = TranscriptGroupedToolRowChrome.insertEditGroup(
            changes: [change],
            at: 1,
            in: transcript,
            onOpenChange: { _, _ in }
        )

        XCTAssertEqual(transcript.arrangedSubviews, [before, row.container, after])
        XCTAssertEqual(transcript.customSpacing(after: row.container), TranscriptStackChrome.toolSpacingAfter)
        XCTAssertTrue(row.content is EditGroupView)
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
