import Foundation

enum TranscriptLiveUpdateModel {
    static let markdownRenderInterval: TimeInterval = 0.45
    static let scrollInterval: TimeInterval = 0.25

    static func shouldRenderMarkdown(
        force: Bool,
        now: TimeInterval,
        lastRenderAt: TimeInterval?,
        interval: TimeInterval = markdownRenderInterval
    ) -> Bool {
        if force { return true }
        guard let lastRenderAt else { return true }
        return now - lastRenderAt >= interval
    }

    static func shouldThrottleScroll(
        streaming: Bool,
        now: TimeInterval,
        lastScrollAt: TimeInterval,
        interval: TimeInterval = scrollInterval
    ) -> Bool {
        streaming && now - lastScrollAt < interval
    }
}
