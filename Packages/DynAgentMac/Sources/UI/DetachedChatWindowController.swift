import AppKit

final class DetachedChatWindowController: NSObject, NSWindowDelegate {
    let conversation: Conversation
    private let window: NSWindow
    private let chat = ChatViewController()
    private let onClose: (DetachedChatWindowController) -> Void

    init(client: AgentClient,
         conversation: Conversation,
         models: [String],
         onActivity: @escaping (Conversation) -> Void,
         onTitleGenerated: @escaping (Conversation, String) -> Void,
         onClose: @escaping (DetachedChatWindowController) -> Void) {
        self.conversation = conversation
        self.onClose = onClose
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered,
                               defer: false)
        super.init()
        chat.client = client
        chat.onActivity = onActivity
        chat.onTitleGenerated = onTitleGenerated
        chat.setHarness(conversation.harness, preferredModel: conversation.model)
        if !models.isEmpty { chat.setModels(models) }
        chat.show(conversation)

        let title = ChatTitleModel.displayTitle(for: conversation)
        window.title = title
        chat.setHeaderTitle(title)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 560, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = chat
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        refreshTitle()
        chat.show(conversation)
    }

    func refreshTitle() {
        let title = ChatTitleModel.displayTitle(for: conversation)
        window.title = title
        chat.setHeaderTitle(title)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
