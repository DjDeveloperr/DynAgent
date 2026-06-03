import Foundation

struct SidebarWidthSyncPlan: Equatable {
    var appliedWidth: Double?
    var correctionPayload: [String: Double]?
}

enum AppSidebarSyncModel {
    static func widthPlan(
        receivedWidth: Double?,
        minimumWidth: Double,
        maximumWidth: Double,
        correctionTolerance: Double = 1
    ) -> SidebarWidthSyncPlan {
        guard let receivedWidth else {
            return SidebarWidthSyncPlan(appliedWidth: nil, correctionPayload: nil)
        }

        let capped = min(max(receivedWidth, minimumWidth), maximumWidth)
        let correction: [String: Double]? =
            abs(receivedWidth - capped) > correctionTolerance ? ["sidebarWidth": capped] : nil

        return SidebarWidthSyncPlan(appliedWidth: capped, correctionPayload: correction)
    }

    static func sectionPayload(section: String, collapsed: Bool) -> [String: Any] {
        ["section": section, "sectionCollapsed": collapsed]
    }

    static func workspacePayload(path: String, collapsed: Bool) -> [String: Any] {
        ["groupPath": path, "groupCollapsed": collapsed]
    }
}
