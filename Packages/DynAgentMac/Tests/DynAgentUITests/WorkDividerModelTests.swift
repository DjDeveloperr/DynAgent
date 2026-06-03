import XCTest
@testable import DynAgentUI

final class WorkDividerModelTests: XCTestCase {
    func testDurationTextUsesWorkingAndWorkedLabels() {
        XCTAssertEqual(WorkDividerModel.durationText(seconds: nil, active: true), "Working for 0s")
        XCTAssertEqual(WorkDividerModel.durationText(seconds: 0.4, active: true), "Working for 0s")
        XCTAssertEqual(WorkDividerModel.durationText(seconds: 1.5, active: true), "Working for 2s")
        XCTAssertEqual(WorkDividerModel.durationText(seconds: 61, active: false), "Worked for 1m 1s")
    }

    func testLabelOmitsChevronForActiveTurnsAndShowsChevronForCompletedTurns() {
        XCTAssertEqual(WorkDividerModel.label(seconds: 7, active: true, collapsed: false), "Working for 7s")
        XCTAssertEqual(WorkDividerModel.label(seconds: 7, active: false, collapsed: true), "▸  Worked for 7s")
        XCTAssertEqual(WorkDividerModel.label(seconds: 7, active: false, collapsed: false), "▾  Worked for 7s")
    }
}
