import Foundation

enum ComposerConversationAdoptionAction: Equatable {
    case installCodexMenu([String])
    case selectPopupItem(String)
    case none
}

enum ComposerHarnessSyncMode: Equatable {
    case rememberPreferred
    case applyDefault
}

enum ComposerHarnessSyncAction: Equatable {
    case installFallback(preferred: String?)
    case selectPopupItem(String)
    case syncOnly
}

struct ComposerHarnessSyncPlan: Equatable {
    var harnessChanged: Bool
    var action: ComposerHarnessSyncAction
}

enum ComposerModelListSyncAction: Equatable {
    case installFallback(preferred: String?)
    case installCodexMenu([String])
    case replacePopupItems(ids: [String], selected: String?)
}

struct ComposerSelectionState: Equatable {
    var desiredModel: String?
    var codexModelIds: [String] = []
    var selectedCodexModel = "gpt-5.5"
    var selectedCodexEffort = "high"

    var resolvedCodexModel: String {
        ComposerModel.resolvedCodexModel(selectedCodexModel, available: codexModelIds)
    }

    mutating func rememberPreferredModel(_ model: String?) {
        if let model { desiredModel = model }
    }

    mutating func applyDefaultModel(_ model: String?) {
        desiredModel = model
    }

    mutating func planHarnessSync(
        targetHarness: Harness,
        preferredModel: String?,
        currentHarness: Harness,
        availablePopupItems: [String],
        popupItemCount: Int,
        mode: ComposerHarnessSyncMode
    ) -> ComposerHarnessSyncPlan {
        switch mode {
        case .rememberPreferred:
            rememberPreferredModel(preferredModel)
        case .applyDefault:
            applyDefaultModel(preferredModel)
        }

        let harnessChanged = currentHarness != targetHarness
        if harnessChanged {
            return ComposerHarnessSyncPlan(
                harnessChanged: true,
                action: .installFallback(preferred: preferredModel)
            )
        }

        if let preferredModel, availablePopupItems.contains(preferredModel) {
            return ComposerHarnessSyncPlan(
                harnessChanged: false,
                action: .selectPopupItem(preferredModel)
            )
        }

        if popupItemCount == 0 {
            return ComposerHarnessSyncPlan(
                harnessChanged: false,
                action: .installFallback(preferred: preferredModel)
            )
        }

        return ComposerHarnessSyncPlan(harnessChanged: false, action: .syncOnly)
    }

    mutating func adoptConversationModel(_ model: String?, harness: Harness) {
        desiredModel = model
        if harness == .codex, let model = model?.nilIfEmpty {
            selectedCodexModel = model
        }
    }

    mutating func adoptConversationModel(
        _ model: String?,
        harness: Harness,
        availablePopupItems: [String]
    ) -> ComposerConversationAdoptionAction {
        adoptConversationModel(model, harness: harness)
        if harness == .codex {
            return codexModelIds.isEmpty ? .none : .installCodexMenu(codexModelIds)
        }
        guard let model, availablePopupItems.contains(model) else { return .none }
        return .selectPopupItem(model)
    }

    func planModelListSync(ids: [String], selectedHarness: Harness) -> ComposerModelListSyncAction {
        guard !ids.isEmpty else {
            return .installFallback(preferred: desiredModel)
        }
        if selectedHarness == .codex {
            return .installCodexMenu(ids)
        }
        return .replacePopupItems(
            ids: ids,
            selected: ComposerModel.selectedModelForList(ids: ids, desiredModel: desiredModel)
        )
    }

    mutating func installFallback(for harness: Harness, preferred: String?) -> String {
        let fallback = ComposerModel.fallbackModel(for: harness, preferred: preferred)
        if harness == .codex {
            selectedCodexModel = fallback
        }
        return fallback
    }

    mutating func ensureCodexModelIsSupported() -> Bool {
        let resolved = self.resolvedCodexModel
        guard resolved != selectedCodexModel else { return false }
        selectedCodexModel = resolved
        return true
    }

    mutating func installCodexMenu(ids: [String]) -> ComposerCodexMenuModel {
        codexModelIds = ids
        let model = ComposerModel.codexMenuModel(
            ids: ids,
            desiredModel: desiredModel,
            currentModel: selectedCodexModel,
            selectedEffort: selectedCodexEffort
        )
        selectedCodexModel = model.selectedModel
        return model
    }

    mutating func pickCodexModel(_ id: String) -> ComposerCodexMenuModel {
        desiredModel = id
        selectedCodexModel = id
        return installCodexMenu(ids: codexModelIds.isEmpty ? [id] : codexModelIds)
    }

    mutating func pickCodexEffort(_ effort: String) -> ComposerCodexMenuModel {
        selectedCodexEffort = effort
        return installCodexMenu(ids: codexModelIds.isEmpty ? [selectedCodexModel] : codexModelIds)
    }
}
