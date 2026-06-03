@testable import DynAgentUI
import XCTest

final class AppActivityRefreshModelTests: XCTestCase {
    func testActiveActivityWithinSidebarIntervalOnlyUpdatesDock() {
        let plan = AppActivityRefreshModel.activityPlan(
            isActive: true,
            now: 100.4,
            lastSidebarRefresh: 100,
            lastHistoryRefresh: 96,
            sidebarInterval: 1,
            historyInterval: 8
        )

        XCTAssertFalse(plan.refreshSidebar)
        XCTAssertTrue(plan.updateDockOnly)
        XCTAssertFalse(plan.refreshQuota)
        XCTAssertFalse(plan.reloadGit)
        XCTAssertFalse(plan.persist)
        XCTAssertNil(plan.nextSidebarRefresh)
        XCTAssertNil(plan.nextHistoryRefresh)
        XCTAssertNil(plan.nextGitReload)
    }

    func testActiveActivityRefreshesSidebarAndQuotaAfterIntervals() {
        let plan = AppActivityRefreshModel.activityPlan(
            isActive: true,
            now: 110,
            lastSidebarRefresh: 108,
            lastHistoryRefresh: 101,
            sidebarInterval: 1,
            historyInterval: 8
        )

        XCTAssertTrue(plan.refreshSidebar)
        XCTAssertFalse(plan.updateDockOnly)
        XCTAssertTrue(plan.refreshQuota)
        XCTAssertFalse(plan.reloadGit)
        XCTAssertFalse(plan.persist)
        XCTAssertEqual(plan.nextSidebarRefresh, 110)
        XCTAssertEqual(plan.nextHistoryRefresh, 110)
    }

    func testInactiveActivityAlwaysRefreshesSidebarQuotaGitAndPersists() {
        let plan = AppActivityRefreshModel.activityPlan(
            isActive: false,
            now: 120,
            lastSidebarRefresh: 119.9,
            lastHistoryRefresh: 119.9
        )

        XCTAssertTrue(plan.refreshSidebar)
        XCTAssertFalse(plan.updateDockOnly)
        XCTAssertTrue(plan.refreshQuota)
        XCTAssertTrue(plan.reloadGit)
        XCTAssertTrue(plan.persist)
        XCTAssertEqual(plan.nextSidebarRefresh, 120)
        XCTAssertEqual(plan.nextHistoryRefresh, 120)
        XCTAssertEqual(plan.nextGitReload, 120)
    }

    func testSelectedActiveCodexThreadRefreshRequiresRemoteActiveThreadOutsideInterval() {
        XCTAssertTrue(AppActivityRefreshModel.shouldRefreshSelectedActiveCodexThread(
            harness: .codex,
            status: .running,
            hasLocalStream: false,
            now: 103,
            lastRefresh: 100,
            interval: 2
        ))
        XCTAssertFalse(AppActivityRefreshModel.shouldRefreshSelectedActiveCodexThread(
            harness: .dynagent,
            status: .running,
            hasLocalStream: false,
            now: 103,
            lastRefresh: 100,
            interval: 2
        ))
        XCTAssertFalse(AppActivityRefreshModel.shouldRefreshSelectedActiveCodexThread(
            harness: .codex,
            status: .idle,
            hasLocalStream: false,
            now: 103,
            lastRefresh: 100,
            interval: 2
        ))
        XCTAssertFalse(AppActivityRefreshModel.shouldRefreshSelectedActiveCodexThread(
            harness: .codex,
            status: .running,
            hasLocalStream: true,
            now: 103,
            lastRefresh: 100,
            interval: 2
        ))
        XCTAssertFalse(AppActivityRefreshModel.shouldRefreshSelectedActiveCodexThread(
            harness: .codex,
            status: .thinking,
            hasLocalStream: false,
            now: 101.9,
            lastRefresh: 100,
            interval: 2
        ))
    }
}
