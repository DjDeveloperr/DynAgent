import Foundation

final class AppCodexThreadListCoordinator {
    typealias WorkspaceThreadsLoader = (_ cwd: String) async -> [AgentClient.CodexThread]?
    typealias ProjectlessThreadsLoader = () async -> [AgentClient.CodexThread]?

    private let loadWorkspaceThreads: WorkspaceThreadsLoader
    private let loadProjectlessThreads: ProjectlessThreadsLoader

    init(
        loadWorkspaceThreads: @escaping WorkspaceThreadsLoader,
        loadProjectlessThreads: @escaping ProjectlessThreadsLoader
    ) {
        self.loadWorkspaceThreads = loadWorkspaceThreads
        self.loadProjectlessThreads = loadProjectlessThreads
    }

    convenience init(client: AgentClient) {
        self.init(
            loadWorkspaceThreads: { cwd in
                try? await client.codexThreads(cwd: cwd)
            },
            loadProjectlessThreads: {
                try? await client.codexThreads()
            }
        )
    }

    func load(
        workspaceRefs: [WorkspaceRef],
        worktreesByPath: [String: [String]],
        existingStubs: [String: [Conversation]],
        localConversations: [Conversation],
        archivedIds: Set<String>,
        defaultModel: String,
        projectlessKey: String,
        primaryPath: String
    ) async -> [String: [Conversation]] {
        var nextStubs = existingStubs
        if let threads = await loadProjectlessThreads() {
            nextStubs[projectlessKey] = AppCodexThreadStubModel.projectlessStubs(
                threads: threads,
                existingStubs: existingStubs[projectlessKey] ?? [],
                archivedIds: archivedIds,
                defaultModel: defaultModel,
                fallbackWorkspace: primaryPath
            )
        }

        for ref in workspaceRefs {
            var batches: [(cwd: String, threads: [AgentClient.CodexThread])] = []
            for cwd in [ref.path] + (worktreesByPath[ref.path] ?? []) {
                guard let threads = await loadWorkspaceThreads(cwd) else { continue }
                batches.append((cwd: cwd, threads: threads))
            }
            nextStubs[ref.path] = AppCodexThreadStubModel.workspaceStubs(
                threadBatches: batches,
                existingStubs: existingStubs[ref.path] ?? [],
                localConversations: localConversations,
                archivedIds: archivedIds,
                defaultModel: defaultModel
            )
        }
        return nextStubs
    }
}
