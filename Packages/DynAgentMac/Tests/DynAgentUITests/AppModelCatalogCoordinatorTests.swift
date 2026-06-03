@testable import DynAgentUI
import XCTest

final class AppModelCatalogCoordinatorTests: XCTestCase {
    func testRefreshStoresLoadedModelsPerHarness() async {
        let coordinator = AppModelCatalogCoordinator(
            dynagentLoader: { ["auto", "dyn-2"] },
            codexLoader: { ["gpt-5.5", "gpt-5.5-codex"] },
            piLoader: { ["kiro::custom"] }
        )

        let codex = await coordinator.refresh(harness: .codex)
        let dynagent = await coordinator.refresh(harness: .dynagent)
        let pi = await coordinator.refresh(harness: .pi)

        XCTAssertEqual(codex, ["gpt-5.5", "gpt-5.5-codex"])
        XCTAssertEqual(dynagent, ["auto", "dyn-2"])
        XCTAssertEqual(pi, ["kiro::custom"])
        XCTAssertEqual(coordinator.cachedModels(for: .codex), codex)
        XCTAssertEqual(coordinator.cachedModels(for: .dynagent), dynagent)
        XCTAssertEqual(coordinator.cachedModels(for: .pi), pi)
    }

    func testRefreshUsesFallbackWhenLoaderReturnsNilOrEmpty() async {
        let coordinator = AppModelCatalogCoordinator(
            dynagentLoader: { nil },
            codexLoader: { [] },
            piLoader: { nil }
        )

        let dynagent = await coordinator.refresh(harness: .dynagent)
        let codex = await coordinator.refresh(harness: .codex)
        let pi = await coordinator.refresh(harness: .pi)

        XCTAssertEqual(dynagent, ["auto"])
        XCTAssertEqual(codex, ["gpt-5.5"])
        XCTAssertEqual(pi, ["kiro::kiro/claude-opus-4.8"])
        XCTAssertEqual(coordinator.preferredModel(for: .codex), "gpt-5.5")
    }

    func testRestoreAndPreferredModelUseCachedModels() {
        let coordinator = AppModelCatalogCoordinator.stub()

        coordinator.restore([
            .codex: ["gpt-5.5-cached", "gpt-5.5"],
            .dynagent: ["dyn-cached"]
        ])

        XCTAssertEqual(coordinator.models(for: .codex), ["gpt-5.5-cached", "gpt-5.5"])
        XCTAssertEqual(coordinator.preferredModel(for: .codex), "gpt-5.5-cached")
        XCTAssertEqual(coordinator.models(for: .pi), ["kiro::kiro/claude-opus-4.8"])
    }

    func testBootstrapLoadsDefaultCatalogForCodexAndDynagent() async {
        let coordinator = AppModelCatalogCoordinator(
            dynagentLoader: { ["dyn-default"] },
            codexLoader: { ["codex-default"] },
            piLoader: { ["pi-default"] }
        )

        let bootstrap = await coordinator.bootstrapDefaultCatalog()

        XCTAssertEqual(bootstrap, AppModelCatalogBootstrap(
            codexModels: ["codex-default"],
            dynagentModels: ["dyn-default"],
            defaultHarness: .codex,
            defaultModel: "codex-default"
        ))
        XCTAssertEqual(coordinator.cachedModels(for: .codex), ["codex-default"])
        XCTAssertEqual(coordinator.cachedModels(for: .dynagent), ["dyn-default"])
        XCTAssertNil(coordinator.cachedModels(for: .pi))
    }
}

private extension AppModelCatalogCoordinator {
    static func stub() -> AppModelCatalogCoordinator {
        AppModelCatalogCoordinator(
            dynagentLoader: { nil },
            codexLoader: { nil },
            piLoader: { nil }
        )
    }
}
