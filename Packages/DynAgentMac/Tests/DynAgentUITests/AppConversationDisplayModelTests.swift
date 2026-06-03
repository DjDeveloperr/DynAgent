@testable import DynAgentUI
import XCTest

final class AppConversationDisplayModelTests: XCTestCase {
    func testLoadedConversationRendersCachedTranscriptImmediately() {
        XCTAssertEqual(
            AppConversationDisplayModel.mode(needsLoad: false, status: .idle),
            .renderCached
        )
        XCTAssertEqual(
            AppConversationDisplayModel.mode(needsLoad: false, status: .running),
            .renderCached
        )
    }

    func testUnloadedConversationShowsShellAndForcesRefreshOnlyWhenActive() {
        XCTAssertEqual(
            AppConversationDisplayModel.mode(needsLoad: true, status: .idle),
            .loadingShellAndRefresh(force: false)
        )
        XCTAssertEqual(
            AppConversationDisplayModel.mode(needsLoad: true, status: .thinking),
            .loadingShellAndRefresh(force: true)
        )
        XCTAssertEqual(
            AppConversationDisplayModel.mode(needsLoad: true, status: .running),
            .loadingShellAndRefresh(force: true)
        )
    }
}
