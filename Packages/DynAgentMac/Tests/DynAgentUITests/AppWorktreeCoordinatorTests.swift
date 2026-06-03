@testable import DynAgentUI
import XCTest

final class AppWorktreeCoordinatorTests: XCTestCase {
    func testDetectWorktreesBuildsPathMapInWorkspaceOrder() async {
        var requested: [String] = []
        let coordinator = AppWorktreeCoordinator(
            loadWorktrees: { cwd in
                requested.append(cwd)
                return cwd == "/repo/a" ? ["/repo/a-wt"] : []
            },
            createWorktree: { _, _ in .failed("unused") }
        )

        let result = await coordinator.detectWorktrees(for: [
            WorkspaceRef(name: "A", path: "/repo/a"),
            WorkspaceRef(name: "B", path: "/repo/b")
        ])

        XCTAssertEqual(requested, ["/repo/a", "/repo/b"])
        XCTAssertEqual(result["/repo/a"], ["/repo/a-wt"])
        XCTAssertEqual(result["/repo/b"], [])
    }

    func testCreateNormalizesBranchAndReturnsCreatedWorkspace() async {
        var created: [(String, String)] = []
        let coordinator = AppWorktreeCoordinator(
            loadWorktrees: { _ in [] },
            createWorktree: { cwd, branch in
                created.append((cwd, branch))
                return .created(WorkspaceRef(name: branch, path: "/repo/worktrees/\(branch)"))
            }
        )

        let result = await coordinator.create(cwd: "/repo", branch: " feature/new-ui\n")

        XCTAssertEqual(created.map { "\($0.0):\($0.1)" }, ["/repo:feature/new-ui"])
        XCTAssertEqual(result, .created(WorkspaceRef(name: "feature/new-ui", path: "/repo/worktrees/feature/new-ui")))
    }

    func testCreateRejectsEmptyBranchBeforeCallingCreator() async {
        var didCreate = false
        let coordinator = AppWorktreeCoordinator(
            loadWorktrees: { _ in [] },
            createWorktree: { _, _ in
                didCreate = true
                return .failed("should not run")
            }
        )

        let result = await coordinator.create(cwd: "/repo", branch: " \n\t")

        XCTAssertEqual(result, .failed("Branch name is required"))
        XCTAssertFalse(didCreate)
    }

    func testNormalizedBranchTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(AppWorktreeCoordinator.normalizedBranch(" branch "), "branch")
        XCTAssertEqual(AppWorktreeCoordinator.normalizedBranch("\nbranch\t"), "branch")
    }
}
