import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class ChatEmptyStateChromeTests: XCTestCase {
    func testConfiguresTitleSubtitleAndStacks() {
        let title = NSTextField(labelWithString: "Start a conversation")
        let subtitle = NSTextField(labelWithString: "Workspace")
        let actions = NSStackView()
        let stack = NSStackView()

        ChatEmptyStateChrome.configureTitle(title)
        ChatEmptyStateChrome.configureSubtitle(subtitle)
        ChatEmptyStateChrome.configureActions(actions)
        ChatEmptyStateChrome.configureStack(stack, title: title, subtitle: subtitle, actions: actions)

        XCTAssertEqual(ChatEmptyStateChrome.titleFont, DesignSystem.Font.emptyStateTitle)
        XCTAssertEqual(ChatEmptyStateChrome.subtitleFont, DesignSystem.Font.emptyStateSubtitle)
        XCTAssertEqual(ChatEmptyStateChrome.stackSpacing, DesignSystem.Spacing.large)
        XCTAssertEqual(ChatEmptyStateChrome.actionSpacing, DesignSystem.Spacing.large)
        XCTAssertEqual(title.font, ChatEmptyStateChrome.titleFont)
        XCTAssertEqual(title.alignment, .center)
        XCTAssertEqual(subtitle.font, ChatEmptyStateChrome.subtitleFont)
        XCTAssertEqual(subtitle.textColor, .secondaryLabelColor)
        XCTAssertEqual(subtitle.maximumNumberOfLines, 3)
        XCTAssertEqual(subtitle.preferredMaxLayoutWidth, ChatEmptyStateChrome.subtitleMaxWidth)
        XCTAssertEqual(actions.orientation, .horizontal)
        XCTAssertEqual(actions.alignment, .centerY)
        XCTAssertEqual(actions.spacing, ChatEmptyStateChrome.actionSpacing)
        XCTAssertEqual(stack.orientation, .vertical)
        XCTAssertEqual(stack.spacing, ChatEmptyStateChrome.stackSpacing)
        XCTAssertEqual(stack.arrangedSubviews, [title, subtitle, actions])
        XCTAssertFalse(stack.translatesAutoresizingMaskIntoConstraints)
    }

    func testActionUsesLiquidGlassWrapperAndStableWidths() throws {
        let target = EmptyStateTarget()
        let worktree = ChatEmptyStateChrome.makeAction(
            title: "New Worktree",
            symbol: "arrow.triangle.branch",
            target: target,
            action: #selector(EmptyStateTarget.tap(_:))
        )
        let workspace = ChatEmptyStateChrome.makeAction(
            title: "Add Workspace",
            symbol: "folder.badge.plus",
            target: target,
            action: #selector(EmptyStateTarget.tap(_:))
        )

        let worktreeShell = try XCTUnwrap(worktree as? NSVisualEffectView)
        let workspaceShell = try XCTUnwrap(workspace as? NSVisualEffectView)
        XCTAssertEqual(worktreeShell.material, .menu)
        XCTAssertEqual(worktreeShell.blendingMode, .withinWindow)
        XCTAssertEqual(worktreeShell.layer?.cornerRadius, ChatEmptyStateChrome.actionCornerRadius)
        XCTAssertTrue(worktreeShell.layer?.masksToBounds ?? false)
        XCTAssertWidthConstraint(worktreeShell, ChatEmptyStateChrome.newWorktreeWidth)
        XCTAssertWidthConstraint(workspaceShell, ChatEmptyStateChrome.addWorkspaceWidth)

        let button = try XCTUnwrap(worktreeShell.subviews.first as? NSButton)
        XCTAssertEqual(button.title, "New Worktree")
        XCTAssertEqual(button.target as? EmptyStateTarget, target)
        XCTAssertEqual(button.action, #selector(EmptyStateTarget.tap(_:)))
        XCTAssertEqual(button.imagePosition, .imageLeading)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.controlSize, .large)
        XCTAssertEqual(button.font, DesignSystem.Font.actionButton)
    }

    private func XCTAssertWidthConstraint(
        _ view: NSView,
        _ width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            view.constraints.contains { constraint in
                constraint.firstAnchor == view.widthAnchor && constraint.relation == .greaterThanOrEqual && constraint.constant == width
            },
            "Missing expected width constraint \(width)",
            file: file,
            line: line
        )
    }
}

private final class EmptyStateTarget: NSObject {
    @objc func tap(_ sender: NSButton) {}
}
