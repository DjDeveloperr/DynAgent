import AppKit
import Darwin
import Foundation

private typealias AttachFunction = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias AttachWithStateFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias DetachFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void

private struct LoadedUI {
    let handle: UnsafeMutableRawPointer
    let controller: UnsafeMutableRawPointer
    let detach: DetachFunction
    let copiedDylib: URL
}

private final class HotReloadLoader {
    private let window: NSWindow
    private let packageDirectory: URL
    private let hotState = NSMutableDictionary()
    private var current: LoadedUI?
    private var isReloading = false

    init(window: NSWindow) {
        self.window = window
        self.packageDirectory = Self.findPackageDirectory()
    }

    func reload(reason: String) {
        guard !isReloading else { return }
        isReloading = true
        NSLog("DynAgent hot reload requested: \(reason)")

        if current == nil {
            showHostMessage(title: "Building DynAgent UI", detail: "Preparing the reloadable interface...")
        }

        let packageDirectory = self.packageDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.buildAndCopyDylib(packageDirectory: packageDirectory) }
            DispatchQueue.main.async {
                self.isReloading = false
                switch result {
                case .success(let dylib):
                    self.load(dylib: dylib, reason: reason)
                case .failure(let error):
                    self.handleFailure(error, title: "DynAgent UI Build Failed")
                }
            }
        }
    }

    func unload() {
        guard let loaded = current else { return }
        current = nil
        loaded.detach(loaded.controller)
        dlclose(loaded.handle)
        try? FileManager.default.removeItem(at: loaded.copiedDylib)
    }

    private func load(dylib: URL, reason: String) {
        let preservedFrame = window.frame
        guard let handle = dlopen(dylib.path, RTLD_NOW | RTLD_LOCAL) else {
            handleFailure(HotReloadError.load(dlerrorMessage()), title: "DynAgent UI Load Failed")
            try? FileManager.default.removeItem(at: dylib)
            return
        }
        guard let attachSymbol = dlsym(handle, "dynagent_attach"),
              let detachSymbol = dlsym(handle, "dynagent_detach") else {
            let message = dlerrorMessage()
            dlclose(handle)
            try? FileManager.default.removeItem(at: dylib)
            handleFailure(HotReloadError.symbol(message), title: "DynAgent UI Load Failed")
            return
        }

        let attach = unsafeBitCast(attachSymbol, to: AttachFunction.self)
        let attachWithState = dlsym(handle, "dynagent_attach_with_state").map {
            unsafeBitCast($0, to: AttachWithStateFunction.self)
        }
        let detach = unsafeBitCast(detachSymbol, to: DetachFunction.self)

        let previous = current
        if let previous {
            current = nil
            previous.detach(previous.controller)
            dlclose(previous.handle)
            try? FileManager.default.removeItem(at: previous.copiedDylib)
        }

        let controllerPointer = attachWithState?(
            Unmanaged.passUnretained(window).toOpaque(),
            Unmanaged.passUnretained(hotState).toOpaque()
        ) ?? attach(Unmanaged.passUnretained(window).toOpaque())

        guard let controller = controllerPointer else {
            dlclose(handle)
            try? FileManager.default.removeItem(at: dylib)
            handleFailure(HotReloadError.attach, title: "DynAgent UI Attach Failed")
            return
        }

        current = LoadedUI(handle: handle, controller: controller, detach: detach, copiedDylib: dylib)
        restoreUsableFrame(from: preservedFrame)
        window.subtitle = ""
        NSLog("DynAgent hot reload attached: \(dylib.path)")
    }

    private func restoreUsableFrame(from preservedFrame: NSRect) {
        window.styleMask.insert(.resizable)
        window.minSize = NSSize(width: 820, height: 480)
        window.maxSize = NSSize(width: 20_000, height: 20_000)
        window.contentMinSize = NSSize(width: 820, height: 480)
        window.contentMaxSize = NSSize(width: 20_000, height: 20_000)

        var frame = preservedFrame
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 900)
        let targetWidth = min(visible.width - 16, max(1240, visible.width * 0.96))
        if frame.width < targetWidth {
            frame.size.width = targetWidth
            frame.origin.x = visible.midX - targetWidth / 2
        }
        if frame.height < 720 { frame.size.height = 720 }
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
    }

    private func handleFailure(_ error: Error, title: String) {
        if current == nil {
            showHostMessage(title: title, detail: String(describing: error))
            HostDelegate.installHostMenu()
        } else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = String(describing: error)
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
        }
    }

    private func showHostMessage(title: String, detail: String) {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.alignment = .center

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -40),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
        ])

        let controller = NSViewController()
        controller.view = root
        window.contentViewController = controller
    }

    private static func buildAndCopyDylib(packageDirectory: URL) throws -> URL {
        _ = try runSwift(["build", "--disable-sandbox", "--product", "DynAgentUI"], in: packageDirectory)
        let binPath = try runSwift(["build", "--disable-sandbox", "--show-bin-path"], in: packageDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let builtDylib = URL(fileURLWithPath: binPath).appendingPathComponent("libDynAgentUI.dylib")
        guard FileManager.default.fileExists(atPath: builtDylib.path) else {
            throw HotReloadError.missingDylib(builtDylib.path)
        }

        let reloadDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynAgentHotReload", isDirectory: true)
        try FileManager.default.createDirectory(at: reloadDir, withIntermediateDirectories: true)
        let copy = reloadDir.appendingPathComponent("libDynAgentUI-\(UUID().uuidString).dylib")
        try FileManager.default.copyItem(at: builtDylib, to: copy)
        _ = try runTool("/usr/bin/install_name_tool", ["-id", copy.path, copy.path], in: packageDirectory)
        _ = try? runTool("/usr/bin/codesign", ["--force", "--sign", "-", copy.path], in: packageDirectory)
        return copy
    }

    private static func runSwift(_ arguments: [String], in directory: URL) throws -> String {
        try runTool("/usr/bin/swift", arguments, in: directory)
    }

    private static func runTool(_ executable: String, _ arguments: [String], in directory: URL) throws -> String {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("dynagent-tool-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let file = try FileHandle(forWritingTo: output)
        defer {
            try? file.close()
            try? FileManager.default.removeItem(at: output)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["CLANG_MODULE_CACHE_PATH"] = "/private/tmp/dynagent-clang-cache"
        process.environment = environment
        process.standardOutput = file
        process.standardError = file
        try process.run()
        process.waitUntilExit()

        let data = (try? Data(contentsOf: output)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let command = ([executable] + arguments).joined(separator: " ")
            throw HotReloadError.process(command, text)
        }
        return text
    }

    private static func findPackageDirectory() -> URL {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["DYNAGENT_PACKAGE_DIR"],
           fileManager.fileExists(atPath: URL(fileURLWithPath: override).appendingPathComponent("Package.swift").path) {
            return URL(fileURLWithPath: override)
        }

        var candidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            Bundle.main.bundleURL,
            Bundle.main.executableURL ?? Bundle.main.bundleURL,
        ]

        while let candidate = candidates.first {
            candidates.removeFirst()
            var url = candidate.hasDirectoryPath ? candidate : candidate.deletingLastPathComponent()
            while url.path != "/" {
                if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                    return url
                }
                url.deleteLastPathComponent()
            }
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }
}

private enum HotReloadError: Error, CustomStringConvertible {
    case process(String, String)
    case missingDylib(String)
    case load(String)
    case symbol(String)
    case attach

    var description: String {
        switch self {
        case .process(let command, let output):
            return "\(command) failed:\n\(output)"
        case .missingDylib(let path):
            return "Expected dynamic library was not found at \(path)."
        case .load(let message):
            return "dlopen failed: \(message)"
        case .symbol(let message):
            return "Required reload symbols were not found: \(message)"
        case .attach:
            return "dynagent_attach returned nil."
        }
    }
}

private final class HostDelegate: NSObject, NSApplicationDelegate {
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    private var loader: HotReloadLoader?
    private var eventMonitor: Any?
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("DynAgent keeps its hot-reload host alive")
        configureWindow()
        Self.installHostMenu()

        let loader = HotReloadLoader(window: window)
        self.loader = loader
        installReloadMonitor()
        installReloadSignal()

        setWideInitialFrame()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loader.reload(reason: "Loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        signalSource?.cancel()
        loader?.unload()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Recent Threads")
        let recent = readRecentDockThreads()
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No Recent Threads", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in recent.prefix(10) {
                let title = item.title.isEmpty ? "New Chat" : item.title
                let menuItem = NSMenuItem(title: title, action: #selector(openDockThread(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item.id
                menu.addItem(menuItem)
            }
        }
        menu.addItem(.separator())
        let reload = NSMenuItem(title: "Reload UI", action: #selector(dynagentReloadUI(_:)), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        return menu
    }

    @objc private func openDockThread(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        showMainWindow()
        NotificationCenter.default.post(name: Notification.Name("DynAgentOpenConversation"), object: id)
    }

    private func showMainWindow() {
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func dynagentReloadUI(_ sender: Any?) {
        loader?.reload(reason: "Reloaded \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))")
    }

    private func configureWindow() {
        window.title = "DynAgent"
        window.styleMask.insert(.resizable)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 820, height: 480)
        window.maxSize = NSSize(width: 20_000, height: 20_000)
        window.contentMinSize = NSSize(width: 820, height: 480)
        window.contentMaxSize = NSSize(width: 20_000, height: 20_000)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private func setWideInitialFrame() {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 900)
        let targetWidth = min(visible.width - 16, max(1240, visible.width * 0.96))
        let targetHeight = min(visible.height - 24, max(720, visible.height * 0.84))
        let frame = NSRect(
            x: visible.midX - targetWidth / 2,
            y: visible.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        window.setFrame(frame, display: true)
    }

    private func installReloadMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "r" {
                self?.dynagentReloadUI(nil)
                return nil
            }
            return event
        }
    }

    private func installReloadSignal() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            self?.dynagentReloadUI(nil)
        }
        source.resume()
        signalSource = source
    }

    static func installHostMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "DynAgent")
        appMenu.addItem(NSMenuItem(title: "Hide DynAgent", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit DynAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Reload UI", action: #selector(HostDelegate.dynagentReloadUI(_:)), keyEquivalent: "r"))
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        NSApp.mainMenu = main
    }
}

private struct DockThread {
    let id: String
    let title: String
}

private func readRecentDockThreads() -> [DockThread] {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dynagent")
        .appendingPathComponent("dock-recent.json")
    guard let data = try? Data(contentsOf: url),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return raw.compactMap { item in
        guard let id = item["id"] as? String else { return nil }
        return DockThread(id: id, title: item["title"] as? String ?? "New Chat")
    }
}

private func dlerrorMessage() -> String {
    guard let message = dlerror() else { return "unknown dynamic loader error" }
    return String(cString: message)
}

let app = NSApplication.shared
private let delegate = HostDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
