import Foundation

struct AppModelCatalogBootstrap: Equatable {
    var codexModels: [String]
    var dynagentModels: [String]
    var defaultHarness: Harness
    var defaultModel: String
}

final class AppModelCatalogCoordinator {
    typealias Loader = () async -> [String]?

    private let dynagentLoader: Loader
    private let codexLoader: Loader
    private let piLoader: Loader
    private(set) var cache: [Harness: [String]] = [:]

    init(
        dynagentLoader: @escaping Loader,
        codexLoader: @escaping Loader,
        piLoader: @escaping Loader
    ) {
        self.dynagentLoader = dynagentLoader
        self.codexLoader = codexLoader
        self.piLoader = piLoader
    }

    convenience init(client: AgentClient) {
        self.init(
            dynagentLoader: {
                guard let models = try? await client.models() else { return nil }
                return models.map(\.id)
            },
            codexLoader: {
                guard let models = try? await client.codexModels() else { return nil }
                return models.map(\.id)
            },
            piLoader: {
                guard let models = try? await client.piModels() else { return nil }
                return models.map(\.id)
            }
        )
    }

    func restore(_ cache: [Harness: [String]]) {
        self.cache = cache
    }

    func cachedModels(for harness: Harness) -> [String]? {
        cache[harness]
    }

    func preferredModel(for harness: Harness) -> String {
        models(for: harness).first ?? fallbackModels(for: harness)[0]
    }

    func models(for harness: Harness) -> [String] {
        guard let cached = cache[harness], !cached.isEmpty else {
            return fallbackModels(for: harness)
        }
        return cached
    }

    func refresh(harness: Harness) async -> [String] {
        let loaded = await loader(for: harness)()
        let ids = loaded.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackModels(for: harness)
        cache[harness] = ids
        return ids
    }

    func bootstrapDefaultCatalog() async -> AppModelCatalogBootstrap {
        let codexModels = await refresh(harness: .codex)
        let dynagentModels = await refresh(harness: .dynagent)
        return AppModelCatalogBootstrap(
            codexModels: codexModels,
            dynagentModels: dynagentModels,
            defaultHarness: .codex,
            defaultModel: codexModels.first ?? fallbackModels(for: .codex)[0]
        )
    }

    func fallbackModels(for harness: Harness) -> [String] {
        switch harness {
        case .dynagent: return ["auto"]
        case .codex: return ["gpt-5.5"]
        case .pi: return ["kiro::kiro/claude-opus-4.8"]
        }
    }

    private func loader(for harness: Harness) -> Loader {
        switch harness {
        case .dynagent: return dynagentLoader
        case .codex: return codexLoader
        case .pi: return piLoader
        }
    }
}
