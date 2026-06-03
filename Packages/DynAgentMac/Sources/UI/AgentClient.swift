import Foundation

/// Talks to the local TypeScript agent server (see ../../src/server.ts).
final class AgentClient: NSObject, URLSessionDataDelegate {
    enum ClientError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self {
            case .server(let message): return message
            }
        }
    }

    struct Model: Decodable { let id: String; let name: String }
    struct Metering: Decodable { let unit: String; let unitPlural: String; let value: Double }
    struct Quota: Decodable {
        let sessionCredits: Double?
        let contextUsagePercentage: Double?
        let metering: [Metering]?
    }
    enum Event { case thread(String), text(String), steer, tool(String, String?), toolResult(String, String?), done, error(String) }

    let base: URL
    private struct StreamState {
        var buffer = Data()
        let onEvent: (Event) -> Void
    }
    private let streamLock = NSLock()
    private var streams: [Int: StreamState] = [:]
    private weak var lastTask: URLSessionDataTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(base: URL = URL(string: "http://127.0.0.1:4319")!) { self.base = base }

    func models() async throws -> [Model] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("models"))
        return try JSONDecoder().decode([Model].self, from: data)
    }

    func codexModels() async throws -> [Model] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("codex/models"))
        return try JSONDecoder().decode([Model].self, from: data)
    }

    func piModels() async throws -> [Model] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("pi/models"))
        return try JSONDecoder().decode([Model].self, from: data)
    }

    /// Stream a turn through the Pi CLI harness (session keyed by conversation id).
    @discardableResult
    func piChat(model: String, text: String, cwd: String, sessionId: String, onEvent: @escaping (Event) -> Void) -> URLSessionDataTask {
        var req = URLRequest(url: base.appendingPathComponent("pi/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "text": text, "cwd": cwd, "sessionId": sessionId])
        return startStream(req, onEvent: onEvent)
    }

    struct Worktree: Decodable { let path: String; let branch: String }
    /// Detect existing git worktrees for a repo.
    func worktrees(cwd: String) async -> [Worktree] {
        var c = URLComponents(url: base.appendingPathComponent("worktrees"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "cwd", value: cwd)]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!) else { return [] }
        return (try? JSONDecoder().decode([Worktree].self, from: data)) ?? []
    }

    struct CodexThread: Decodable {
        let id: String
        let title: String
        let preview: String
        let updatedAt: Double
        let pinned: Bool?
        let projectless: Bool?
        let workspace: String?
    }
    /// List Codex's existing threads for a workspace directory.
    func codexThreads(cwd: String? = nil) async throws -> [CodexThread] {
        var c = URLComponents(url: base.appendingPathComponent("codex/threads"), resolvingAgainstBaseURL: false)!
        if let cwd { c.queryItems = [.init(name: "cwd", value: cwd)] }
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return (try? JSONDecoder().decode([CodexThread].self, from: data)) ?? []
    }

    struct CodexWorkspace: Decodable { let name: String; let path: String; let source: String }
    /// Workspaces from Codex Desktop's ~/.codex state.
    func codexWorkspaces() async throws -> [CodexWorkspace] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("codex/workspaces"))
        return (try? JSONDecoder().decode([CodexWorkspace].self, from: data)) ?? []
    }

    struct CodexSidebarState: Decodable {
        let collapsedGroups: [String: Bool]
        let collapsedSections: [String: Bool]
        let sidebarWidth: Double?
    }

    /// Sidebar state mirrored from Codex Desktop's ~/.codex state.
    func codexSidebarState() async throws -> CodexSidebarState {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("codex/sidebar"))
        return try JSONDecoder().decode(CodexSidebarState.self, from: data)
    }

    func codexSetSidebarState(_ body: [String: Any]) async {
        _ = try? await postJSON("codex/sidebar", body)
    }

    struct HistMsg: Decodable {
        let role: String
        let content: String
        let toolName: String?
        let toolDetail: String?
        let toolDone: Bool?
        let timestamp: Double?
        let turnDuration: Double?
        let turnStartedAt: Double?
        let turnStatus: String?
        let isFinal: Bool?
        let isSteer: Bool?
    }
    /// Read a Codex thread's message history.
    func codexThread(id: String) async throws -> [HistMsg] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("codex/thread/\(id)"))
        return (try? JSONDecoder().decode([HistMsg].self, from: data)) ?? []
    }

    func codexArchive(threadId: String) async throws {
        _ = try await postJSON("codex/archive", ["threadId": threadId])
    }

    func codexRename(threadId: String, name: String) async throws {
        _ = try await postJSON("codex/rename", ["threadId": threadId, "name": name])
    }

    func codexPin(threadId: String, pinned: Bool) async throws {
        _ = try await postJSON("codex/pin", ["threadId": threadId, "pinned": pinned])
    }

    struct Cwd: Decodable { let cwd: String; let name: String }
    func cwd() async throws -> Cwd {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("cwd"))
        return try JSONDecoder().decode(Cwd.self, from: data)
    }

    struct GitFile: Decodable { let x: String; let path: String }
    struct GitStatus: Decodable { let branch: String?; let files: [GitFile]?; let diff: String?; let error: String? }
    func gitStatus(_ workspace: String, staged: Bool = false) async throws -> GitStatus {
        var c = URLComponents(url: base.appendingPathComponent("git"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "cwd", value: workspace),
            .init(name: "scope", value: staged ? "staged" : "all"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(GitStatus.self, from: data)
    }

    @discardableResult
    func post(_ path: String, _ body: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @discardableResult
    func postJSON(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60 // auto-gen commit message can take time
        let (data, response) = try await URLSession.shared.data(for: req)
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ClientError.server(Self.errorMessage(from: object) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        if let message = Self.errorMessage(from: object) {
            throw ClientError.server(message)
        }
        return object
    }

    private static func errorMessage(from object: [String: Any]) -> String? {
        if let message = object["error"] as? String, !message.isEmpty { return message }
        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty { return message }
        }
        return nil
    }

    struct PRInfo: Decodable {
        let number: Int?; let title: String?; let state: String?; let url: String?
        let headRefName: String?; let additions: Int?; let deletions: Int?; let reviewDecision: String?
        let none: Bool?
    }
    func prInfo(_ workspace: String) async throws -> PRInfo {
        var c = URLComponents(url: base.appendingPathComponent("git/pr-info"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "cwd", value: workspace)]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(PRInfo.self, from: data)
    }

    struct TitleResponse: Decodable { let title: String }
    func generateTitle(prompt: String, model: String) async -> String {
        var req = URLRequest(url: base.appendingPathComponent("generate-title"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": prompt, "model": model])
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let r = try? JSONDecoder().decode(TitleResponse.self, from: data) else { return "New Chat" }
        return r.title
    }

    func quota() async throws -> Quota {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("quota"))
        return try JSONDecoder().decode(Quota.self, from: data)
    }

    struct Credits: Decodable { let used: Double; let limit: Double; let plan: String; let daysUntilReset: Int }
    func credits() async throws -> Credits {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("credits"))
        return try JSONDecoder().decode(Credits.self, from: data)
    }

    /// Stream a chat turn over the full history. Events arrive on the main queue.
    @discardableResult
    func chat(model: String, conversationId: String, cwd: String, messages: [[String: String]],
              onEvent: @escaping (Event) -> Void) -> URLSessionDataTask {
        var req = URLRequest(url: base.appendingPathComponent("chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "conversationId": conversationId, "cwd": cwd, "messages": messages,
        ])
        return startStream(req, onEvent: onEvent)
    }

    /// Stream a turn through the real Codex app-server (stateful; resumes by threadId).
    @discardableResult
    func codexChat(model: String, text: String, cwd: String, threadId: String?, effort: String,
                   onEvent: @escaping (Event) -> Void) -> URLSessionDataTask {
        var req = URLRequest(url: base.appendingPathComponent("codex/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": model, "text": text, "cwd": cwd, "effort": effort]
        if let threadId { body["threadId"] = threadId }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return startStream(req, onEvent: onEvent)
    }

    /// Cancel the active streaming turn (stop). The server aborts the run / interrupts the Codex turn.
    func cancel() { lastTask?.cancel(); lastTask = nil }
    func cancel(_ task: URLSessionDataTask?) { task?.cancel() }

    @discardableResult
    private func startStream(_ request: URLRequest, onEvent: @escaping (Event) -> Void) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        streamLock.lock()
        streams[task.taskIdentifier] = StreamState(onEvent: onEvent)
        lastTask = task
        streamLock.unlock()
        task.resume()
        return task
    }

    /// Inject a message into a running Codex turn via `turn/steer`.
    func codexSteer(threadId: String, text: String) async throws {
        _ = try await postJSON("codex/steer", ["threadId": threadId, "text": text])
    }

    /// Explicitly stop a running Codex turn. Stream disconnects alone should not stop it.
    func codexCancel(threadId: String) async {
        _ = try? await postJSON("codex/cancel", ["threadId": threadId])
    }

    // MARK: - Terminal/Browser control polling

    struct TerminalAction: Decodable { let text: String; let id: String? }
    struct BrowserAction: Decodable { let type: String; let url: String?; let script: String?; let id: String?; let resultId: String? }

    /// Poll for pending terminal write commands from the agent.
    func pollTerminalActions() async -> [TerminalAction] {
        guard let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("terminal/pending")) else { return [] }
        struct Resp: Decodable { let actions: [TerminalAction] }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.actions ?? []
    }

    /// Poll for pending browser actions from the agent.
    func pollBrowserActions() async -> [BrowserAction] {
        guard let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("browser/pending")) else { return [] }
        struct Resp: Decodable { let actions: [BrowserAction] }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.actions ?? []
    }

    /// Report terminal output back to the server.
    func reportTerminalOutput(id: String, output: String) async {
        var req = URLRequest(url: base.appendingPathComponent("terminal/report"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "output": output])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Report browser eval result back to the server.
    func reportBrowserResult(resultId: String, result: String) async {
        var req = URLRequest(url: base.appendingPathComponent("browser/result"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["resultId": resultId, "result": result])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Report browser state (URL + title) to the server.
    func reportBrowserState(id: String, url: String, title: String) async {
        var req = URLRequest(url: base.appendingPathComponent("browser/report"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "url": url, "title": title])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var events: [(Event, (Event) -> Void)] = []
        streamLock.lock()
        guard var state = streams[dataTask.taskIdentifier] else {
            streamLock.unlock()
            return
        }
        state.buffer.append(data)
        while let r = state.buffer.range(of: Data("\n\n".utf8)) {
            let line = state.buffer.subdata(in: state.buffer.startIndex..<r.lowerBound)
            state.buffer.removeSubrange(state.buffer.startIndex..<r.upperBound)
            guard let s = String(data: line, encoding: .utf8) else { continue }
            for raw in s.split(separator: "\n") where raw.hasPrefix("data:") {
                let payload = raw.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let d = payload.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let type = obj["type"] as? String else { continue }
                let event: Event
                switch type {
                case "thread": event = .thread(obj["id"] as? String ?? "")
                case "text": event = .text(obj["text"] as? String ?? "")
                case "steer": event = .steer
                case "tool": event = .tool(obj["name"] as? String ?? "?", obj["detail"] as? String)
                case "tool-result": event = .toolResult(obj["name"] as? String ?? "?", obj["detail"] as? String)
                case "error": event = .error(obj["error"] as? String ?? "error")
                default: event = .done
                }
                events.append((event, state.onEvent))
            }
        }
        streams[dataTask.taskIdentifier] = state
        streamLock.unlock()
        for (event, callback) in events {
            DispatchQueue.main.async { callback(event) }
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        streamLock.lock()
        let state = streams.removeValue(forKey: task.taskIdentifier)
        streamLock.unlock()
        DispatchQueue.main.async {
            if let error, (error as NSError).code != NSURLErrorCancelled {
                state?.onEvent(.error(error.localizedDescription))
            }
        }
    }
}
