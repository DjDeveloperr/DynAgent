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
            preferredMainWidth: preferredMainWidth
        )
        workspaceArea.forceLayoutToBounds()
        return plan
    }
}
