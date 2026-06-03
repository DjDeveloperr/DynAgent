@testable import DynAgentUI
import XCTest

@MainActor
final class SidebarHoverTipCoordinatorTests: XCTestCase {
    func testSchedulesTooltipAfterDelay() {
        var scheduledDelay: TimeInterval?
        var scheduledItem: DispatchWorkItem?
        let coordinator = SidebarHoverTipCoordinator(
            scheduler: { delay, item in
                scheduledDelay = delay
                scheduledItem = item
            },
            canShow: { _ in true }
        )
        let row = SidebarRow(height: 24, onClick: {}, build: { _ in })
        var shown: [(String, String, SidebarRow)] = []

        coordinator.schedule(title: "Title", detail: "Detail", row: row) { title, detail, row in
            shown.append((title, detail, row))
        }

        XCTAssertEqual(try XCTUnwrap(scheduledDelay), SidebarHoverTipCoordinator.delay, accuracy: 0.001)
        scheduledItem?.perform()
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown[0].0, "Title")
        XCTAssertEqual(shown[0].1, "Detail")
        XCTAssertTrue(shown[0].2 === row)
    }

    func testSchedulingNewTooltipCancelsPreviousItem() throws {
        var scheduledItems: [DispatchWorkItem] = []
        let coordinator = SidebarHoverTipCoordinator(
            scheduler: { _, item in scheduledItems.append(item) },
            canShow: { _ in true }
        )
        let first = SidebarRow(height: 24, onClick: {}, build: { _ in })
        let second = SidebarRow(height: 24, onClick: {}, build: { _ in })
        var shownTitles: [String] = []

        coordinator.schedule(title: "First", detail: "", row: first) { title, _, _ in
            shownTitles.append(title)
        }
        coordinator.schedule(title: "Second", detail: "", row: second) { title, _, _ in
            shownTitles.append(title)
        }

        XCTAssertEqual(scheduledItems.count, 2)
        XCTAssertTrue(try XCTUnwrap(scheduledItems.first).isCancelled)
        scheduledItems[0].perform()
        scheduledItems[1].perform()
        XCTAssertEqual(shownTitles, ["Second"])
    }

    func testHideCancelsPendingTooltipAndRunsHideAction() throws {
        var scheduledItem: DispatchWorkItem?
        let coordinator = SidebarHoverTipCoordinator(
            scheduler: { _, item in scheduledItem = item },
            canShow: { _ in true }
        )
        let row = SidebarRow(height: 24, onClick: {}, build: { _ in })
        var didHide = false
        var didShow = false

        coordinator.schedule(title: "Title", detail: "", row: row) { _, _, _ in
            didShow = true
        }
        coordinator.hide {
            didHide = true
        }

        XCTAssertTrue(try XCTUnwrap(scheduledItem).isCancelled)
        scheduledItem?.perform()
        XCTAssertTrue(didHide)
        XCTAssertFalse(didShow)
    }

    func testDoesNotShowWhenRowIsNoLongerEligible() {
        var scheduledItem: DispatchWorkItem?
        let coordinator = SidebarHoverTipCoordinator(
            scheduler: { _, item in scheduledItem = item },
            canShow: { _ in false }
        )
        let row = SidebarRow(height: 24, onClick: {}, build: { _ in })
        var didShow = false

        coordinator.schedule(title: "Title", detail: "", row: row) { _, _, _ in
            didShow = true
        }
        scheduledItem?.perform()

        XCTAssertFalse(didShow)
    }
}
