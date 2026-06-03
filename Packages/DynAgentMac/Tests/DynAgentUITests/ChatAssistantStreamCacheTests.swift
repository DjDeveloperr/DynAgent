@testable import DynAgentUI
import XCTest

final class ChatAssistantStreamCacheTests: XCTestCase {
    func testCachesAssistantsPerConversationAndAdoptsVisibleAssistant() {
        let cache = ChatAssistantStreamCache()
        let firstConversation = Conversation(model: "gpt-5.5")
        let secondConversation = Conversation(model: "gpt-5.5")
        let firstAssistant = ChatMessage(role: .assistant, text: "first")
        let secondAssistant = ChatMessage(role: .assistant, text: "second")

        cache.setAssistant(firstAssistant, for: firstConversation, visible: true)
        cache.setAssistant(secondAssistant, for: secondConversation, visible: false)

        XCTAssertTrue(cache.cachedAssistant(for: firstConversation) === firstAssistant)
        XCTAssertTrue(cache.cachedAssistant(for: secondConversation) === secondAssistant)
        XCTAssertTrue(cache.finalizableAssistant(for: firstConversation, visible: true) === firstAssistant)
        XCTAssertTrue(cache.adoptVisibleAssistant(for: secondConversation) === secondAssistant)
        XCTAssertTrue(cache.finalizableAssistant(for: secondConversation, visible: true) === secondAssistant)
    }

    func testClearingHiddenConversationDoesNotClearVisibleFallback() {
        let cache = ChatAssistantStreamCache()
        let visibleConversation = Conversation(model: "gpt-5.5")
        let hiddenConversation = Conversation(model: "gpt-5.5")
        let visibleAssistant = ChatMessage(role: .assistant, text: "visible")
        let hiddenAssistant = ChatMessage(role: .assistant, text: "hidden")

        cache.setAssistant(visibleAssistant, for: visibleConversation, visible: true)
        cache.setAssistant(hiddenAssistant, for: hiddenConversation, visible: false)
        cache.clearAssistant(for: hiddenConversation, visible: false)

        XCTAssertNil(cache.cachedAssistant(for: hiddenConversation))
        XCTAssertTrue(cache.finalizableAssistant(for: visibleConversation, visible: true) === visibleAssistant)
    }

    func testClearingVisibleConversationRemovesVisibleFallback() {
        let cache = ChatAssistantStreamCache()
        let conversation = Conversation(model: "gpt-5.5")
        let assistant = ChatMessage(role: .assistant, text: "streaming")

        cache.setAssistant(assistant, for: conversation, visible: true)
        cache.clearAssistant(for: conversation, visible: true)

        XCTAssertNil(cache.cachedAssistant(for: conversation))
        XCTAssertNil(cache.finalizableAssistant(for: conversation, visible: true))
    }

    func testAdoptingConversationWithoutCachedAssistantClearsVisibleFallback() {
        let cache = ChatAssistantStreamCache()
        let firstConversation = Conversation(model: "gpt-5.5")
        let secondConversation = Conversation(model: "gpt-5.5")
        let assistant = ChatMessage(role: .assistant, text: "first")

        cache.setAssistant(assistant, for: firstConversation, visible: true)
        XCTAssertNil(cache.adoptVisibleAssistant(for: secondConversation))

        XCTAssertNil(cache.finalizableAssistant(for: secondConversation, visible: true))
    }
}
