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
        configureMainMinimumThickness(
            rootSplitController: rootSplitController,
            gitItem: gitItem,
            preferredMainWidth: preferredMainWidth
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

    private static func configureMainMinimumThickness(
        rootSplitController: RootSplitViewController?,
        gitItem: NSSplitViewItem,
        preferredMainWidth: CGFloat
    ) {
        guard let mainItem = rootSplitController?.splitViewItems.dropFirst().first else { return }
        mainItem.minimumThickness = gitItem.isCollapsed
            ? preferredMainWidth
            : AppSplitLayoutChrome.mainMinimumWidth
    }

    private static func expandWorkspaceForCollapsedGit(
        splitView: NSSplitView?,
        workspaceArea: WorkspaceAreaViewController,
        gitItem: NSSplitViewItem
    ) {
        guard gitItem.isCollapsed,
              let wrapper = workspaceArea.view.superview else { return }
        workspaceArea.view.autoresizingMask = [.width, .height]
        if workspaceArea.view.frame != wrapper.bounds {
            workspaceArea.view.frame = wrapper.bounds
        }
    }
}
