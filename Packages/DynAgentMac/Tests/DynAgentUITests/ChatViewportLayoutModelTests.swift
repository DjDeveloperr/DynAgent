@testable import DynAgentUI
import XCTest

final class ChatViewportLayoutModelTests: XCTestCase {
    func testScrollFrameCorrectionPinsScrollToRootBoundsOnlyWhenNeeded() {
        let root = CGRect(x: 0, y: 0, width: 1188, height: 798)

        XCTAssertNil(ChatViewportLayoutModel.scrollFrameCorrection(scrollFrame: root, rootBounds: root))
        XCTAssertEqual(
            ChatViewportLayoutModel.scrollFrameCorrection(
                scrollFrame: CGRect(x: 0, y: 0, width: 1068, height: 798),
                rootBounds: root
            ),
            root
        )
    }

    func testDocumentWidthCorrectionUsesRootWidthWithTolerance() {
        XCTAssertNil(ChatViewportLayoutModel.documentWidthCorrection(rootWidth: 1188, documentWidth: 1187.7))
        XCTAssertEqual(ChatViewportLayoutModel.documentWidthCorrection(rootWidth: 1188, documentWidth: 1068), 1188)
    }

    func testBottomInsetTracksComposerHeightWithTolerance() {
        let next = ChatViewportLayoutModel.bottomInset(composerHeight: 144)

        XCTAssertEqual(next, 172)
        XCTAssertFalse(ChatViewportLayoutModel.shouldUpdateBottomInset(current: 171.5, next: next))
        XCTAssertTrue(ChatViewportLayoutModel.shouldUpdateBottomInset(current: 160, next: next))
    }
}
