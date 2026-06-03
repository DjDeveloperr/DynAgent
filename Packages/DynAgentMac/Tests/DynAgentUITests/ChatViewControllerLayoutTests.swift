import AppKit
@testable import DynAgentUI
import XCTest

final class ChatViewControllerLayoutTests: XCTestCase {
    func testLoadedThreadKeepsChatContentTrackingWideContainer() {
        let controller = ChatViewController()
        controller.loadView()
        let host = host(controller, width: 900, height: 780)

        let conversation = Conversation(model: "gpt-5.5", workspace: "/Users/dj/Developer/dynamic_agent", harness: .codex)
        conversation.title = "Loaded width regression"
        conversation.needsLoad = true

        controller.showShell(conversation)
        layoutMounted(controller, in: host)
        assertLayout(
            in: controller,
            viewWidth: 900,
            expectedReadableWidth: Double(ChatLayoutModel.readableWidth(for: 900)),
            file: #filePath,
            line: #line
        )

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
        layoutMounted(controller, in: host)

        assertLayout(
            in: controller,
            viewWidth: 900,
            expectedReadableWidth: Double(ChatLayoutModel.readableWidth(for: 900)),
            file: #filePath,
            line: #line
        )
    }

    func testLoadedThreadCentersReadableColumnInWideContainer() {
        let controller = ChatViewController()
        controller.loadView()
        let host = host(controller, width: 1_320, height: 780)

        let conversation = Conversation(model: "gpt-5.5", workspace: "/Users/dj/Developer/dynamic_agent", harness: .codex)
        conversation.messages = [
            ChatMessage(role: .user, text: "Keep the canvas wide."),
            ChatMessage(role: .assistant, text: "The readable column is centered and capped."),
        ]
        conversation.messages[1].isFinal = true

        controller.show(conversation)
        layoutMounted(controller, in: host)

        assertLayout(
            in: controller,
            viewWidth: 1_320,
            expectedReadableWidth: Double(ChatLayoutModel.maxReadableWidth),
            file: #filePath,
            line: #line
        )
    }

    private func assertLayout(
        in controller: ChatViewController,
        viewWidth: Double,
        expectedReadableWidth: Double,
        file: StaticString,
        line: UInt
    ) {
        let metrics = controller.layoutMetrics
        guard let chatWidth = metrics["chatViewWidth"] as? Double,
              let scrollWidth = metrics["scrollWidth"] as? Double,
              let documentWidth = metrics["documentWidth"] as? Double,
              let transcriptWidth = metrics["transcriptWidth"] as? Double,
              let composerWidth = metrics["composerWidth"] as? Double else {
            XCTFail("Missing chat layout metrics", file: file, line: line)
            return
        }

        XCTAssertEqual(chatWidth, viewWidth, accuracy: 0.5, "chatViewWidth", file: file, line: line)
        XCTAssertEqual(scrollWidth, viewWidth, accuracy: 0.5, "scrollWidth", file: file, line: line)
        XCTAssertEqual(documentWidth, viewWidth, accuracy: 0.5, "documentWidth", file: file, line: line)
        XCTAssertEqual(transcriptWidth, expectedReadableWidth, accuracy: 0.5, "transcriptWidth", file: file, line: line)
        XCTAssertEqual(composerWidth, expectedReadableWidth, accuracy: 0.5, "composerWidth", file: file, line: line)
    }

    private func host(_ controller: ChatViewController, width: CGFloat, height: CGFloat) -> NSView {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        host.translatesAutoresizingMaskIntoConstraints = false
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(controller.view)
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: width),
            host.heightAnchor.constraint(equalToConstant: height),
            controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: host.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return host
    }

    private func layoutMounted(_ controller: ChatViewController, in host: NSView) {
        host.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
    }
}
