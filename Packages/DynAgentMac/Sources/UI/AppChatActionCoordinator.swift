import Foundation

struct AppChatRenamePlan: Equatable {
    var threadId: String?
    var title: String
}

struct AppChatPinPlan: Equatable {
    var threadId: String?
    var pinned: Bool
}

struct AppChatArchivePlan: Equatable {
    var threadId: String?
    var removedLocalConversation: Bool
    var removedStubCount: Int
    var didStoreArchivedIds: Bool
}

final class AppChatActionCoordinator {
    typealias RenameSync = (_ threadId: String, _ title: String) -> Void
    typealias PinSync = (_ threadId: String, _ pinned: Bool) -> Void
    typealias ArchiveSync = (_ threadId: String) -> Void
    typealias ArchivedIdStore = (_ ids: Set<String>) -> Void

    private let renameSync: RenameSync
    private let pinSync: PinSync
    private let archiveSync: ArchiveSync
    private let storeArchivedIds: ArchivedIdStore

    init(
        renameSync: @escaping RenameSync,
        pinSync: @escaping PinSync,
        archiveSync: @escaping ArchiveSync,
        storeArchivedIds: @escaping ArchivedIdStore
    ) {
        self.renameSync = renameSync
        self.pinSync = pinSync
        self.archiveSync = archiveSync
        self.storeArchivedIds = storeArchivedIds
    }

    convenience init(client: AgentClient, storeArchivedIds: @escaping ArchivedIdStore) {
        self.init(
            renameSync: { threadId, title in
                Task { [client] in
                    try? await client.codexRename(threadId: threadId, name: title)
                }
            },
            pinSync: { threadId, pinned in
                Task { [client] in
                    try? await client.codexPin(threadId: threadId, pinned: pinned)
                }
            },
            archiveSync: { threadId in
                Task { [client] in
                    try? await client.codexArchive(threadId: threadId)
                }
            },
            storeArchivedIds: storeArchivedIds
        )
    }

    @discardableResult
    func rename(_ conversation: Conversation) -> AppChatRenamePlan {
        let plan = AppChatRenamePlan(threadId: conversation.codexThreadId, title: conversation.title)
        if let threadId = plan.threadId {
            renameSync(threadId, plan.title)
        }
        return plan
    }

    @discardableResult
    func togglePin(_ conversation: Conversation) -> AppChatPinPlan {
        conversation.pinned.toggle()
        let plan = AppChatPinPlan(threadId: conversation.codexThreadId, pinned: conversation.pinned)
        if let threadId = plan.threadId {
            pinSync(threadId, plan.pinned)
        }
        return plan
    }

    @discardableResult
    func archive(
        _ conversation: Conversation,
        conversations: inout [Conversation],
        codexStubs: inout [String: [Conversation]],
        archivedCodexIds: inout Set<String>
    ) -> AppChatArchivePlan {
        let localCount = conversations.count
        conversations.removeAll { $0 === conversation }
        let removedLocal = conversations.count != localCount

        guard let threadId = conversation.codexThreadId else {
            return AppChatArchivePlan(
                threadId: nil,
                removedLocalConversation: removedLocal,
                removedStubCount: 0,
                didStoreArchivedIds: false
            )
        }

        archivedCodexIds.insert(threadId)
        storeArchivedIds(archivedCodexIds)

        var removedStubs = 0
        for key in codexStubs.keys {
            let before = codexStubs[key]?.count ?? 0
            codexStubs[key]?.removeAll { $0.codexThreadId == threadId }
            removedStubs += before - (codexStubs[key]?.count ?? 0)
        }
        archiveSync(threadId)

        return AppChatArchivePlan(
            threadId: threadId,
            removedLocalConversation: removedLocal,
            removedStubCount: removedStubs,
            didStoreArchivedIds: true
        )
    }
}
