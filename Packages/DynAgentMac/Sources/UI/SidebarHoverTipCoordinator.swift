import AppKit

final class SidebarHoverTipCoordinator {
    typealias Scheduler = (_ delay: TimeInterval, _ item: DispatchWorkItem) -> Void

    static let delay: TimeInterval = 0.12

    private var workItem: DispatchWorkItem?
    private let scheduler: Scheduler
    private let canShow: (SidebarRow) -> Bool

    init(
        scheduler: @escaping Scheduler = { delay, item in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        },
        canShow: @escaping (SidebarRow) -> Bool = { $0.window != nil }
    ) {
        self.scheduler = scheduler
        self.canShow = canShow
    }

    func schedule(
        title: String,
        detail: String,
        row: SidebarRow,
        show: @escaping (_ title: String, _ detail: String, _ row: SidebarRow) -> Void
    ) {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak row] in
            guard let self, let row, self.canShow(row) else { return }
            show(title, detail, row)
        }
        workItem = item
        scheduler(Self.delay, item)
    }

    func hide(_ hide: () -> Void) {
        workItem?.cancel()
        workItem = nil
        hide()
    }
}
