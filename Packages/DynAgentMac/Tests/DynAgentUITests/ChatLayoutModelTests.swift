@testable import DynAgentUI
import XCTest

final class ChatLayoutModelTests: XCTestCase {
    func testReadableWidthFillsTightContainersWithInsets() {
        XCTAssertEqual(ChatLayoutModel.readableWidth(for: 900), 872)
        XCTAssertEqual(ChatLayoutModel.readableWidth(for: 20), 0)
    }

    func testReadableWidthCapsWideContainers() {
        XCTAssertEqual(ChatLayoutModel.readableWidth(for: 1_400), ChatLayoutModel.maxReadableWidth)
        XCTAssertEqual(ChatLayoutModel.maxReadableWidth, 1_100)
        XCTAssertEqual(ChatLayoutModel.preferredMainWidthWithInspector, ChatLayoutModel.maxReadableWidth + ChatLayoutModel.horizontalInset * 2)
    }

    func testReadableWidthAllowsCustomTokensForPlatformAdaptation() {
        XCTAssertEqual(
            ChatLayoutModel.readableWidth(for: 600, horizontalInset: 20, maxReadableWidth: 480),
            480
        )
        XCTAssertEqual(
            ChatLayoutModel.readableWidth(for: 440, horizontalInset: 20, maxReadableWidth: 480),
            400
        )
    }
}
