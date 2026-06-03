@testable import DynAgentUI
import XCTest

@MainActor
final class AppControlPollingCoordinatorTests: XCTestCase {
    func testPollWritesTerminalActionAndReportsDelayedOutput() async {
        let terminal = FakeControlTerminal(id: "term-1", output: "command output")
        var scheduled: [(TimeInterval, () -> Void)] = []
        var reported: [(id: String, output: String)] = []
        var refreshCount = 0
        let coordinator = AppControlPollingCoordinator(
            pollTerminalActions: { [AgentClient.TerminalAction(text: "ls\n", id: "term-1")] },
            pollBrowserActions: { [] },
            terminal: { id in id == "term-1" ? terminal : nil },
            browser: { _ in nil },
            reportTerminalOutput: { id, output in reported.append((id, output)) },
            reportBrowserState: { _, _, _ in },
            reportBrowserResult: { _, _ in },
            refreshSelectedActiveCodexThread: { refreshCount += 1 },
            scheduler: { delay, action in scheduled.append((delay, action)) }
        )

        await coordinator.pollOnce()

        XCTAssertEqual(terminal.writes, ["ls\n"])
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].0, 0.4, accuracy: 0.001)
        XCTAssertEqual(refreshCount, 1)

        scheduled[0].1()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported[0].id, "term-1")
        XCTAssertEqual(reported[0].output, "command output")
    }

    func testTerminalActionFallsBackToPanelIdWhenActionIdIsMissing() async {
        let terminal = FakeControlTerminal(id: "fallback-terminal", output: "fallback output")
        var scheduled: [() -> Void] = []
        var reportedId: String?
        let coordinator = AppControlPollingCoordinator(
            pollTerminalActions: { [AgentClient.TerminalAction(text: "pwd\n", id: nil)] },
            pollBrowserActions: { [] },
            terminal: { id in id == nil ? terminal : nil },
            browser: { _ in nil },
            reportTerminalOutput: { id, _ in reportedId = id },
            reportBrowserState: { _, _, _ in },
            reportBrowserResult: { _, _ in },
            refreshSelectedActiveCodexThread: {},
            scheduler: { _, action in scheduled.append(action) }
        )

        await coordinator.pollOnce()
        scheduled.first?()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(reportedId, "fallback-terminal")
    }

    func testBrowserNavigateLoadsAndReportsDelayedState() async {
        let browser = FakeControlBrowser(id: "browser-1", currentURL: "https://example.com", title: "Example")
        var scheduled: [(TimeInterval, () -> Void)] = []
        var reported: [(id: String, url: String, title: String)] = []
        let coordinator = AppControlPollingCoordinator(
            pollTerminalActions: { [] },
            pollBrowserActions: { [AgentClient.BrowserAction(type: "navigate", url: "example.com", script: nil, id: "browser-1", resultId: nil)] },
            terminal: { _ in nil },
            browser: { id in id == "browser-1" ? browser : nil },
            reportTerminalOutput: { _, _ in },
            reportBrowserState: { id, url, title in reported.append((id, url, title)) },
            reportBrowserResult: { _, _ in },
            refreshSelectedActiveCodexThread: {},
            scheduler: { delay, action in scheduled.append((delay, action)) }
        )

        await coordinator.pollOnce()

        XCTAssertEqual(browser.loadedURLs, ["example.com"])
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].0, 1.0, accuracy: 0.001)

        scheduled[0].1()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported[0].id, "browser-1")
        XCTAssertEqual(reported[0].url, "https://example.com")
        XCTAssertEqual(reported[0].title, "Example")
    }

    func testBrowserEvalReportsResultImmediately() async {
        let browser = FakeControlBrowser(id: "browser-1", evalResult: "42")
        var reported: [(resultId: String, result: String)] = []
        let coordinator = AppControlPollingCoordinator(
            pollTerminalActions: { [] },
            pollBrowserActions: { [AgentClient.BrowserAction(type: "eval", url: nil, script: "answer()", id: "browser-1", resultId: "result-1")] },
            terminal: { _ in nil },
            browser: { id in id == "browser-1" ? browser : nil },
            reportTerminalOutput: { _, _ in },
            reportBrowserState: { _, _, _ in },
            reportBrowserResult: { resultId, result in reported.append((resultId, result)) },
            refreshSelectedActiveCodexThread: {},
            scheduler: { _, _ in XCTFail("Eval should not schedule delayed reporting") }
        )

        await coordinator.pollOnce()

        XCTAssertEqual(browser.evaluatedScripts, ["answer()"])
        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported[0].resultId, "result-1")
        XCTAssertEqual(reported[0].result, "42")
    }

    func testUnknownActionsAndMissingTargetsAreIgnoredButRefreshStillRuns() async {
        var refreshCount = 0
        let coordinator = AppControlPollingCoordinator(
            pollTerminalActions: { [AgentClient.TerminalAction(text: "ignored", id: "missing")] },
            pollBrowserActions: {
                [
                    AgentClient.BrowserAction(type: "navigate", url: nil, script: nil, id: "missing", resultId: nil),
                    AgentClient.BrowserAction(type: "unknown", url: nil, script: nil, id: nil, resultId: nil),
                ]
            },
            terminal: { _ in nil },
            browser: { _ in nil },
            reportTerminalOutput: { _, _ in XCTFail("Missing terminal should not report") },
            reportBrowserState: { _, _, _ in XCTFail("Missing browser should not report state") },
            reportBrowserResult: { _, _ in XCTFail("Missing browser should not report result") },
            refreshSelectedActiveCodexThread: { refreshCount += 1 },
            scheduler: { _, _ in XCTFail("Missing targets should not schedule") }
        )

        await coordinator.pollOnce()

        XCTAssertEqual(refreshCount, 1)
    }
}

private final class FakeControlTerminal: ControlTerminalPanelRepresenting {
    let panelId: String
    private let output: String
    private(set) var writes: [String] = []

    init(id: String, output: String = "") {
        panelId = id
        self.output = output
    }

    func write(_ text: String) {
        writes.append(text)
    }

    func readBuffer(last: Int) -> String {
        String(output.suffix(last))
    }
}

private final class FakeControlBrowser: ControlBrowserPanelRepresenting {
    let panelId: String
    var currentURL: String
    private let title: String
    private let evalResult: String
    private(set) var loadedURLs: [String] = []
    private(set) var evaluatedScripts: [String] = []

    init(id: String, currentURL: String = "", title: String = "", evalResult: String = "") {
        panelId = id
        self.currentURL = currentURL
        self.title = title
        self.evalResult = evalResult
    }

    func load(_ url: String) {
        loadedURLs.append(url)
    }

    func evaluateJS(_ script: String) async -> String {
        evaluatedScripts.append(script)
        return evalResult
    }

    func pageTitle() -> String {
        title
    }
}
