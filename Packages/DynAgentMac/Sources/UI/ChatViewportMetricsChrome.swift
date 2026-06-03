import AppKit

enum ChatViewportMetricsChrome {
    static func payload(
        root: NSView,
        scroll: NSScrollView,
        transcript: NSStackView,
        composer: NSView
    ) -> [String: Any] {
        let rootSubviewFrames = frameMetrics(for: root.subviews)
        return [
            "chatViewWidth": Double(root.frame.width),
            "chatViewHeight": Double(root.frame.height),
            "scrollWidth": Double(scroll.frame.width),
            "scrollHeight": Double(scroll.frame.height),
            "documentWidth": Double((scroll.documentView?.frame.width) ?? -1),
            "documentHeight": Double((scroll.documentView?.frame.height) ?? -1),
            "transcriptWidth": Double(transcript.frame.width),
            "transcriptHeight": Double(transcript.frame.height),
            "composerWidth": Double(composer.frame.width),
            "composerHeight": Double(composer.frame.height),
            "visibleRows": transcript.arrangedSubviews.count,
            "rootSubviewFrames": rootSubviewFrames,
        ]
    }

    static func frameMetrics(for subviews: [NSView]) -> [[String: Any]] {
        subviews.enumerated().map { index, subview in
            [
                "index": index,
                "class": String(describing: type(of: subview)),
                "x": Double(subview.frame.minX),
                "y": Double(subview.frame.minY),
                "width": Double(subview.frame.width),
                "height": Double(subview.frame.height),
            ] as [String: Any]
        }
    }
}
