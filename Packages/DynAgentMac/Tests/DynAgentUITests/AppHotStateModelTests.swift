import XCTest
@testable import DynAgentUI

final class AppHotStateModelTests: XCTestCase {
    func testRestoreKeepsRecentIncompleteCodexThreadRunningAndNeedingLoad() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.updatedAt = Date().timeIntervalSince1970
        conversation.status = .idle
        let prompt = ChatMessage(role: .user, text: "Keep working")
        prompt.turnStatus = "running"
        conversation.messages = [prompt]

        let restored = AppHotStateModel.restored(from: state(conversations: [conversation]))

        XCTAssertEqual(restored.conversations[0].status, .running)
        XCTAssertTrue(restored.conversations[0].needsLoad)
    }

    func testRestoreClearsStaleRunningCodexThread() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.updatedAt = 1
        conversation.status = .running
        let prompt = ChatMessage(role: .user, text: "Old prompt")
        prompt.turnStatus = "running"
        conversation.messages = [prompt]

        let restored = AppHotStateModel.restored(from: state(conversations: [conversation]))

        XCTAssertEqual(restored.conversations[0].status, .idle)
        XCTAssertFalse(restored.conversations[0].needsLoad)
    }

    func testRestoreFiltersLegacyWorktreeWorkspaceRefsAndInvalidModelCacheKeys() {
        let restored = AppHotStateModel.restored(from: state(
            workspaceRefs: [
                WorkspaceRef(name: "Main", path: "/repo"),
                WorkspaceRef(name: "Tree", path: "/repo/worktrees/feature"),
            ],
            modelCache: [
                "Codex": ["gpt-5.5"],
                "Bogus": ["nope"],
            ]
        ))

        XCTAssertEqual(restored.workspaceRefs.map(\.path), ["/repo"])
        XCTAssertEqual(restored.modelCache[.codex], ["gpt-5.5"])
        XCTAssertNil(restored.modelCache[.dynagent])
    }

    func testSnapshotRoundTripsSelectionAndArchivedState() throws {
        let conversation = Conversation(model: "auto", workspace: "/repo")
        conversation.id = "local-1"
        let snapshot = AppHotStateModel.snapshot(
            conversations: [conversation],
            draft: nil,
            codexStubs: [:],
            workspaceRefs: [WorkspaceRef(name: "Main", path: "/repo")],
            worktreesByPath: ["/repo": ["/repo/wt"]],
            modelCache: [.dynagent: ["auto"]],
            primaryPath: "/repo",
            active: WorkspaceRef(name: "Main", path: "/repo"),
            archivedCodexIds: ["thread-1"],
            selectedConversationId: "local-1",
            savedAt: 42
        )

        let data = try XCTUnwrap(AppHotStateModel.encode(snapshot))
        let decoded = try XCTUnwrap(AppHotStateModel.decode(data))
        let restored = AppHotStateModel.restored(from: decoded)

        XCTAssertEqual(restored.conversations[0].id, "local-1")
        XCTAssertEqual(restored.worktreesByPath["/repo"], ["/repo/wt"])
        XCTAssertEqual(restored.modelCache[.dynagent], ["auto"])
        XCTAssertEqual(restored.archivedCodexIds, ["thread-1"])
        XCTAssertEqual(restored.selectedConversationId, "local-1")
    }

    private func state(
        conversations: [Conversation] = [],
        workspaceRefs: [WorkspaceRef] = [],
        modelCache: [String: [String]] = [:]
    ) -> AppHotState {
        AppHotState(
            conversations: conversations,
            draft: nil,
            codexStubs: [:],
            workspaceRefs: workspaceRefs,
            worktreesByPath: [:],
            modelCache: modelCache,
            primaryPath: "/repo",
            active: WorkspaceRef(name: "Main", path: "/repo"),
            archivedCodexIds: [],
            selectedConversationId: nil,
            savedAt: 1
        )
    }
}
