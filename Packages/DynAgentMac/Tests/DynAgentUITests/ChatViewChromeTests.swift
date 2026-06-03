import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class ChatViewChromeTests: XCTestCase {
    func testRootInstallsSubviewsAndKeepsLowHorizontalPriorities() {
        let scroll = NSView()
        let title = NSView()
        let menu = NSView()
        let card = NSView()
        let empty = NSView()
        let border = NSView()

        let root = ChatViewChrome.makeRoot(
            scroll: scroll,
            headerTitle: title,
            headerMenuButton: menu,
            composerCard: card,
            emptyStack: empty,
            topBorder: border
        )

        XCTAssertEqual(root.subviews, [scroll, title, menu, card, empty, border])
        XCTAssertEqual(root.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        XCTAssertEqual(root.contentHuggingPriority(for: .horizontal), .defaultLow)
    }

    func testTopBorderUsesSeparatorChrome() {
        let border = ChatViewChrome.makeTopBorder()

        XCTAssertEqual(border.boxType, .separator)
        XCTAssertFalse(border.translatesAutoresizingMaskIntoConstraints)
    }

    func testComposerConstraintsKeepCardCenteredReadableAndBottomPinned() throws {
        let root = NSView()
        let card = NSView()
        root.addSubview(card)

        let layout = ChatViewChrome.composerConstraints(root: root, card: card)

        XCTAssertEqual(layout.bottom.constant, -ChatViewChrome.composerBottomInset)
        XCTAssertFalse(layout.centerY.isActive)
        XCTAssertEqual(layout.centerY.constant, ChatViewChrome.composerEmptyStateCenterYOffset)
        XCTAssertTrue(layout.all.contains(layout.bottom))
        XCTAssertTrue(layout.all.contains {
            $0.firstItem === card
                && $0.firstAttribute == .leading
                && $0.relation == .greaterThanOrEqual
                && $0.secondItem === root
                && $0.constant == ChatLayoutModel.horizontalInset
        })
        XCTAssertTrue(layout.all.contains {
            $0.firstItem === card
                && $0.firstAttribute == .trailing
                && $0.relation == .lessThanOrEqual
                && $0.secondItem === root
                && $0.constant == -ChatLayoutModel.horizontalInset
        })
        XCTAssertTrue(layout.all.contains {
            $0.firstItem === card
                && $0.firstAttribute == .width
                && $0.relation == .lessThanOrEqual
                && $0.constant == ChatLayoutModel.maxReadableWidth
        })
        let fillWidth = try XCTUnwrap(layout.all.first {
            $0.firstItem === card
                && $0.firstAttribute == .width
                && $0.secondItem === root
                && $0.secondAttribute == .width
        })
        XCTAssertEqual(fillWidth.constant, -(ChatLayoutModel.horizontalInset * 2))
        XCTAssertEqual(fillWidth.priority, .defaultHigh)
    }

    func testEmptyStateAndTopBorderConstraintsUseSharedConstants() {
        let root = NSView()
        let scroll = NSView()
        let card = NSView()
        let empty = NSView()
        let border = NSView()
        for view in [scroll, card, empty, border] { root.addSubview(view) }

        let emptyConstraints = ChatViewChrome.emptyStateConstraints(emptyStack: empty, scroll: scroll, card: card)
        let borderConstraints = ChatViewChrome.topBorderConstraints(topBorder: border, root: root)

        XCTAssertTrue(emptyConstraints.contains {
            $0.firstItem === empty
                && $0.firstAttribute == .bottom
                && $0.secondItem === card
                && $0.secondAttribute == .top
                && $0.constant == -ChatViewChrome.emptyStackToComposerSpacing
        })
        XCTAssertTrue(emptyConstraints.contains {
            $0.firstItem === empty
                && $0.firstAttribute == .width
                && $0.relation == .lessThanOrEqual
                && $0.constant == ChatViewChrome.emptyStackMaxWidth
        })
        XCTAssertTrue(borderConstraints.contains {
            $0.firstItem === border && $0.firstAttribute == .top && $0.secondItem === root
        })
        XCTAssertTrue(borderConstraints.contains {
            $0.firstItem === border && $0.firstAttribute == .leading && $0.secondItem === root
        })
        XCTAssertTrue(borderConstraints.contains {
            $0.firstItem === border && $0.firstAttribute == .trailing && $0.secondItem === root
        })
    }
}
