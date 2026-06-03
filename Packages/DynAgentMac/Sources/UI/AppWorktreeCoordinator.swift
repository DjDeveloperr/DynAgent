import Foundation

enum AppWorktreeCreateResult: Equatable {
    case created(WorkspaceRef)
    case failed(String)
}

final class AppWorktreeCoordinator {
    typealias WorktreeLoader = (_ cwd: String) async -> [String]
    typealias WorktreeCreator = (_ cwd: String, _ branch: String) async -> AppWorktreeCreateResult

    private let loadWorktrees: WorktreeLoader
    private let createWorktree: WorktreeCreator

    init(
        loadWorktrees: @escaping WorktreeLoader,
        createWorktree: @escaping WorktreeCreator
    ) {
        self.loadWorktrees = loadWorktrees
        self.createWorktree = createWorktree
    }

    convenience init(client: AgentClient) {
        self.init(
            loadWorktrees: { cwd in
                await client.worktrees(cwd: cwd).map(\.path)
            },
            createWorktree: { cwd, branch in
                let response = try? await client.post("worktree", ["cwd": cwd, "branch": branch])
                guard let path = response?["path"] as? String,
                      let name = response?["name"] as? String else {
                    return .failed((response?["error"] as? String) ?? "Is this a git repository?")
                }
                return .created(WorkspaceRef(name: name, path: path))
            }
        )
    }

    func detectWorktrees(for workspaces: [WorkspaceRef]) async -> [String: [String]] {
        var result: [String: [String]] = [:]
        for workspace in workspaces {
            result[workspace.path] = await loadWorktrees(workspace.path)
        }
        return result
    }

    func create(cwd: String, branch rawBranch: String) async -> AppWorktreeCreateResult {
        let branch = Self.normalizedBranch(rawBranch)
        guard !branch.isEmpty else { return .failed("Branch name is required") }
        return await createWorktree(cwd, branch)
    }

    static func normalizedBranch(_ branch: String) -> String {
        branch.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
