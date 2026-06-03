@testable import DynAgentUI
import XCTest

final class ShellToolModelTests: XCTestCase {
    func testSummarizesLastPromptCommandExitAndOutput() {
        let detail = """
        $ pwd
        /repo
        $ /bin/zsh -lc "sed -n '1,40p' Packages/DynAgentMac/Sources/UI/ChatViewController.swift"
        exit 0

        final class ChatViewController
        """

        let summary = ShellToolModel.summary(from: detail)

        XCTAssertEqual(summary.command, #"/bin/zsh -lc "sed -n '1,40p' Packages/DynAgentMac/Sources/UI/ChatViewController.swift""#)
        XCTAssertEqual(summary.exitCode, "0")
        XCTAssertEqual(summary.output, "final class ChatViewController")
    }

    func testLabelsWrappedSedAsReadingFile() {
        let title = ShellToolModel.title(
            command: #"/bin/zsh -lc "sed -n '1,40p' Packages/DynAgentMac/Sources/UI/ChatViewController.swift""#,
            done: false
        )

        XCTAssertEqual(title.action, "Reading")
        XCTAssertEqual(title.detail, "Packages/DynAgentMac/Sources/UI/ChatViewController.swift")
        XCTAssertEqual(title.category, "read")
    }

    func testLabelsRipgrepAsSearchQuery() {
        let title = ShellToolModel.title(command: #"rg -n "ShellSummary|shellToolTitle" Packages/DynAgentMac/Sources/UI"#, done: true)

        XCTAssertEqual(title.action, "Searched for")
        XCTAssertEqual(title.detail, "ShellSummary|shellToolTitle")
        XCTAssertEqual(title.category, "search")
    }

    func testShellWordsPreserveQuotedArguments() {
        XCTAssertEqual(
            ShellToolModel.shellWords(#"rg -n "hello world" 'Sources/UI'"#),
            ["rg", "-n", "hello world", "Sources/UI"]
        )
    }
}
