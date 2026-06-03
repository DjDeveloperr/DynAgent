@testable import DynAgentUI
import XCTest

final class WindowLayoutModelTests: XCTestCase {
    func testWideFrameMatchesVisibleScreenContract() {
        let frame = WindowLayoutModel.wideFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949))

        XCTAssertEqual(frame.width, 1451.52, accuracy: 0.001)
        XCTAssertEqual(frame.height, 797.16, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 474.5, accuracy: 0.001)
    }

    func testRestoredFrameRejectsTooSmallOrOffscreenFrames() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let minSize = CGSize(width: 820, height: 480)

        XCTAssertNil(WindowLayoutModel.restoredFrame(CGRect(x: 0, y: 0, width: 700, height: 600), minSize: minSize, visibleFrame: visible))
        XCTAssertNil(WindowLayoutModel.restoredFrame(CGRect(x: 3000, y: 3000, width: 1000, height: 700), minSize: minSize, visibleFrame: visible))

        let good = CGRect(x: 30, y: 75, width: 1452, height: 798)
        XCTAssertEqual(WindowLayoutModel.restoredFrame(good, minSize: minSize, visibleFrame: visible), good)
    }

    func testRestoredFrameCanRejectStaleNarrowSavedFrames() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let minSize = CGSize(width: 820, height: 480)

        XCTAssertNil(WindowLayoutModel.restoredFrame(
            CGRect(x: 30, y: 75, width: 1291, height: 798),
            minSize: minSize,
            visibleFrame: visible,
            minimumRestoredWidth: 1335
        ))
        XCTAssertNotNil(WindowLayoutModel.restoredFrame(
            CGRect(x: 30, y: 75, width: 1400, height: 798),
            minSize: minSize,
            visibleFrame: visible,
            minimumRestoredWidth: 1335
        ))
    }

    func testShouldRestoreAppliedFrameOnlyWhenWindowShrank() {
        let applied = CGRect(x: 0, y: 0, width: 1452, height: 798)

        XCTAssertTrue(WindowLayoutModel.shouldRestoreAppliedFrame(
            current: CGRect(x: 0, y: 0, width: 900, height: 798),
            applied: applied
        ))
        XCTAssertFalse(WindowLayoutModel.shouldRestoreAppliedFrame(
            current: CGRect(x: 0, y: 0, width: 1451.5, height: 797.5),
            applied: applied
        ))
        XCTAssertFalse(WindowLayoutModel.shouldRestoreAppliedFrame(
            current: CGRect(x: 0, y: 0, width: 1600, height: 900),
            applied: applied
        ))
    }

    func testUnexpectedShrinkRestoreIgnoresUserLiveResize() {
        let applied = CGRect(x: 0, y: 0, width: 1452, height: 798)
        let current = CGRect(x: 0, y: 0, width: 1291, height: 798)

        XCTAssertTrue(WindowLayoutModel.shouldRestoreUnexpectedShrink(
            current: current,
            applied: applied,
            isUserLiveResizing: false
        ))
        XCTAssertFalse(WindowLayoutModel.shouldRestoreUnexpectedShrink(
            current: current,
            applied: applied,
            isUserLiveResizing: true
        ))
        XCTAssertFalse(WindowLayoutModel.shouldRestoreUnexpectedShrink(
            current: applied,
            applied: applied,
            isUserLiveResizing: false
        ))
    }

    func testRootBoundsPrefersContentViewBoundsOverWindowFrame() {
        let bounds = WindowLayoutModel.rootBounds(
            contentBounds: CGRect(x: 0, y: 0, width: 1211, height: 798),
            windowFrame: CGRect(x: 20, y: 20, width: 1472, height: 846),
            contentLayoutRect: CGRect(x: 0, y: 0, width: 1472, height: 798)
        )

        XCTAssertEqual(bounds.origin, .zero)
        XCTAssertEqual(bounds.size, CGSize(width: 1211, height: 798))
    }

    func testRootBoundsFallsBackWhenContentBoundsAreUnavailable() {
        let layoutBounds = WindowLayoutModel.rootBounds(
            contentBounds: .zero,
            windowFrame: CGRect(x: 20, y: 20, width: 1472, height: 846),
            contentLayoutRect: CGRect(x: 0, y: 0, width: 1452, height: 798)
        )
        let windowBounds = WindowLayoutModel.rootBounds(
            contentBounds: .zero,
            windowFrame: CGRect(x: 20, y: 20, width: 1472, height: 846),
            contentLayoutRect: .zero
        )

        XCTAssertEqual(layoutBounds.size, CGSize(width: 1452, height: 798))
        XCTAssertEqual(windowBounds.size, CGSize(width: 1472, height: 846))
    }

    func testSplitPlanKeepsCenterWideWhenGitIsCollapsed() {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 1452,
            sidebarCurrentWidth: 260,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 0,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: true
        ))

        XCTAssertEqual(plan.sidebarWidth, 260)
        XCTAssertEqual(plan.gitWidth, 0)
        XCTAssertEqual(plan.firstDividerPosition, 260)
        XCTAssertNil(plan.secondDividerPosition)
    }

    func testSplitPlanDoesNotPreserveMaxSidebarWhenGitIsCollapsed() {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 1472,
            sidebarCurrentWidth: 380,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 0,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: true,
            fallbackSidebarWidth: 260
        ))

        XCTAssertEqual(plan.sidebarWidth, 260)
        XCTAssertEqual(plan.firstDividerPosition, 260)
        XCTAssertNil(plan.secondDividerPosition)
    }

    func testSplitPlanClampsSidebarAndGitWidths() {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 1452,
            sidebarCurrentWidth: 999,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 999,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: false
        ))

        XCTAssertEqual(plan.sidebarWidth, 380)
        XCTAssertEqual(plan.gitWidth, 300)
        XCTAssertEqual(plan.firstDividerPosition, 380)
        XCTAssertEqual(plan.secondDividerPosition, 1152)
    }

    func testSplitPlanPreservesMinimumMainWidthWhenWindowIsTight() {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 900,
            sidebarCurrentWidth: 300,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 520,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: false
        ))

        XCTAssertEqual(plan.secondDividerPosition, 660)
    }

    func testSplitPlanPreservesReadableMainWidthBeforeExpandingGit() {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 1472,
            sidebarCurrentWidth: 260,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 520,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: false,
            preferredMainWidth: 900
        ))

        XCTAssertEqual(plan.firstDividerPosition, 260)
        XCTAssertEqual(plan.secondDividerPosition, 1160)
        XCTAssertEqual(plan.gitWidth, 312)
    }

    func testSplitPlanUsesRightSideRemainderForExpandedGitPanel() throws {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 1472,
            sidebarCurrentWidth: 284,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 420,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: false,
            preferredMainWidth: 900
        ))

        let sidebarWidth = try XCTUnwrap(plan.firstDividerPosition)
        let secondDivider = try XCTUnwrap(plan.secondDividerPosition)
        let mainWidth = secondDivider - sidebarWidth

        XCTAssertEqual(sidebarWidth, 284)
        XCTAssertEqual(mainWidth, 888)
        XCTAssertEqual(plan.gitWidth, 300)
        XCTAssertEqual(sidebarWidth + mainWidth + plan.gitWidth, 1472)
    }

    func testSplitPlanKeepsReadableMainWidthOnWideWindowsWhenGitOpens() throws {
        let plan = WindowLayoutModel.splitPlan(WindowSplitConfiguration(
            totalWidth: 2_200,
            sidebarCurrentWidth: 284,
            sidebarMinimumWidth: 260,
            sidebarMaximumWidth: 380,
            sidebarCollapsed: false,
            gitCurrentWidth: 520,
            gitMinimumWidth: 300,
            gitMaximumWidth: 520,
            gitCollapsed: false,
            preferredMainWidth: ChatLayoutModel.preferredMainWidthWithInspector
        ))

        let sidebarWidth = try XCTUnwrap(plan.firstDividerPosition)
        let secondDivider = try XCTUnwrap(plan.secondDividerPosition)
        let mainWidth = secondDivider - sidebarWidth

        XCTAssertGreaterThanOrEqual(mainWidth, ChatLayoutModel.preferredMainWidthWithInspector)
        XCTAssertEqual(plan.gitWidth, 520)
        XCTAssertEqual(sidebarWidth + mainWidth + plan.gitWidth, 2_200)
    }

    func testMetricsPayloadPreservesWidthInvariantFields() throws {
        let payload = WindowLayoutModel.metricsPayload(from: WindowLayoutMetricsSnapshot(
            reason: "codex-history-render",
            windowWidth: 1452,
            windowHeight: 798,
            contentViewWidth: 1452,
            contentViewHeight: 798,
            contentControllerWidth: 1452,
            contentControllerHeight: 798,
            contentLayoutWidth: 1452,
            contentLayoutHeight: 746,
            rootSplitViewWidth: 1452,
            rootSplitViewHeight: 798,
            splitViewWidth: 1452,
            splitViewHeight: 798,
            splitViewX: 0,
            splitViewClass: "NSSplitView",
            rootSubviews: [
                WindowLayoutViewFrame(index: 0, className: "NSSplitView", x: 0, width: 1452, height: 798),
            ],
            requestedFrameWidth: 1452,
            requestedFrameHeight: 798,
            appliedFrameWidth: 1452,
            appliedFrameHeight: 798,
            screenVisibleWidth: 1512,
            screenVisibleHeight: 949,
            sidebarCollapsed: false,
            gitCollapsed: true,
            splitFrames: [
                WindowLayoutViewFrame(index: 0, className: "Sidebar", x: 0, width: 260, height: 798),
                WindowLayoutViewFrame(index: 1, className: "Main", x: 261, width: 1191, height: 798),
            ],
            chatViewWidth: 1191,
            chatViewHeight: 798,
            workspaceWidth: 1191,
            workspaceHeight: 798,
            mainSplitItemWidth: 1191,
            chatMetrics: ["composerWidth": 1163],
            workspaceMetrics: ["workspaceRootWidth": 1191]
        ))

        XCTAssertEqual(payload["reason"] as? String, "codex-history-render")
        XCTAssertEqual(payload["windowWidth"] as? Double, 1452)
        XCTAssertEqual(payload["splitViewWidth"] as? Double, 1452)
        XCTAssertEqual(payload["chatViewWidth"] as? Double, 1191)
        XCTAssertEqual(payload["workspaceWidth"] as? Double, 1191)
        XCTAssertEqual(payload["workspaceWidthSlack"] as? Double, 0)
        XCTAssertEqual(payload["gitCollapsed"] as? Bool, true)
        let rootSubviews = try XCTUnwrap(payload["rootSubviews"] as? [[String: Any]])
        XCTAssertEqual(rootSubviews.first?["class"] as? String, "NSSplitView")
        XCTAssertEqual((payload["chat"] as? [String: Any])?["composerWidth"] as? Int, 1163)
    }

    func testWorkspaceWidthSlackReportsDeadArea() {
        XCTAssertEqual(WindowLayoutModel.workspaceWidthSlack(mainSplitItemWidth: 1191, workspaceWidth: 1191), 0)
        XCTAssertEqual(WindowLayoutModel.workspaceWidthSlack(mainSplitItemWidth: 1191, workspaceWidth: 900), 291)
    }
}
