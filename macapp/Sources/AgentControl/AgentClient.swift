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

    func quota() async throws -> Quota {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("quota"))
        return try JSONDecoder().decode(Quota.self, from: data)
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
