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

    func testConversationAdoptionOnlyChangesCodexModelForCodexThreads() {
        var state = ComposerSelectionState(selectedCodexModel: "gpt-5.5-codex")

        state.adoptConversationModel("claude-opus", harness: .dynagent)
        XCTAssertEqual(state.desiredModel, "claude-opus")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-codex")

        state.adoptConversationModel("gpt-5.5-mini", harness: .codex)
        XCTAssertEqual(state.desiredModel, "gpt-5.5-mini")
        XCTAssertEqual(state.selectedCodexModel, "gpt-5.5-mini")
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
