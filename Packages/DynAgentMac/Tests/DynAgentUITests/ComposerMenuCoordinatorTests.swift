import AppKit
@testable import DynAgentUI
import XCTest

final class ComposerMenuCoordinatorTests: XCTestCase {
    func testSetModelsForNonCodexReplacesPopupItemsAndSelectsPreferredModel() {
        let fixture = Fixture()
        let didChange = fixture.coordinator.applyHarnessSyncPlan(
            for: .dynagent,
            preferredModel: "claude-opus",
            mode: .rememberPreferred,
            conversation: nil
        )

        fixture.coordinator.setModels(["auto", "claude-opus"], conversation: nil)

        XCTAssertFalse(didChange)
        XCTAssertEqual(fixture.coordinator.selectedHarness, .dynagent)
        XCTAssertEqual(fixture.coordinator.selectedModel, "claude-opus")
        XCTAssertEqual(fixture.modelPopup.itemTitles, ["auto", "claude-opus"])
        XCTAssertNotNil(fixture.modelPopup.item(at: 0)?.image)
        XCTAssertEqual(fixture.placeholder.stringValue, "Ask DynAgent")
    }

    func testSwitchingToCodexInstallsFallbackAndHidesReasoningPopup() {
        let fixture = Fixture()

        let didChange = fixture.coordinator.applyHarnessSyncPlan(
            for: .codex,
            preferredModel: "gpt-5.5-mini",
            mode: .rememberPreferred,
            conversation: nil
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(fixture.coordinator.selectedHarness, .codex)
        XCTAssertEqual(fixture.coordinator.selectedModel, "gpt-5.5-mini")
        XCTAssertTrue(fixture.reasoningPopup.isHidden)
        XCTAssertEqual(fixture.placeholder.stringValue, "Ask Codex")
    }

    func testCodexModelListInstallsNestedMenuAndPickUpdatesSelection() {
        let fixture = Fixture()
        _ = fixture.coordinator.applyHarnessSyncPlan(
            for: .codex,
            preferredModel: "gpt-5.5-codex",
            mode: .rememberPreferred,
            conversation: nil
        )

        fixture.coordinator.setModels(["gpt-5.5-codex", "gpt-5.5-mini"], conversation: nil)
        fixture.coordinator.pickCodexModel("gpt-5.5-mini", conversation: nil)
        fixture.coordinator.pickCodexEffort("xhigh", conversation: nil)

        let menu = try! XCTUnwrap(fixture.modelPopup.menu)
        XCTAssertEqual(menu.items.map(\.title), ["Model", "Reasoning"])
        XCTAssertEqual(fixture.coordinator.selectedModel, "gpt-5.5-mini")
        XCTAssertEqual(fixture.coordinator.selectedReasoning, "xhigh")
        XCTAssertEqual(fixture.coordinator.selectedCodexEffort, "xhigh")
        XCTAssertTrue(fixture.reasoningPopup.isHidden)
    }

    func testAdoptingExistingCodexThreadLocksHarnessMenuAndUsesThreadModel() {
        let fixture = Fixture()
        let conversation = Conversation(model: "gpt-5.5-mini", workspace: "/repo", harness: .codex)
        conversation.codexThreadId = "thread-1"
        conversation.messages = [ChatMessage(role: .user, text: "existing")]
        _ = fixture.coordinator.applyHarnessSyncPlan(
            for: .codex,
            preferredModel: nil,
            mode: .rememberPreferred,
            conversation: conversation
        )
        fixture.coordinator.setModels(["gpt-5.5-codex", "gpt-5.5-mini"], conversation: conversation)

        fixture.coordinator.adoptConversation(conversation)

        XCTAssertEqual(fixture.coordinator.selectedModel, "gpt-5.5-mini")
        XCTAssertTrue(fixture.harnessMenu.isHidden)
        XCTAssertEqual(fixture.placeholder.stringValue, "Ask Codex")
    }

    private final class Target: NSObject {
        @objc func chooseModel(_ sender: NSMenuItem) {}
        @objc func chooseEffort(_ sender: NSMenuItem) {}
    }

    private final class Fixture {
        let modelPopup = NSPopUpButton()
        let harnessPopup = NSPopUpButton()
        let reasoningPopup = NSPopUpButton()
        let placeholder = NSTextField(labelWithString: "")
        let harnessMenu: ComposerMenuChrome
        let modelMenu: ComposerMenuChrome
        let reasoningMenu: ComposerMenuChrome
        let target = Target()
        let coordinator: ComposerMenuCoordinator

        init() {
            harnessPopup.addItems(withTitles: Harness.allCases.map(\.rawValue))
            harnessPopup.selectItem(withTitle: Harness.dynagent.rawValue)
            modelPopup.addItem(withTitle: "auto")
            reasoningPopup.addItems(withTitles: ComposerModel.codexEfforts.map(\.value))
            reasoningPopup.selectItem(withTitle: "high")
            harnessMenu = ComposerMenuChrome(popup: harnessPopup, minWidth: 82)
            modelMenu = ComposerMenuChrome(popup: modelPopup, minWidth: 58)
            reasoningMenu = ComposerMenuChrome(popup: reasoningPopup, minWidth: 70)
            coordinator = ComposerMenuCoordinator(
                modelPopup: modelPopup,
                harnessPopup: harnessPopup,
                reasoningPopup: reasoningPopup,
                placeholder: placeholder,
                harnessMenu: harnessMenu,
                modelMenu: modelMenu,
                reasoningMenu: reasoningMenu,
                menuTarget: target,
                modelAction: #selector(Target.chooseModel(_:)),
                effortAction: #selector(Target.chooseEffort(_:))
            )
        }
    }
}
