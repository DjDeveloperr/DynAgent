@testable import DynAgentUI
import XCTest

final class ChatTitleGenerationCoordinatorTests: XCTestCase {
    func testGenerateAcceptsTitleMutatesConversationAndCallsCallback() async {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.title = "Old Title"
        var callbackTitle: String?
        var callbackConversation: Conversation?
        let coordinator = ChatTitleGenerationCoordinator { _, _ in "  Better Width Debugging  " }

        let title = await coordinator.generate(
            for: conversation,
            prompt: "fix the loaded width",
            model: "gpt-5.5"
        ) { conversation, title in
            callbackConversation = conversation
            callbackTitle = title
        }

        XCTAssertEqual(title, "Better Width Debugging")
        XCTAssertEqual(conversation.title, "Better Width Debugging")
        XCTAssertTrue(callbackConversation === conversation)
        XCTAssertEqual(callbackTitle, "Better Width Debugging")
    }

    func testGenerateRejectsFallbackOrBlankTitlesWithoutMutatingOrCallingBack() async {
        for rejected in ["New Chat", "  New Chat  ", "", "   \n\t"] {
            let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
            conversation.title = "Existing Title"
            var callbackCount = 0
            let coordinator = ChatTitleGenerationCoordinator { _, _ in rejected }

            let title = await coordinator.generate(
                for: conversation,
                prompt: "anything",
                model: "gpt-5.5"
            ) { _, _ in
                callbackCount += 1
            }

            XCTAssertNil(title)
            XCTAssertEqual(conversation.title, "Existing Title")
            XCTAssertEqual(callbackCount, 0)
        }
    }

    func testGeneratePassesPromptAndModelToLoader() async {
        var requests: [(prompt: String, model: String)] = []
        let coordinator = ChatTitleGenerationCoordinator { prompt, model in
            requests.append((prompt, model))
            return "Accepted"
        }

        _ = await coordinator.generate(
            for: Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex),
            prompt: "make chat fast",
            model: "gpt-5.5-high"
        ) { _, _ in }

        XCTAssertEqual(requests.map(\.prompt), ["make chat fast"])
        XCTAssertEqual(requests.map(\.model), ["gpt-5.5-high"])
    }
}
