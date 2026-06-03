import AppKit

struct AppSplitLayoutBundle {
    var root: RootSplitViewController
    var splitView: NSSplitView
    var sidebarItem: NSSplitViewItem
    var mainItem: NSSplitViewItem
    var gitItem: NSSplitViewItem
}

enum AppSplitLayoutChrome {
    static let mainMinimumWidth: CGFloat = 360
    static let gitMinimumWidth: CGFloat = 300
    static let gitMaximumWidth: CGFloat = 520
    static let sidebarHoldingPriority = NSLayoutConstraint.Priority(251)
    static let mainHoldingPriority = NSLayoutConstraint.Priority(1)
    static let gitHoldingPriority = NSLayoutConstraint.Priority(249)

    static func makeRootSplit(
        sidebar: NSViewController,
        workspaceArea: WorkspaceAreaViewController,
        primaryChatView: NSView,
        gitPanel: NSViewController,
        cwdProvider: @escaping () -> String
    ) -> AppSplitLayoutBundle {
        let root = RootSplitViewController()
        root.splitView.dividerStyle = .thin
        root.splitView.autosaveName = nil

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = SidebarLayoutModel.minimumWidth
        sidebarItem.maximumThickness = SidebarLayoutModel.maximumWidth
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = sidebarHoldingPriority
        sidebarItem.preferredThicknessFraction = 0
        root.addSplitViewItem(sidebarItem)

        workspaceArea.cwdProvider = cwdProvider
        workspaceArea.setPrimary(primaryChatView, title: "")
        let mainItem = NSSplitViewItem(viewController: workspaceArea)
        mainItem.minimumThickness = mainMinimumWidth
        mainItem.maximumThickness = WindowLayoutChrome.defaultMaximumWindowSize.width
        mainItem.holdingPriority = mainHoldingPriority
        root.addSplitViewItem(mainItem)

        let gitItem = NSSplitViewItem(viewController: gitPanel)
        gitItem.minimumThickness = gitMinimumWidth
        gitItem.maximumThickness = gitMaximumWidth
        gitItem.canCollapse = true
        gitItem.preferredThicknessFraction = 0.30
        gitItem.holdingPriority = gitHoldingPriority
        root.addSplitViewItem(gitItem)
        gitItem.isCollapsed = true

        return AppSplitLayoutBundle(
            root: root,
            splitView: root.splitView,
            sidebarItem: sidebarItem,
            mainItem: mainItem,
            gitItem: gitItem
        )
    }

    static func installAutoresizing(on root: RootSplitViewController, size: NSSize) {
        root.splitView.translatesAutoresizingMaskIntoConstraints = true
        root.view.frame = NSRect(origin: .zero, size: size)
        root.view.autoresizingMask = [.width, .height]
        root.splitView.frame = root.view.bounds
        root.splitView.autoresizingMask = [.width, .height]
    }
}
