import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class MainLayoutStabilizerTests: XCTestCase {
    func testStabilizePinsRootSplitAndWorkspaceAfterStaleNarrowFrames() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)

        fixture.root.view.frame = NSRect(x: 0, y: 0, width: 640, height: 500)
        fixture.root.splitView.frame = fixture.root.view.bounds
        fixture.workspace.view.frame = NSRect(x: 0, y: 0, width: 420, height: 500)
        fixture.chat.frame = fixture.workspace.view.bounds

        let plan = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let contentWidth = try XCTUnwrap(fixture.window.contentView?.bounds.width)
        XCTAssertEqual(fixture.root.view.frame.width, contentWidth, accuracy: 0.5)
        XCTAssertEqual(fixture.root.splitView.frame.width, contentWidth, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(plan.firstDividerPosition), 260, accuracy: 0.5)
        XCTAssertNil(plan.secondDividerPosition)

        let mainFrame = try XCTUnwrap(fixture.root.splitView.subviews[safe: 1]?.frame)
        XCTAssertEqual(fixture.workspace.view.frame.width, mainFrame.width, accuracy: 0.5)
        XCTAssertEqual(fixture.chat.frame.width, mainFrame.width, accuracy: 0.5)
        XCTAssertGreaterThan(mainFrame.width, 1_100)

        let metrics = fixture.workspace.layoutMetrics
        XCTAssertEqual(metrics["workspaceWidthSlack"] as? Double, nil)
        XCTAssertEqual(try XCTUnwrap(metrics["workspaceViewWidth"] as? Double), Double(mainFrame.width), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(metrics["workspaceRootWidth"] as? Double), Double(mainFrame.width), accuracy: 0.5)
    }

    func testStabilizeKeepsGitPanelOutsideReadableMainColumn() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)
        fixture.gitItem.isCollapsed = false

        let plan = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: 900
        ))

        XCTAssertEqual(try XCTUnwrap(plan.firstDividerPosition), 260, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(plan.secondDividerPosition), 1_160, accuracy: 0.5)

        let mainFrame = try XCTUnwrap(fixture.root.splitView.subviews[safe: 1]?.frame)
        let gitFrame = try XCTUnwrap(fixture.root.splitView.subviews[safe: 2]?.frame)
        XCTAssertEqual(mainFrame.width, 899, accuracy: 2)
        XCTAssertEqual(gitFrame.width, 311, accuracy: 2)
        XCTAssertEqual(fixture.workspace.view.frame.width, mainFrame.width, accuracy: 0.5)
    }

    private func makeFixture(windowWidth: CGFloat, windowHeight: CGFloat) -> Fixture {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )

        let root = RootSplitViewController()
        let sidebar = NSViewController()
        sidebar.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: windowHeight))
        let workspace = WorkspaceAreaViewController()
        workspace.loadView()
        let chat = NSView(frame: .zero)
        workspace.setPrimary(chat, title: "")
        let git = NSViewController()
        git.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: windowHeight))

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 260
        sidebarItem.maximumThickness = 380
        sidebarItem.canCollapse = true
        let mainItem = NSSplitViewItem(viewController: workspace)
        mainItem.minimumThickness = 360
        mainItem.maximumThickness = WindowLayoutChrome.defaultMaximumWindowSize.width
        let gitItem = NSSplitViewItem(viewController: git)
        gitItem.minimumThickness = 300
        gitItem.maximumThickness = 520
        gitItem.canCollapse = true
        gitItem.isCollapsed = true

        root.addSplitViewItem(sidebarItem)
        root.addSplitViewItem(mainItem)
        root.addSplitViewItem(gitItem)
        root.deactivateInternalSplitSizingConstraints()
        window.contentViewController = root
        root.view.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        root.splitView.frame = root.view.bounds

        return Fixture(
            window: window,
            root: root,
            workspace: workspace,
            chat: chat,
            sidebarItem: sidebarItem,
            gitItem: gitItem
        )
    }

    private struct Fixture {
        let window: NSWindow
        let root: RootSplitViewController
        let workspace: WorkspaceAreaViewController
        let chat: NSView
        let sidebarItem: NSSplitViewItem
        let gitItem: NSSplitViewItem
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
