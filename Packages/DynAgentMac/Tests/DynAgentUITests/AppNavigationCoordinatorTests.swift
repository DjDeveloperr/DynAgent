@testable import DynAgentUI
import XCTest

final class AppNavigationCoordinatorTests: XCTestCase {
    func testCurrentConversationOnlyAllowsVisibleLocalOrCodexConversations() {
        let local = conversation("local")
        let codex = conversation("codex")
        let draft = conversation("draft")
        let coordinator = AppNavigationCoordinator()

        XCTAssertTrue(coordinator.currentConversation(
            displayed: local,
            localConversations: [local],
            codexStubs: [:]
        ) === local)
        XCTAssertTrue(coordinator.currentConversation(
            displayed: codex,
            localConversations: [],
            codexStubs: ["/repo": [codex]]
        ) === codex)
        XCTAssertNil(coordinator.currentConversation(
            displayed: draft,
            localConversations: [local],
            codexStubs: ["/repo": [codex]]
        ))
        XCTAssertNil(coordinator.currentConversation(
            displayed: nil,
            localConversations: [local],
            codexStubs: ["/repo": [codex]]
        ))
    }

    func testRecordLeavingEnablesBackAndClearsForward() {
        let a = conversation("a")
        let b = conversation("b")
        let c = conversation("c")
        let coordinator = AppNavigationCoordinator()

        var state = coordinator.recordLeaving(
            displayed: a,
            localConversations: [a, b, c],
            codexStubs: [:],
            to: b
        )
        XCTAssertEqual(state, AppNavigationState(canGoBack: true, canGoForward: false))

        XCTAssertTrue(coordinator.goBack(
            displayed: b,
            localConversations: [a, b, c],
            codexStubs: [:]
        ) === a)
        XCTAssertEqual(coordinator.state, AppNavigationState(canGoBack: false, canGoForward: true))

        state = coordinator.recordLeaving(
            displayed: a,
            localConversations: [a, b, c],
            codexStubs: [:],
            to: c
        )
        XCTAssertEqual(state, AppNavigationState(canGoBack: true, canGoForward: false))
    }

    func testBackAndForwardUseCurrentCodexConversation() {
        let local = conversation("local")
        let codex = conversation("codex")
        let coordinator = AppNavigationCoordinator()

        coordinator.recordLeaving(
            displayed: local,
            localConversations: [local],
            codexStubs: ["/repo": [codex]],
            to: codex
        )

        XCTAssertTrue(coordinator.goBack(
            displayed: codex,
            localConversations: [local],
            codexStubs: ["/repo": [codex]]
        ) === local)
        XCTAssertTrue(coordinator.goForward(
            displayed: local,
            localConversations: [local],
            codexStubs: ["/repo": [codex]]
        ) === codex)
        XCTAssertEqual(coordinator.state, AppNavigationState(canGoBack: true, canGoForward: false))
    }

    func testNewChatRecordsCurrentButDraftDoesNotEnterHistory() {
        let existing = conversation("existing")
        let draft = conversation("draft")
        let coordinator = AppNavigationCoordinator()

        XCTAssertEqual(coordinator.recordLeaving(
            displayed: existing,
            localConversations: [existing],
            codexStubs: [:],
            to: nil
        ), AppNavigationState(canGoBack: true, canGoForward: false))

        XCTAssertTrue(coordinator.goBack(
            displayed: draft,
            localConversations: [existing],
            codexStubs: [:]
        ) === existing)
        XCTAssertEqual(coordinator.state, AppNavigationState(canGoBack: false, canGoForward: false))
    }
}

private func conversation(_ title: String) -> Conversation {
    let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
    conversation.title = title
    return conversation
}
