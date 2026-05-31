import AppKit

/// View whose origin is top-left so transcript content grows downward.
final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// NSTextView that sends on Return and inserts a newline on Shift+Return.
final class ComposerTextView: NSTextView {
    var onSend: (() -> Void)?
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 36, !e.modifierFlags.contains(.shift) { onSend?(); return }
        super.keyDown(with: e)
    }
}

/// Animated "Thinking" label with shimmer effect.
final class ShimmerLabel: NSView {
    private let label = NSTextField(labelWithString: "Thinking")
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        setupShimmer()
    }

    private func setupShimmer() {
        gradient.frame = bounds.insetBy(dx: -bounds.width, dy: 0)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        let base = NSColor.tertiaryLabelColor.cgColor
        let highlight = NSColor.labelColor.cgColor
        gradient.colors = [base, base, highlight, base, base]
        gradient.locations = [0, 0.35, 0.5, 0.65, 1.0]
        layer?.mask = gradient

        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [0, 0.0, 0.1, 0.2, 0.3]
        anim.toValue = [0.7, 0.8, 0.9, 1.0, 1.0]
        anim.duration = 1.5
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: "shimmer")
    }
}

/// Detail pane: a centered transcript (user / assistant / tool rows) and a composer card.
final class ChatViewController: NSViewController, NSTextViewDelegate {
    var client: AgentClient!
    var onActivity: (() -> Void)?
    var onTitleGenerated: ((Conversation, String) -> Void)?

    private(set) var conversation: Conversation?
    private let transcript = NSStackView()
    private let scroll = NSScrollView()
    private let composer = ComposerTextView()
    private let placeholder = NSTextField(labelWithString: "Message the agent…  (⏎ to send, ⇧⏎ for newline)")
    private let modelPopup = NSPopUpButton()
    private let harnessPopup = NSPopUpButton()
    private let reasoningPopup = NSPopUpButton()
    private let contextLabel = NSTextField(labelWithString: "")
    private let sendButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let emptyTitle = NSTextField(labelWithString: "Start a conversation")
    private let emptySub = NSTextField(labelWithString: "Pick a model and send a prompt. The agent can run shell, edit files, and write its own tools.")
    private let emptyStack = NSStackView()
    private var labels: [ObjectIdentifier: NSTextField] = [:]
    private var streaming = false
    private let maxColumn: CGFloat = 100_000
    private var shimmerView: ShimmerLabel?
    /// The current assistant message being streamed into (for proper interleaving).
    private var currentAssistant: ChatMessage?

    var selectedModel: String { modelPopup.titleOfSelectedItem ?? "auto" }
    var selectedHarness: Harness { Harness(rawValue: harnessPopup.titleOfSelectedItem ?? "") ?? .dynagent }
    var selectedReasoning: String { reasoningPopup.titleOfSelectedItem ?? "high" }
    var onHarnessChanged: ((Harness) -> Void)?

    func setModels(_ ids: [String]) {
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: ids)
        let icon = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        for i in modelPopup.itemArray.indices { modelPopup.item(at: i)?.image = icon }
        if let i = ids.firstIndex(where: { $0 != "auto" }) { modelPopup.selectItem(at: i) }
    }
    func setContext(_ percent: Double?) {
        contextLabel.stringValue = percent.map { "context \(Int($0))%" } ?? ""
    }

    override func loadView() {
        transcript.orientation = .vertical
        transcript.alignment = .leading
        transcript.spacing = 18
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.addSubview(transcript)
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = doc
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Composer card
        composer.delegate = self
        composer.onSend = { [weak self] in self?.send() }
        composer.font = .systemFont(ofSize: 13.5)
        composer.isRichText = false
        composer.drawsBackground = false
        composer.textContainerInset = NSSize(width: 4, height: 8)
        composer.isVerticallyResizable = true
        composer.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        composer.autoresizingMask = [.width]
        let composerScroll = NSScrollView()
        composerScroll.drawsBackground = false
        composerScroll.documentView = composer
        composerScroll.translatesAutoresizingMaskIntoConstraints = false

        placeholder.textColor = .placeholderTextColor
        placeholder.font = .systemFont(ofSize: 13.5)
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        // Composer footer: harness + model selector + context usage on the left, send on the right.
        harnessPopup.controlSize = .small
        harnessPopup.font = .systemFont(ofSize: 11)
        harnessPopup.bezelStyle = .texturedRounded
        harnessPopup.addItems(withTitles: Harness.allCases.map(\.rawValue))
        harnessPopup.target = self
        harnessPopup.action = #selector(harnessDidChange)
        modelPopup.controlSize = .small
        modelPopup.font = .systemFont(ofSize: 11)
        modelPopup.bezelStyle = .texturedRounded
        reasoningPopup.controlSize = .small
        reasoningPopup.font = .systemFont(ofSize: 11)
        reasoningPopup.bezelStyle = .texturedRounded
        reasoningPopup.addItems(withTitles: ["high", "medium", "low"])
        reasoningPopup.selectItem(withTitle: "high")
        contextLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        contextLabel.textColor = .tertiaryLabelColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        sendButton.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        sendButton.isBordered = false
        sendButton.imagePosition = .imageOnly
        sendButton.target = self
        sendButton.action = #selector(send)
        let sendStack = NSVisualEffectView()
        sendStack.material = .menu
        sendStack.blendingMode = .withinWindow
        sendStack.state = .active
        sendStack.wantsLayer = true
        sendStack.layer?.cornerRadius = 14
        sendStack.layer?.masksToBounds = true
        sendStack.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendStack.addSubview(sendButton)
        sendStack.addSubview(spinner)

        let footer = NSStackView(views: [harnessPopup, modelPopup, reasoningPopup, contextLabel, NSView(), sendStack] as [NSView])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(composerScroll)
        card.addSubview(placeholder)
        card.addSubview(footer)

        emptyTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyTitle.alignment = .center
        emptySub.font = .systemFont(ofSize: 13)
        emptySub.textColor = .secondaryLabelColor
        emptySub.alignment = .center
        emptySub.lineBreakMode = .byWordWrapping
        emptySub.maximumNumberOfLines = 3
        emptySub.preferredMaxLayoutWidth = 360
        emptyStack.orientation = .vertical
        emptyStack.spacing = 6
        emptyStack.addArrangedSubview(emptyTitle)
        emptyStack.addArrangedSubview(emptySub)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scroll)
        root.addSubview(card)
        root.addSubview(emptyStack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -12),

            // Centered, max-width transcript column.
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            transcript.topAnchor.constraint(equalTo: doc.topAnchor, constant: 12),
            transcript.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -12),
            transcript.centerXAnchor.constraint(equalTo: doc.centerXAnchor),
            transcript.widthAnchor.constraint(lessThanOrEqualToConstant: maxColumn),
            transcript.leadingAnchor.constraint(greaterThanOrEqualTo: doc.leadingAnchor, constant: 28),
            column(transcript.widthAnchor.constraint(equalTo: doc.widthAnchor, constant: -56)),

            // Composer column (matches transcript width).
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: maxColumn),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 28),
            column(card.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56)),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            composerScroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            composerScroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            composerScroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            composerScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            composerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            composerScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            placeholder.leadingAnchor.constraint(equalTo: composerScroll.leadingAnchor, constant: 6),
            placeholder.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            footer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            footer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            sendStack.widthAnchor.constraint(equalToConstant: 28),
            sendStack.heightAnchor.constraint(equalToConstant: 28),
            sendButton.centerXAnchor.constraint(equalTo: sendStack.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendStack.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 28),
            sendButton.heightAnchor.constraint(equalToConstant: 28),
            spinner.centerXAnchor.constraint(equalTo: sendStack.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sendStack.centerYAnchor),

            emptyStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStack.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
        view = root
    }

    /// Lower the priority of a "preferred width" constraint so the column can shrink.
    private func column(_ c: NSLayoutConstraint) -> NSLayoutConstraint {
        c.priority = .defaultHigh
        return c
    }

    func show(_ c: Conversation) {
        conversation = c
        currentAssistant = nil
        labels.removeAll()
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for m in c.messages { addRow(for: m) }
        updateEmptyState()
        view.window?.makeFirstResponder(composer)
        scrollToBottom()
    }

    private func updateEmptyState() {
        let isEmpty = conversation?.messages.isEmpty ?? true
        emptyStack.isHidden = !isEmpty
    }

    // MARK: - Sending

    @objc private func send() {
        guard let c = conversation, !streaming else { return }
        let text = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composer.string = ""
        textDidChange(Notification(name: NSText.didChangeNotification))

        let isFirstMessage = c.messages.isEmpty

        let user = ChatMessage(role: .user, text: text)
        c.messages.append(user); addRow(for: user)
        updateEmptyState()

        // Show "Thinking" shimmer
        showThinking()

        setStreaming(true)
        c.status = .thinking
        onActivity?()

        // Generate title in parallel on first message
        if isFirstMessage {
            generateTitle(for: c, prompt: text)
        }

        currentAssistant = nil
        let handler: (AgentClient.Event) -> Void = { [weak self, weak c] ev in
            guard let self, let c else { return }
            switch ev {
            case .text(let t):
                self.hideThinking()
                if self.currentAssistant == nil {
                    let assistant = ChatMessage(role: .assistant, text: "")
                    c.messages.append(assistant)
                    self.addRow(for: assistant)
                    self.currentAssistant = assistant
                }
                self.currentAssistant!.text += t
                self.labels[ObjectIdentifier(self.currentAssistant!)]?.stringValue = self.currentAssistant!.text
            case .tool(let n):
                self.hideThinking()
                c.status = .running; self.onActivity?()
                self.currentAssistant = nil
                let tool = ChatMessage(role: .tool, text: "", toolName: n)
                c.messages.append(tool); self.addRow(for: tool)
            case .toolResult(let n):
                if let t = c.messages.last(where: { $0.role == .tool && $0.toolName == n && !$0.toolDone }) {
                    t.toolDone = true
                    self.labels[ObjectIdentifier(t)]?.attributedStringValue = self.toolString(t)
                }
            case .error(let e):
                self.hideThinking()
                if self.currentAssistant == nil {
                    let assistant = ChatMessage(role: .assistant, text: "")
                    c.messages.append(assistant)
                    self.addRow(for: assistant)
                    self.currentAssistant = assistant
                }
                self.currentAssistant!.text += (self.currentAssistant!.text.isEmpty ? "" : "\n") + "⚠︎ " + e
                self.labels[ObjectIdentifier(self.currentAssistant!)]?.stringValue = self.currentAssistant!.text
                c.status = .error; self.finish()
            case .done:
                self.hideThinking()
                c.status = .idle; self.finish()
            }
            self.scrollToBottom()
        }

        // Route to correct harness
        if selectedHarness == .codex {
            client.codexChat(model: selectedModel, messages: c.history, onEvent: handler)
        } else {
            client.chat(model: selectedModel, conversationId: c.id, cwd: c.workspace, messages: c.history, onEvent: handler)
        }
    }

    private func finish() { setStreaming(false); currentAssistant = nil; onActivity?() }

    @objc private func harnessDidChange() { onHarnessChanged?(selectedHarness) }

    private func setStreaming(_ on: Bool) {
        streaming = on
        sendButton.isHidden = on
        on ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    // MARK: - Thinking shimmer

    private func showThinking() {
        guard shimmerView == nil else { return }
        let s = ShimmerLabel()
        shimmerView = s
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(s)
        NSLayoutConstraint.activate([
            s.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            s.topAnchor.constraint(equalTo: container.topAnchor),
            s.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        scrollToBottom()
    }

    private func hideThinking() {
        guard let s = shimmerView else { return }
        s.superview?.removeFromSuperview()
        shimmerView = nil
    }

    // MARK: - Title generation

    private func generateTitle(for c: Conversation, prompt: String) {
        Task { @MainActor in
            let title = await client.generateTitle(prompt: prompt, model: selectedModel)
            if !title.isEmpty && title != "New Chat" {
                c.title = title
                onTitleGenerated?(c, title)
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !composer.string.isEmpty
    }

    // MARK: - Row rendering

    private func addRow(for m: ChatMessage) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let content = NSTextField(wrappingLabelWithString: "")
        content.isSelectable = true
        content.font = .systemFont(ofSize: 13.5)
        content.translatesAutoresizingMaskIntoConstraints = false

        switch m.role {
        case .assistant:
            content.stringValue = m.text
            container.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: container.topAnchor),
                content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        case .user:
            content.stringValue = m.text
            content.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let bubble = box(content, bg: NSColor.controlAccentColor.withAlphaComponent(0.16), inset: 10, radius: 14)
            container.addSubview(bubble)
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: container.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 70),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.78),
            ])
        case .tool:
            content.attributedStringValue = toolString(m)
            let pill = box(content, bg: NSColor.textColor.withAlphaComponent(0.05), inset: 8, radius: 8)
            container.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.topAnchor.constraint(equalTo: container.topAnchor),
                pill.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                pill.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                pill.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            ])
        }
        labels[ObjectIdentifier(m)] = content
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
    }

    private func toolString(_ m: ChatMessage) -> NSAttributedString {
        let mark = m.toolDone ? "✓" : "▸"
        return NSAttributedString(
            string: "\(mark)  \(m.toolName ?? "tool")",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                         .foregroundColor: m.toolDone ? NSColor.systemGreen : NSColor.systemOrange])
    }

    /// A rounded, padded background box hugging its content.
    private func box(_ content: NSView, bg: NSColor, inset: CGFloat, radius: CGFloat) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = bg.cgColor
        v.layer?.cornerRadius = radius
        v.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: v.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -inset),
            content.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: inset + 2),
            content.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -inset - 2),
        ])
        return v
    }

    private func scrollToBottom() {
        view.layoutSubtreeIfNeeded()
        guard let doc = scroll.documentView else { return }
        let y = max(0, doc.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
