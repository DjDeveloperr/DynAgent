@testable import DynAgentUI
import XCTest

final class AppCodexThreadStubModelTests: XCTestCase {
    func testWorkspaceStubsReuseExistingLocalConversationAndMarkNeedsLoadOnNewerThread() {
        let existing = conversation(threadId: "thread-1", title: "Old", workspace: "/repo", updatedAt: 100, messages: ["cached"])

        let stubs = AppCodexThreadStubModel.workspaceStubs(
            threadBatches: [(
                cwd: "/repo",
                threads: [thread(id: "thread-1", title: "New", updatedAt: 103, pinned: true)]
            )],
            existingStubs: [],
            localConversations: [existing],
            archivedIds: [],
            defaultModel: "gpt-5.5"
        )

        XCTAssertEqual(stubs.count, 1)
        XCTAssertTrue(stubs[0] === existing)
        XCTAssertEqual(existing.title, "New")
        XCTAssertEqual(existing.workspace, "/repo")
        XCTAssertEqual(existing.harness, .codex)
        XCTAssertTrue(existing.pinned)
        XCTAssertTrue(existing.needsLoad)
    }

    func testWorkspaceStubsFilterArchivedAndProjectlessThreads() {
        let stubs = AppCodexThreadStubModel.workspaceStubs(
            threadBatches: [(
                cwd: "/repo",
                threads: [
                    thread(id: "archived", title: "Archived", updatedAt: 1),
                    thread(id: "projectless", title: "Projectless", updatedAt: 2, projectless: true),
                    thread(id: "kept", title: "Kept", updatedAt: 3),
                ]
            )],
            existingStubs: [],
            localConversations: [],
            archivedIds: ["archived"],
            defaultModel: "gpt-5.5"
        )

        XCTAssertEqual(stubs.map(\.codexThreadId), ["kept"])
        XCTAssertEqual(stubs.first?.id, "codex:kept")
        XCTAssertTrue(stubs.first?.needsLoad ?? false)
    }

    func testWorkspaceStubsRespectLimitAcrossBatches() {
        let stubs = AppCodexThreadStubModel.workspaceStubs(
            threadBatches: [
                (cwd: "/repo", threads: [thread(id: "one", title: "One", updatedAt: 1)]),
                (cwd: "/repo-worktree", threads: [thread(id: "two", title: "Two", updatedAt: 2)]),
            ],
            existingStubs: [],
            localConversations: [],
            archivedIds: [],
            defaultModel: "gpt-5.5",
            limit: 1
        )

        XCTAssertEqual(stubs.map(\.codexThreadId), ["one"])
        XCTAssertEqual(stubs.first?.workspace, "/repo")
    }

    func testProjectlessStubsIncludeProjectlessAndPinnedThreadsWithFallbackWorkspace() {
        let stubs = AppCodexThreadStubModel.projectlessStubs(
            threads: [
                thread(id: "plain", title: "Plain", updatedAt: 1, workspace: "/ignored"),
                thread(id: "projectless", title: "Projectless", updatedAt: 2, projectless: true),
                thread(id: "pinned", title: "Pinned", updatedAt: 3, pinned: true, workspace: "/repo"),
            ],
            existingStubs: [],
            archivedIds: [],
            defaultModel: "gpt-5.5",
            fallbackWorkspace: "/fallback"
        )

        XCTAssertEqual(stubs.map(\.codexThreadId), ["projectless", "pinned"])
        XCTAssertEqual(stubs[0].workspace, "/fallback")
        XCTAssertEqual(stubs[1].workspace, "/repo")
    }

    func testExistingThreadMapPrefersLocalConversationWhenIdsCollide() {
        let stub = conversation(threadId: "thread", title: "Stub")
        let local = conversation(threadId: "thread", title: "Local")

        let existing = AppCodexThreadStubModel.existingThreadMap(stubs: [stub], localConversations: [local])

        XCTAssertTrue(existing["thread"] === local)
    }

    func testNeedsLoadStaysFalseWhenCachedMessagesAreCurrent() {
        let existing = conversation(threadId: "thread", title: "Old", updatedAt: 100, messages: ["cached"])
        existing.needsLoad = false

        let stubs = AppCodexThreadStubModel.workspaceStubs(
            threadBatches: [(
                cwd: "/repo",
                threads: [thread(id: "thread", title: "Current", updatedAt: 100.5)]
            )],
            existingStubs: [existing],
            localConversations: [],
            archivedIds: [],
            defaultModel: "gpt-5.5"
        )

        XCTAssertTrue(stubs[0] === existing)
        XCTAssertFalse(existing.needsLoad)
    }

    private func conversation(
        threadId: String,
        title: String,
        workspace: String = "/repo",
        updatedAt: Double = 0,
        messages: [String] = []
    ) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", workspace: workspace, harness: .codex)
        conversation.codexThreadId = threadId
        conversation.id = "local-\(threadId)"
        conversation.title = title
        conversation.updatedAt = updatedAt
        conversation.messages = messages.map { ChatMessage(role: .assistant, text: $0) }
        return conversation
    }

    private func thread(
        id: String,
        title: String,
        updatedAt: Double,
        pinned: Bool? = nil,
        projectless: Bool? = nil,
        workspace: String? = nil
    ) -> AgentClient.CodexThread {
        AgentClient.CodexThread(
            id: id,
            title: title,
            preview: "",
            updatedAt: updatedAt,
            pinned: pinned,
            projectless: projectless,
            workspace: workspace
        )
    }
}
