@testable import DynAgentUI
import XCTest

final class MainWindowFrameModelTests: XCTestCase {
    func testInitialFrameUsesValidWideSavedFrameAndRejectsStaleNarrowFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1_512, height: 949)
        let minSize = CGSize(width: 820, height: 480)
        let wideEnough = CGRect(x: 20, y: 20, width: 1_400, height: 780)
        let staleNarrow = CGRect(x: 20, y: 20, width: 1_000, height: 780)

        XCTAssertEqual(
            MainWindowFrameModel.initialFrame(savedFrame: wideEnough, minSize: minSize, visibleFrame: visible),
            wideEnough
        )
        XCTAssertEqual(
            MainWindowFrameModel.initialFrame(savedFrame: staleNarrow, minSize: minSize, visibleFrame: visible),
            WindowLayoutModel.wideFrame(visibleFrame: visible)
        )
    }

    func testRecordingRequestAppliedAndLiveResizeState() {
        let requested = CGRect(x: 1, y: 2, width: 1_200, height: 700)
        let applied = CGRect(x: 3, y: 4, width: 1_180, height: 680)

        var state = MainWindowFrameState()
        state = MainWindowFrameModel.recordingRequest(requested, in: state)
        state = MainWindowFrameModel.recordingApplied(applied, in: state)
        state = MainWindowFrameModel.recordingLiveResize(true, in: state)

        XCTAssertEqual(state.requestedFrame, requested)
        XCTAssertEqual(state.appliedFrame, applied)
        XCTAssertTrue(state.isUserLiveResizing)
    }

    func testResizeDecisionRestoresUnexpectedShrinkUnlessUserIsLiveResizing() {
        let applied = CGRect(x: 0, y: 0, width: 1_472, height: 780)
        let shrunken = CGRect(x: 0, y: 0, width: 900, height: 780)
        let grown = CGRect(x: 0, y: 0, width: 1_600, height: 800)

        let stable = MainWindowFrameState(appliedFrame: applied)
        let resizing = MainWindowFrameState(appliedFrame: applied, isUserLiveResizing: true)

        XCTAssertEqual(
            MainWindowFrameModel.resizeDecision(current: shrunken, state: stable),
            .restore(applied)
        )
        XCTAssertEqual(
            MainWindowFrameModel.resizeDecision(current: shrunken, state: resizing),
            .accept(shrunken)
        )
        XCTAssertEqual(
            MainWindowFrameModel.resizeDecision(current: grown, state: stable),
            .accept(grown)
        )
    }
}
