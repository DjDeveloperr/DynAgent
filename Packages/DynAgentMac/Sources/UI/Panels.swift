import AppKit
import WebKit
import SwiftTerm

enum PanelKind { case browser, shell }

// MARK: - Panel Registry (agent-addressable panels)

/// Global registry so the server can control panels by ID.
final class PanelRegistry {
    static let shared = PanelRegistry()
    private var terminals: [String: TerminalPanel] = [:]
    private var browsers: [String: BrowserPanel] = [:]

    func register(terminal: TerminalPanel, id: String) { terminals[id] = terminal }
    func register(browser: BrowserPanel, id: String) { browsers[id] = browser }
    func unregisterTerminal(_ id: String) { terminals.removeValue(forKey: id) }
    func unregisterBrowser(_ id: String) { browsers.removeValue(forKey: id) }
    func removeAll() {
        terminals.removeAll()
        browsers.removeAll()
    }

    func terminal(_ id: String? = nil) -> TerminalPanel? {
        if let id { return terminals[id] }
        return terminals.values.first
    }
    func browser(_ id: String? = nil) -> BrowserPanel? {
        if let id { return browsers[id] }
        return browsers.values.first
    }
    var terminalIDs: [String] { Array(terminals.keys) }
    var browserIDs: [String] { Array(browsers.keys) }
}

// MARK: - Tile Panel (header + content)

private struct SplitSpec { let sideBySide: Bool; let kind: PanelKind }

final class TilePanel: NSView {
    let content: NSView
    var splitHandler: ((TilePanel, Bool, PanelKind) -> Void)?
    var closeHandler: ((TilePanel) -> Void)?

    init(title: String, content: NSView, closable: Bool, showsHeader: Bool = true) {
        self.content = content
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        let add = iconButton("plus", #selector(showAddMenu(_:)))
        let close = iconButton("xmark", #selector(doClose))
        close.isHidden = !closable
        let header = NSStackView(views: [titleLabel, NSView(), add, close] as [NSView])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.clear.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        if showsHeader {
            addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: topAnchor),
                header.leadingAnchor.constraint(equalTo: leadingAnchor),
                header.trailingAnchor.constraint(equalTo: trailingAnchor),
                header.heightAnchor.constraint(equalToConstant: 26),
                content.topAnchor.constraint(equalTo: header.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func iconButton(_ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: self, action: action)
        b.isBordered = false
        b.imageScaling = .scaleProportionallyDown
        return b
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        let m = NSMenu()
        let specs: [(String, SplitSpec)] = [
            ("Browser  →", .init(sideBySide: true, kind: .browser)),
            ("Browser  ↓", .init(sideBySide: false, kind: .browser)),
            ("Terminal  →", .init(sideBySide: true, kind: .shell)),
            ("Terminal  ↓", .init(sideBySide: false, kind: .shell)),
        ]
        for (t, spec) in specs {
            let it = NSMenuItem(title: t, action: #selector(addItem(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = spec
            m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
    @objc private func addItem(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? SplitSpec else { return }
        splitHandler?(self, s.sideBySide, s.kind)
    }
    @objc private func doClose() { closeHandler?(self) }
}

// MARK: - Workspace Area (tiling container)

final class WorkspaceAreaViewController: NSViewController {
    var cwdProvider: () -> String = { FileManager.default.currentDirectoryPath }
    private let root = NSSplitView()
    private var primaryContent: NSView?
    private var primaryTitle = "Chat"

    override func loadView() {
        root.isVertical = true
        root.dividerStyle = .thin
        root.translatesAutoresizingMaskIntoConstraints = false
        let v = NSView()
        v.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor),
            root.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        view = v
    }

    func setPrimary(_ content: NSView, title: String) {
        primaryContent = content; primaryTitle = title
        root.addArrangedSubview(makePanel(title: title, content: content, closable: false, showsHeader: false))
    }

    /// Tear down all browser/terminal panels, leaving only the primary chat. Used to isolate panels per chat.
    func resetPanels() {
        root.arrangedSubviews.forEach { teardown($0) }
        root.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let c = primaryContent {
            c.removeFromSuperview()
            root.addArrangedSubview(makePanel(title: primaryTitle, content: c, closable: false, showsHeader: false))
        }
    }

    private func teardown(_ v: NSView) {
        if let p = v as? TilePanel {
            if let t = p.content as? TerminalPanel { PanelRegistry.shared.unregisterTerminal(t.panelId) }
            if let b = p.content as? BrowserPanel { PanelRegistry.shared.unregisterBrowser(b.panelId) }
        } else if let s = v as? NSSplitView {
            s.arrangedSubviews.forEach { teardown($0) }
        }
    }

    private func makePanel(title: String, content: NSView, closable: Bool, showsHeader: Bool = true) -> TilePanel {
        let p = TilePanel(title: title, content: content, closable: closable, showsHeader: showsHeader)
        // NOTE: arranged subviews of an NSSplitView must stay frame-managed (autoresizing),
        // otherwise the divider snaps back to the intrinsic/min width on every layout pass.
        p.splitHandler = { [weak self] panel, side, kind in self?.split(panel, sideBySide: side, kind: kind) }
        p.closeHandler = { [weak self] panel in self?.close(panel) }
        return p
    }

    private func makeContent(_ kind: PanelKind) -> (NSView, String) {
        switch kind {
        case .browser: return (BrowserPanel(), "Browser")
        case .shell: return (TerminalPanel(cwd: cwdProvider()), "Terminal")
        }
    }

    private func split(_ panel: TilePanel, sideBySide: Bool, kind: PanelKind) {
        guard let parent = panel.superview as? NSSplitView,
              let idx = parent.arrangedSubviews.firstIndex(of: panel) else { return }
        let (c, title) = makeContent(kind)
        let newPanel = makePanel(title: title, content: c, closable: true)
        let split = NSSplitView()
        split.isVertical = sideBySide
        split.dividerStyle = .thin
        parent.insertArrangedSubview(split, at: idx)
        panel.removeFromSuperview()
        split.addArrangedSubview(panel)
        split.addArrangedSubview(newPanel)
        DispatchQueue.main.async {
            split.setPosition((sideBySide ? split.bounds.width : split.bounds.height) / 2, ofDividerAt: 0)
        }
    }

    private func close(_ panel: TilePanel) {
        guard let parent = panel.superview as? NSSplitView else { return }
        // Unregister from panel registry
        if let term = panel.content as? TerminalPanel { PanelRegistry.shared.unregisterTerminal(term.panelId) }
        if let brow = panel.content as? BrowserPanel { PanelRegistry.shared.unregisterBrowser(brow.panelId) }
        panel.removeFromSuperview()
        if parent.arrangedSubviews.count == 1, let only = parent.arrangedSubviews.first,
           let gp = parent.superview as? NSSplitView, let gi = gp.arrangedSubviews.firstIndex(of: parent) {
            only.removeFromSuperview()
            gp.insertArrangedSubview(only, at: gi)
            parent.removeFromSuperview()
        }
    }
}

// MARK: - Terminal Panel (real PTY via SwiftTerm)

/// Subclass to intercept data from the PTY for agent readback.
final class CaptureTerminalView: LocalProcessTerminalView {
    var onData: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onData?(slice)
    }
}

final class TerminalPanel: NSView, LocalProcessTerminalViewDelegate {
    let panelId = UUID().uuidString
    private let termView: CaptureTerminalView
    private let cwd: String
    private var outputBuffer = ""
    private let bufferLimit = 64_000

    init(cwd: String) {
        self.cwd = cwd
        self.termView = CaptureTerminalView(frame: .zero)
        super.init(frame: .zero)

        termView.translatesAutoresizingMaskIntoConstraints = false
        termView.processDelegate = self
        // Match the system text colors so the terminal looks native (light/dark aware).
        termView.nativeBackgroundColor = .textBackgroundColor
        termView.nativeForegroundColor = .textColor
        termView.onData = { [weak self] slice in
            let str = String(bytes: slice, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.outputBuffer += str
                if self.outputBuffer.count > self.bufferLimit {
                    self.outputBuffer = String(self.outputBuffer.suffix(self.bufferLimit))
                }
            }
        }
        addSubview(termView)
        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: topAnchor),
            termView.leadingAnchor.constraint(equalTo: leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: trailingAnchor),
            termView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        termView.startProcess(executable: shell, args: [], environment: nil, execName: nil)

        // cd to workspace
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.write("cd \(cwd)\n")
        }

        PanelRegistry.shared.register(terminal: self, id: panelId)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { PanelRegistry.shared.unregisterTerminal(panelId) }

    // MARK: Agent control API

    func write(_ text: String) { termView.send(txt: text) }

    func readBuffer(last: Int = 4000) -> String {
        if outputBuffer.count <= last { return outputBuffer }
        return String(outputBuffer.suffix(last))
    }

    func clearBuffer() { outputBuffer = "" }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.outputBuffer += "\n[process exited: \(exitCode ?? -1)]"
        }
    }
}

// MARK: - Browser Panel (WKWebView, agent-controllable)

final class BrowserPanel: NSView, WKNavigationDelegate {
    let panelId = UUID().uuidString
    let web = WKWebView()
    private let urlField = NSTextField()
    var currentURL: String = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        urlField.placeholderString = "Enter a URL…"
        urlField.target = self
        urlField.action = #selector(go)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlField)
        addSubview(web)
        NSLayoutConstraint.activate([
            urlField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            urlField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            urlField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            web.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 6),
            web.leadingAnchor.constraint(equalTo: leadingAnchor),
            web.trailingAnchor.constraint(equalTo: trailingAnchor),
            web.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        PanelRegistry.shared.register(browser: self, id: panelId)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { PanelRegistry.shared.unregisterBrowser(panelId) }

    @objc private func go() { load(urlField.stringValue) }

    func load(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return }
        if !t.contains("://") { t = "https://" + t }
        urlField.stringValue = t
        currentURL = t
        if let u = URL(string: t) { web.load(URLRequest(url: u)) }
    }

    /// Execute JavaScript and return the result as a string.
    func evaluateJS(_ script: String) async -> String {
        do {
            let result = try await web.evaluateJavaScript(script)
            return "\(result ?? "undefined")"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// Get the page title.
    func pageTitle() -> String { web.title ?? "" }

    // WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            self?.currentURL = webView.url?.absoluteString ?? ""
            self?.urlField.stringValue = self?.currentURL ?? ""
        }
    }
}
