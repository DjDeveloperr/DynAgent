@testable import DynAgentUI
import XCTest

final class AppUsageCoordinatorTests: XCTestCase {
    func testTitleFormatsRemainingCreditsAndClampsNegativeRemainingToZero() {
        XCTAssertEqual(
            AppUsageCoordinator.title(for: AppUsageCredits(used: 8.4, limit: 20)),
            "Usage remaining: 12 / 20 credits"
        )
        XCTAssertEqual(
            AppUsageCoordinator.title(for: AppUsageCredits(used: 24, limit: 20)),
            "Usage remaining: 0 / 20 credits"
        )
    }

    func testRefreshLoadsCreditsQuotaAndAppliesContext() async {
        let coordinator = AppUsageCoordinator(
            loadCredits: { AppUsageCredits(used: 5, limit: 12) },
            loadQuota: { quota(percent: 37.5) }
        )
        var appliedContext: Double?

        let snapshot = await coordinator.refresh { appliedContext = $0 }

        XCTAssertEqual(snapshot, AppUsageSnapshot(
            usageTitle: "Usage remaining: 7 / 12 credits",
            contextUsagePercentage: 37.5
        ))
        XCTAssertEqual(coordinator.usageRemainingTitle, "Usage remaining: 7 / 12 credits")
        XCTAssertEqual(appliedContext, 37.5)
    }

    func testRefreshResetsTitleWhenCreditsAreUnavailableButStillAppliesQuota() async {
        let coordinator = AppUsageCoordinator(
            loadCredits: { AppUsageCredits(used: 1, limit: 2) },
            loadQuota: { quota(percent: 10) }
        )
        _ = await coordinator.refresh { _ in }

        var contexts: [Double?] = []
        let snapshot = await AppUsageCoordinator(
            loadCredits: { nil },
            loadQuota: { quota(percent: 44) }
        ).refresh { contexts.append($0) }

        XCTAssertEqual(snapshot.usageTitle, AppUsageCoordinator.defaultUsageTitle)
        XCTAssertEqual(snapshot.contextUsagePercentage, 44)
        XCTAssertEqual(contexts, [44])
    }

    func testRefreshAppliesNilContextWhenQuotaIsUnavailable() async {
        let coordinator = AppUsageCoordinator(
            loadCredits: { AppUsageCredits(used: 0, limit: 1) },
            loadQuota: { nil }
        )
        var didApply = false
        var appliedContext: Double? = -1

        let snapshot = await coordinator.refresh {
            didApply = true
            appliedContext = $0
        }

        XCTAssertTrue(didApply)
        XCTAssertNil(appliedContext)
        XCTAssertNil(snapshot.contextUsagePercentage)
        XCTAssertEqual(snapshot.usageTitle, "Usage remaining: 1 / 1 credits")
    }
}

private func quota(percent: Double?) -> AgentClient.Quota {
    AgentClient.Quota(sessionCredits: nil, contextUsagePercentage: percent, metering: nil)
}
