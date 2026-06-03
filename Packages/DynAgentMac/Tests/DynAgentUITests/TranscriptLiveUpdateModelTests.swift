@testable import DynAgentUI
import XCTest

final class TranscriptLiveUpdateModelTests: XCTestCase {
    func testMarkdownRenderAllowsFirstAndForcedUpdates() {
        XCTAssertTrue(TranscriptLiveUpdateModel.shouldRenderMarkdown(
            force: false,
            now: 100,
            lastRenderAt: nil
        ))
        XCTAssertTrue(TranscriptLiveUpdateModel.shouldRenderMarkdown(
            force: true,
            now: 100,
            lastRenderAt: 99.99
        ))
    }

    func testMarkdownRenderThrottlesUntilIntervalPasses() {
        XCTAssertFalse(TranscriptLiveUpdateModel.shouldRenderMarkdown(
            force: false,
            now: 100.2,
            lastRenderAt: 100,
            interval: 0.45
        ))
        XCTAssertTrue(TranscriptLiveUpdateModel.shouldRenderMarkdown(
            force: false,
            now: 100.45,
            lastRenderAt: 100,
            interval: 0.45
        ))
    }

    func testScrollThrottleOnlyAppliesWhileStreamingInsideInterval() {
        XCTAssertTrue(TranscriptLiveUpdateModel.shouldThrottleScroll(
            streaming: true,
            now: 100.1,
            lastScrollAt: 100,
            interval: 0.25
        ))
        XCTAssertFalse(TranscriptLiveUpdateModel.shouldThrottleScroll(
            streaming: true,
            now: 100.25,
            lastScrollAt: 100,
            interval: 0.25
        ))
        XCTAssertFalse(TranscriptLiveUpdateModel.shouldThrottleScroll(
            streaming: false,
            now: 100.1,
            lastScrollAt: 100,
            interval: 0.25
        ))
    }

    func testScrollPlanPerformsImmediatelyWhenIdleAndRequestsLayout() {
        let state = TranscriptScrollState(lastScrollAt: 100, hasPendingScroll: true)

        let plan = TranscriptLiveUpdateModel.scrollPlan(
            streaming: false,
            now: 100.1,
            state: state,
            interval: 0.25
        )

        XCTAssertEqual(plan.action, .perform(layoutBeforeScroll: true))
        XCTAssertEqual(plan.state.lastScrollAt, 100.1)
        XCTAssertFalse(plan.state.hasPendingScroll)
    }

    func testScrollPlanPerformsStreamingScrollWhenIntervalPassedWithoutLayout() {
        let state = TranscriptScrollState(lastScrollAt: 100, hasPendingScroll: true)

        let plan = TranscriptLiveUpdateModel.scrollPlan(
            streaming: true,
            now: 100.25,
            state: state,
            interval: 0.25
        )

        XCTAssertEqual(plan.action, .perform(layoutBeforeScroll: false))
        XCTAssertEqual(plan.state.lastScrollAt, 100.25)
        XCTAssertFalse(plan.state.hasPendingScroll)
    }

    func testScrollPlanSchedulesOnePendingScrollWhileStreamingInsideInterval() {
        let initial = TranscriptScrollState(lastScrollAt: 100, hasPendingScroll: false)

        let scheduled = TranscriptLiveUpdateModel.scrollPlan(
            streaming: true,
            now: 100.1,
            state: initial,
            interval: 0.25
        )
        XCTAssertEqual(scheduled.action, .schedule(delay: 0.25))
        XCTAssertEqual(scheduled.state.lastScrollAt, 100)
        XCTAssertTrue(scheduled.state.hasPendingScroll)

        let ignored = TranscriptLiveUpdateModel.scrollPlan(
            streaming: true,
            now: 100.12,
            state: scheduled.state,
            interval: 0.25
        )
        XCTAssertEqual(ignored.action, .ignorePending)
        XCTAssertEqual(ignored.state, scheduled.state)
    }

    func testPendingScrollFiredClearsPendingFlagWithoutChangingLastScroll() {
        let state = TranscriptScrollState(lastScrollAt: 100, hasPendingScroll: true)

        let fired = TranscriptLiveUpdateModel.pendingScrollFired(state: state)

        XCTAssertEqual(fired.lastScrollAt, 100)
        XCTAssertFalse(fired.hasPendingScroll)
    }
}
