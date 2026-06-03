@testable import DynAgentUI
import AppKit
import XCTest

final class AppSearchOverlayCoordinatorTests: XCTestCase {
    func testShowCreatesRetainsAndPresentsOverlay() {
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [], backing: .buffered, defer: false)
        let factory = SearchOverlayFactory()
        let coordinator = AppSearchOverlayCoordinator(makeOverlay: factory.makeOverlay)

        coordinator.show(over: host)

        XCTAssertEqual(factory.overlays.count, 1)
        XCTAssertTrue(factory.overlays[0].shownWindow === host)
    }

    func testRepeatedShowReplacesCurrentOverlayButPresentsEachOne() {
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [], backing: .buffered, defer: false)
        let factory = SearchOverlayFactory()
        let coordinator = AppSearchOverlayCoordinator(makeOverlay: factory.makeOverlay)

        coordinator.show(over: host)
        coordinator.show(over: host)

        XCTAssertEqual(factory.overlays.count, 2)
        XCTAssertTrue(factory.overlays.allSatisfy { $0.shownWindow === host })
    }
}

private final class SearchOverlayFactory {
    private(set) var overlays: [FakeSearchOverlay] = []

    func makeOverlay() -> any SearchOverlayPresenting {
        let overlay = FakeSearchOverlay()
        overlays.append(overlay)
        return overlay
    }
}

private final class FakeSearchOverlay: SearchOverlayPresenting {
    private(set) weak var shownWindow: NSWindow?

    func show(over window: NSWindow) {
        shownWindow = window
    }
}
