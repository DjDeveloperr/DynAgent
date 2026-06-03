import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class SidebarRowsChromeTests: XCTestCase {
    func testSingleLineLabelUsesTruncatingSidebarTextChrome() {
        let label = SidebarRowsChrome.singleLineLabel(
            "Upload IR receiver code",
            size: 14.5,
            weight: .regular,
            color: .secondaryLabelColor
        )

        XCTAssertEqual(label.stringValue, "Upload IR receiver code")
        XCTAssertEqual(label.font, .systemFont(ofSize: 14.5, weight: .regular))
        XCTAssertEqual(label.textColor, .secondaryLabelColor)
        XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(label.maximumNumberOfLines, 1)
        XCTAssertTrue(label.cell?.usesSingleLineMode ?? false)
        XCTAssertTrue(label.cell?.truncatesLastVisibleLine ?? false)
        XCTAssertEqual(label.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
    }

    func testActionRowBuildsAlignedIconAndLabel() {
        let row = SidebarRowsChrome.actionRow(symbol: "magnifyingglass", title: "Search") {}

        XCTAssertEqual(row.constraints.first { $0.firstAnchor == row.heightAnchor }?.constant, 36)
        XCTAssertEqual(row.descendantTextFields().map(\.stringValue), ["Search"])
        XCTAssertEqual(row.descendantImageViews().count, 1)
    }

    func testSectionHeaderReturnsHoverOnlyAddButtonWithTargetAction() throws {
        let target = Target()
        let section = SidebarRowsChrome.sectionHeader(
            title: "Projects",
            expanded: true,
            addSymbol: "folder.badge.plus",
            addToolTip: "Add workspace",
            addTarget: target,
            addAction: #selector(Target.addWorkspace),
            toggle: {}
        )

        let button = try XCTUnwrap(section.addButton)
        XCTAssertEqual(section.row.descendantTextFields().map(\.stringValue), ["Projects"])
        XCTAssertTrue(button.isHidden)
        XCTAssertEqual(button.toolTip, "Add workspace")
        XCTAssertTrue(button.target === target)
        XCTAssertEqual(button.action, #selector(Target.addWorkspace))
        XCTAssertTrue(section.row.descendantImageViews().contains { $0.isHidden })
    }

    func testWorkspaceHeaderBuildsSecondaryLabelAndHiddenNewChatButton() throws {
        let model = SidebarWorkspaceRowModel(
            name: "dynamic_agent",
            path: "/repo/dynamic_agent",
            tooltip: SidebarTooltipModel(title: "dynamic_agent", detail: "/repo/dynamic_agent"),
            hasChats: true
        )
        var newChatCount = 0

        let row = SidebarRowsChrome.workspaceHeader(
            model: model,
            onClick: {},
            onNewChat: { newChatCount += 1 },
            onHoverChanged: { _, _ in }
        )

        let label = try XCTUnwrap(row.descendantTextFields().first)
        XCTAssertEqual(label.stringValue, "dynamic_agent")
        XCTAssertEqual(label.textColor, .secondaryLabelColor)
        let button = try XCTUnwrap(row.descendantButtons().first)
        XCTAssertTrue(button.isHidden)
        XCTAssertEqual(button.toolTip, "New chat")
        button.performClick(nil)
        XCTAssertEqual(newChatCount, 1)
    }

    func testEmptyAndMoreRowsUseExpectedLabelsAndHeights() {
        let empty = SidebarRowsChrome.emptyWorkspaceRow()
        let more = SidebarRowsChrome.moreToggleRow(title: "Show 4 more") {}

        XCTAssertEqual(empty.descendantTextFields().map(\.stringValue), ["No chats"])
        XCTAssertEqual(empty.constraints.first { $0.firstAnchor == empty.heightAnchor }?.constant, 26)
        XCTAssertEqual(more.descendantTextFields().map(\.stringValue), ["Show 4 more"])
        XCTAssertEqual(more.constraints.first { $0.firstAnchor == more.heightAnchor }?.constant, 26)
    }
}

private final class Target: NSObject {
    @objc func addWorkspace() {}
}

private extension NSView {
    func descendantTextFields() -> [NSTextField] {
        descendants(of: NSTextField.self)
    }

    func descendantImageViews() -> [NSImageView] {
        descendants(of: NSImageView.self)
    }

    func descendantButtons() -> [NSButton] {
        descendants(of: NSButton.self)
    }

    func descendants<T: NSView>(of type: T.Type) -> [T] {
        var result: [T] = []
        if let match = self as? T {
            result.append(match)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendants(of: type))
        }
        return result
    }
}
