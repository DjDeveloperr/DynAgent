import AppKit
@testable import DynAgentUI
import XCTest

final class DesignSystemTests: XCTestCase {
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
