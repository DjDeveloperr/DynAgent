import Foundation

enum ComposerConversationAdoptionAction: Equatable {
    case installCodexMenu([String])
    case selectPopupItem(String)
    case none
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
        selectedCodexModel = id
        return installCodexMenu(ids: codexModelIds.isEmpty ? [id] : codexModelIds)
    }

    mutating func pickCodexEffort(_ effort: String) -> ComposerCodexMenuModel {
        selectedCodexEffort = effort
        return installCodexMenu(ids: codexModelIds.isEmpty ? [selectedCodexModel] : codexModelIds)
    }
}
