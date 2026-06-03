import Foundation

protocol ControlTerminalPanelRepresenting: AnyObject {
    var panelId: String { get }
    func write(_ text: String)
    func readBuffer(last: Int) -> String
}

protocol ControlBrowserPanelRepresenting: AnyObject {
    var panelId: String { get }
    var currentURL: String { get }
    func load(_ url: String)
    func evaluateJS(_ script: String) async -> String
    func pageTitle() -> String
}

extension TerminalPanel: ControlTerminalPanelRepresenting {}
extension BrowserPanel: ControlBrowserPanelRepresenting {}

final class AppControlPollingCoordinator {
    typealias TerminalAction = AgentClient.TerminalAction
    typealias BrowserAction = AgentClient.BrowserAction
    typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> Void

    private let pollTerminalActions: () async -> [TerminalAction]
    private let pollBrowserActions: () async -> [BrowserAction]
    private let terminal: (String?) -> (any ControlTerminalPanelRepresenting)?
    private let browser: (String?) -> (any ControlBrowserPanelRepresenting)?
    private let reportTerminalOutput: (String, String) async -> Void
    private let reportBrowserState: (String, String, String) async -> Void
    private let reportBrowserResult: (String, String) async -> Void
    private let refreshSelectedActiveCodexThread: () -> Void
    private let scheduler: Scheduler
    private var timer: Timer?

    init(
        pollTerminalActions: @escaping () async -> [TerminalAction],
        pollBrowserActions: @escaping () async -> [BrowserAction],
        terminal: @escaping (String?) -> (any ControlTerminalPanelRepresenting)?,
        browser: @escaping (String?) -> (any ControlBrowserPanelRepresenting)?,
        reportTerminalOutput: @escaping (String, String) async -> Void,
        reportBrowserState: @escaping (String, String, String) async -> Void,
        reportBrowserResult: @escaping (String, String) async -> Void,
        refreshSelectedActiveCodexThread: @escaping () -> Void,
        scheduler: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                action()
            }
        }
    ) {
        self.pollTerminalActions = pollTerminalActions
        self.pollBrowserActions = pollBrowserActions
        self.terminal = terminal
        self.browser = browser
        self.reportTerminalOutput = reportTerminalOutput
        self.reportBrowserState = reportBrowserState
        self.reportBrowserResult = reportBrowserResult
        self.refreshSelectedActiveCodexThread = refreshSelectedActiveCodexThread
        self.scheduler = scheduler
    }

    convenience init(
        client: AgentClient,
        registry: PanelRegistry = .shared,
        refreshSelectedActiveCodexThread: @escaping () -> Void
    ) {
        self.init(
            pollTerminalActions: { await client.pollTerminalActions() },
            pollBrowserActions: { await client.pollBrowserActions() },
            terminal: { registry.terminal($0) },
            browser: { registry.browser($0) },
            reportTerminalOutput: { id, output in await client.reportTerminalOutput(id: id, output: output) },
            reportBrowserState: { id, url, title in await client.reportBrowserState(id: id, url: url, title: title) },
            reportBrowserResult: { resultId, result in await client.reportBrowserResult(resultId: resultId, result: result) },
            refreshSelectedActiveCodexThread: refreshSelectedActiveCodexThread
        )
    }

    func start(interval: TimeInterval = 0.3) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollOnce()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollOnce() async {
        await processTerminalActions()
        await processBrowserActions()
        refreshSelectedActiveCodexThread()
    }

    private func processTerminalActions() async {
        let actions = await pollTerminalActions()
        for action in actions {
            guard let terminal = terminal(action.id) else { continue }
            terminal.write(action.text)
            let termId = action.id ?? terminal.panelId
            scheduler(0.4) { [weak terminal, reportTerminalOutput] in
                guard let terminal else { return }
                let output = terminal.readBuffer(last: 8000)
                Task { await reportTerminalOutput(termId, output) }
            }
        }
    }

    private func processBrowserActions() async {
        let actions = await pollBrowserActions()
        for action in actions {
            guard let browser = browser(action.id) else { continue }
            switch action.type {
            case "navigate":
                guard let url = action.url else { continue }
                browser.load(url)
                scheduler(1.0) { [weak browser, reportBrowserState] in
                    guard let browser else { return }
                    let id = action.id ?? browser.panelId
                    Task { await reportBrowserState(id, browser.currentURL, browser.pageTitle()) }
                }
            case "eval":
                guard let script = action.script, let resultId = action.resultId else { continue }
                let result = await browser.evaluateJS(script)
                await reportBrowserResult(resultId, result)
            default:
                break
            }
        }
    }
}
