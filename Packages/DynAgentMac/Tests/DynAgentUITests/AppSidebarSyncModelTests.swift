@testable import DynAgentUI
import XCTest

final class AppSidebarSyncModelTests: XCTestCase {
    func testWidthPlanClampsTooSmallWidthAndRequestsCorrection() {
        let plan = AppSidebarSyncModel.widthPlan(
            receivedWidth: 120,
            minimumWidth: 220,
            maximumWidth: 360
        )

        XCTAssertEqual(plan.appliedWidth, 220)
        XCTAssertEqual(plan.correctionPayload?["sidebarWidth"], 220)
    }

    func testWidthPlanClampsTooLargeWidthAndRequestsCorrection() {
        let plan = AppSidebarSyncModel.widthPlan(
            receivedWidth: 500,
            minimumWidth: 220,
            maximumWidth: 360
        )

        XCTAssertEqual(plan.appliedWidth, 360)
        XCTAssertEqual(plan.correctionPayload?["sidebarWidth"], 360)
    }

    func testWidthPlanKeepsInRangeWidthWithoutCorrection() {
        let plan = AppSidebarSyncModel.widthPlan(
            receivedWidth: 280,
            minimumWidth: 220,
            maximumWidth: 360
        )

        XCTAssertEqual(plan.appliedWidth, 280)
        XCTAssertNil(plan.correctionPayload)
    }

    func testWidthPlanMissingWidthDoesNothing() {
        let plan = AppSidebarSyncModel.widthPlan(
            receivedWidth: nil,
            minimumWidth: 220,
            maximumWidth: 360
        )

        XCTAssertNil(plan.appliedWidth)
        XCTAssertNil(plan.correctionPayload)
    }

    func testCollapsePayloadsMatchCodexSidebarContract() {
        let section = AppSidebarSyncModel.sectionPayload(section: "threads", collapsed: true)
        XCTAssertEqual(section["section"] as? String, "threads")
        XCTAssertEqual(section["sectionCollapsed"] as? Bool, true)

        let workspace = AppSidebarSyncModel.workspacePayload(path: "/repo/app", collapsed: false)
        XCTAssertEqual(workspace["groupPath"] as? String, "/repo/app")
        XCTAssertEqual(workspace["groupCollapsed"] as? Bool, false)
    }
}
