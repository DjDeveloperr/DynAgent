import AppKit

enum WindowLayoutChrome {
    static let defaultMinimumWindowSize = NSSize(width: 820, height: 480)
    static let defaultMaximumWindowSize = NSSize(width: 20_000, height: 20_000)

    @discardableResult
    static func applyUsableSizing(
        to window: NSWindow,
        minSize: NSSize = defaultMinimumWindowSize,
        maxSize: NSSize = defaultMaximumWindowSize
    ) -> (minSize: NSSize, maxSize: NSSize) {
        window.styleMask.insert(.resizable)
        window.minSize = minSize
        window.maxSize = maxSize
        window.contentMinSize = minSize
        window.contentMaxSize = maxSize
        return (minSize, maxSize)
    }

    @discardableResult
    static func pinRootToContentBounds(
        window: NSWindow,
        rootContentController: NSViewController?,
        splitView: NSSplitView?
    ) -> NSRect {
        let bounds = WindowLayoutModel.rootBounds(
            contentBounds: window.contentView?.bounds ?? .zero,
            windowFrame: window.frame,
            contentLayoutRect: window.contentLayoutRect
        )
        if rootContentController?.view.frame != bounds {
            rootContentController?.view.frame = bounds
        }
        if splitView?.frame != bounds {
            splitView?.frame = bounds
        }
        return bounds
    }

    @discardableResult
    static func applySplitPlan(
        splitView: NSSplitView?,
        rootSplitController: RootSplitViewController?,
        sidebarItem: NSSplitViewItem,
        gitItem: NSSplitViewItem,
        preferredMainWidth: CGFloat
    ) -> WindowSplitPlan? {
        guard let splitView, splitView.subviews.count >= 2 else { return nil }
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: splitView.bounds.width,
            sidebarCurrentWidth: splitItemWidth(containing: sidebarItem.viewController.view),
            sidebarMinimumWidth: sidebarItem.minimumThickness,
            sidebarMaximumWidth: sidebarItem.maximumThickness,
            sidebarCollapsed: sidebarItem.isCollapsed,
            gitCurrentWidth: splitItemWidth(containing: gitItem.viewController.view),
            gitMinimumWidth: gitItem.minimumThickness,
            gitMaximumWidth: gitItem.maximumThickness,
            gitCollapsed: gitItem.isCollapsed,
            fallbackSidebarWidth: sidebarItem.minimumThickness,
            preferredMainWidth: preferredMainWidth
        ))
        apply(plan, to: splitView)
        splitView.adjustSubviews()
        expandMainItemForCollapsedGit(splitView: splitView, rootSplitController: rootSplitController, gitItem: gitItem)
        rootSplitController?.pinSplitViewToRoot()
        apply(plan, to: splitView)
        splitView.adjustSubviews()
        expandMainItemForCollapsedGit(splitView: splitView, rootSplitController: rootSplitController, gitItem: gitItem)
        rootSplitController?.pinSplitViewToRoot()
        return plan
    }

    static func frameMetrics(for views: [NSView]) -> [WindowLayoutViewFrame] {
        views.enumerated().map { index, view in
            WindowLayoutViewFrame(
                index: index,
                className: String(describing: type(of: view)),
                x: Double(view.frame.minX),
                width: Double(view.frame.width),
                height: Double(view.frame.height)
            )
        }
    }

    static func splitItemWidth(containing view: NSView) -> CGFloat {
        view.superview?.frame.width ?? view.frame.width
    }

    private static func apply(_ plan: WindowSplitPlan, to splitView: NSSplitView) {
        if let first = plan.firstDividerPosition {
            splitView.setPosition(first, ofDividerAt: 0)
        }
        if splitView.subviews.count >= 3, let second = plan.secondDividerPosition {
            splitView.setPosition(second, ofDividerAt: 1)
        }
    }

    private static func expandMainItemForCollapsedGit(
        splitView: NSSplitView,
        rootSplitController: RootSplitViewController?,
        gitItem: NSSplitViewItem
    ) {
        guard gitItem.isCollapsed,
              let mainView = rootSplitController?.splitViewItems.dropFirst().first?.viewController.view,
              let wrapper = mainView.superview else { return }
        let target = NSRect(
            x: wrapper.frame.minX,
            y: 0,
            width: max(0, splitView.bounds.width - wrapper.frame.minX),
            height: splitView.bounds.height
        )
        guard wrapper.frame != target else { return }
        wrapper.frame = target
        mainView.frame = wrapper.bounds
    }
}
