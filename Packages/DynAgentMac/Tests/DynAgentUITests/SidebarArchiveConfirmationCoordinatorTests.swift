@testable import DynAgentUI
import XCTest

final class SidebarArchiveConfirmationCoordinatorTests: XCTestCase {
    func testFirstClickShowsConfirmationAndSecondClickConfirms() {
        let coordinator = SidebarArchiveConfirmationCoordinator()
        var showCount = 0
        var confirmCount = 0

        coordinator.clickArchive(conversationId: "chat-1") {
            showCount += 1
        } confirmArchive: {
            confirmCount += 1
        }
        XCTAssertTrue(coordinator.isConfirming(conversationId: "chat-1"))

        coordinator.clickArchive(conversationId: "chat-1") {
            showCount += 1
        } confirmArchive: {
            confirmCount += 1
        }

        XCTAssertEqual(showCount, 1)
        XCTAssertEqual(confirmCount, 1)
        XCTAssertFalse(coordinator.hasPendingArchive)
    }

    func testClickingDifferentConversationMovesConfirmation() {
        let coordinator = SidebarArchiveConfirmationCoordinator()
        var showCount = 0

        coordinator.clickArchive(conversationId: "chat-1") {
            showCount += 1
        } confirmArchive: {
            XCTFail("First click should not confirm")
        }
        coordinator.clickArchive(conversationId: "chat-2") {
            showCount += 1
        } confirmArchive: {
            XCTFail("Different conversation should not confirm")
        }

        XCTAssertEqual(showCount, 2)
        XCTAssertFalse(coordinator.isConfirming(conversationId: "chat-1"))
        XCTAssertTrue(coordinator.isConfirming(conversationId: "chat-2"))
    }

    func testHoverOutSchedulesCancelAndReloadsWhenTimerFires() {
        var scheduledDelay: TimeInterval?
        var scheduledItem: DispatchWorkItem?
        let coordinator = SidebarArchiveConfirmationCoordinator(
            scheduler: { delay, item in
                scheduledDelay = delay
                scheduledItem = item
            }
        )
        var reloadCount = 0

        coordinator.clickArchive(conversationId: "chat-1") {
        } confirmArchive: {
            XCTFail("First click should not confirm")
        }
        coordinator.updateHover(hovering: false, conversationId: "chat-1") {
            reloadCount += 1
        }

        XCTAssertEqual(try XCTUnwrap(scheduledDelay), SidebarArchiveConfirmationModel.cancelDelay, accuracy: 0.001)
        scheduledItem?.perform()
        XCTAssertEqual(reloadCount, 1)
        XCTAssertFalse(coordinator.hasPendingArchive)
    }

    func testHoverBackInCancelsScheduledCancel() {
        var scheduledItem: DispatchWorkItem?
        let coordinator = SidebarArchiveConfirmationCoordinator(
            scheduler: { _, item in scheduledItem = item }
        )
        var reloadCount = 0

        coordinator.clickArchive(conversationId: "chat-1") {
        } confirmArchive: {
            XCTFail("First click should not confirm")
        }
        coordinator.updateHover(hovering: false, conversationId: "chat-1") {
            reloadCount += 1
        }
        coordinator.updateHover(hovering: true, conversationId: "chat-1") {
            reloadCount += 1
        }

        XCTAssertTrue(try XCTUnwrap(scheduledItem).isCancelled)
        scheduledItem?.perform()
        XCTAssertEqual(reloadCount, 0)
        XCTAssertTrue(coordinator.hasPendingArchive)
    }

    func testImmediateCancelReloadsOnlyWhenPending() {
        let coordinator = SidebarArchiveConfirmationCoordinator()
        var reloadCount = 0

        coordinator.cancelPending(immediate: true) {
            reloadCount += 1
        }
        coordinator.clickArchive(conversationId: "chat-1") {
        } confirmArchive: {
            XCTFail("First click should not confirm")
        }
        coordinator.cancelPending(immediate: true) {
            reloadCount += 1
        }

        XCTAssertEqual(reloadCount, 1)
        XCTAssertFalse(coordinator.hasPendingArchive)
    }
}
