@testable import DynAgentUI
import XCTest

final class ChatTitleModelTests: XCTestCase {
    func testDisplayTitleTrimsWhitespaceAndFallsBackForBlankOrNil() {
        XCTAssertEqual(ChatTitleModel.displayTitle("  Build UI  "), "Build UI")
        XCTAssertEqual(ChatTitleModel.displayTitle("   \n\t  "), "New Chat")
        XCTAssertEqual(ChatTitleModel.displayTitle(nil), "New Chat")
    }

    func testDisplayTitleForConversationUsesSameFallbackRule() {
        let conversation = Conversation(model: "gpt-5.5")
        conversation.title = "  Latest Thread  "
        XCTAssertEqual(ChatTitleModel.displayTitle(for: conversation), "Latest Thread")

        conversation.title = ""
        XCTAssertEqual(ChatTitleModel.displayTitle(for: conversation), "New Chat")
        XCTAssertEqual(ChatTitleModel.displayTitle(for: nil), "New Chat")
    }

    func testAcceptedGeneratedTitleTrimsAndRejectsFallbackTitles() {
        XCTAssertEqual(ChatTitleModel.acceptedGeneratedTitle("  Fix width bug  "), "Fix width bug")
        XCTAssertNil(ChatTitleModel.acceptedGeneratedTitle(""))
        XCTAssertNil(ChatTitleModel.acceptedGeneratedTitle(" \n\t "))
        XCTAssertNil(ChatTitleModel.acceptedGeneratedTitle(nil))
        XCTAssertNil(ChatTitleModel.acceptedGeneratedTitle("New Chat"))
        XCTAssertNil(ChatTitleModel.acceptedGeneratedTitle("  New Chat  "))
    }
}
