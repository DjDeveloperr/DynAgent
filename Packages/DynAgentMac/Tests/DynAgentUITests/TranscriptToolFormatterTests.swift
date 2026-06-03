@testable import DynAgentUI
import XCTest

final class TranscriptToolFormatterTests: XCTestCase {
    func testShellTitleUsesModelActionAndDetail() {
        let message = ChatMessage(
            role: .tool,
            text: "",
            toolName: "shell",
            toolDetail: #"$ /bin/zsh -lc "sed -n '1,20p' Sources/App.swift""#
        )
        message.toolDone = false
        let summary = TranscriptToolFormatter.shellSummary(message)

        let title = TranscriptToolFormatter.shellTitle(message, summary: summary).string

        XCTAssertEqual(title, "Reading  Sources/App.swift")
    }

    func testShellGroupTitleCollapsesSameCategory() {
        let messages = [
            ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' A.swift"#),
            ChatMessage(role: .tool, text: "", toolName: "shell", toolDetail: #"$ sed -n '1p' B.swift"#),
        ]
        let summaries = messages.map(TranscriptToolFormatter.shellSummary)

        XCTAssertEqual(TranscriptToolFormatter.shellGroupTitle(summaries).string, "Read 2 files  A.swift +1")
    }

    func testEditToolStringAndIconNames() {
        let edit = ChatMessage(
            role: .tool,
            text: "",
            toolName: "edit",
            toolDetail: #"{"path":"/repo/App.swift","added":2,"deleted":1,"diff":"+new"}"#
        )
        edit.toolDone = true

        XCTAssertEqual(TranscriptToolFormatter.toolString(edit).string, "Edited 1 file")
        XCTAssertEqual(TranscriptToolFormatter.toolIconName("edit"), "pencil")
        XCTAssertEqual(TranscriptToolFormatter.toolIconName("web_search"), "magnifyingglass")
        XCTAssertEqual(TranscriptToolFormatter.toolIconName("unknown"), "hammer")
    }

    func testFallbackToolPreviewIsIncluded() {
        let tool = ChatMessage(role: .tool, text: "", toolName: "custom_tool", toolDetail: "first\n\nsecond")
        tool.toolDone = true

        XCTAssertEqual(TranscriptToolFormatter.toolString(tool).string, "Completed custom tool\nfirst\nsecond")
    }
}
