import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class AppSplitLayoutChromeTests: XCTestCase {
    func testMakeRootSplitConfiguresSidebarMainAndGitItems() {
        let sidebar = NSViewController()
        sidebar.view = NSView()
        let workspace = WorkspaceAreaViewController()
        let chatView = NSView()
        let git = NSViewController()
        git.view = NSView()

        let bundle = AppSplitLayoutChrome.makeRootSplit(
            sidebar: sidebar,
            workspaceArea: workspace,
            primaryChatView: chatView,
            gitPanel: git,
            cwdProvider: { "/repo" }
        )

        XCTAssertIdentical(bundle.splitView, bundle.root.splitView)
        XCTAssertEqual(bundle.root.splitViewItems.count, 3)
        XCTAssertEqual(bundle.splitView.dividerStyle, .thin)
        XCTAssertNil(bundle.splitView.autosaveName)

        XCTAssertEqual(bundle.sidebarItem.minimumThickness, SidebarLayoutModel.minimumWidth)
        XCTAssertEqual(bundle.sidebarItem.maximumThickness, SidebarLayoutModel.maximumWidth)
        XCTAssertEqual(bundle.sidebarItem.behavior, .sidebar)
        XCTAssertTrue(bundle.sidebarItem.canCollapse)
        XCTAssertEqual(bundle.sidebarItem.holdingPriority, AppSplitLayoutChrome.sidebarHoldingPriority)
        XCTAssertEqual(bundle.sidebarItem.preferredThicknessFraction, 0)

        XCTAssertEqual(bundle.mainItem.minimumThickness, AppSplitLayoutChrome.mainMinimumWidth)
        XCTAssertEqual(bundle.mainItem.maximumThickness, WindowLayoutChrome.defaultMaximumWindowSize.width)
        XCTAssertEqual(bundle.mainItem.preferredThicknessFraction, 1)
        XCTAssertEqual(bundle.mainItem.holdingPriority, AppSplitLayoutChrome.mainHoldingPriority)

        XCTAssertEqual(bundle.gitItem.minimumThickness, AppSplitLayoutChrome.gitMinimumWidth)
        XCTAssertEqual(bundle.gitItem.maximumThickness, AppSplitLayoutChrome.gitMaximumWidth)
        XCTAssertTrue(bundle.gitItem.canCollapse)
        XCTAssertTrue(bundle.gitItem.isCollapsed)
        XCTAssertEqual(bundle.gitItem.preferredThicknessFraction, 0.30)
        XCTAssertEqual(bundle.gitItem.holdingPriority, AppSplitLayoutChrome.gitHoldingPriority)
        XCTAssertEqual(workspace.cwdProvider(), "/repo")
    }

    func testInstallAutoresizingPinsRootAndSplitToRequestedSize() {
        let root = RootSplitViewController()
        _ = root.view

        AppSplitLayoutChrome.installAutoresizing(on: root, size: NSSize(width: 1_472, height: 798))

        XCTAssertEqual(root.preferredContentSize, NSSize(width: 1_472, height: 798))
        XCTAssertTrue(root.splitView.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(root.view.frame.size.width, 1_472, accuracy: 0.5)
        XCTAssertEqual(root.view.frame.size.height, 798, accuracy: 0.5)
        XCTAssertEqual(root.splitView.frame, root.view.bounds)
        XCTAssertTrue(root.view.autoresizingMask.contains(.width))
        XCTAssertTrue(root.view.autoresizingMask.contains(.height))
        XCTAssertTrue(root.splitView.autoresizingMask.contains(.width))
        XCTAssertTrue(root.splitView.autoresizingMask.contains(.height))
    }

    func testInstallRootViewUsesFrameManagedContentHost() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_472, height: 798),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let root = RootSplitViewController()
        _ = root.view

        let host = AppSplitLayoutChrome.installRootView(root, in: window, size: NSSize(width: 1_472, height: 798))
        host.layoutSubtreeIfNeeded()

        XCTAssertNil(window.contentViewController)
        XCTAssertIdentical(window.contentView, host)
        XCTAssertIdentical(root.view.superview, host)
        XCTAssertIdentical(host.pinnedView, root.view)
        XCTAssertEqual(host.fittingSize, .zero)
        XCTAssertEqual(root.view.frame.width, host.bounds.width, accuracy: 0.5)
        XCTAssertEqual(root.splitView.frame, root.view.bounds)
    }
}
