import Foundation

final class SidebarArchiveConfirmationCoordinator {
    typealias Scheduler = (_ delay: TimeInterval, _ item: DispatchWorkItem) -> Void

    private var state = SidebarArchiveConfirmationState.idle
    private var cancelWorkItem: DispatchWorkItem?
    private let scheduler: Scheduler

    init(scheduler: @escaping Scheduler = { delay, item in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }) {
        self.scheduler = scheduler
    }

    var hasPendingArchive: Bool {
        state.hasPendingArchive
    }

    func isConfirming(conversationId: String) -> Bool {
        SidebarArchiveConfirmationModel.isConfirming(conversationId: conversationId, state: state)
    }

    func clickArchive(
        conversationId: String,
        showConfirmation: () -> Void,
        confirmArchive: () -> Void
    ) {
        switch SidebarArchiveConfirmationModel.clickArchive(conversationId: conversationId, state: state) {
        case .confirmArchive(let next):
            cancelWorkItem?.cancel()
            cancelWorkItem = nil
            state = next
            confirmArchive()
        case .showConfirmation(let next):
            cancelWorkItem?.cancel()
            cancelWorkItem = nil
            state = next
            showConfirmation()
        }
    }

    func updateHover(
        hovering: Bool,
        conversationId: String,
        cancelAndReload: @escaping () -> Void
    ) {
        if SidebarArchiveConfirmationModel.shouldScheduleCancel(
            hovering: hovering,
            conversationId: conversationId,
            state: state
        ) {
            scheduleCancel(for: conversationId, cancelAndReload: cancelAndReload)
        }
        if SidebarArchiveConfirmationModel.shouldCancelScheduledCancel(
            hovering: hovering,
            conversationId: conversationId,
            state: state
        ) {
            cancelWorkItem?.cancel()
        }
    }

    func cancelPending(immediate: Bool, reload: () -> Void) {
        cancelWorkItem?.cancel()
        cancelWorkItem = nil
        let result = SidebarArchiveConfirmationModel.cancel(state: state)
        state = result.state
        if immediate && result.shouldReload {
            reload()
        }
    }

    private func scheduleCancel(for conversationId: String, cancelAndReload: @escaping () -> Void) {
        cancelWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isConfirming(conversationId: conversationId) else { return }
            self.cancelPending(immediate: true, reload: cancelAndReload)
        }
        cancelWorkItem = item
        scheduler(SidebarArchiveConfirmationModel.cancelDelay, item)
    }
}
