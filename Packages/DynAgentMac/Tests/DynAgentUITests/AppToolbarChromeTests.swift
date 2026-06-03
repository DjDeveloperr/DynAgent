import AppKit
import XCTest
@testable import DynAgentUI

final class AppToolbarChromeTests: XCTestCase {
    func testDefaultIdentifiersPreserveToolbarOrder() {
        XCTAssertEqual(AppToolbarID.defaultIdentifiers, [
            .toggleSidebar,
            AppToolbarID.navBack,
            AppToolbarID.navForward,
            .flexibleSpace,
            AppToolbarID.addWorkspace,
            .sidebarTrackingSeparator,
            AppToolbarID.chatTitle,
            .flexibleSpace,
            AppToolbarID.gitScope,
            AppToolbarID.gitCommit,
            AppToolbarID.git,
        ])
    }

    func testMainToolbarUsesMainIdentifierAndIconOnlyDisplay() {
        let toolbar = AppToolbarChrome.makeMainToolbar(delegate: Target())

        XCTAssertEqual(toolbar.identifier, "main")
        XCTAssertEqual(toolbar.displayMode, .iconOnly)
    }

    func testNavigationButtonConfiguration() {
        let target = Target()
        let button = AppToolbarChrome.configureNavigationButton(
            NSButton(),
            symbol: "chevron.left",
            target: target,
            action: #selector(Target.action),
            tooltip: "Back"
        )

        XCTAssertTrue(button.target === target)
        XCTAssertEqual(button.action, #selector(Target.action))
        XCTAssertEqual(button.toolTip, "Back")
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.contentTintColor, .secondaryLabelColor)
    }

    func testScopeItemAndChatTitleViewConfiguration() throws {
        let item = NSToolbarItem(itemIdentifier: AppToolbarID.gitScope)
        let control = NSSegmentedControl(labels: ["All", "Staged"], trackingMode: .selectOne, target: nil, action: nil)

        AppToolbarChrome.configureScopeItem(item, control: control)

        XCTAssertTrue(item.view === control)
        XCTAssertEqual(item.label, "Diff Scope")
        XCTAssertEqual(item.toolTip, "Show all or staged changes")

        let target = Target()
        let title = NSTextField(labelWithString: "Thread")
        let button = NSButton()
        let view = AppToolbarChrome.makeChatTitleView(
            titleLabel: title,
            menuButton: button,
            target: target,
            menuAction: #selector(Target.action)
        )

        let stack = try XCTUnwrap(view as? NSStackView)
        XCTAssertEqual(stack.orientation, .horizontal)
        XCTAssertEqual(stack.spacing, 8)
        XCTAssertTrue(button.target === target)
        XCTAssertEqual(button.action, #selector(Target.action))
        XCTAssertEqual(title.lineBreakMode, .byTruncatingTail)
    }

    private final class Target: NSObject, NSToolbarDelegate {
        @objc func action() {}
    }
}
