import AppKit

enum MainLayoutStabilizer {
    @discardableResult
    static func stabilize(
        window: NSWindow,
        rootContentController: NSViewController?,
        splitView: NSSplitView?,
        rootSplitController: RootSplitViewController?,
        workspaceArea: WorkspaceAreaViewController,
        sidebarItem: NSSplitViewItem,
        gitItem: NSSplitViewItem,
        preferredMainWidth: CGFloat,
        minSize: NSSize = WindowLayoutChrome.defaultMinimumWindowSize,
        maxSize: NSSize = WindowLayoutChrome.defaultMaximumWindowSize
    ) -> WindowSplitPlan? {
        WindowLayoutChrome.applyUsableSizing(to: window, minSize: minSize, maxSize: maxSize)
        WindowLayoutChrome.pinRootToContentBounds(
            window: window,
            rootContentController: rootContentController,
            splitView: splitView
        )
        workspaceArea.forceLayoutToBounds()
        let plan = WindowLayoutChrome.applySplitPlan(
            splitView: splitView,
            rootSplitController: rootSplitController,
            sidebarItem: sidebarItem,
            gitItem: gitItem,
            preferredMainWidth: preferredMainWidth,
            mainViewForCollapsedGit: workspaceArea.view
        )
        expandWorkspaceForCollapsedGit(splitView: splitView, workspaceArea: workspaceArea, gitItem: gitItem)
        workspaceArea.forceLayoutToBounds()
        return plan
    }

    private static func expandWorkspaceForCollapsedGit(
        splitView: NSSplitView?,
        workspaceArea: WorkspaceAreaViewController,
        gitItem: NSSplitViewItem
    ) {
        guard gitItem.isCollapsed,
              let splitView,
              let wrapper = workspaceArea.view.superview else { return }
        let target = NSRect(
            x: wrapper.frame.minX,
            y: 0,
            width: max(0, splitView.bounds.width - wrapper.frame.minX),
            height: splitView.bounds.height
        )
        guard wrapper.frame != target else { return }
        wrapper.frame = target
        workspaceArea.view.frame = wrapper.bounds
    }
}
