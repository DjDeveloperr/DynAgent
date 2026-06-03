@testable import DynAgentUI
import XCTest

final class AppHotStateCoordinatorTests: XCTestCase {
    func testRestoreReadsHotStateDictionaryThroughModel() throws {
        let c = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        c.id = "thread-local"
        let state = AppHotStateModel.snapshot(
            conversations: [c],
            draft: nil,
            codexStubs: [:],
            workspaceRefs: [WorkspaceRef(name: "Repo", path: "/repo")],
            worktreesByPath: ["/repo": ["/repo-wt"]],
            modelCache: [.codex: ["gpt-5.5"]],
            primaryPath: "/repo",
            active: WorkspaceRef(name: "Repo", path: "/repo"),
            archivedCodexIds: ["codex-1"],
            selectedConversationId: "thread-local",
            savedAt: 10
        )
        let data = try XCTUnwrap(AppHotStateModel.encode(state))
        let dictionary = NSMutableDictionary()
        dictionary[AppHotStateModel.stateKey] = data

        let restored = try XCTUnwrap(AppHotStateCoordinator(hotState: dictionary).restore())

        XCTAssertEqual(restored.conversations.first?.id, "thread-local")
        XCTAssertEqual(restored.workspaceRefs.map(\.path), ["/repo"])
        XCTAssertEqual(restored.worktreesByPath["/repo"], ["/repo-wt"])
        XCTAssertEqual(restored.modelCache[.codex], ["gpt-5.5"])
        XCTAssertEqual(restored.archivedCodexIds, ["codex-1"])
        XCTAssertEqual(restored.selectedConversationId, "thread-local")
    }

    func testSaveWritesEncodedSnapshotAndCancelsPendingSave() throws {
        var scheduled: DispatchWorkItem?
        let dictionary = NSMutableDictionary()
        let coordinator = AppHotStateCoordinator(hotState: dictionary) { _, item in
            scheduled = item
        }
        XCTAssertTrue(coordinator.scheduleSave {})
        let pending = try XCTUnwrap(scheduled)

        let c = Conversation(model: "auto", workspace: "/repo", harness: .dynagent)
        c.id = "local-1"
        XCTAssertTrue(coordinator.save(
            conversations: [c],
            draft: nil,
            codexStubs: [:],
            workspaceRefs: [WorkspaceRef(name: "Repo", path: "/repo")],
            worktreesByPath: [:],
            modelCache: [.dynagent: ["auto"]],
            primaryPath: "/repo",
            active: WorkspaceRef(name: "Repo", path: "/repo"),
            archivedCodexIds: [],
            selectedConversationId: "local-1"
        ))

        XCTAssertTrue(pending.isCancelled)
        let data = try XCTUnwrap(dictionary[AppHotStateModel.stateKey] as? Data)
        let restored = try XCTUnwrap(AppHotStateModel.decode(data)).selectedConversationId
        XCTAssertEqual(restored, "local-1")
    }

    func testScheduleSaveCancelsEarlierPendingItemAndRunsLatestWhenPerformed() throws {
        var scheduled: [DispatchWorkItem] = []
        let coordinator = AppHotStateCoordinator(hotState: NSMutableDictionary()) { delay, item in
            XCTAssertEqual(delay, AppHotStateCoordinator.saveDelay)
            scheduled.append(item)
        }
        var saves = 0

        XCTAssertTrue(coordinator.scheduleSave { saves += 1 })
        XCTAssertTrue(coordinator.scheduleSave { saves += 10 })

        XCTAssertEqual(scheduled.count, 2)
        XCTAssertTrue(try XCTUnwrap(scheduled.first).isCancelled)
        scheduled[0].perform()
        XCTAssertEqual(saves, 0)
        scheduled[1].perform()
        XCTAssertEqual(saves, 10)
    }

    func testMissingHotStateNoopsRestoreSaveAndSchedule() {
        var schedulerCalled = false
        let coordinator = AppHotStateCoordinator(hotState: nil) { _, _ in
            schedulerCalled = true
        }

        XCTAssertNil(coordinator.restore())
        XCTAssertFalse(coordinator.scheduleSave {})
        XCTAssertFalse(schedulerCalled)
        XCTAssertFalse(coordinator.save(
            conversations: [],
            draft: nil,
            codexStubs: [:],
            workspaceRefs: [],
            worktreesByPath: [:],
            modelCache: [:],
            primaryPath: "/repo",
            active: WorkspaceRef(name: "Repo", path: "/repo"),
            archivedCodexIds: [],
            selectedConversationId: nil
        ))
    }
}
