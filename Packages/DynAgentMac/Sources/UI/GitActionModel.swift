import CoreGraphics
import Foundation

enum GitActionKind: Equatable {
    case commit
    case commitPush
    case push
    case createBranch
    case createPR

    var title: String {
        switch self {
        case .commit: return "Commit"
        case .commitPush: return "Commit & Push"
        case .push: return "Push"
        case .createBranch: return "New Branch"
        case .createPR: return "Create PR"
        }
    }

    func pendingStatus(hasMessage: Bool) -> String {
        switch self {
        case .commit:
            return hasMessage ? "committing..." : "generating commit message..."
        case .commitPush:
            return hasMessage ? "committing & pushing..." : "generating message & pushing..."
        case .push:
            return "pushing..."
        case .createBranch:
            return "creating branch..."
        case .createPR:
            return "creating PR..."
        }
    }
}

enum GitActionSheetModel {
    static let panelWidth: CGFloat = 380
    static let commitPanelHeight: CGFloat = 220
    static let worktreePanelHeight: CGFloat = 302
    static let commitPlaceholder = "Commit message (blank = auto-generate)"

    static func panelHeight(isWorktree: Bool) -> CGFloat {
        isWorktree ? worktreePanelHeight : commitPanelHeight
    }

    static func primaryActions(isWorktree: Bool) -> [GitActionKind] {
        isWorktree
            ? [.commit, .commitPush, .push, .createBranch, .createPR]
            : [.commit, .commitPush, .push]
    }

    static func trimmedMessage(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func commitBody(cwd: String, message: String) -> [String: Any] {
        var body: [String: Any] = ["cwd": cwd]
        let trimmed = trimmedMessage(message)
        if !trimmed.isEmpty { body["message"] = trimmed }
        return body
    }
}
