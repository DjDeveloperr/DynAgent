@testable import DynAgentUI
import XCTest

final class ChatToolRefreshModelTests: XCTestCase {
    func testCompletedEditAndShellToolsScheduleRefreshWhenVisibleAndInactive() {
        XCTAssertTrue(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .completedTool(name: "edit"),
            isVisible: true,
            isActive: false
        ))
        XCTAssertTrue(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .completedTool(name: "shell"),
            isVisible: true,
            isActive: false
        ))
    }

    func testCompletedNonRenderingToolsDoNotScheduleRefresh() {
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .completedTool(name: "web"),
            isVisible: true,
            isActive: false
        ))
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .completedTool(name: nil),
            isVisible: true,
            isActive: false
        ))
    }

    func testHiddenOrActiveConversationDoesNotScheduleRefresh() {
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .completedTool(name: "edit"),
            isVisible: false,
            isActive: false
        ))
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .completedTool(name: "edit"),
            isVisible: true,
            isActive: true
        ))
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .streamDone,
            isVisible: true,
            isActive: true
        ))
    }

    func testStreamDoneDoesNotScheduleTranscriptRebuild() {
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .streamDone,
            isVisible: true,
            isActive: false
        ))
        XCTAssertFalse(ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: .streamDone,
            isVisible: false,
            isActive: false
        ))
    }

    func testDelayMatchesDebouncedRenderWindow() {
        XCTAssertEqual(ChatToolRefreshModel.delay, 0.18, accuracy: 0.001)
    }
}
