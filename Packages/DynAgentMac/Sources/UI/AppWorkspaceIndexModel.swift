import Foundation

struct WorkspaceIndexSyncResult: Equatable {
    var workspaceRefs: [WorkspaceRef]
    var active: WorkspaceRef
    var primaryPath: String
    var didChange: Bool
}

enum AppWorkspaceIndexModel {
    static func sync(
        indexed: [AgentClient.CodexWorkspace],
        existing: [WorkspaceRef],
        active: WorkspaceRef,
        primaryPath: String
    ) -> WorkspaceIndexSyncResult {
        let merged = mergedWorkspaceRefs(indexed: indexed, existing: existing)
        var nextActive = active
        var nextPrimaryPath = primaryPath

        if !merged.contains(where: { $0.path == nextActive.path }), let first = merged.first {
            nextActive = first
            nextPrimaryPath = first.path
        }

        return WorkspaceIndexSyncResult(
            workspaceRefs: merged,
            active: nextActive,
            primaryPath: nextPrimaryPath,
            didChange: merged != existing || nextActive != active || nextPrimaryPath != primaryPath
        )
    }

    static func mergedWorkspaceRefs(
        indexed: [AgentClient.CodexWorkspace],
        existing: [WorkspaceRef]
    ) -> [WorkspaceRef] {
        var merged: [WorkspaceRef] = []
        var seen = Set<String>()

        func append(_ ref: WorkspaceRef) {
            guard shouldInclude(ref), seen.insert(ref.path).inserted else { return }
            merged.append(ref)
        }

        for workspace in indexed {
            append(WorkspaceRef(name: workspace.name, path: workspace.path))
        }
        for ref in existing {
            append(ref)
        }
        return merged
    }

    static func shouldInclude(_ ref: WorkspaceRef) -> Bool {
        !ref.path.isEmpty && !ref.path.contains("/.codex/worktrees/")
    }
}
