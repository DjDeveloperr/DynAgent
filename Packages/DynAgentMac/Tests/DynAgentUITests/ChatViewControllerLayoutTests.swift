import AppKit
@testable import DynAgentUI
import XCTest

final class ChatViewControllerLayoutTests: XCTestCase {
    func testLoadedThreadKeepsChatContentTrackingWideContainer() {
        let controller = ChatViewController()
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1180, height: 780)

        let conversation = Conversation(model: "gpt-5.5", workspace: "/Users/dj/Developer/dynamic_agent", harness: .codex)
        conversation.title = "Loaded width regression"
        conversation.needsLoad = true

        controller.showShell(conversation)
        controller.view.layoutSubtreeIfNeeded()
        assertLayout(in: controller, viewWidth: 1180, file: #filePath, line: #line)

        conversation.needsLoad = false
        conversation.messages = [
            ChatMessage(role: .user, text: "Why is the width wrong after the latest thread loads?"),
            ChatMessage(
                role: .assistant,
                text: """
                The loaded transcript should keep wrapping inside the current chat width.

                - It should not install stale narrow row constraints.
                - It should not make the split view reserve dead space.
                """,
                toolName: nil,
                toolDetail: nil
            ),
        ]
        conversation.messages[1].isFinal = true
        conversation.messages[1].turnDuration = 12

        controller.show(conversation)
        controller.view.layoutSubtreeIfNeeded()

        assertLayout(in: controller, viewWidth: 1180, file: #filePath, line: #line)
    }

    private func assertLayout(
        in controller: ChatViewController,
        viewWidth: Double,
        file: StaticString,
        line: UInt
    ) {
        let metrics = controller.layoutMetrics
        guard let chatWidth = metrics["chatViewWidth"] as? Double,
              let documentWidth = metrics["documentWidth"] as? Double,
              let transcriptWidth = metrics["transcriptWidth"] as? Double,
              let composerWidth = metrics["composerWidth"] as? Double else {
            XCTFail("Missing chat layout metrics", file: file, line: line)
            return
        }

        XCTAssertEqual(chatWidth, viewWidth, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(documentWidth, viewWidth, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(transcriptWidth, viewWidth - (ChatLayoutModel.horizontalInset * 2), accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(composerWidth, viewWidth - (ChatLayoutModel.horizontalInset * 2), accuracy: 0.5, file: file, line: line)
    }
}
