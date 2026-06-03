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

enum ComposerModel {
    static let defaultDraftPrefix = "DynAgentComposerDraft."

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
