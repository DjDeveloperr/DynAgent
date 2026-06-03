import CoreGraphics

enum ChatLayoutModel {
    static let horizontalInset: CGFloat = 14
    static let maxReadableWidth: CGFloat = 880
    static let preferredMainWidthWithInspector: CGFloat = 1_128

    static func readableWidth(for containerWidth: CGFloat,
                              horizontalInset: CGFloat = horizontalInset,
                              maxReadableWidth: CGFloat = maxReadableWidth) -> CGFloat {
        min(maxReadableWidth, max(0, containerWidth - horizontalInset * 2))
    }
}
