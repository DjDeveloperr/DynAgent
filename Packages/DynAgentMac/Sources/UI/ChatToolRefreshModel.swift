import Foundation

enum ChatToolRefreshTrigger: Equatable {
    case completedTool(name: String?)
    case streamDone
}

enum ChatToolRefreshModel {
    static let delay: TimeInterval = 0.18

    static func shouldScheduleRefresh(
        trigger: ChatToolRefreshTrigger,
        isVisible: Bool,
        isActive: Bool
    ) -> Bool {
        guard isVisible, !isActive else { return false }
        switch trigger {
        case .completedTool(let name):
            return name == "edit" || name == "shell"
        case .streamDone:
            return false
        }
    }
}
