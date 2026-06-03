import AppKit
@testable import DynAgentUI
import XCTest

final class DesignSystemTests: XCTestCase {
    func testLabelFactoryAppliesSingleLineTextStyle() {
        let label = DesignSystem.label("dynamic_agent", style: DesignSystem.Text.sidebarWorkspace)

        XCTAssertEqual(label.stringValue, "dynamic_agent")
        XCTAssertEqual(label.font, DesignSystem.Font.sidebarWorkspace)
        XCTAssertEqual(label.textColor, .secondaryLabelColor)
        XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(label.maximumNumberOfLines, 1)
        XCTAssertTrue(label.cell?.usesSingleLineMode ?? false)
        XCTAssertTrue(label.cell?.truncatesLastVisibleLine ?? false)
        XCTAssertEqual(label.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        XCTAssertFalse(label.translatesAutoresizingMaskIntoConstraints)
    }

    func testLabelFactoryPreservesWrappingTextStyle() {
        let label = DesignSystem.label("Pull request details", style: DesignSystem.Text.panelBodySecondary)

        XCTAssertEqual(label.font, DesignSystem.Font.panelBody)
        XCTAssertEqual(label.textColor, .secondaryLabelColor)
        XCTAssertEqual(label.lineBreakMode, .byWordWrapping)
        XCTAssertEqual(label.maximumNumberOfLines, 0)
        XCTAssertFalse(label.cell?.usesSingleLineMode ?? false)
    }

    func testIconButtonUsesSharedSymbolChrome() {
        let target = Target()

        let button = DesignSystem.iconButton(
            symbol: "ellipsis",
            accessibilityDescription: "Chat actions",
            tint: .secondaryLabelColor,
            target: target,
            action: #selector(Target.tap(_:))
        )

        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.imageScaling, .scaleProportionallyDown)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(button.target as? Target, target)
        XCTAssertEqual(button.action, #selector(Target.tap(_:)))
        XCTAssertFalse(button.translatesAutoresizingMaskIntoConstraints)
    }

    func testSharedChromeFontTokensUseExpectedSizes() {
        XCTAssertEqual(DesignSystem.Font.controlSmall.pointSize, 13.5, accuracy: 0.01)
        XCTAssertEqual(DesignSystem.Font.actionButton.pointSize, 13, accuracy: 0.01)
        XCTAssertEqual(DesignSystem.Font.emptyStateTitle.pointSize, 22, accuracy: 0.01)
        XCTAssertEqual(DesignSystem.Font.emptyStateSubtitle.pointSize, 13, accuracy: 0.01)
        XCTAssertEqual(DesignSystem.Font.overlaySearch.pointSize, 18, accuracy: 0.01)
        XCTAssertEqual(DesignSystem.Font.overlayRowTitle.pointSize, 14, accuracy: 0.01)
        XCTAssertEqual(DesignSystem.Font.overlayRowDetail.pointSize, 11.5, accuracy: 0.01)
    }

    func testSharedChromeRadiusAndSpacingTokens() {
        XCTAssertEqual(DesignSystem.Radius.sidebarRow, 7)
        XCTAssertEqual(DesignSystem.Radius.attachmentChip, 8)
        XCTAssertEqual(DesignSystem.Radius.compactGlassControl, 13)
        XCTAssertEqual(DesignSystem.Radius.floatingPill, 14)
        XCTAssertEqual(DesignSystem.Radius.overlayCard, 18)

        XCTAssertEqual(DesignSystem.Spacing.xSmall, 4)
        XCTAssertEqual(DesignSystem.Spacing.medium, 8)
        XCTAssertEqual(DesignSystem.Spacing.large, 10)
    }

    func testBackdropTokenPreservesRequestedAlpha() {
        let color = DesignSystem.Color.backdrop(alpha: 0.38)

        XCTAssertEqual(color.cgColor.alpha, 0.38, accuracy: 0.001)
    }
}

private final class Target: NSObject {
    @objc func tap(_ sender: NSButton) {}
}
