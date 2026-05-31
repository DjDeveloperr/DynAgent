import Foundation

/// Talks to the local TypeScript agent server (see ../../src/server.ts).
final class AgentClient: NSObject, URLSessionDataDelegate {
    struct Model: Decodable { let id: String; let name: String }
    struct Metering: Decodable { let unit: String; let unitPlural: String; let value: Double }
    struct Quota: Decodable {
        let sessionCredits: Double?
        let contextUsagePercentage: Double?
        let metering: [Metering]?
    }
    enum Event { case text(String), tool(String), toolResult(String), done, error(String) }

    let base: URL
    private var buffer = Data()
    private var onEvent: ((Event) -> Void)?
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

    struct Cwd: Decodable { let cwd: String; let name: String }
    func cwd() async throws -> Cwd {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("cwd"))
        return try JSONDecoder().decode(Cwd.self, from: data)
    }

    struct GitFile: Decodable { let x: String; let path: String }
    struct GitStatus: Decodable { let branch: String?; let files: [GitFile]?; let diff: String?; let error: String? }
    func gitStatus(_ workspace: String) async throws -> GitStatus {
        var c = URLComponents(url: base.appendingPathComponent("git"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "cwd", value: workspace)]
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
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
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
    func chat(model: String, conversationId: String, cwd: String, messages: [[String: String]],
              onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        buffer.removeAll()
        var req = URLRequest(url: base.appendingPathComponent("chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "conversationId": conversationId, "cwd": cwd, "messages": messages,
        ])
        session.dataTask(with: req).resume()
    }

    /// Stream through Codex harness (OpenAI-compatible, translated by server).
    func codexChat(model: String, messages: [[String: String]], onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        buffer.removeAll()
        var req = URLRequest(url: base.appendingPathComponent("codex/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let msgs = messages.map { ["role": $0["role"] ?? "user", "content": $0["content"] ?? ""] }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs])
        session.dataTask(with: req).resume()
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
        buffer.append(data)
        while let r = buffer.range(of: Data("\n\n".utf8)) {
            let line = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<r.upperBound)
            guard let s = String(data: line, encoding: .utf8) else { continue }
            for raw in s.split(separator: "\n") where raw.hasPrefix("data:") {
                let payload = raw.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let d = payload.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let type = obj["type"] as? String else { continue }
                let event: Event
                switch type {
                case "text": event = .text(obj["text"] as? String ?? "")
                case "tool": event = .tool(obj["name"] as? String ?? "?")
                case "tool-result": event = .toolResult(obj["name"] as? String ?? "?")
                case "error": event = .error(obj["error"] as? String ?? "error")
                default: event = .done
                }
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
            }
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error { self?.onEvent?(.error(error.localizedDescription)) }
        }
    }
}
