@testable import DynAgentUI
import XCTest

final class AppWorkspaceIndexModelTests: XCTestCase {
    func testMergedWorkspaceRefsPrefersCodexOrderAndDedupesByPath() {
        let indexed = [
            codexWorkspace(name: "Alpha", path: "/repo/alpha"),
            codexWorkspace(name: "Beta", path: "/repo/beta"),
        ]
        let existing = [
            WorkspaceRef(name: "Old Beta", path: "/repo/beta"),
            WorkspaceRef(name: "Gamma", path: "/repo/gamma"),
        ]

        let merged = AppWorkspaceIndexModel.mergedWorkspaceRefs(indexed: indexed, existing: existing)

        XCTAssertEqual(merged, [
            WorkspaceRef(name: "Alpha", path: "/repo/alpha"),
            WorkspaceRef(name: "Beta", path: "/repo/beta"),
            WorkspaceRef(name: "Gamma", path: "/repo/gamma"),
        ])
    }

    func testMergedWorkspaceRefsFiltersEmptyAndCodexWorktreePaths() {
        let indexed = [
            codexWorkspace(name: "Empty", path: ""),
            codexWorkspace(name: "Codex Worktree", path: "/Users/dj/.codex/worktrees/repo"),
            codexWorkspace(name: "Root", path: "/repo/root"),
        ]
        let existing = [
            WorkspaceRef(name: "Existing Worktree", path: "/repo/.codex/worktrees/branch"),
            WorkspaceRef(name: "Existing", path: "/repo/existing"),
        ]

        let merged = AppWorkspaceIndexModel.mergedWorkspaceRefs(indexed: indexed, existing: existing)

        XCTAssertEqual(merged, [
            WorkspaceRef(name: "Root", path: "/repo/root"),
            WorkspaceRef(name: "Existing", path: "/repo/existing"),
        ])
    }

    func testSyncPreservesActiveWorkspaceWhenItStillExists() {
        let active = WorkspaceRef(name: "Existing", path: "/repo/existing")

        let result = AppWorkspaceIndexModel.sync(
            indexed: [codexWorkspace(name: "Indexed", path: "/repo/indexed")],
            existing: [active],
            active: active,
            primaryPath: active.path
        )

        XCTAssertEqual(result.workspaceRefs.map(\.path), ["/repo/indexed", "/repo/existing"])
        XCTAssertEqual(result.active, active)
        XCTAssertEqual(result.primaryPath, "/repo/existing")
        XCTAssertTrue(result.didChange)
    }

    func testSyncFallsBackToFirstWorkspaceWhenActiveDisappears() {
        let result = AppWorkspaceIndexModel.sync(
            indexed: [codexWorkspace(name: "Indexed", path: "/repo/indexed")],
            existing: [],
            active: WorkspaceRef(name: "Missing", path: "/repo/missing"),
            primaryPath: "/repo/missing"
        )

        XCTAssertEqual(result.active, WorkspaceRef(name: "Indexed", path: "/repo/indexed"))
        XCTAssertEqual(result.primaryPath, "/repo/indexed")
        XCTAssertTrue(result.didChange)
    }

    func testSyncReportsNoChangeForEquivalentState() {
        let active = WorkspaceRef(name: "Root", path: "/repo/root")

        let result = AppWorkspaceIndexModel.sync(
            indexed: [codexWorkspace(name: "Root", path: "/repo/root")],
            existing: [active],
            active: active,
            primaryPath: active.path
        )

        XCTAssertFalse(result.didChange)
    }

    private func codexWorkspace(name: String, path: String) -> AgentClient.CodexWorkspace {
        AgentClient.CodexWorkspace(name: name, path: path, source: "test")
    }
}
