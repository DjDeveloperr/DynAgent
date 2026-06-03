import Foundation

enum Role: String, Codable { case user, assistant, tool }

/// Which backend harness to use.
enum Harness: String, Codable, CaseIterable {
    case dynagent = "DynAgent"
    case codex = "Codex"
    case pi = "Pi"
}

/// One rendered item in a conversation transcript.
final class ChatMessage: Codable {
    let role: Role
    var text: String
    var toolName: String?
    var toolDetail: String?
    var toolDone = false
    /// Epoch seconds when this message completed (assistant messages).
    var timestamp: Double?
    /// For a turn's final assistant message: how long the turn took (seconds).
    var turnDuration: Double?
    /// Codex turn metadata, used to avoid collapsing still-running/incomplete turns.
    var turnStartedAt: Double?
    var turnStatus: String?
    var isFinal: Bool?
    /// User message sent into an already-running turn. Steers render in-place and do not start a new turn.
    var isSteer: Bool?
    init(role: Role, text: String = "", toolName: String? = nil, toolDetail: String? = nil) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolDetail = toolDetail
    }
}

/// A single agent conversation with its own history, model, and live status.
final class Conversation: Codable {
    enum Status: String, Codable { case idle, thinking, running, error }

    var id = UUID().uuidString
    var title = "New Chat"
    var model: String
    var harness: Harness = .dynagent
    var workspace = ""
    var messages: [ChatMessage] = []
    var status: Status = .idle
    /// For Codex harness: the app-server thread id, used to resume the session.
    var codexThreadId: String?
    /// True when this is a Codex thread stub whose history hasn't been loaded yet.
    var needsLoad = false
    /// Last-activity timestamp (epoch seconds) for chronological ordering.
    var updatedAt: Double = Date().timeIntervalSince1970
    /// Messages typed while a turn is streaming, delivered on the next turn (steering). Not persisted.
    var steerQueue: [String] = []
    /// True when there is unseen agent output (shows a blue dot in the sidebar).
    var unread = false
    /// Pinned chats render in a separate sidebar section above projects.
    var pinned = false

    init(model: String, workspace: String = "", harness: Harness = .dynagent) {
        self.model = model; self.workspace = workspace; self.harness = harness
    }

    enum CodingKeys: String, CodingKey { case id, title, model, harness, workspace, messages, status, codexThreadId, needsLoad, updatedAt, unread, pinned }

    /// User/assistant text turns for the server (tool rows are server-side detail).
    var history: [[String: String]] {
        messages.compactMap { m in
            guard !m.text.isEmpty, m.role == .user || m.role == .assistant else { return nil }
            guard m.isSteer != true else { return nil }
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
    #if os(macOS)
    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
    #else
    private static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("DynAgent", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("DynAgent", isDirectory: true)
    #endif
    private static let sessions = dir.appendingPathComponent("sessions.json")
    private static let workspaces = dir.appendingPathComponent("workspaces.json")
    private static let codexStubs = dir.appendingPathComponent("codex-stubs.json")

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
    static func loadCodexStubs() -> [String: [Conversation]] {
        (try? JSONDecoder().decode([String: [Conversation]].self, from: Data(contentsOf: codexStubs))) ?? [:]
    }
    static func saveCodexStubs(_ stubs: [String: [Conversation]]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(stubs).write(to: codexStubs)
    }

    // Last-used harness/model, applied as defaults for new chats.
    static func saveLast(harness: Harness, model: String) {
        UserDefaults.standard.set(harness.rawValue, forKey: "lastHarness")
        UserDefaults.standard.set(model, forKey: "lastModel")
    }
    static var lastHarness: Harness { Harness(rawValue: UserDefaults.standard.string(forKey: "lastHarness") ?? "") ?? .dynagent }
    static var lastModel: String? { UserDefaults.standard.string(forKey: "lastModel") }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
