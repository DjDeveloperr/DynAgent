@testable import DynAgentUI
import XCTest

final class ComposerSelectionModelTests: XCTestCase {
    func testPreferredAndDefaultModelsTrackDesiredSelection() {
        var state = ComposerSelectionState()

        state.rememberPreferredModel("gpt-5.5-codex")
        XCTAssertEqual(state.desiredModel, "gpt-5.5-codex")

        state.rememberPreferredModel(nil)
        XCTAssertEqual(state.desiredModel, "gpt-5.5-codex")

        state.applyDefaultModel("gpt-5.5-mini")
        XCTAssertEqual(state.desiredModel, "gpt-5.5-mini")
    }

    func testHarnessSyncPlanRemembersPreferredModelButIgnoresNilPreferred() {
        var state = ComposerSelectionState(desiredModel: "gpt-5.5-codex")

        let plan = state.planHarnessSync(
            targetHarness: .codex,
            preferredModel: nil,
            currentHarness: .codex,
            availablePopupItems: ["gpt-5.5-codex"],
            popupItemCount: 1,
            mode: .rememberPreferred
        )

        XCTAssertEqual(plan, ComposerHarnessSyncPlan(harnessChanged: false, action: .syncOnly))
        XCTAssertEqual(state.desiredModel, "gpt-5.5-codex")
    }

    func testHarnessSyncPlanApplyDefaultAllowsNilDefault() {
        var state = ComposerSelectionState(desiredModel: "gpt-5.5-codex")

        let plan = state.planHarnessSync(
            targetHarness: .codex,
            preferredModel: nil,
            currentHarness: .codex,
            availablePopupItems: ["gpt-5.5-codex"],
            popupItemCount: 1,
            mode: .applyDefault
        )

        XCTAssertEqual(plan, ComposerHarnessSyncPlan(harnessChanged: false, action: .syncOnly))
        XCTAssertNil(state.desiredModel)
    }

    func testHarnessSyncPlanInstallsFallbackWhenHarnessChanges() {
        var state = ComposerSelectionState()

        let plan = state.planHarnessSync(
            targetHarness: .codex,
            preferredModel: "gpt-5.5-mini",
            currentHarness: .dynagent,
            availablePopupItems: ["auto"],
            popupItemCount: 1,
            mode: .rememberPreferred
        )

        XCTAssertEqual(plan, ComposerHarnessSyncPlan(
            harnessChanged: true,
            action: .installFallback(preferred: "gpt-5.5-mini")
        ))
        XCTAssertEqual(state.desiredModel, "gpt-5.5-mini")
    }

    func testHarnessSyncPlanSelectsPreferredExistingPopupItem() {
        var state = ComposerSelectionState()

        let plan = state.planHarnessSync(
            targetHarness: .dynagent,
            preferredModel: "claude-opus",
            currentHarness: .dynagent,
            availablePopupItems: ["auto", "claude-opus"],
            popupItemCount: 2,
            mode: .rememberPreferred
        )

        XCTAssertEqual(plan, ComposerHarnessSyncPlan(
            harnessChanged: false,
            action: .selectPopupItem("claude-opus")
        ))
        XCTAssertEqual(state.desiredModel, "claude-opus")
    }

    func testHarnessSyncPlanInstallsFallbackWhenPopupIsEmpty() {
        var state = ComposerSelectionState()

        let plan = state.planHarnessSync(
            targetHarness: .dynagent,
            preferredModel: "missing",
            currentHarness: .dynagent,
            availablePopupItems: [],
            popupItemCount: 0,
            mode: .rememberPreferred
        )

        XCTAssertEqual(plan, ComposerHarnessSyncPlan(
            harnessChanged: false,
            action: .installFallback(preferred: "missing")
        ))
    }

    func testConversationAdoptionOnlyChangesCodexModelForCodexThreads() {
        var state = ComposerSelectionState(selectedCodexModel: "gpt-5.5-codex")

        state.adoptConversationModel("claude-opus", harness: .dynagent)
        XCTAssertEqual(state.desiredModel, "claude-opus")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-codex")

        state.adoptConversationModel("gpt-5.5-mini", harness: .codex)
        XCTAssertEqual(state.desiredModel, "gpt-5.5-mini")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-mini")
    }

    func testConversationAdoptionRequestsCodexMenuInstallWhenModelsAreKnown() {
        var state = ComposerSelectionState(
            codexModelIds: ["gpt-5.5-codex", "gpt-5.5-mini"],
            selectedCodexModel: "gpt-5.5-codex"
        )

        let action = state.adoptConversationModel(
            "gpt-5.5-mini",
            harness: .codex,
            availablePopupItems: ["auto"]
        )

        XCTAssertEqual(action, .installCodexMenu(["gpt-5.5-codex", "gpt-5.5-mini"]))
        XCTAssertEqual(state.desiredModel, "gpt-5.5-mini")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-mini")
    }

    func testConversationAdoptionSelectsNonCodexPopupOnlyWhenItemExists() {
        var state = ComposerSelectionState(selectedCodexModel: "gpt-5.5-codex")

        let matching = state.adoptConversationModel(
            "claude-opus",
            harness: .dynagent,
            availablePopupItems: ["auto", "claude-opus"]
        )
        XCTAssertEqual(matching, .selectPopupItem("claude-opus"))
        XCTAssertEqual(state.desiredModel, "claude-opus")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-codex")

        let missing = state.adoptConversationModel(
            "missing-model",
            harness: .dynagent,
            availablePopupItems: ["auto", "claude-opus"]
        )
        XCTAssertEqual(missing, .none)
        XCTAssertEqual(state.desiredModel, "missing-model")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-codex")
    }

    func testModelListSyncInstallsFallbackForEmptyModelList() {
        let state = ComposerSelectionState(desiredModel: "preferred")

        XCTAssertEqual(
            state.planModelListSync(ids: [], selectedHarness: .dynagent),
            .installFallback(preferred: "preferred")
        )
    }

    func testModelListSyncInstallsCodexMenuForCodexHarness() {
        let state = ComposerSelectionState(desiredModel: "gpt-5.5-mini")

        XCTAssertEqual(
            state.planModelListSync(ids: ["gpt-5.5-codex", "gpt-5.5-mini"], selectedHarness: .codex),
            .installCodexMenu(["gpt-5.5-codex", "gpt-5.5-mini"])
        )
    }

    func testModelListSyncReplacesPopupAndSelectsDesiredModelForNonCodexHarness() {
        let state = ComposerSelectionState(desiredModel: "claude-opus")

        XCTAssertEqual(
            state.planModelListSync(ids: ["auto", "claude-opus"], selectedHarness: .dynagent),
            .replacePopupItems(ids: ["auto", "claude-opus"], selected: "claude-opus")
        )
    }

    func testModelListSyncReplacesPopupAndPrefersFirstNonAutoWhenDesiredMissing() {
        let state = ComposerSelectionState(desiredModel: "missing")

        XCTAssertEqual(
            state.planModelListSync(ids: ["auto", "sonnet"], selectedHarness: .pi),
            .replacePopupItems(ids: ["auto", "sonnet"], selected: "sonnet")
        )
    }

    func testFallbackUpdatesCodexSelectionOnlyForCodexHarness() {
        var state = ComposerSelectionState(selectedCodexModel: "gpt-5.5-codex")

        XCTAssertEqual(state.installFallback(for: .dynagent, preferred: nil), "auto")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-codex")

        XCTAssertEqual(state.installFallback(for: .codex, preferred: "gpt-5.5-mini"), "gpt-5.5-mini")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-mini")
    }

    func testInstallCodexMenuUsesDesiredModelAndTracksAvailability() {
        var state = ComposerSelectionState(desiredModel: "gpt-5.5-mini", selectedCodexModel: "gpt-5.5-codex")

        let menu = state.installCodexMenu(ids: ["gpt-5.5-codex", "gpt-5.5-mini"])

        XCTAssertEqual(state.codexModelIds, ["gpt-5.5-codex", "gpt-5.5-mini"])
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-mini")
        XCTAssertEqual(state.resolvedCodexModel, "gpt-5.5-mini")
        XCTAssertEqual(menu.modelItems.map(\.isSelected), [false, true])
    }

    func testUnsupportedCodexModelResolvesToAvailableModel() {
        var state = ComposerSelectionState(
            codexModelIds: ["gpt-5.5-codex"],
            selectedCodexModel: "missing"
        )

        XCTAssertTrue(state.ensureCodexModelIsSupported())
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-codex")
        XCTAssertFalse(state.ensureCodexModelIsSupported())
    }

    func testPickingCodexModelAndEffortProducesUpdatedMenuModel() {
        var state = ComposerSelectionState(codexModelIds: ["gpt-5.5-codex", "gpt-5.5-mini"])

        let modelMenu = state.pickCodexModel("gpt-5.5-mini")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-mini")
        XCTAssertEqual(modelMenu.modelItems.map(\.isSelected), [false, true])

        let effortMenu = state.pickCodexEffort("xhigh")
        XCTAssertEqual(state.selectedCodexEffort, "xhigh")
        XCTAssertEqual(effortMenu.effortItems.map(\.isSelected), [false, false, false, true])
    }
}
