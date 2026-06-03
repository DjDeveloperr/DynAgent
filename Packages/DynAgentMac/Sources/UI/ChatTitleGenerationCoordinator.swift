import Foundation

final class ChatTitleGenerationCoordinator {
    typealias TitleLoader = (_ prompt: String, _ model: String) async -> String?
    typealias TitleGenerated = (_ conversation: Conversation, _ title: String) -> Void

    private let loadTitle: TitleLoader

    init(loadTitle: @escaping TitleLoader) {
        self.loadTitle = loadTitle
    }

    convenience init(client: AgentClient) {
        self.init { prompt, model in
            await client.generateTitle(prompt: prompt, model: model)
        }
    }

    @discardableResult
    func generate(
        for conversation: Conversation,
        prompt: String,
        model: String,
        onTitleGenerated: TitleGenerated?
    ) async -> String? {
        guard let title = ChatTitleModel.acceptedGeneratedTitle(
            await loadTitle(prompt, model)
        ) else { return nil }
        conversation.title = title
        onTitleGenerated?(conversation, title)
        return title
    }
}
