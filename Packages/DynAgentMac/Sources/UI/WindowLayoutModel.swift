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
    var preferredMainWidth: CGFloat = 900
}

struct WindowSplitPlan: Equatable {
    var sidebarWidth: CGFloat
    var gitWidth: CGFloat
    var firstDividerPosition: CGFloat?
    var secondDividerPosition: CGFloat?
}

struct WindowLayoutViewFrame: Equatable {
    var index: Int
    var className: String
    var x: Double
    var width: Double
    var height: Double

    var dictionary: [String: Any] {
        [
            "index": index,
            "class": className,
            "x": x,
            "width": width,
            "height": height,
        ]
    }
}

struct WindowLayoutMetricsSnapshot {
    var reason: String
    var windowWidth: Double
    var windowHeight: Double
    var contentViewWidth: Double
    var contentViewHeight: Double
    var contentControllerWidth: Double
    var contentControllerHeight: Double
    var contentLayoutWidth: Double
    var contentLayoutHeight: Double
    var rootSplitViewWidth: Double
    var rootSplitViewHeight: Double
    var splitViewWidth: Double
    var splitViewHeight: Double
    var splitViewX: Double
    var splitViewClass: String
    var rootSubviews: [WindowLayoutViewFrame]
    var requestedFrameWidth: Double
    var requestedFrameHeight: Double
    var appliedFrameWidth: Double
    var appliedFrameHeight: Double
    var screenVisibleWidth: Double
    var screenVisibleHeight: Double
    var sidebarCollapsed: Bool
    var gitCollapsed: Bool
    var splitFrames: [WindowLayoutViewFrame]
    var chatViewWidth: Double
    var chatViewHeight: Double
    var workspaceWidth: Double
    var workspaceHeight: Double
    var mainSplitItemWidth: Double
    var chatMetrics: [String: Any]
    var workspaceMetrics: [String: Any]
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

    static func restoredFrame(
        _ rect: CGRect?,
        minSize: CGSize,
        visibleFrame: CGRect,
        minimumRestoredWidth: CGFloat? = nil
    ) -> CGRect? {
        let minimumWidth = max(minSize.width, minimumRestoredWidth ?? minSize.width)
        guard let rect,
              rect.width >= minimumWidth,
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

    static func rootBounds(contentBounds: CGRect, windowFrame: CGRect, contentLayoutRect: CGRect) -> CGRect {
        if contentBounds.width > 0, contentBounds.height > 0 {
            return CGRect(origin: .zero, size: contentBounds.size)
        }
        if contentLayoutRect.width > 0, contentLayoutRect.height > 0 {
            return CGRect(origin: .zero, size: contentLayoutRect.size)
        }
        return CGRect(origin: .zero, size: windowFrame.size)
    }

    static func splitPlan(_ config: WindowSplitConfiguration) -> WindowSplitPlan {
        let sidebarWidth: CGFloat
        if config.sidebarCollapsed {
            sidebarWidth = 0
        } else {
            let current = config.sidebarCurrentWidth > 0 ? config.sidebarCurrentWidth : config.fallbackSidebarWidth
            let effectiveCurrent = config.gitCollapsed
                ? min(current, max(config.sidebarMinimumWidth, config.fallbackSidebarWidth))
                : current
            sidebarWidth = clamp(effectiveCurrent, min: config.sidebarMinimumWidth, max: config.sidebarMaximumWidth)
        }

        guard !config.gitCollapsed else {
            return WindowSplitPlan(
                sidebarWidth: sidebarWidth,
                gitWidth: 0,
                firstDividerPosition: config.sidebarCollapsed ? nil : sidebarWidth,
                secondDividerPosition: config.totalWidth
            )
        }

        let availableForMainAndGit = max(0, config.totalWidth - sidebarWidth)
        let reserveGitWidth = min(config.gitMinimumWidth, max(0, availableForMainAndGit - config.minimumMainWidth))
        let maxMainWidthWhileKeepingGitUsable = max(config.minimumMainWidth, availableForMainAndGit - reserveGitWidth)
        let preferredMainWidth = clamp(
            config.preferredMainWidth,
            min: config.minimumMainWidth,
            max: maxMainWidthWhileKeepingGitUsable
        )

        let currentGitWidth = config.gitCurrentWidth > 0 ? config.gitCurrentWidth : config.fallbackGitWidth
        let gitWidth = clamp(currentGitWidth, min: config.gitMinimumWidth, max: config.gitMaximumWidth)
        let mainWidth = max(preferredMainWidth, availableForMainAndGit - gitWidth)
        let rawSecondDivider = sidebarWidth + mainWidth
        let secondDivider = min(max(rawSecondDivider, sidebarWidth), config.totalWidth)
        return WindowSplitPlan(
            sidebarWidth: sidebarWidth,
            gitWidth: max(0, config.totalWidth - secondDivider),
            firstDividerPosition: config.sidebarCollapsed ? nil : sidebarWidth,
            secondDividerPosition: secondDivider
        )
    }

    static func workspaceWidthSlack(mainSplitItemWidth: Double, workspaceWidth: Double) -> Double {
        mainSplitItemWidth - workspaceWidth
    }

    static func metricsPayload(from snapshot: WindowLayoutMetricsSnapshot) -> [String: Any] {
        [
            "reason": snapshot.reason,
            "windowWidth": snapshot.windowWidth,
            "windowHeight": snapshot.windowHeight,
            "contentViewWidth": snapshot.contentViewWidth,
            "contentViewHeight": snapshot.contentViewHeight,
            "contentControllerWidth": snapshot.contentControllerWidth,
            "contentControllerHeight": snapshot.contentControllerHeight,
            "contentLayoutWidth": snapshot.contentLayoutWidth,
            "contentLayoutHeight": snapshot.contentLayoutHeight,
            "rootSplitViewWidth": snapshot.rootSplitViewWidth,
            "rootSplitViewHeight": snapshot.rootSplitViewHeight,
            "splitViewWidth": snapshot.splitViewWidth,
            "splitViewHeight": snapshot.splitViewHeight,
            "splitViewX": snapshot.splitViewX,
            "splitViewClass": snapshot.splitViewClass,
            "rootSubviews": snapshot.rootSubviews.map(\.dictionary),
            "requestedFrameWidth": snapshot.requestedFrameWidth,
            "requestedFrameHeight": snapshot.requestedFrameHeight,
            "appliedFrameWidth": snapshot.appliedFrameWidth,
            "appliedFrameHeight": snapshot.appliedFrameHeight,
            "screenVisibleWidth": snapshot.screenVisibleWidth,
            "screenVisibleHeight": snapshot.screenVisibleHeight,
            "sidebarCollapsed": snapshot.sidebarCollapsed,
            "gitCollapsed": snapshot.gitCollapsed,
            "splitFrames": snapshot.splitFrames.map(\.dictionary),
            "chatViewWidth": snapshot.chatViewWidth,
            "chatViewHeight": snapshot.chatViewHeight,
            "workspaceWidth": snapshot.workspaceWidth,
            "workspaceHeight": snapshot.workspaceHeight,
            "mainSplitItemWidth": snapshot.mainSplitItemWidth,
            "workspaceWidthSlack": workspaceWidthSlack(
                mainSplitItemWidth: snapshot.mainSplitItemWidth,
                workspaceWidth: snapshot.workspaceWidth
            ),
            "chat": snapshot.chatMetrics,
            "workspace": snapshot.workspaceMetrics,
        ]
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
