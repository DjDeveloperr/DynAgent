import AppKit

final class TranscriptToolPopoverCoordinator {
    private let popover: NSPopover

    init(popover: NSPopover = NSPopover()) {
        self.popover = popover
    }

    func plan(message: ChatMessage, from anchor: NSView, clickPoint: NSPoint?) -> TranscriptToolPopoverPlan {
        TranscriptToolPopoverPresenter.plan(
            for: message,
            clickPoint: clickPoint,
            anchorBounds: anchor.bounds
        )
    }

    func planEditChanges(_ changes: [EditToolChange], from anchor: NSView) -> TranscriptToolPopoverPlan {
        TranscriptToolPopoverPresenter.editPlan(changes: changes, anchorBounds: anchor.bounds)
    }

    func present(message: ChatMessage, from anchor: NSView, clickPoint: NSPoint?) {
        show(plan(message: message, from: anchor, clickPoint: clickPoint), from: anchor)
    }

    func presentEditChanges(_ changes: [EditToolChange], from anchor: NSView) {
        show(planEditChanges(changes, from: anchor), from: anchor)
    }

    private func show(_ plan: TranscriptToolPopoverPlan, from anchor: NSView) {
        TranscriptPopoverChrome.show(plan.content, in: popover, relativeTo: plan.anchorRect, of: anchor)
    }
}
