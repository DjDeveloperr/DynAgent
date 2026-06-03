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
        XCTAssertEqual(plan.gitWidth, 520)
        XCTAssertEqual(plan.firstDividerPosition, 380)
        XCTAssertEqual(plan.secondDividerPosition, 932)
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
}
