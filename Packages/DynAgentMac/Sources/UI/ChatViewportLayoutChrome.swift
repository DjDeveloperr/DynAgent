import AppKit

enum ChatViewportLayoutChrome {
    @discardableResult
    static func apply(
        root: NSView,
        scroll: NSScrollView,
        composer: NSView,
        bottomInsetCache: CGFloat
    ) -> CGFloat {
        if let correction = ChatViewportLayoutModel.scrollFrameCorrection(
            scrollFrame: scroll.frame,
            rootBounds: root.bounds
        ) {
            scroll.frame = correction
        }

        if let document = scroll.documentView,
           let targetWidth = ChatViewportLayoutModel.documentWidthCorrection(
            rootWidth: root.bounds.width,
            documentWidth: document.frame.width
           ) {
            document.setFrameSize(NSSize(width: targetWidth, height: document.frame.height))
        }

        let inset = ChatViewportLayoutModel.bottomInset(composerHeight: composer.frame.height)
        guard ChatViewportLayoutModel.shouldUpdateBottomInset(current: bottomInsetCache, next: inset) else {
            return bottomInsetCache
        }
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
        return inset
    }
}
