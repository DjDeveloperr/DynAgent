@testable import DynAgentUI
import XCTest

final class SidebarArchiveConfirmationModelTests: XCTestCase {
    func testFirstArchiveClickShowsConfirmationForConversation() {
        let action = SidebarArchiveConfirmationModel.clickArchive(
            conversationId: "chat-1",
            state: .idle
        )

        XCTAssertEqual(action, .showConfirmation(SidebarArchiveConfirmationState(pendingConversationId: "chat-1")))
    }

    func testSecondArchiveClickOnSameConversationConfirmsAndClearsState() {
        let state = SidebarArchiveConfirmationState(pendingConversationId: "chat-1")

        let action = SidebarArchiveConfirmationModel.clickArchive(
            conversationId: "chat-1",
            state: state
        )

        XCTAssertEqual(action, .confirmArchive(.idle))
    }

    func testArchiveClickOnDifferentConversationMovesConfirmation() {
        let state = SidebarArchiveConfirmationState(pendingConversationId: "chat-1")

        let action = SidebarArchiveConfirmationModel.clickArchive(
            conversationId: "chat-2",
            state: state
        )

        XCTAssertEqual(action, .showConfirmation(SidebarArchiveConfirmationState(pendingConversationId: "chat-2")))
    }

    func testHoverCancellationOnlyAppliesToPendingConversation() {
        let state = SidebarArchiveConfirmationState(pendingConversationId: "chat-1")

        XCTAssertTrue(SidebarArchiveConfirmationModel.shouldScheduleCancel(
            hovering: false,
            conversationId: "chat-1",
            state: state
        ))
        XCTAssertFalse(SidebarArchiveConfirmationModel.shouldScheduleCancel(
            hovering: false,
            conversationId: "chat-2",
            state: state
        ))
        XCTAssertTrue(SidebarArchiveConfirmationModel.shouldCancelScheduledCancel(
            hovering: true,
            conversationId: "chat-1",
            state: state
        ))
        XCTAssertFalse(SidebarArchiveConfirmationModel.shouldCancelScheduledCancel(
            hovering: false,
            conversationId: "chat-1",
            state: state
        ))
    }

    func testCancelClearsStateAndReportsWhetherReloadIsNeeded() {
        let active = SidebarArchiveConfirmationModel.cancel(
            state: SidebarArchiveConfirmationState(pendingConversationId: "chat-1")
        )
        let idle = SidebarArchiveConfirmationModel.cancel(state: .idle)

        XCTAssertEqual(active.state, .idle)
        XCTAssertTrue(active.shouldReload)
        XCTAssertEqual(idle.state, .idle)
        XCTAssertFalse(idle.shouldReload)
    }
}
