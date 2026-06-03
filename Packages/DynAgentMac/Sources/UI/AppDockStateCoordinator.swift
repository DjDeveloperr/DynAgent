import AppKit
import Foundation

final class AppDockStateCoordinator {
    typealias RecentWriter = (_ recent: [DockRecentConversation]) -> Void
    typealias BadgeSetter = (_ label: String?) -> Void

    private let recentWriter: RecentWriter
    private let badgeSetter: BadgeSetter

    init(
        recentWriter: @escaping RecentWriter = { recent in
            AppDockStateCoordinator.writeRecentDockConversations(recent)
        },
        badgeSetter: @escaping BadgeSetter = { label in
            #if os(macOS)
            NSApp.dockTile.badgeLabel = label
            #endif
        }
    ) {
        self.recentWriter = recentWriter
        self.badgeSetter = badgeSetter
    }

    func update(conversations: [Conversation]) {
        recentWriter(AppConversationIndexModel.dockRecent(conversations: conversations))
        let unread = AppConversationIndexModel.unreadFinishedCount(conversations)
        badgeSetter(unread > 0 ? "\(unread)" : nil)
    }

    static func writeRecentDockConversations(
        _ recent: [DockRecentConversation],
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent")
    ) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = recent.map(\.dictionary)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            try? data.write(to: dir.appendingPathComponent("dock-recent.json"))
        }
    }
}
