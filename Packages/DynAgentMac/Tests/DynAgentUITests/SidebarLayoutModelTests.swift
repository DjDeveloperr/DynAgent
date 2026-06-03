@testable import DynAgentUI
import XCTest

final class SidebarLayoutModelTests: XCTestCase {
    func testDefaultWidthBandMatchesAppLayoutContract() {
        XCTAssertEqual(SidebarLayoutModel.minimumWidth, 260)
        XCTAssertEqual(SidebarLayoutModel.maximumWidth, 320)
    }

    func testClampedWidthUsesSidebarBand() {
        XCTAssertEqual(SidebarLayoutModel.clampedWidth(120), SidebarLayoutModel.minimumWidth)
        XCTAssertEqual(SidebarLayoutModel.clampedWidth(300), 300)
        XCTAssertEqual(SidebarLayoutModel.clampedWidth(500), SidebarLayoutModel.maximumWidth)
    }

    func testSyncPlanUsesSidebarBandAndRequestsCodexCorrection() {
        let tooWide = SidebarLayoutModel.syncPlan(receivedWidth: 380)
        XCTAssertEqual(tooWide.appliedWidth, Double(SidebarLayoutModel.maximumWidth))
        XCTAssertEqual(tooWide.correctionPayload?["sidebarWidth"], Double(SidebarLayoutModel.maximumWidth))

        let inRange = SidebarLayoutModel.syncPlan(receivedWidth: 300)
        XCTAssertEqual(inRange.appliedWidth, 300)
        XCTAssertNil(inRange.correctionPayload)
    }
}
