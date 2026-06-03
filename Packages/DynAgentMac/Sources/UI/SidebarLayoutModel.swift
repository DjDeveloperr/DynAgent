import CoreGraphics

enum SidebarLayoutModel {
    static let minimumWidth: CGFloat = 260
    static let maximumWidth: CGFloat = 320

    static func clampedWidth(_ width: CGFloat,
                             minimumWidth: CGFloat = minimumWidth,
                             maximumWidth: CGFloat = maximumWidth) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }

    static func syncPlan(receivedWidth: Double?,
                         correctionTolerance: Double = 1) -> SidebarWidthSyncPlan {
        AppSidebarSyncModel.widthPlan(
            receivedWidth: receivedWidth,
            minimumWidth: Double(minimumWidth),
            maximumWidth: Double(maximumWidth),
            correctionTolerance: correctionTolerance
        )
    }
}
