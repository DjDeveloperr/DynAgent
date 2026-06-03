import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class MainLayoutStabilizerTests: XCTestCase {
    func testStabilizePinsRootSplitAndWorkspaceAfterStaleNarrowFrames() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)

        fixture.root.splitView.frame = NSRect(x: 0, y: 0, width: 640, height: 500)
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
        XCTAssertEqual(try XCTUnwrap(plan.secondDividerPosition), 1_472, accuracy: 0.5)

        let mainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
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
        fixture.root.splitView.setPosition(260, ofDividerAt: 0)
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
        XCTAssertEqual(try XCTUnwrap(plan.secondDividerPosition), 1_172, accuracy: 0.5)

        let mainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        let gitFrame = try XCTUnwrap(splitFrame(containing: fixture.gitItem.viewController.view))
        XCTAssertEqual(mainFrame.width, 911, accuracy: 2)
        XCTAssertEqual(gitFrame.width, 299, accuracy: 2)
        XCTAssertEqual(fixture.workspace.view.frame.width, mainFrame.width, accuracy: 0.5)
    }

    func testStabilizeExpandsGitPanelFromLoadedWideChatWithoutStealingEmptySpace() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)

        fixture.root.splitView.setPosition(260, ofDividerAt: 0)
        fixture.gitItem.isCollapsed = true
        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let loadedMainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        XCTAssertGreaterThan(loadedMainFrame.width, 1_100)
        XCTAssertEqual(fixture.workspace.view.frame.width, loadedMainFrame.width, accuracy: 0.5)
        XCTAssertEqual(fixture.chat.frame.width, loadedMainFrame.width, accuracy: 0.5)

        fixture.gitItem.isCollapsed = false
        let expandedPlan = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let mainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        let gitFrame = try XCTUnwrap(splitFrame(containing: fixture.gitItem.viewController.view))
        XCTAssertEqual(try XCTUnwrap(expandedPlan.firstDividerPosition), 260, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(expandedPlan.secondDividerPosition), 1_172, accuracy: 0.5)
        XCTAssertEqual(mainFrame.width, 911, accuracy: 2)
        XCTAssertEqual(gitFrame.width, 299, accuracy: 2)
        XCTAssertEqual(fixture.workspace.view.frame.width, mainFrame.width, accuracy: 0.5)
        XCTAssertEqual(fixture.chat.frame.width, mainFrame.width, accuracy: 0.5)
        XCTAssertEqual(mainFrame.maxX, gitFrame.minX - 1, accuracy: 2)
        XCTAssertEqual(gitFrame.maxX, fixture.root.splitView.bounds.maxX, accuracy: 2)
    }

    func testStabilizeAfterLateSidebarWidthSyncKeepsLoadedThreadWide() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)
        fixture.root.splitView.setPosition(260, ofDividerAt: 0)

        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))
        XCTAssertGreaterThan(fixture.chat.frame.width, 1_100)

        fixture.root.splitView.setPosition(SidebarLayoutModel.maximumWidth, ofDividerAt: 0)
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

        let mainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        XCTAssertNotNil(plan.firstDividerPosition)
        XCTAssertNotNil(plan.secondDividerPosition)
        XCTAssertGreaterThan(mainFrame.width, 1_100)
        XCTAssertEqual(fixture.workspace.view.frame.width, mainFrame.width, accuracy: 0.5)
        XCTAssertEqual(fixture.chat.frame.width, mainFrame.width, accuracy: 0.5)
    }

    func testStabilizeRepinsStaleWorkspaceWhenCollapsedGitWrapperIsAlreadyWide() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)
        fixture.root.splitView.setPosition(328, ofDividerAt: 0)

        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let wideWrapper = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        XCTAssertGreaterThan(wideWrapper.width, ChatLayoutModel.preferredMainWidthWithInspector)

        fixture.workspace.view.frame = NSRect(
            x: 0,
            y: 0,
            width: ChatLayoutModel.preferredMainWidthWithInspector,
            height: wideWrapper.height
        )
        fixture.chat.frame = fixture.workspace.view.bounds

        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let repairedWrapper = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        XCTAssertEqual(repairedWrapper.width, wideWrapper.width, accuracy: 0.5)
        XCTAssertEqual(fixture.workspace.view.frame.width, repairedWrapper.width, accuracy: 0.5)
        XCTAssertEqual(fixture.chat.frame.width, repairedWrapper.width, accuracy: 0.5)
    }

    func testStabilizeKeepsMainMinimumFlexibleWhileGitIsCollapsed() throws {
        let fixture = makeFixture(windowWidth: 1_472, windowHeight: 780)
        fixture.root.splitView.setPosition(328, ofDividerAt: 0)
        let mainItem = fixture.root.splitViewItems[1]
        XCTAssertEqual(mainItem.minimumThickness, AppSplitLayoutChrome.mainMinimumWidth)

        fixture.gitItem.isCollapsed = true
        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        XCTAssertEqual(mainItem.minimumThickness, AppSplitLayoutChrome.mainMinimumWidth)
        fixture.gitItem.isCollapsed = false
        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))
        XCTAssertEqual(mainItem.minimumThickness, AppSplitLayoutChrome.mainMinimumWidth)
    }

    func testLatestThreadLoadDoesNotShrinkWorkspaceAfterShellTransition() throws {
        let fixture = makeChatFixture(windowWidth: 1_472, windowHeight: 780)
        fixture.root.splitView.setPosition(260, ofDividerAt: 0)
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.title = "Latest thread width"
        conversation.needsLoad = true

        fixture.chatController.showShell(conversation)
        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let shellMainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        XCTAssertGreaterThanOrEqual(shellMainFrame.width, ChatLayoutModel.preferredMainWidthWithInspector)
        XCTAssertEqual(fixture.chatController.view.frame.width, shellMainFrame.width, accuracy: 0.5)

        conversation.needsLoad = false
        conversation.messages = [
            ChatMessage(role: .user, text: "Load the latest thread contents."),
            ChatMessage(role: .assistant, text: "The chat panel should keep the full split item width."),
        ]
        conversation.messages[1].isFinal = true
        fixture.chatController.show(conversation)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        fixture.root.view.layoutSubtreeIfNeeded()

        _ = try XCTUnwrap(MainLayoutStabilizer.stabilize(
            window: fixture.window,
            rootContentController: fixture.root,
            splitView: fixture.root.splitView,
            rootSplitController: fixture.root,
            workspaceArea: fixture.workspace,
            sidebarItem: fixture.sidebarItem,
            gitItem: fixture.gitItem,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let loadedMainFrame = try XCTUnwrap(splitFrame(containing: fixture.workspace.view))
        let chatMetrics = fixture.chatController.layoutMetrics
        XCTAssertGreaterThanOrEqual(loadedMainFrame.width, ChatLayoutModel.preferredMainWidthWithInspector)
        XCTAssertEqual(fixture.workspace.view.frame.width, loadedMainFrame.width, accuracy: 0.5)
        XCTAssertEqual(fixture.chatController.view.frame.width, loadedMainFrame.width, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(chatMetrics["chatViewWidth"] as? Double), Double(loadedMainFrame.width), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(chatMetrics["scrollWidth"] as? Double), Double(loadedMainFrame.width), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(chatMetrics["documentWidth"] as? Double), Double(loadedMainFrame.width), accuracy: 0.5)
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
        sidebarItem.minimumThickness = SidebarLayoutModel.minimumWidth
        sidebarItem.maximumThickness = SidebarLayoutModel.maximumWidth
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
        installFullWindowHost(root: root, in: window, width: windowWidth, height: windowHeight)
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
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

    private func makeChatFixture(windowWidth: CGFloat, windowHeight: CGFloat) -> ChatFixture {
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
        let chatController = ChatViewController()
        chatController.loadView()
        workspace.setPrimary(chatController.view, title: "")
        let git = NSViewController()
        git.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: windowHeight))

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = SidebarLayoutModel.minimumWidth
        sidebarItem.maximumThickness = SidebarLayoutModel.maximumWidth
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
        installFullWindowHost(root: root, in: window, width: windowWidth, height: windowHeight)
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        root.view.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        root.splitView.frame = root.view.bounds

        return ChatFixture(
            window: window,
            root: root,
            workspace: workspace,
            chatController: chatController,
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

    private struct ChatFixture {
        let window: NSWindow
        let root: RootSplitViewController
        let workspace: WorkspaceAreaViewController
        let chatController: ChatViewController
        let sidebarItem: NSSplitViewItem
        let gitItem: NSSplitViewItem
    }

    private func splitFrame(containing view: NSView) -> NSRect? {
        view.superview?.frame ?? view.frame
    }

    private func installFullWindowHost(root: RootSplitViewController, in window: NSWindow, width: CGFloat, height: CGFloat) {
        let host = FullWindowHostView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height))
        host.autoresizingMask = [.width, .height]
        host.pinnedView = root.view
        root.view.removeFromSuperview()
        host.addSubview(root.view)
        root.view.frame = host.bounds
        window.contentViewController = nil
        window.contentView = host
    }
}
