@testable import DynAgentUI
import XCTest

final class TranscriptRenderModelTests: XCTestCase {
    func testBatchRangeUsesDefaultChunkSizeAndStopsAtEnd() {
        XCTAssertEqual(TranscriptRenderModel.batchRange(totalCount: 13, startIndex: 0), 0..<6)
        XCTAssertEqual(TranscriptRenderModel.batchRange(totalCount: 13, startIndex: 6), 6..<12)
        XCTAssertEqual(TranscriptRenderModel.batchRange(totalCount: 13, startIndex: 12), 12..<13)
        XCTAssertNil(TranscriptRenderModel.batchRange(totalCount: 13, startIndex: 13))
        XCTAssertNil(TranscriptRenderModel.batchRange(totalCount: 13, startIndex: 0, batchSize: 0))
    }

    func testGroupsCompletedEditToolsIntoOneEditItem() {
        let first = editTool(path: "/repo/A.swift", added: 2, deleted: 1)
        let second = editTool(path: "/repo/B.swift", added: 3, deleted: 0)

        let items = TranscriptRenderModel.groupedItems(messages: [first, second])

        guard case .editGroup(let changes) = items.first else {
            return XCTFail("Expected edit group")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(changes.map(\.path), ["/repo/A.swift", "/repo/B.swift"])
        XCTAssertEqual(changes.map(\.added), [2, 3])
    }

    func testKeepsRunningEditToolAsSingleMessage() {
        let running = ChatMessage(role: .tool, text: "Editing /repo/A.swift", toolName: "edit")
        running.toolDone = false

        let items = TranscriptRenderModel.groupedItems(messages: [running])

        guard case .message(let message) = items.first else {
            return XCTFail("Expected message row")
        }
        XCTAssertTrue(message === running)
    }

    func testGroupsCompletedShellToolsButShowsLatestRunningShellOnly() {
        let doneA = shellTool(done: true, detail: "$ ls\nexit 0")
        let doneB = shellTool(done: true, detail: "$ rg foo\nexit 0")
        let running = shellTool(done: false, detail: "$ sed -n '1,20p' A.swift")

        let completed = TranscriptRenderModel.groupedItems(messages: [doneA, doneB])
        guard case .shellGroup(let shellMessages) = completed.first else {
            return XCTFail("Expected shell group")
        }
        XCTAssertEqual(shellMessages.count, 2)

        let active = TranscriptRenderModel.groupedItems(messages: [doneA, running])
        guard case .message(let message) = active.first else {
            return XCTFail("Expected latest running shell message")
        }
        XCTAssertTrue(message === running)
    }

    func testCollapseDisabledKeepsShellMessagesSeparateButStillGroupsCompletedEdits() {
        let doneShell = shellTool(done: true, detail: "$ ls\nexit 0")
        let doneEdit = editTool(path: "/repo/A.swift", added: 1, deleted: 1)

        let items = TranscriptRenderModel.groupedItems(
            messages: [doneShell, doneEdit],
            collapseCompletedTools: false
        )

        XCTAssertEqual(items.count, 2)
        guard case .message(let shell) = items[0] else {
            return XCTFail("Expected shell message")
        }
        XCTAssertTrue(shell === doneShell)
        guard case .editGroup(let changes) = items[1] else {
            return XCTFail("Expected completed edits to remain grouped")
        }
        XCTAssertEqual(changes.count, 1)
    }

    private func editTool(path: String, added: Int, deleted: Int) -> ChatMessage {
        let detail = #"{"path":"\#(path)","added":\#(added),"deleted":\#(deleted),"diff":"+line"}"#
        let message = ChatMessage(role: .tool, toolName: "edit", toolDetail: detail)
        message.toolDone = true
        return message
    }

    private func shellTool(done: Bool, detail: String) -> ChatMessage {
        let message = ChatMessage(role: .tool, toolName: "shell", toolDetail: detail)
        message.toolDone = done
        return message
    }
}
