import Foundation

protocol DetachedChatWindowRepresenting: AnyObject {
    var conversation: Conversation { get }
    func show()
    func refresh()
    func refreshTitle()
}

extension DetachedChatWindowController: DetachedChatWindowRepresenting {}

final class AppDetachedChatWindowCoordinator {
    typealias WindowFactory = (
        _ conversation: Conversation,
        _ onClose: @escaping (any DetachedChatWindowRepresenting) -> Void
    ) -> any DetachedChatWindowRepresenting

    private let makeWindow: WindowFactory
    private var windows: [any DetachedChatWindowRepresenting] = []

    init(makeWindow: @escaping WindowFactory) {
        self.makeWindow = makeWindow
    }

    var windowCount: Int { windows.count }

    func open(_ conversation: Conversation) {
        let window = makeWindow(conversation) { [weak self] window in
            self?.remove(window)
        }
        windows.append(window)
        window.show()
    }

    func removeWindows(for conversation: Conversation) {
        windows.removeAll { $0.conversation === conversation }
    }

    func refreshWindows(for conversation: Conversation, rerender: Bool) {
        windows.forEach { window in
            guard window.conversation === conversation else { return }
            if rerender {
                window.refresh()
            } else {
                window.refreshTitle()
            }
        }
    }

    private func remove(_ window: any DetachedChatWindowRepresenting) {
        let id = ObjectIdentifier(window)
        windows.removeAll { ObjectIdentifier($0) == id }
    }
}
