@testable import DynAgentUI
import XCTest

final class MobilePresentationModelTests: XCTestCase {
    func testComposerPresentationUsesSharedComposerRules() {
        let presentation = MobilePresentationModel.composer(
            model: "gpt-5.5-codex",
            harness: .codex,
            input: "  fix it  ",
            sending: false
        )

        XCTAssertEqual(presentation.modelTitle, "5.5 Codex")
        XCTAssertEqual(presentation.placeholder, "Ask Codex")
        XCTAssertEqual(presentation.sendSymbol, "arrow.up")
        XCTAssertEqual(presentation.sendAccessibilityLabel, "Send")
        XCTAssertTrue(presentation.canSend)
    }

    func testComposerPresentationDisablesSendWhileStreamingOrBlank() {
        XCTAssertFalse(MobilePresentationModel.composer(
            model: "auto",
            harness: .dynagent,
            input: "steer",
            sending: true
        ).canSend)
        XCTAssertFalse(MobilePresentationModel.composer(
            model: "auto",
            harness: .dynagent,
            input: "   ",
            sending: false
        ).canSend)
    }

    func testToolPresentationUsesShellSummaryAndHidesEmptyOutput() {
        let withOutput = ChatMessage(
            role: .tool,
            text: "",
            toolName: "shell",
            toolDetail: "$ sed -n '1,20p' App.swift\nhello"
        )
        withOutput.toolDone = true

        let outputPresentation = MobilePresentationModel.tool(message: withOutput)
        XCTAssertEqual(outputPresentation.title, "Read App.swift")
        XCTAssertEqual(outputPresentation.output, "hello")
        XCTAssertTrue(outputPresentation.showsOutput)

        let noOutput = ChatMessage(role: .tool, text: "$ ls", toolName: "shell", toolDetail: "$ ls")
        let emptyPresentation = MobilePresentationModel.tool(message: noOutput)
        XCTAssertFalse(emptyPresentation.showsOutput)
    }
}
