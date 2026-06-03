@testable import DynAgentUI
import XCTest

final class AppChatActionCoordinatorTests: XCTestCase {
    func testRenameSchedulesCodexSyncButLeavesLocalTitleMutationToCaller() {
        var renames: [(String, String)] = []
        let coordinator = coordinator(renameSync: { renames.append(($0, $1)) })
        let conversation = conversation(title: "New Name", threadId: "thread-1")

        let plan = coordinator.rename(conversation)

        XCTAssertEqual(plan, AppChatRenamePlan(threadId: "thread-1", title: "New Name"))
        XCTAssertEqual(renames.map { "\($0.0):\($0.1)" }, ["thread-1:New Name"])
    }

    func testRenameSkipsRemoteSyncForLocalChats() {
        var didRename = false
        let coordinator = coordinator(renameSync: { _, _ in didRename = true })
        let conversation = conversation(title: "Local", threadId: nil)

        let plan = coordinator.rename(conversation)

        XCTAssertEqual(plan, AppChatRenamePlan(threadId: nil, title: "Local"))
        XCTAssertFalse(didRename)
    }

    func testTogglePinMutatesConversationAndSyncsCodexThread() {
        var pins: [(String, Bool)] = []
        let coordinator = coordinator(pinSync: { pins.append(($0, $1)) })
        let conversation = conversation(threadId: "thread-2")

        let first = coordinator.togglePin(conversation)
        let second = coordinator.togglePin(conversation)

        XCTAssertEqual(first, AppChatPinPlan(threadId: "thread-2", pinned: true))
        XCTAssertEqual(second, AppChatPinPlan(threadId: "thread-2", pinned: false))
        XCTAssertEqual(pins.map { "\($0.0):\($0.1)" }, ["thread-2:true", "thread-2:false"])
    }

    func testArchiveRemovesLocalConversationArchivesThreadAndRemovesMatchingStubs() {
        var archivedIds: [String] = []
        var storedArchivedIds: [Set<String>] = []
        let coordinator = coordinator(
            archiveSync: { archivedIds.append($0) },
            storeArchivedIds: { storedArchivedIds.append($0) }
        )
        let target = conversation(threadId: "thread-3")
        let other = conversation(threadId: "other")
        var conversations = [target, other]
        var codexStubs = [
            "/repo": [target, conversation(threadId: "thread-3"), other],
            "__projectless__": [conversation(threadId: "thread-3")]
        ]
        var archived = Set<String>()

        let plan = coordinator.archive(
            target,
            conversations: &conversations,
            codexStubs: &codexStubs,
            archivedCodexIds: &archived
        )

        XCTAssertEqual(plan, AppChatArchivePlan(
            threadId: "thread-3",
            removedLocalConversation: true,
            removedStubCount: 3,
            didStoreArchivedIds: true
        ))
        XCTAssertTrue(conversations.first === other)
        XCTAssertEqual(codexStubs["/repo"]?.map(\.codexThreadId), ["other"])
        XCTAssertEqual(codexStubs["__projectless__"]?.count, 0)
        XCTAssertEqual(archived, ["thread-3"])
        XCTAssertEqual(storedArchivedIds, [["thread-3"]])
        XCTAssertEqual(archivedIds, ["thread-3"])
    }

    func testArchiveLocalChatRemovesLocalConversationWithoutCodexSideEffects() {
        var didArchive = false
        var didStore = false
        let coordinator = coordinator(
            archiveSync: { _ in didArchive = true },
            storeArchivedIds: { _ in didStore = true }
        )
        let target = conversation(threadId: nil)
        var conversations = [target]
        var codexStubs: [String: [Conversation]] = ["/repo": [conversation(threadId: "stub")]]
        var archived = Set<String>()

        let plan = coordinator.archive(
            target,
            conversations: &conversations,
            codexStubs: &codexStubs,
            archivedCodexIds: &archived
        )

        XCTAssertEqual(plan, AppChatArchivePlan(
            threadId: nil,
            removedLocalConversation: true,
            removedStubCount: 0,
            didStoreArchivedIds: false
        ))
        XCTAssertTrue(conversations.isEmpty)
        XCTAssertEqual(codexStubs["/repo"]?.map(\.codexThreadId), ["stub"])
        XCTAssertTrue(archived.isEmpty)
        XCTAssertFalse(didArchive)
        XCTAssertFalse(didStore)
    }

    private func coordinator(
        renameSync: @escaping AppChatActionCoordinator.RenameSync = { _, _ in },
        pinSync: @escaping AppChatActionCoordinator.PinSync = { _, _ in },
        archiveSync: @escaping AppChatActionCoordinator.ArchiveSync = { _ in },
        storeArchivedIds: @escaping AppChatActionCoordinator.ArchivedIdStore = { _ in }
    ) -> AppChatActionCoordinator {
        AppChatActionCoordinator(
            renameSync: renameSync,
            pinSync: pinSync,
            archiveSync: archiveSync,
            storeArchivedIds: storeArchivedIds
        )
    }

    private func conversation(title: String = "Chat", threadId: String?) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.title = title
        conversation.codexThreadId = threadId
        return conversation
    }
}
