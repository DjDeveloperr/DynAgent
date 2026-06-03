import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class TranscriptScrollCoordinatorTests: XCTestCase {
    func testIdleScrollPerformsImmediatelyAndRequestsLayout() {
        let now: TimeInterval = 100
        let coordinator = TranscriptScrollCoordinator(now: { now })
        let fixture = ScrollFixture(documentHeight: 900, viewportHeight: 240, bottomInset: 80)

        coordinator.scrollToBottom(streaming: false, root: fixture.root, scroll: fixture.scroll)

        XCTAssertEqual(fixture.root.layoutCount, 1)
        XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, fixture.expectedBottomY, accuracy: 0.5)
        XCTAssertEqual(coordinator.state.lastScrollAt, 100)
        XCTAssertFalse(coordinator.state.hasPendingScroll)
    }

    func testStreamingScrollInsideIntervalSchedulesThenPerformsWithoutLayout() {
        var now: TimeInterval = 100.10
        var scheduledDelay: TimeInterval?
        var scheduledBlock: (() -> Void)?
        let coordinator = TranscriptScrollCoordinator(
            state: TranscriptScrollState(lastScrollAt: 100, hasPendingScroll: false),
            now: { now },
            scheduler: { delay, block in
                scheduledDelay = delay
                scheduledBlock = block
            }
        )
        let fixture = ScrollFixture(documentHeight: 700, viewportHeight: 200, bottomInset: 30)

        coordinator.scrollToBottom(streaming: true, root: fixture.root, scroll: fixture.scroll)

        XCTAssertEqual(scheduledDelay, TranscriptLiveUpdateModel.scrollInterval)
        XCTAssertNotNil(scheduledBlock)
        XCTAssertTrue(coordinator.state.hasPendingScroll)
        XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, 0, accuracy: 0.5)

        now = 100.30
        scheduledBlock?()

        XCTAssertEqual(fixture.root.layoutCount, 0)
        XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, fixture.expectedBottomY, accuracy: 0.5)
        XCTAssertEqual(coordinator.state.lastScrollAt, 100.30, accuracy: 0.001)
        XCTAssertFalse(coordinator.state.hasPendingScroll)
    }

    func testDuplicateStreamingScrollWhilePendingDoesNotScheduleAgain() {
        var scheduledCount = 0
        let coordinator = TranscriptScrollCoordinator(
            state: TranscriptScrollState(lastScrollAt: 100, hasPendingScroll: false),
            now: { 100.10 },
            scheduler: { _, _ in scheduledCount += 1 }
        )
        let fixture = ScrollFixture(documentHeight: 600, viewportHeight: 200, bottomInset: 0)

        coordinator.scrollToBottom(streaming: true, root: fixture.root, scroll: fixture.scroll)
        coordinator.scrollToBottom(streaming: true, root: fixture.root, scroll: fixture.scroll)

        XCTAssertEqual(scheduledCount, 1)
        XCTAssertTrue(coordinator.state.hasPendingScroll)
        XCTAssertEqual(fixture.scroll.contentView.bounds.origin.y, 0, accuracy: 0.5)
    }
}

@MainActor
private final class ScrollFixture {
    let root = LayoutCountingView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))

    init(documentHeight: CGFloat, viewportHeight: CGFloat, bottomInset: CGFloat) {
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 420, height: documentHeight))
        scroll.documentView = document
        scroll.contentView.frame = NSRect(x: 0, y: 0, width: 420, height: viewportHeight)
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        root.addSubview(scroll)
    }

    var expectedBottomY: CGFloat {
        guard let document = scroll.documentView else { return 0 }
        return max(0, document.bounds.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height)
    }
}

private final class LayoutCountingView: NSView {
    var layoutCount = 0

    override func layoutSubtreeIfNeeded() {
        layoutCount += 1
        super.layoutSubtreeIfNeeded()
    }
}
