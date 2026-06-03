import Foundation

struct AppUsageCredits: Equatable {
    var used: Double
    var limit: Double
}

struct AppUsageSnapshot: Equatable {
    var usageTitle: String
    var contextUsagePercentage: Double?
}

final class AppUsageCoordinator {
    static let defaultUsageTitle = "Usage remaining"

    typealias CreditsLoader = () async -> AppUsageCredits?
    typealias QuotaLoader = () async -> AgentClient.Quota?

    private let loadCredits: CreditsLoader
    private let loadQuota: QuotaLoader
    private(set) var usageRemainingTitle = AppUsageCoordinator.defaultUsageTitle

    init(loadCredits: @escaping CreditsLoader, loadQuota: @escaping QuotaLoader) {
        self.loadCredits = loadCredits
        self.loadQuota = loadQuota
    }

    convenience init(client: AgentClient) {
        self.init(
            loadCredits: {
                guard let credits = try? await client.credits() else { return nil }
                return AppUsageCredits(used: credits.used, limit: credits.limit)
            },
            loadQuota: {
                try? await client.quota()
            }
        )
    }

    @discardableResult
    func refresh(applyContext: @escaping (Double?) -> Void) async -> AppUsageSnapshot {
        if let credits = await loadCredits() {
            usageRemainingTitle = AppUsageCoordinator.title(for: credits)
        } else {
            usageRemainingTitle = AppUsageCoordinator.defaultUsageTitle
        }

        let quota = await loadQuota()
        applyContext(quota?.contextUsagePercentage)
        return AppUsageSnapshot(
            usageTitle: usageRemainingTitle,
            contextUsagePercentage: quota?.contextUsagePercentage
        )
    }

    static func title(for credits: AppUsageCredits) -> String {
        String(
            format: "Usage remaining: %.0f / %.0f credits",
            max(0, credits.limit - credits.used),
            credits.limit
        )
    }
}
