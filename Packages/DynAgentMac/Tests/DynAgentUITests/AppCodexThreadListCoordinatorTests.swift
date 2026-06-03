@testable import DynAgentUI
import XCTest

final class AppCodexThreadListCoordinatorTests: XCTestCase {
    func testLoadBuildsProjectlessAndWorkspaceStubsIncludingWorktrees() async {
        let root = WorkspaceRef(name: "Repo", path: "/repo")
        let coordinator = AppCodexThreadListCoordinator(
            loadWorkspaceThreads: { cwd in
                switch cwd {
                case "/repo": return [thread(id: "root", title: "Root", workspace: "/repo")]
                case "/repo-wt": return [thread(id: "wt", title: "Worktree", workspace: "/repo-wt")]
                default: return nil
                }
            },
            loadProjectlessThreads: {
                [thread(id: "floating", title: "Floating", projectless: true, workspace: nil)]
            }
        )

        let stubs = await coordinator.load(
            workspaceRefs: [root],
            worktreesByPath: ["/repo": ["/repo-wt"]],
            existingStubs: [:],
            localConversations: [],
            archivedIds: [],
            defaultModel: "gpt-5.5",
            projectlessKey: "projectless",
            primaryPath: "/repo"
        )

        XCTAssertEqual(stubs["projectless"]?.map(\.codexThreadId), ["floating"])
        XCTAssertEqual(stubs["projectless"]?.first?.workspace, "/repo")
        XCTAssertEqual(stubs["/repo"]?.map(\.codexThreadId), ["root", "wt"])
        XCTAssertEqual(stubs["/repo"]?.map(\.workspace), ["/repo", "/repo-wt"])
    }

    func testLoadPreservesExistingProjectlessStubsWhenEndpointIsUnavailable() async {
        let existing = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        existing.codexThreadId = "existing"
        let coordinator = AppCodexThreadListCoordinator(
            loadWorkspaceThreads: { _ in [] },
            loadProjectlessThreads: { nil }
        )

        let stubs = await coordinator.load(
            workspaceRefs: [WorkspaceRef(name: "Repo", path: "/repo")],
            worktreesByPath: [:],
            existingStubs: ["projectless": [existing]],
            localConversations: [],
            archivedIds: [],
            defaultModel: "gpt-5.5",
            projectlessKey: "projectless",
            primaryPath: "/repo"
        )

        XCTAssertTrue(stubs["projectless"]?.first === existing)
        XCTAssertEqual(stubs["/repo"]?.count, 0)
    }

    func testLoadFiltersArchivedThreadsAndReusesLocalConversations() async {
        let local = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        local.codexThreadId = "keep"
        local.title = "Local Title"
        let coordinator = AppCodexThreadListCoordinator(
            loadWorkspaceThreads: { _ in [
                thread(id: "keep", title: "Remote Title", workspace: "/repo"),
                thread(id: "archived", title: "Archived", workspace: "/repo")
            ] },
            loadProjectlessThreads: { [] }
        )

        let stubs = await coordinator.load(
            workspaceRefs: [WorkspaceRef(name: "Repo", path: "/repo")],
            worktreesByPath: [:],
            existingStubs: [:],
            localConversations: [local],
            archivedIds: ["archived"],
            defaultModel: "gpt-5.5",
            projectlessKey: "projectless",
            primaryPath: "/repo"
        )

        XCTAssertEqual(stubs["/repo"]?.count, 1)
        XCTAssertTrue(stubs["/repo"]?.first === local)
        XCTAssertEqual(stubs["/repo"]?.first?.title, "Remote Title")
    }
}

private func thread(
    id: String,
    title: String,
    projectless: Bool? = false,
    workspace: String?
) -> AgentClient.CodexThread {
    AgentClient.CodexThread(
        id: id,
        title: title,
        preview: title,
        updatedAt: 100,
        pinned: false,
        projectless: projectless,
        workspace: workspace
    )
}
