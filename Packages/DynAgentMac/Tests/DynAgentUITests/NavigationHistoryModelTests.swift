@testable import DynAgentUI
import XCTest

final class NavigationHistoryModelTests: XCTestCase {
    func testRecordLeavingDeduplicatesCurrentAndClearsForward() {
        let a = NavItem("a")
        let b = NavItem("b")
        let c = NavItem("c")
        var history = NavigationHistoryModel<NavItem>()

        history.recordLeaving(current: a, to: b)
        _ = history.goBack(from: b)
        XCTAssertTrue(history.canGoForward)

        history.recordLeaving(current: a, to: c)
        history.recordLeaving(current: a, to: c)

        XCTAssertEqual(history.backStack.map(\.id), ["a"])
        XCTAssertFalse(history.canGoForward)
    }

    func testBackAndForwardMoveCurrentBetweenStacks() {
        let a = NavItem("a")
        let b = NavItem("b")
        let c = NavItem("c")
        var history = NavigationHistoryModel<NavItem>()

        history.recordLeaving(current: a, to: b)
        history.recordLeaving(current: b, to: c)

        XCTAssertTrue(history.canGoBack)
        XCTAssertTrue(history.goBack(from: c) === b)
        XCTAssertEqual(history.backStack.map(\.id), ["a"])
        XCTAssertEqual(history.forwardStack.map(\.id), ["c"])

        XCTAssertTrue(history.goForward(from: b) === c)
        XCTAssertEqual(history.backStack.map(\.id), ["a", "b"])
        XCTAssertFalse(history.canGoForward)
    }

    func testRecordIgnoresSameObjectAndCapsBackStack() {
        let a = NavItem("a")
        var history = NavigationHistoryModel<NavItem>(maxDepth: 2)

        history.recordLeaving(current: a, to: a)
        XCTAssertFalse(history.canGoBack)

        let b = NavItem("b")
        let c = NavItem("c")
        let d = NavItem("d")
        history.recordLeaving(current: a, to: b)
        history.recordLeaving(current: b, to: c)
        history.recordLeaving(current: c, to: d)

        XCTAssertEqual(history.backStack.map(\.id), ["b", "c"])
    }
}

private final class NavItem {
    let id: String

    init(_ id: String) {
        self.id = id
    }
}
