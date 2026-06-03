import Foundation

final class AppHotStateCoordinator {
    typealias Scheduler = (_ delay: TimeInterval, _ item: DispatchWorkItem) -> Void

    static let saveDelay: TimeInterval = 2.5

    private let hotState: NSMutableDictionary?
    private let scheduler: Scheduler
    private var pendingSave: DispatchWorkItem?

    init(
        hotState: NSMutableDictionary?,
        scheduler: @escaping Scheduler = { delay, item in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    ) {
        self.hotState = hotState
        self.scheduler = scheduler
    }

    func restore() -> AppHotStateModel.Restored? {
        guard let data = hotState?[AppHotStateModel.stateKey] as? Data,
              let state = AppHotStateModel.decode(data) else { return nil }
        return AppHotStateModel.restored(from: state)
    }

    @discardableResult
    func save(
        conversations: [Conversation],
        draft: Conversation?,
        codexStubs: [String: [Conversation]],
        workspaceRefs: [WorkspaceRef],
        worktreesByPath: [String: [String]],
        modelCache: [Harness: [String]],
        primaryPath: String,
        active: WorkspaceRef,
        archivedCodexIds: Set<String>,
        selectedConversationId: String?
    ) -> Bool {
        guard let hotState else { return false }
        cancelPendingSave()
        let state = AppHotStateModel.snapshot(
            conversations: conversations,
            draft: draft,
            codexStubs: codexStubs,
            workspaceRefs: workspaceRefs,
            worktreesByPath: worktreesByPath,
            modelCache: modelCache,
            primaryPath: primaryPath,
            active: active,
            archivedCodexIds: archivedCodexIds,
            selectedConversationId: selectedConversationId
        )
        guard let data = AppHotStateModel.encode(state) else { return false }
        hotState[AppHotStateModel.stateKey] = data
        return true
    }

    @discardableResult
    func scheduleSave(_ save: @escaping () -> Void) -> Bool {
        guard hotState != nil else { return false }
        cancelPendingSave()
        let item = DispatchWorkItem(block: save)
        pendingSave = item
        scheduler(Self.saveDelay, item)
        return true
    }

    func cancelPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
    }
}
