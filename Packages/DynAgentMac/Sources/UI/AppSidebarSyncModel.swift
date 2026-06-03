import Foundation

struct SidebarWidthSyncPlan: Equatable {
    var appliedWidth: Double?
    var correctionPayload: [String: Double]?
}

struct SidebarResizeSyncPlan: Equatable {
    var syncedWidth: Double?
    var payload: [String: Double]?
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

    static func resizeSyncPlan(
        observedWidth: Double?,
        lastSyncedWidth: Double,
        minimumWidth: Double,
        maximumWidth: Double,
        syncTolerance: Double = 1
    ) -> SidebarResizeSyncPlan {
        guard let observedWidth, observedWidth > 0 else {
            return SidebarResizeSyncPlan(syncedWidth: nil, payload: nil)
        }

        let capped = min(max(observedWidth, minimumWidth), maximumWidth)
        guard abs(capped - lastSyncedWidth) > syncTolerance else {
            return SidebarResizeSyncPlan(syncedWidth: nil, payload: nil)
        }

        return SidebarResizeSyncPlan(
            syncedWidth: capped,
            payload: ["sidebarWidth": capped]
        )
    }

    static func sectionPayload(section: String, collapsed: Bool) -> [String: Any] {
        ["section": section, "sectionCollapsed": collapsed]
    }

    static func workspacePayload(path: String, collapsed: Bool) -> [String: Any] {
        ["groupPath": path, "groupCollapsed": collapsed]
    }
}
