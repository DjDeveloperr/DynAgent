import Foundation

enum Role: String, Codable { case user, assistant, tool }

/// One rendered item in a conversation transcript.
final class ChatMessage: Codable {
    let role: Role
    var text: String
    var toolName: String?
    var toolDone = false
    init(role: Role, text: String = "", toolName: String? = nil) {
        self.role = role
        self.text = text
        self.toolName = toolName
    }
}

/// A single agent conversation with its own history, model, and live status.
final class Conversation: Codable {
    enum Status { case idle, thinking, running, error }

    var id = UUID().uuidString
    var title = "New Chat"
    var model: String
    var workspace = ""
    var messages: [ChatMessage] = []
    var status: Status = .idle

    init(model: String, workspace: String = "") { self.model = model; self.workspace = workspace }

    enum CodingKeys: String, CodingKey { case id, title, model, workspace, messages }

    /// User/assistant text turns for the server (tool rows are server-side detail).
    var history: [[String: String]] {
        messages.compactMap { m in
            guard !m.text.isEmpty, m.role == .user || m.role == .assistant else { return nil }
            return ["role": m.role == .user ? "user" : "assistant", "content": m.text]
        }
    }
}

/// A named group of conversations rooted at a working directory.
final class Workspace {
    let name: String
    let path: String
    var conversations: [Conversation]
    init(name: String, path: String, conversations: [Conversation]) {
        self.name = name; self.path = path; self.conversations = conversations
    }
}

/// Persisted workspace reference (path + display name).
struct WorkspaceRef: Codable, Equatable { var name: String; var path: String }

/// Persists conversations and workspaces under ~/.dynagent.
enum Store {
    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
    private static let sessions = dir.appendingPathComponent("sessions.json")
    private static let workspaces = dir.appendingPathComponent("workspaces.json")

    static func load() -> [Conversation] {
        (try? JSONDecoder().decode([Conversation].self, from: Data(contentsOf: sessions))) ?? []
    }
    static func save(_ conversations: [Conversation]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(conversations).write(to: sessions)
    }
    static func loadWorkspaces() -> [WorkspaceRef] {
        (try? JSONDecoder().decode([WorkspaceRef].self, from: Data(contentsOf: workspaces))) ?? []
    }
    static func saveWorkspaces(_ refs: [WorkspaceRef]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(refs).write(to: workspaces)
    }
}

