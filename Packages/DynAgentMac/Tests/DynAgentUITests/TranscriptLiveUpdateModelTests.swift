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
}
