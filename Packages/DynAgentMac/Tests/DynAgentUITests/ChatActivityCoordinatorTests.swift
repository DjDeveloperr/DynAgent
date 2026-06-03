@testable import DynAgentUI
import XCTest

final class ChatActivityCoordinatorTests: XCTestCase {
    func testEmitActivityUsesThrottleAndForceBypassesIt() {
        var now: TimeInterval = 100
        let coordinator = ChatActivityCoordinator(now: { now })
        let conversation = Conversation(model: "gpt-5.5")
        var emitted: [Conversation] = []

        coordinator.emitActivity(for: conversation) { emitted.append($0) }
        coordinator.emitActivity(for: conversation) { emitted.append($0) }
        now = 101
        coordinator.emitActivity(for: conversation) { emitted.append($0) }
        coordinator.emitActivity(for: conversation, force: true) { emitted.append($0) }

        XCTAssertEqual(emitted.count, 2)
        XCTAssertTrue(emitted[0] === conversation)
        XCTAssertTrue(emitted[1] === conversation)
    }

    func testToolRefreshSchedulesVisibleInactiveRenderingTools() {
        var scheduledDelay: TimeInterval?
        var scheduledItem: DispatchWorkItem?
        let coordinator = ChatActivityCoordinator(
            scheduler: { delay, item in
                scheduledDelay = delay
                scheduledItem = item
            }
        )
        let conversation = Conversation(model: "gpt-5.5")
        var refreshed: [Conversation] = []

        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .completedTool(name: "edit"),
            isVisible: true,
            isActive: false,
            shouldRefresh: { true },
            refresh: { refreshed.append($0) }
        )

        XCTAssertEqual(try XCTUnwrap(scheduledDelay), ChatToolRefreshModel.delay, accuracy: 0.001)
        scheduledItem?.perform()
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertTrue(refreshed.first === conversation)
    }

    func testToolRefreshSkipsHiddenActiveAndNonRenderingTools() {
        var scheduleCount = 0
        let coordinator = ChatActivityCoordinator(
            scheduler: { _, _ in scheduleCount += 1 }
        )
        let conversation = Conversation(model: "gpt-5.5")

        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .completedTool(name: "web"),
            isVisible: true,
            isActive: false,
            shouldRefresh: { true },
            refresh: { _ in }
        )
        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .completedTool(name: "edit"),
            isVisible: false,
            isActive: false,
            shouldRefresh: { true },
            refresh: { _ in }
        )
        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .streamDone,
            isVisible: true,
            isActive: true,
            shouldRefresh: { true },
            refresh: { _ in }
        )

        XCTAssertEqual(scheduleCount, 0)
    }

    func testToolRefreshCancelsEarlierPendingRefreshForSameConversation() {
        var scheduledItems: [DispatchWorkItem] = []
        let coordinator = ChatActivityCoordinator(
            scheduler: { _, item in scheduledItems.append(item) }
        )
        let conversation = Conversation(model: "gpt-5.5")
        var refreshCount = 0

        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .completedTool(name: "shell"),
            isVisible: true,
            isActive: false,
            shouldRefresh: { true },
            refresh: { _ in refreshCount += 1 }
        )
        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .streamDone,
            isVisible: true,
            isActive: false,
            shouldRefresh: { true },
            refresh: { _ in refreshCount += 1 }
        )

        XCTAssertEqual(scheduledItems.count, 2)
        XCTAssertTrue(scheduledItems[0].isCancelled)
        scheduledItems[0].perform()
        scheduledItems[1].perform()
        XCTAssertEqual(refreshCount, 1)
    }

    func testToolRefreshRechecksVisibilityBeforeRefreshing() {
        var scheduledItem: DispatchWorkItem?
        let coordinator = ChatActivityCoordinator(
            scheduler: { _, item in scheduledItem = item }
        )
        let conversation = Conversation(model: "gpt-5.5")
        var refreshCount = 0

        coordinator.scheduleToolRefresh(
            for: conversation,
            trigger: .streamDone,
            isVisible: true,
            isActive: false,
            shouldRefresh: { false },
            refresh: { _ in refreshCount += 1 }
        )

        scheduledItem?.perform()
        XCTAssertEqual(refreshCount, 0)
    }
}
