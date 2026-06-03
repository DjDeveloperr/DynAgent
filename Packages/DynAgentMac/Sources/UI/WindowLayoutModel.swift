import CoreGraphics
import Foundation

struct WindowSplitConfiguration: Equatable {
    var totalWidth: CGFloat
    var sidebarCurrentWidth: CGFloat
    var sidebarMinimumWidth: CGFloat
    var sidebarMaximumWidth: CGFloat
    var sidebarCollapsed: Bool
    var gitCurrentWidth: CGFloat
    var gitMinimumWidth: CGFloat
    var gitMaximumWidth: CGFloat
    var gitCollapsed: Bool
    var fallbackSidebarWidth: CGFloat = 300
    var fallbackGitWidth: CGFloat = 360
    var minimumMainWidth: CGFloat = 360
}

struct WindowSplitPlan: Equatable {
    var sidebarWidth: CGFloat
    var gitWidth: CGFloat
    var firstDividerPosition: CGFloat?
    var secondDividerPosition: CGFloat?
}

enum WindowLayoutModel {
    static func wideFrame(visibleFrame: CGRect) -> CGRect {
        let visible = visibleFrame.isEmpty
            ? CGRect(x: 0, y: 0, width: 1512, height: 900)
            : visibleFrame
        let width = min(visible.width - 16, max(1240, visible.width * 0.96))
        let height = min(visible.height - 24, max(720, visible.height * 0.84))
        return CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func restoredFrame(_ rect: CGRect?, minSize: CGSize, visibleFrame: CGRect) -> CGRect? {
        guard let rect,
              rect.width >= minSize.width,
              rect.height >= minSize.height else { return nil }
        guard visibleFrame.isEmpty || visibleFrame.intersects(rect) else { return nil }
        return rect
    }

    static func shouldPersistFrame(_ frame: CGRect, minSize: CGSize) -> Bool {
        frame.width >= minSize.width && frame.height >= minSize.height
    }

    static func shouldRestoreAppliedFrame(current: CGRect, applied: CGRect, tolerance: CGFloat = 1) -> Bool {
        current.width < applied.width - tolerance || current.height < applied.height - tolerance
    }

    static func shouldRestoreUnexpectedShrink(current: CGRect, applied: CGRect, isUserLiveResizing: Bool, tolerance: CGFloat = 1) -> Bool {
        guard !isUserLiveResizing, applied.width > 0, applied.height > 0 else { return false }
        return current.width < applied.width - tolerance
    }

    static func splitPlan(_ config: WindowSplitConfiguration) -> WindowSplitPlan {
        let sidebarWidth: CGFloat
        if config.sidebarCollapsed {
            sidebarWidth = 0
        } else {
            let current = config.sidebarCurrentWidth > 0 ? config.sidebarCurrentWidth : config.fallbackSidebarWidth
            sidebarWidth = clamp(current, min: config.sidebarMinimumWidth, max: config.sidebarMaximumWidth)
        }

        guard !config.gitCollapsed else {
            return WindowSplitPlan(
                sidebarWidth: sidebarWidth,
                gitWidth: 0,
                firstDividerPosition: config.sidebarCollapsed ? nil : sidebarWidth,
                secondDividerPosition: nil
            )
        }

        let currentGitWidth = config.gitCurrentWidth > 0 ? config.gitCurrentWidth : config.fallbackGitWidth
        let gitWidth = clamp(currentGitWidth, min: config.gitMinimumWidth, max: config.gitMaximumWidth)
        let rawSecondDivider = max(sidebarWidth + config.minimumMainWidth, config.totalWidth - gitWidth)
        let secondDivider = min(max(rawSecondDivider, sidebarWidth), config.totalWidth)
        return WindowSplitPlan(
            sidebarWidth: sidebarWidth,
            gitWidth: gitWidth,
            firstDividerPosition: config.sidebarCollapsed ? nil : sidebarWidth,
            secondDividerPosition: secondDivider
        )
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
