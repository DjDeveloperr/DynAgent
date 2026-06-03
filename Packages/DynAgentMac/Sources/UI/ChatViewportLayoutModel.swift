import CoreGraphics

enum ChatViewportLayoutModel {
    static let composerBottomPadding: CGFloat = 28

    static func scrollFrameCorrection(scrollFrame: CGRect, rootBounds: CGRect) -> CGRect? {
        scrollFrame == rootBounds ? nil : rootBounds
    }

    static func documentWidthCorrection(rootWidth: CGFloat, documentWidth: CGFloat, tolerance: CGFloat = 0.5) -> CGFloat? {
        abs(documentWidth - rootWidth) > tolerance ? rootWidth : nil
    }

    static func bottomInset(composerHeight: CGFloat, bottomPadding: CGFloat = composerBottomPadding) -> CGFloat {
        composerHeight + bottomPadding
    }

    static func shouldUpdateBottomInset(current: CGFloat, next: CGFloat, tolerance: CGFloat = 1) -> Bool {
        abs(next - current) > tolerance
    }
}
