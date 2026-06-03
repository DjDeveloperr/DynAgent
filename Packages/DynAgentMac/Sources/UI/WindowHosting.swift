import AppKit

final class FullWindowHostView: NSView {
    weak var pinnedView: NSView?

    override func layout() {
        super.layout()
        guard let pinnedView else { return }
        pinnedView.frame = bounds
        pinnedView.subviews.forEach { subview in
            if subview is NSSplitView {
                subview.frame = pinnedView.bounds
            }
        }
    }
}

final class RootSplitViewController: NSSplitViewController {
    override func viewDidLayout() {
        super.viewDidLayout()
        pinSplitViewToRoot()
    }

    func deactivateInternalSplitSizingConstraints() {
        splitView.translatesAutoresizingMaskIntoConstraints = true
        splitView.autoresizingMask = [.width, .height]
    }

    func pinSplitViewToRoot() {
        deactivateInternalSplitSizingConstraints()
        let bounds = view.bounds
        guard splitView.frame.size != bounds.size || splitView.frame.origin != bounds.origin else { return }
        splitView.frame = bounds
    }
}
