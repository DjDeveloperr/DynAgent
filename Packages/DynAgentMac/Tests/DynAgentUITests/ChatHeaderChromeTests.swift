import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class ChatHeaderChromeTests: XCTestCase {
    func testConfiguresTitleAndMenuButton() {
        let title = NSTextField(labelWithString: "Thread title")
        let button = NSButton()
        let target = HeaderTarget()

        ChatHeaderChrome.configureTitle(title)
        ChatHeaderChrome.configureMenuButton(button, target: target, action: #selector(HeaderTarget.tap(_:)))

        XCTAssertEqual(title.font, ChatHeaderChrome.titleFont)
        XCTAssertEqual(title.textColor, .labelColor)
        XCTAssertEqual(title.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(title.maximumNumberOfLines, 1)
        XCTAssertTrue(title.isHidden)
        XCTAssertFalse(title.translatesAutoresizingMaskIntoConstraints)

        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.contentTintColor, .secondaryLabelColor)
        XCTAssertTrue(button.isHidden)
        XCTAssertEqual(button.target as? HeaderTarget, target)
        XCTAssertEqual(button.action, #selector(HeaderTarget.tap(_:)))
        XCTAssertFalse(button.translatesAutoresizingMaskIntoConstraints)
    }

    func testConstraintsPreserveHeaderPlacement() {
        let root = NSView()
        let title = NSTextField(labelWithString: "Thread title")
        let button = NSButton()

        let constraints = ChatHeaderChrome.constraints(title: title, menuButton: button, root: root)

        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == title.leadingAnchor && $0.secondAnchor == root.leadingAnchor && $0.constant == ChatHeaderChrome.titleLeadingInset
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == title.topAnchor && $0.secondAnchor == root.topAnchor && $0.constant == ChatHeaderChrome.titleTopInset
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == button.leadingAnchor && $0.secondAnchor == title.trailingAnchor && $0.constant == ChatHeaderChrome.titleToButtonSpacing
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == button.widthAnchor && $0.constant == ChatHeaderChrome.menuButtonSize.width
        })
        XCTAssertTrue(constraints.contains {
            $0.firstAnchor == button.heightAnchor && $0.constant == ChatHeaderChrome.menuButtonSize.height
        })
    }
}

private final class HeaderTarget: NSObject {
    @objc func tap(_ sender: NSButton) {}
}
