import Foundation

struct ComposerMenuState: Equatable {
    var placeholder: String
    var showsHarnessMenu: Bool
    var showsReasoningMenu: Bool
}

enum ComposerSendMode: Equatable {
    case send
    case stop
}

struct ComposerSendState: Equatable {
    var symbol: String
    var accessibilityDescription: String
    var isStop: Bool
}

struct ComposerContextState: Equatable {
    var fraction: Double
    var tooltip: String
}

struct ComposerMenuItemModel: Equatable {
    var title: String
    var representedValue: String
    var isSelected: Bool
}

struct ComposerCodexMenuModel: Equatable {
    var selectedModel: String
    var modelItems: [ComposerMenuItemModel]
    var effortItems: [ComposerMenuItemModel]
}

struct ComposerAttachment: Equatable {
    let id: UUID
    let url: URL

    init(url: URL, id: UUID = UUID()) {
        self.id = id
        self.url = url
    }
}

struct ComposerDraftSnapshot: Codable, Equatable {
    var text: String
    var attachments: [String]

    var isEmpty: Bool {
        text.isEmpty && attachments.isEmpty
    }
}

enum ComposerModel {
    static let defaultDraftPrefix = "DynAgentComposerDraft."
    static let codexEfforts: [(title: String, value: String)] = [
        ("Low", "low"),
        ("Medium", "medium"),
        ("High", "high"),
        ("Extra High", "xhigh"),
    ]

    static func menuState(conversation: Conversation?,
                          selectedHarness: Harness,
                          reasoningControlHidden: Bool) -> ComposerMenuState {
        let harness = conversation?.harness ?? selectedHarness
        let editableAgent = conversation?.messages.isEmpty ?? true
        let lockedToCodex = conversation?.codexThreadId?.isEmpty == false
        return ComposerMenuState(
            placeholder: "Ask \(harness.rawValue)",
            showsHarnessMenu: editableAgent && !lockedToCodex,
            showsReasoningMenu: selectedHarness != .codex && !reasoningControlHidden
        )
    }

    static func placeholder(agent: Harness) -> String {
        "Ask \(agent.rawValue)"
    }

    static func fallbackModel(for harness: Harness, preferred: String?) -> String {
        preferred?.nilIfEmpty ?? {
            switch harness {
            case .dynagent: return "auto"
            case .codex: return "gpt-5.5"
            case .pi: return "kiro::kiro/claude-opus-4.8"
            }
        }()
    }

    static func resolvedCodexModel(_ preferred: String?, available: [String]) -> String {
        if let preferred = preferred?.nilIfEmpty {
            if available.isEmpty || available.contains(preferred) { return preferred }
        }
        return available.first ?? "gpt-5.5"
    }

    static func selectedModelForList(ids: [String], desiredModel: String?) -> String? {
        if let desiredModel = desiredModel?.nilIfEmpty, ids.contains(desiredModel) {
            return desiredModel
        }
        return ids.first { $0 != "auto" } ?? ids.first
    }

    static func codexMenuModel(
        ids: [String],
        desiredModel: String?,
        currentModel: String,
        selectedEffort: String
    ) -> ComposerCodexMenuModel {
        let selectedModel: String
        if let desiredModel = desiredModel?.nilIfEmpty, ids.contains(desiredModel) {
            selectedModel = desiredModel
        } else if ids.contains(currentModel) {
            selectedModel = currentModel
        } else {
            selectedModel = ids.first ?? "gpt-5.5"
        }

        return ComposerCodexMenuModel(
            selectedModel: selectedModel,
            modelItems: ids.map { id in
                ComposerMenuItemModel(
                    title: shortCodexModelName(id),
                    representedValue: id,
                    isSelected: id == selectedModel
                )
            },
            effortItems: codexEfforts.map { title, value in
                ComposerMenuItemModel(
                    title: title,
                    representedValue: value,
                    isSelected: value == selectedEffort
                )
            }
        )
    }

    static func draftKey(for conversation: Conversation, prefix: String = defaultDraftPrefix) -> String {
        if let threadId = conversation.codexThreadId, !threadId.isEmpty {
            return prefix + "codex:" + threadId
        }
        if conversation.messages.isEmpty {
            return prefix + "new:" + (conversation.workspace.nilIfEmpty ?? "projectless")
        }
        return prefix + "local:" + conversation.id
    }

    static func draftKey(prefix: String, conversation: Conversation) -> String {
        draftKey(for: conversation, prefix: prefix)
    }

    static func messageText(typedText text: String, attachmentPaths: [String]) -> String {
        guard !attachmentPaths.isEmpty else { return text }
        let attachmentLines = attachmentPaths.map { "- \($0)" }.joined(separator: "\n")
        let block = "Attached files:\n\(attachmentLines)"
        return text.isEmpty ? block : "\(text)\n\n\(block)"
    }

    static func sendMode(streaming: Bool, typedText: String, attachmentCount: Int) -> ComposerSendMode {
        let hasText = !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return streaming && !hasText && attachmentCount == 0 ? .stop : .send
    }

    static func sendState(streaming: Bool, trimmedText: String, hasAttachments: Bool) -> ComposerSendState {
        let isStop = streaming && trimmedText.isEmpty && !hasAttachments
        return ComposerSendState(
            symbol: isStop ? "stop.fill" : "arrow.up",
            accessibilityDescription: isStop ? "Stop" : "Send",
            isStop: isStop
        )
    }

    static func contextState(percent: Double?) -> ComposerContextState {
        let value = percent ?? 0
        return ComposerContextState(
            fraction: value / 100,
            tooltip: "context \(Int(value))%"
        )
    }

    static func isImageFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"].contains(url.pathExtension.lowercased())
    }

    static func normalizedAttachmentPaths(_ attachments: [ComposerAttachment]) -> [String] {
        attachments.map { $0.url.standardizedFileURL.path }
    }

    static func attachmentAdditions(existing: [ComposerAttachment], incoming urls: [URL]) -> [ComposerAttachment] {
        var seen = Set(normalizedAttachmentPaths(existing))
        var additions: [ComposerAttachment] = []
        for url in urls.map(\.standardizedFileURL) {
            guard seen.insert(url.path).inserted else { continue }
            additions.append(ComposerAttachment(url: url))
        }
        return additions
    }

    static func draftSnapshot(text: String, attachments: [ComposerAttachment]) -> ComposerDraftSnapshot {
        ComposerDraftSnapshot(text: text, attachments: normalizedAttachmentPaths(attachments))
    }

    static func encodeDraftSnapshot(_ snapshot: ComposerDraftSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    static func decodeDraftSnapshot(from data: Data?) -> ComposerDraftSnapshot? {
        data.flatMap { try? JSONDecoder().decode(ComposerDraftSnapshot.self, from: $0) }
    }

    static func restoredAttachments(from snapshot: ComposerDraftSnapshot?, fileExists: (String) -> Bool) -> [ComposerAttachment] {
        (snapshot?.attachments ?? [])
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { fileExists($0.path) }
            .map { ComposerAttachment(url: $0) }
    }

    static func shortCodexModelName(_ id: String) -> String {
        id.replacingOccurrences(of: "gpt-", with: "")
            .replacingOccurrences(of: "-codex-spark", with: " Codex Spark")
            .replacingOccurrences(of: "-codex", with: " Codex")
            .replacingOccurrences(of: "-mini", with: " Mini")
    }

    static func effortDisplayName(_ effort: String) -> String {
        switch effort {
        case "low": return "Low"
        case "medium": return "Medium"
        case "xhigh": return "Extra High"
        default: return "High"
        }
    }
}
