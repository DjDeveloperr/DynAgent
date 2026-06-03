import AppKit

final class ComposerMenuCoordinator {
    private var selection: ComposerSelectionState
    private let modelPopup: NSPopUpButton
    private let harnessPopup: NSPopUpButton
    private let reasoningPopup: NSPopUpButton
    private let placeholder: NSTextField
    private let harnessMenu: ComposerMenuChrome?
    private let modelMenu: ComposerMenuChrome?
    private let reasoningMenu: ComposerMenuChrome?
    private weak var menuTarget: AnyObject?
    private let modelAction: Selector
    private let effortAction: Selector

    init(
        selection: ComposerSelectionState = ComposerSelectionState(),
        modelPopup: NSPopUpButton,
        harnessPopup: NSPopUpButton,
        reasoningPopup: NSPopUpButton,
        placeholder: NSTextField,
        harnessMenu: ComposerMenuChrome?,
        modelMenu: ComposerMenuChrome?,
        reasoningMenu: ComposerMenuChrome?,
        menuTarget: AnyObject,
        modelAction: Selector,
        effortAction: Selector
    ) {
        self.selection = selection
        self.modelPopup = modelPopup
        self.harnessPopup = harnessPopup
        self.reasoningPopup = reasoningPopup
        self.placeholder = placeholder
        self.harnessMenu = harnessMenu
        self.modelMenu = modelMenu
        self.reasoningMenu = reasoningMenu
        self.menuTarget = menuTarget
        self.modelAction = modelAction
        self.effortAction = effortAction
    }

    var selectedModel: String {
        if selectedHarness == .codex { return selection.resolvedCodexModel }
        return modelPopup.titleOfSelectedItem ?? "auto"
    }

    var selectedHarness: Harness {
        Harness(rawValue: harnessPopup.titleOfSelectedItem ?? "") ?? .dynagent
    }

    var selectedReasoning: String {
        if selectedHarness == .codex { return selection.selectedCodexEffort }
        return reasoningPopup.titleOfSelectedItem ?? "high"
    }

    var selectedCodexEffort: String { selection.selectedCodexEffort }
    var selectedCodexModel: String { selection.selectedCodexModel }

    func applyHarnessSyncPlan(
        for harness: Harness,
        preferredModel: String?,
        mode: ComposerHarnessSyncMode,
        conversation: Conversation?
    ) -> Bool {
        let plan = selection.planHarnessSync(
            targetHarness: harness,
            preferredModel: preferredModel,
            currentHarness: selectedHarness,
            availablePopupItems: modelPopup.itemTitles,
            popupItemCount: modelPopup.numberOfItems,
            mode: mode
        )
        if plan.harnessChanged {
            harnessPopup.selectItem(withTitle: harness.rawValue)
            reasoningPopup.isHidden = harness == .codex
        }
        apply(plan.action, for: harness, conversation: conversation)
        return plan.harnessChanged
    }

    func setModels(_ ids: [String], conversation: Conversation?) {
        switch selection.planModelListSync(ids: ids, selectedHarness: selectedHarness) {
        case .installFallback(let preferred):
            installModelFallback(for: selectedHarness, preferred: preferred, conversation: conversation)
        case .installCodexMenu(let ids):
            installCodexModelMenu(ids, conversation: conversation)
        case .replacePopupItems(let ids, let selected):
            replacePopupItems(ids: ids, selected: selected)
            syncMenus(conversation: conversation)
        }
    }

    func ensureSelectedCodexModelIsSupported(conversation: Conversation?) {
        guard selection.ensureCodexModelIsSupported() else { return }
        if !selection.codexModelIds.isEmpty {
            installCodexModelMenu(selection.codexModelIds, conversation: conversation)
        }
    }

    func adoptConversation(_ conversation: Conversation) {
        switch selection.adoptConversationModel(
            conversation.model,
            harness: conversation.harness,
            availablePopupItems: modelPopup.itemTitles
        ) {
        case .installCodexMenu(let ids):
            installCodexModelMenu(ids, conversation: conversation)
        case .selectPopupItem(let title):
            modelPopup.selectItem(withTitle: title)
            syncMenus(conversation: conversation)
        case .none:
            syncMenus(conversation: conversation)
        }
    }

    func syncMenus(conversation: Conversation?) {
        let state = ComposerModel.menuState(
            conversation: conversation,
            selectedHarness: selectedHarness,
            reasoningControlHidden: reasoningPopup.isHidden
        )
        ComposerChrome.applyMenuState(
            state,
            placeholder: placeholder,
            harnessMenu: harnessMenu,
            modelMenu: modelMenu,
            reasoningMenu: reasoningMenu
        )
    }

    func harnessDidChange(conversation: Conversation?) -> Harness {
        reasoningPopup.isHidden = selectedHarness == .codex
        syncMenus(conversation: conversation)
        return selectedHarness
    }

    func pickCodexModel(_ id: String, conversation: Conversation?) {
        installCodexMenu(selection.pickCodexModel(id), conversation: conversation)
    }

    func pickCodexEffort(_ effort: String, conversation: Conversation?) {
        installCodexMenu(selection.pickCodexEffort(effort), conversation: conversation)
    }

    private func apply(
        _ action: ComposerHarnessSyncAction,
        for harness: Harness,
        conversation: Conversation?
    ) {
        switch action {
        case .installFallback(let preferred):
            installModelFallback(for: harness, preferred: preferred, conversation: conversation)
        case .selectPopupItem(let title):
            modelPopup.selectItem(withTitle: title)
            syncMenus(conversation: conversation)
        case .syncOnly:
            syncMenus(conversation: conversation)
        }
    }

    private func installModelFallback(
        for harness: Harness,
        preferred: String?,
        conversation: Conversation?
    ) {
        let fallback = selection.installFallback(for: harness, preferred: preferred)
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: fallback)
        modelPopup.selectItem(withTitle: fallback)
        reasoningPopup.isHidden = harness == .codex
        syncMenus(conversation: conversation)
    }

    private func installCodexModelMenu(_ ids: [String], conversation: Conversation?) {
        installCodexMenu(selection.installCodexMenu(ids: ids), conversation: conversation)
    }

    private func installCodexMenu(_ menuModel: ComposerCodexMenuModel, conversation: Conversation?) {
        guard let menuTarget else { return }
        modelPopup.menu = ComposerChrome.codexNestedMenu(
            model: menuModel,
            target: menuTarget,
            modelAction: modelAction,
            effortAction: effortAction
        )
        reasoningPopup.isHidden = true
        syncMenus(conversation: conversation)
    }

    private func replacePopupItems(ids: [String], selected: String?) {
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: ids)
        let icon = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        for i in modelPopup.itemArray.indices { modelPopup.item(at: i)?.image = icon }
        if let selected {
            modelPopup.selectItem(withTitle: selected)
        }
    }
}
