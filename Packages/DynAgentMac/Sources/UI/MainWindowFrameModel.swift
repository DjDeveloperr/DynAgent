import CoreGraphics
import Foundation

struct MainWindowFrameState: Equatable {
    var requestedFrame: CGRect = .zero
    var appliedFrame: CGRect = .zero
    var isUserLiveResizing = false
}

enum MainWindowResizeDecision: Equatable {
    case accept(CGRect)
    case restore(CGRect)
}

enum MainWindowFrameModel {
    static func initialFrame(savedFrame: CGRect?, minSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let wide = WindowLayoutModel.wideFrame(visibleFrame: visibleFrame)
        return WindowLayoutModel.restoredFrame(
            savedFrame,
            minSize: minSize,
            visibleFrame: visibleFrame,
            minimumRestoredWidth: max(wide.width * 0.98, wide.width - 32)
        ) ?? wide
    }

    static func recordingRequest(_ frame: CGRect, in state: MainWindowFrameState) -> MainWindowFrameState {
        var next = state
        next.requestedFrame = frame
        return next
    }

    static func recordingApplied(_ frame: CGRect, in state: MainWindowFrameState) -> MainWindowFrameState {
        var next = state
        next.appliedFrame = frame
        return next
    }

    static func recordingLiveResize(_ active: Bool, in state: MainWindowFrameState) -> MainWindowFrameState {
        var next = state
        next.isUserLiveResizing = active
        return next
    }

    static func resizeDecision(current: CGRect, state: MainWindowFrameState) -> MainWindowResizeDecision {
        if WindowLayoutModel.shouldRestoreUnexpectedShrink(
            current: current,
            applied: state.appliedFrame,
            isUserLiveResizing: state.isUserLiveResizing
        ) {
            return .restore(state.appliedFrame)
        }
        return .accept(current)
    }

    static func shouldScheduleUnexpectedRestore(current: CGRect, state: MainWindowFrameState, pending: Bool) -> Bool {
        guard !pending else { return false }
        guard case .restore = resizeDecision(current: current, state: state) else { return false }
        return true
    }
}
