import AppKit

final class TranscriptScrollCoordinator {
    typealias Scheduler = (_ delay: TimeInterval, _ block: @escaping () -> Void) -> Void

    private(set) var state: TranscriptScrollState
    private let now: () -> TimeInterval
    private let scheduler: Scheduler

    init(
        state: TranscriptScrollState = TranscriptScrollState(),
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        scheduler: @escaping Scheduler = { delay, block in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
        }
    ) {
        self.state = state
        self.now = now
        self.scheduler = scheduler
    }

    func scrollToBottom(streaming: Bool, root: NSView, scroll: NSScrollView) {
        let plan = TranscriptLiveUpdateModel.scrollPlan(
            streaming: streaming,
            now: now(),
            state: state
        )
        state = plan.state
        switch plan.action {
        case .ignorePending:
            return
        case .schedule(let delay):
            scheduler(delay) { [weak self, weak root, weak scroll] in
                guard let self, let root, let scroll else { return }
                self.state = TranscriptLiveUpdateModel.pendingScrollFired(state: self.state)
                self.scrollToBottom(streaming: streaming, root: root, scroll: scroll)
            }
        case .perform(let layoutBeforeScroll):
            performScroll(layoutBeforeScroll: layoutBeforeScroll, root: root, scroll: scroll)
        }
    }

    private func performScroll(layoutBeforeScroll: Bool, root: NSView, scroll: NSScrollView) {
        if layoutBeforeScroll {
            root.layoutSubtreeIfNeeded()
        }
        guard let document = scroll.documentView else { return }
        let y = max(0, document.bounds.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
