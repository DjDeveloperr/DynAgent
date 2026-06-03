@testable import DynAgentUI
import XCTest

final class AppDetachedChatWindowCoordinatorTests: XCTestCase {
    func testOpenCreatesShowsAndTracksDetachedWindow() {
        let conversation = makeConversation("one")
        let factory = DetachedWindowFactory()
        let coordinator = AppDetachedChatWindowCoordinator(makeWindow: factory.makeWindow)

        coordinator.open(conversation)

        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(factory.windows.count, 1)
        XCTAssertTrue(factory.windows[0].conversation === conversation)
        XCTAssertEqual(factory.windows[0].showCount, 1)
    }

    func testRefreshTargetsOnlyMatchingConversation() {
        let first = makeConversation("first")
        let second = makeConversation("second")
        let factory = DetachedWindowFactory()
        let coordinator = AppDetachedChatWindowCoordinator(makeWindow: factory.makeWindow)

        coordinator.open(first)
        coordinator.open(second)
        coordinator.refreshWindows(for: first, rerender: true)
        coordinator.refreshWindows(for: second, rerender: false)

        XCTAssertEqual(factory.windows[0].refreshCount, 1)
        XCTAssertEqual(factory.windows[0].refreshTitleCount, 0)
        XCTAssertEqual(factory.windows[1].refreshCount, 0)
        XCTAssertEqual(factory.windows[1].refreshTitleCount, 1)
    }

    func testCloseCallbackAndConversationRemovalUntrackWindows() {
        let first = makeConversation("first")
        let second = makeConversation("second")
        let factory = DetachedWindowFactory()
        let coordinator = AppDetachedChatWindowCoordinator(makeWindow: factory.makeWindow)

        coordinator.open(first)
        coordinator.open(second)
        factory.windows[0].close()

        XCTAssertEqual(coordinator.windowCount, 1)

        coordinator.removeWindows(for: second)

        XCTAssertEqual(coordinator.windowCount, 0)
    }
}

private final class DetachedWindowFactory {
    private var closeHandlers: [(any DetachedChatWindowRepresenting) -> Void] = []
    private(set) var windows: [FakeDetachedWindow] = []

    func makeWindow(
        conversation: Conversation,
        onClose: @escaping (any DetachedChatWindowRepresenting) -> Void
    ) -> any DetachedChatWindowRepresenting {
        let window = FakeDetachedWindow(conversation: conversation)
        closeHandlers.append(onClose)
        window.onClose = { [weak self, weak window] in
            guard let self, let window, let index = self.windows.firstIndex(where: { $0 === window }) else { return }
            self.closeHandlers[index](window)
        }
        windows.append(window)
        return window
    }
}

private final class FakeDetachedWindow: DetachedChatWindowRepresenting {
    let conversation: Conversation
    var showCount = 0
    var refreshCount = 0
    var refreshTitleCount = 0
    var onClose: (() -> Void)?

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    func show() {
        showCount += 1
    }

    func refresh() {
        refreshCount += 1
    }

    func refreshTitle() {
        refreshTitleCount += 1
    }

    func close() {
        onClose?()
    }
}

private func makeConversation(_ title: String) -> Conversation {
    let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
    conversation.title = title
    return conversation
}
