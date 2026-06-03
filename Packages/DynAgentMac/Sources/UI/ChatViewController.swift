import AppKit

/// Detail pane: a centered transcript (user / assistant / tool rows) and a composer card.
final class ChatViewController: NSViewController, NSTextViewDelegate {
    var client: AgentClient!
    var onActivity: ((Conversation) -> Void)?
    var onTitleGenerated: ((Conversation, String) -> Void)?
    var onAddWorkspace: (() -> Void)?
    var onNewWorktree: (() -> Void)?
    var onLayoutChanged: (() -> Void)?

    private(set) var conversation: Conversation?
    private let transcript = NSStackView()
    private let scroll = NSScrollView()
    private let headerTitle = NSTextField(labelWithString: "New Chat")
    private let headerMenuButton = NSButton()
    private let composer = ComposerTextView()
    private let placeholder = NSTextField(labelWithString: "Message the agent…  (⏎ to send, ⇧⏎ for newline)")
    private let modelPopup = NSPopUpButton()
    private let harnessPopup = NSPopUpButton()
    private let reasoningPopup = NSPopUpButton()
    private let addAttachmentButton = NSButton()
    private let attachmentScroll = NSScrollView()
    private let attachmentStack = NSStackView()
    private var modelMenu: ComposerMenuChrome?
    private var harnessMenu: ComposerMenuChrome?
    private var reasoningMenu: ComposerMenuChrome?
    private let contextRing = ContextRing()
    private let sendButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let card = NSGlassEffectView()
    private let cardContent = NSView()
    private var bottomInsetCache: CGFloat = 0
    private let emptyTitle = NSTextField(labelWithString: "Start a conversation")
    private let emptySub = NSTextField(labelWithString: "Workspace")
    private let emptyStack = NSStackView()
    private let emptyActions = NSStackView()
    private var cardBottomConstraint: NSLayoutConstraint?
    private var cardCenterYConstraint: NSLayoutConstraint?
    private var attachmentHeightConstraint: NSLayoutConstraint?
    private var labels: [ObjectIdentifier: MessageTextView] = [:]
    private var toolByView: [ObjectIdentifier: ChatMessage] = [:]
    private var editStatsByMessage: [ObjectIdentifier: EditStatsView] = [:]
    private let toolPopover = NSPopover()
    private var streamingConversationIds = Set<String>()
    private var streamTasks: [String: URLSessionDataTask] = [:]
    private var stopping = false
    private var bulkLoading = false
    private var turnStart = Date()
    private var copyText: [ObjectIdentifier: String] = [:]
    private var shimmerView: ShimmerLabel?
    private var liveWorkDividerByConversationId: [String: WorkDivider] = [:]
    /// The current assistant message being streamed into (for proper interleaving).
    private var currentAssistant: ChatMessage?
    private var assistantByConversationId: [String: ChatMessage] = [:]
    private let maxRenderedMessages = 240
    private var codexModelIds: [String] = []
    private var selectedCodexModel = "gpt-5.5"
    private var selectedCodexEffort = "high"
    private var attachments: [ComposerAttachment] = []
    private var attachmentRemoveIds: [ObjectIdentifier: UUID] = [:]
    private var lastLiveMarkdownRender: [ObjectIdentifier: TimeInterval] = [:]
    private var lastActivityEmit: [String: TimeInterval] = [:]
    private var pendingToolRefreshByConversationId: [String: DispatchWorkItem] = [:]
    private var transcriptRenderGeneration = 0
    private var renderedTranscriptConversationId: String?
    private var renderedTranscriptFingerprint: Int?
    private var lastScrollToBottomAt: TimeInterval = 0
    private var pendingScrollToBottom = false
    private var restoringComposerDraft = false
    private var draftSaveWorkItem: DispatchWorkItem?
    private let composerDraftStore = ComposerDraftStore()

    private var streaming: Bool {
        guard let conversation else { return false }
        return isActiveConversation(conversation)
    }

    func hasLocalStream(for c: Conversation) -> Bool {
        streamingConversationIds.contains(c.id)
    }

    var selectedModel: String {
        if selectedHarness == .codex { return resolvedCodexModel(selectedCodexModel) }
        return modelPopup.titleOfSelectedItem ?? "auto"
    }
    var selectedHarness: Harness { Harness(rawValue: harnessPopup.titleOfSelectedItem ?? "") ?? .dynagent }
    var selectedReasoning: String {
        if selectedHarness == .codex { return selectedCodexEffort }
        return reasoningPopup.titleOfSelectedItem ?? "high"
    }
    var onHarnessChanged: ((Harness) -> Void)?
    var onChatMenu: ((NSButton) -> Void)?
    /// Model to auto-select once a (possibly async) model list arrives.
    private var desiredModel: String?

    /// Sync the composer's harness picker to a conversation, reloading models if it changed.
    func setHarness(_ h: Harness, preferredModel: String? = nil) {
        if let preferredModel { desiredModel = preferredModel }
        let changed = selectedHarness != h
        if changed {
            harnessPopup.selectItem(withTitle: h.rawValue)
            reasoningPopup.isHidden = h == .codex
            installModelFallback(for: h, preferred: preferredModel)
            syncComposerMenus()
            onHarnessChanged?(h)
        } else if let preferredModel, modelPopup.itemTitles.contains(preferredModel) {
            modelPopup.selectItem(withTitle: preferredModel)
            syncComposerMenus()
        } else if modelPopup.numberOfItems == 0 {
            installModelFallback(for: h, preferred: preferredModel)
        } else {
            syncComposerMenus()
        }
    }

    /// Apply remembered harness+model as the composer defaults (used for new chats on launch).
    func applyDefaults(harness: Harness, model: String?) {
        desiredModel = model
        if harnessPopup.titleOfSelectedItem != harness.rawValue {
            harnessPopup.selectItem(withTitle: harness.rawValue)
            reasoningPopup.isHidden = harness == .codex
            installModelFallback(for: harness, preferred: model)
            syncComposerMenus()
            onHarnessChanged?(harness)
        } else if let model, modelPopup.itemTitles.contains(model) {
            modelPopup.selectItem(withTitle: model)
            syncComposerMenus()
        } else if modelPopup.numberOfItems == 0 {
            installModelFallback(for: harness, preferred: model)
        } else {
            syncComposerMenus()
        }
    }

    func setModels(_ ids: [String]) {
        guard !ids.isEmpty else {
            installModelFallback(for: selectedHarness, preferred: desiredModel)
            return
        }
        if selectedHarness == .codex {
            installCodexModelMenu(ids)
            return
        }
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: ids)
        let icon = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        for i in modelPopup.itemArray.indices { modelPopup.item(at: i)?.image = icon }
        if let selected = ComposerModel.selectedModelForList(ids: ids, desiredModel: desiredModel) {
            modelPopup.selectItem(withTitle: selected)
        }
        syncComposerMenus()
    }

    private func installModelFallback(for harness: Harness, preferred: String?) {
        let fallback = ComposerModel.fallbackModel(for: harness, preferred: preferred)
        if harness == .codex { selectedCodexModel = fallback }
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: fallback)
        modelPopup.selectItem(withTitle: fallback)
        reasoningPopup.isHidden = harness == .codex
        syncComposerMenus()
    }

    private func resolvedCodexModel(_ preferred: String?) -> String {
        ComposerModel.resolvedCodexModel(preferred, available: codexModelIds)
    }

    private func ensureSelectedCodexModelIsSupported() {
        let resolved = resolvedCodexModel(selectedCodexModel)
        guard resolved != selectedCodexModel else { return }
        selectedCodexModel = resolved
        if !codexModelIds.isEmpty { installCodexModelMenu(codexModelIds) }
    }

    private func installCodexModelMenu(_ ids: [String]) {
        codexModelIds = ids
        let menuModel = ComposerModel.codexMenuModel(
            ids: ids,
            desiredModel: desiredModel,
            currentModel: selectedCodexModel,
            selectedEffort: selectedCodexEffort
        )
        selectedCodexModel = menuModel.selectedModel
        let modelMenu = NSMenu()
        for entry in menuModel.modelItems {
            let item = NSMenuItem(title: entry.title, action: #selector(codexModelPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.representedValue
            item.state = entry.isSelected ? .on : .off
            modelMenu.addItem(item)
        }
        let effortMenu = NSMenu()
        for entry in menuModel.effortItems {
            let item = NSMenuItem(title: entry.title, action: #selector(codexEffortPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.representedValue
            item.state = entry.isSelected ? .on : .off
            effortMenu.addItem(item)
        }
        let menu = NSMenu()
        let modelParent = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelParent.submenu = modelMenu
        let effortParent = NSMenuItem(title: "Reasoning", action: nil, keyEquivalent: "")
        effortParent.submenu = effortMenu
        menu.addItem(modelParent)
        menu.addItem(effortParent)
        modelPopup.menu = menu
        reasoningPopup.isHidden = true
        syncComposerMenus()
    }

    func setContext(_ percent: Double?) {
        let state = ComposerModel.contextState(percent: percent)
        contextRing.fraction = state.fraction
        contextRing.toolTip = state.tooltip
        contextRing.isHidden = false
    }

    func setHeaderTitle(_ title: String) {
        headerTitle.stringValue = title.nilIfEmpty ?? "New Chat"
    }

    var layoutMetrics: [String: Any] {
        let rootSubviewFrames = view.subviews.enumerated().map { index, subview in
            [
                "index": index,
                "class": String(describing: type(of: subview)),
                "x": Double(subview.frame.minX),
                "y": Double(subview.frame.minY),
                "width": Double(subview.frame.width),
                "height": Double(subview.frame.height),
            ] as [String: Any]
        }
        return [
            "chatViewWidth": Double(view.frame.width),
            "chatViewHeight": Double(view.frame.height),
            "scrollWidth": Double(scroll.frame.width),
            "scrollHeight": Double(scroll.frame.height),
            "documentWidth": Double((scroll.documentView?.frame.width) ?? -1),
            "documentHeight": Double((scroll.documentView?.frame.height) ?? -1),
            "transcriptWidth": Double(transcript.frame.width),
            "transcriptHeight": Double(transcript.frame.height),
            "composerWidth": Double(card.frame.width),
            "composerHeight": Double(card.frame.height),
            "visibleRows": transcript.arrangedSubviews.count,
            "rootSubviewFrames": rootSubviewFrames,
        ]
    }

    override func loadView() {
        transcript.orientation = .vertical
        transcript.alignment = .leading
        transcript.spacing = 14
        transcript.translatesAutoresizingMaskIntoConstraints = false
        transcript.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        transcript.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let doc = FlippedView()
        doc.addSubview(transcript)
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        doc.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 96, right: 0)
        scroll.documentView = doc
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)

        ChatHeaderChrome.configureTitle(headerTitle)
        ChatHeaderChrome.configureMenuButton(headerMenuButton, target: self, action: #selector(showHeaderMenu(_:)))

        // Composer card
        composer.delegate = self
        composer.onSend = { [weak self] in self?.send() }
        composer.onPasteAttachments = { [weak self] urls in self?.addAttachments(urls) }
        ComposerChrome.configureTextView(composer)
        let composerScroll = NSScrollView()
        composerScroll.drawsBackground = false
        composerScroll.documentView = composer
        composerScroll.translatesAutoresizingMaskIntoConstraints = false

        ComposerChrome.configurePlaceholder(placeholder)

        ComposerChrome.configureAttachmentStrip(stack: attachmentStack, scroll: attachmentScroll)

        // Composer footer: harness + model selector + context usage on the left, send on the right.
        ComposerChrome.configurePopup(harnessPopup)
        harnessPopup.addItems(withTitles: Harness.allCases.map(\.rawValue))
        harnessPopup.target = self
        harnessPopup.action = #selector(harnessDidChange)
        ComposerChrome.configurePopup(modelPopup)
        modelPopup.target = self
        modelPopup.action = #selector(menuDidChange)
        ComposerChrome.configurePopup(reasoningPopup)
        reasoningPopup.addItems(withTitles: ["high", "medium", "low", "xhigh"])
        reasoningPopup.selectItem(withTitle: "high")
        reasoningPopup.target = self
        reasoningPopup.action = #selector(menuDidChange)

        ComposerChrome.configureSpinner(spinner)
        ComposerChrome.configureSendButton(sendButton, target: self, action: #selector(send))
        ComposerChrome.configureAttachmentButton(addAttachmentButton, target: self, action: #selector(addAttachmentClicked))
        let sendStack = ComposerChrome.makeSendContainer(button: sendButton, spinner: spinner)

        let harnessMenu = ComposerMenuChrome(popup: harnessPopup, minWidth: 82)
        let modelMenu = ComposerMenuChrome(popup: modelPopup, minWidth: 58)
        let reasoningMenu = ComposerMenuChrome(popup: reasoningPopup, minWidth: 70)
        modelMenu.displayProvider = { [weak self] in self?.modelMenuTitle() }
        self.harnessMenu = harnessMenu
        self.modelMenu = modelMenu
        self.reasoningMenu = reasoningMenu

        let footer = ComposerChrome.makeFooter(
            addAttachmentButton: addAttachmentButton,
            harnessMenu: harnessMenu,
            modelMenu: modelMenu,
            reasoningMenu: reasoningMenu,
            contextRing: contextRing,
            sendContainer: sendStack
        )

        card.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        attachmentHeightConstraint = attachmentScroll.heightAnchor.constraint(equalToConstant: 0)
        cardContent.addSubview(composerScroll)
        cardContent.addSubview(placeholder)
        cardContent.addSubview(attachmentScroll)
        cardContent.addSubview(footer)
        card.contentView = cardContent

        ChatEmptyStateChrome.configureTitle(emptyTitle)
        ChatEmptyStateChrome.configureSubtitle(emptySub)
        ChatEmptyStateChrome.configureActions(emptyActions)
        emptyActions.addArrangedSubview(ChatEmptyStateChrome.makeAction(
            title: "New Worktree",
            symbol: "arrow.triangle.branch",
            target: self,
            action: #selector(newWorktreeClicked)
        ))
        emptyActions.addArrangedSubview(ChatEmptyStateChrome.makeAction(
            title: "Add Workspace",
            symbol: "folder.badge.plus",
            target: self,
            action: #selector(addWorkspaceClicked)
        ))
        ChatEmptyStateChrome.configureStack(emptyStack, title: emptyTitle, subtitle: emptySub, actions: emptyActions)

        let root = FlexibleContainerView()
        root.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addSubview(scroll)
        root.addSubview(headerTitle)
        root.addSubview(headerMenuButton)
        root.addSubview(card)
        root.addSubview(emptyStack)

        // Hairline at the very top of the transcript area.
        let topBorder = NSBox()
        topBorder.boxType = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(topBorder)

        cardBottomConstraint = card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        cardCenterYConstraint = card.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 88)
        cardCenterYConstraint?.isActive = false

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            // Transcript fills the available chat panel width with side padding.
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            transcript.topAnchor.constraint(equalTo: doc.topAnchor, constant: 20),
            transcript.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -12),
            transcript.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: ChatLayoutModel.horizontalInset),
            transcript.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -ChatLayoutModel.horizontalInset),

            // Composer matches the full transcript width.
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: ChatLayoutModel.horizontalInset),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -ChatLayoutModel.horizontalInset),
            cardBottomConstraint!,

            attachmentScroll.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 10),
            attachmentScroll.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 12),
            attachmentScroll.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -12),
            attachmentHeightConstraint!,

            composerScroll.topAnchor.constraint(equalTo: attachmentScroll.bottomAnchor, constant: 6),
            composerScroll.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 12),
            composerScroll.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -12),
            composerScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            composerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),
            composerScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            placeholder.leadingAnchor.constraint(equalTo: composerScroll.leadingAnchor, constant: 2),
            placeholder.topAnchor.constraint(equalTo: composerScroll.topAnchor, constant: 8),

            footer.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -12),
        ] + ComposerChrome.footerControlConstraints(
            addAttachmentButton: addAttachmentButton,
            sendContainer: sendStack,
            sendButton: sendButton,
            spinner: spinner
        ) + [

            emptyStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStack.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -24),
            emptyStack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),

        ] + ChatHeaderChrome.constraints(
            title: headerTitle,
            menuButton: headerMenuButton,
            root: root
        ) + [

            topBorder.topAnchor.constraint(equalTo: root.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
    }

    @objc private func showHeaderMenu(_ sender: NSButton) {
        onChatMenu?(sender)
    }

    /// Keep the transcript clear of the floating composer: bottom inset tracks the composer height.
    override func viewDidLayout() {
        super.viewDidLayout()
        let inset = card.frame.height + 28
        if abs(inset - bottomInsetCache) > 1 {
            bottomInsetCache = inset
            scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
        }
    }

    private func syncComposerMenus() {
        harnessMenu?.refresh()
        modelMenu?.refresh()
        reasoningMenu?.refresh()
        let state = ComposerModel.menuState(
            conversation: conversation,
            selectedHarness: selectedHarness,
            reasoningControlHidden: reasoningPopup.isHidden
        )
        placeholder.stringValue = state.placeholder
        harnessMenu?.isHidden = !state.showsHarnessMenu
        reasoningMenu?.isHidden = !state.showsReasoningMenu
    }

    private func modelMenuTitle() -> NSAttributedString? {
        guard selectedHarness == .codex else { return nil }
        let title = NSMutableAttributedString(string: ComposerModel.shortCodexModelName(selectedCodexModel), attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        title.append(NSAttributedString(string: " \(ComposerModel.effortDisplayName(selectedCodexEffort))", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    @objc private func addWorkspaceClicked() {
        onAddWorkspace?()
    }

    @objc private func newWorktreeClicked() {
        onNewWorktree?()
    }

    @objc private func addAttachmentClicked() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.addAttachments(panel.urls)
        }
    }

    private func addAttachments(_ urls: [URL]) {
        let additions = ComposerModel.attachmentAdditions(existing: attachments, incoming: urls)
        guard !additions.isEmpty else { return }
        attachments.append(contentsOf: additions)
        renderAttachments()
        updateSendButton()
        saveComposerDraft()
    }

    private func renderAttachments() {
        attachmentRemoveIds = ComposerAttachmentStripChrome.render(
            attachments: attachments,
            into: attachmentStack,
            inside: attachmentScroll,
            heightConstraint: attachmentHeightConstraint,
            target: self,
            removeAction: #selector(removeAttachment(_:))
        )
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        guard let id = attachmentRemoveIds[ObjectIdentifier(sender)] else { return }
        attachments.removeAll { $0.id == id }
        renderAttachments()
        updateSendButton()
        saveComposerDraft()
    }

    func saveComposerDraft() {
        guard !restoringComposerDraft, let c = conversation else { return }
        draftSaveWorkItem?.cancel()
        draftSaveWorkItem = nil
        composerDraftStore.save(text: composer.string, attachments: attachments, for: c)
    }

    private func scheduleComposerDraftSave() {
        guard !restoringComposerDraft else { return }
        draftSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveComposerDraft() }
        draftSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func restoreComposerDraft(for c: Conversation) {
        let snapshot = composerDraftStore.snapshot(for: c)
        restoringComposerDraft = true
        composer.string = snapshot?.text ?? ""
        attachments = composerDraftStore.restoredAttachments(for: c) { FileManager.default.fileExists(atPath: $0) }
        renderAttachments()
        restoringComposerDraft = false
        placeholder.isHidden = !composer.string.isEmpty
    }

    private func clearComposerDraft(for c: Conversation) {
        composerDraftStore.clear(for: c)
    }

    func show(_ c: Conversation) {
        saveComposerDraft()
        transcriptRenderGeneration += 1
        let generation = transcriptRenderGeneration
        let wasShowingSameConversation = conversation === c
        conversation = c
        desiredModel = c.model
        if c.harness == .codex {
            selectedCodexModel = c.model.nilIfEmpty ?? selectedCodexModel
            if !codexModelIds.isEmpty { installCodexModelMenu(codexModelIds) }
        } else if modelPopup.itemTitles.contains(c.model) {
            modelPopup.selectItem(withTitle: c.model)
        }
        syncComposerMenus()
        let fingerprint = TranscriptRenderModel.fingerprint(for: c, maxRenderedMessages: maxRenderedMessages)
        if wasShowingSameConversation,
           !isActiveConversation(c),
           renderedTranscriptConversationId == c.id,
           renderedTranscriptFingerprint == fingerprint {
            restoreComposerDraft(for: c)
            updateEmptyState()
            updateSendButton()
            view.window?.makeFirstResponder(composer)
            return
        }
        renderedTranscriptConversationId = c.id
        renderedTranscriptFingerprint = fingerprint
        shimmerView = nil
        currentAssistant = assistantByConversationId[c.id]
        labels.removeAll()
        toolByView.removeAll()
        editStatsByMessage.removeAll()
        liveWorkDividerByConversationId.removeValue(forKey: c.id)
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bulkLoading = true
        // Render each turn: prompt + work divider + final answer.
        let plan = TranscriptTurnModel.plan(
            messages: c.messages,
            maxRenderedMessages: maxRenderedMessages,
            isActive: isActiveConversation(c),
            updatedAt: c.updatedAt
        )
        if plan.hiddenCount > 0 { addLargeThreadNotice(hiddenCount: plan.hiddenCount) }
        restoreComposerDraft(for: c)
        updateEmptyState()
        updateSendButton()
        view.window?.makeFirstResponder(composer)
        renderTurnsAsync(plan.turns, conversation: c, generation: generation)
    }

    func showShell(_ c: Conversation) {
        saveComposerDraft()
        transcriptRenderGeneration += 1
        conversation = c
        desiredModel = c.model
        if c.harness == .codex {
            selectedCodexModel = c.model.nilIfEmpty ?? selectedCodexModel
            if !codexModelIds.isEmpty { installCodexModelMenu(codexModelIds) }
        } else if modelPopup.itemTitles.contains(c.model) {
            modelPopup.selectItem(withTitle: c.model)
        }
        shimmerView = nil
        currentAssistant = assistantByConversationId[c.id]
        labels.removeAll()
        toolByView.removeAll()
        editStatsByMessage.removeAll()
        liveWorkDividerByConversationId.removeValue(forKey: c.id)
        renderedTranscriptConversationId = nil
        renderedTranscriptFingerprint = nil
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let loading = NSTextField(labelWithString: c.needsLoad ? "Loading latest thread..." : "Loading conversation...")
        loading.font = .systemFont(ofSize: 12.5, weight: .medium)
        loading.textColor = .tertiaryLabelColor
        loading.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loading.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            loading.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        emptyStack.isHidden = true
        cardBottomConstraint?.isActive = true
        cardCenterYConstraint?.isActive = false
        syncComposerMenus()
        restoreComposerDraft(for: c)
        updateSendButton()
        view.window?.makeFirstResponder(composer)
    }

    private func renderTurnsAsync(_ turns: [TranscriptRenderTurn], conversation c: Conversation, generation: Int, startIndex: Int = 0) {
        guard generation == transcriptRenderGeneration, self.conversation === c else { return }
        if let range = TranscriptRenderModel.batchRange(totalCount: turns.count, startIndex: startIndex) {
            for index in range {
                let turn = turns[index]
                renderTurn(turn.messages, conversation: c, allowCollapse: turn.allowCollapse, forceActive: turn.forceActive)
            }

            if range.upperBound < turns.count {
                DispatchQueue.main.async { [weak self, weak c] in
                    guard let self, let c else { return }
                    self.renderTurnsAsync(turns, conversation: c, generation: generation, startIndex: range.upperBound)
                }
                return
            }
        }

        bulkLoading = false
        if isActiveConversation(c) { showThinking() }
        updateEmptyState()
        scrollToBottom()
        onLayoutChanged?()
    }

    /// Render one turn with its work divider above the final assistant response.
    private func renderTurn(_ turn: [ChatMessage], conversation c: Conversation, allowCollapse: Bool, forceActive: Bool = false) {
        let activeTurn = forceActive || (isActiveConversation(c) && !allowCollapse && TranscriptTurnModel.latestTurnHasRunningStatus(turn))
        if activeTurn {
            renderActiveTurn(turn, conversation: c)
            return
        }
        let finalIdx = allowCollapse ? turn.lastIndex { ($0.isFinal == true) || ($0.isFinal == nil && $0.role == .assistant && !$0.text.isEmpty) } : nil
        guard let finalIdx else {
            for m in turn { addRow(for: m) }
            return
        }
        var middle: [ChatMessage] = []
        for (k, m) in turn.enumerated() {
            if m.role == .user && m.isSteer != true { addRow(for: m) }
            else if k == finalIdx { continue }
            else { middle.append(m) }
        }
        let divider = addWorkDivider(duration: turn[finalIdx].turnDuration)
        divider.rows = addRowsGrouped(middle).map { row in row.isHidden = true; return row }
        divider.refresh()
        addRow(for: turn[finalIdx])
        addFinalFooter(for: turn[finalIdx])
    }

    private func renderActiveTurn(_ turn: [ChatMessage], conversation c: Conversation) {
        let started = turn.compactMap(\.turnStartedAt).first ?? activeTurnStartedAt(for: c) ?? Date().timeIntervalSince1970
        var middle: [ChatMessage] = []
        for m in turn {
            if m.role == .user && m.isSteer != true { addRow(for: m) }
            else { middle.append(m) }
        }
        let divider = addWorkDivider(duration: Date().timeIntervalSince1970 - started, collapsed: false, active: true)
        liveWorkDividerByConversationId[c.id] = divider
        divider.rows = addRowsGrouped(middle, collapseCompletedTools: false)
        divider.refresh()
    }

    private func addRowsGrouped(_ messages: [ChatMessage], collapseCompletedTools: Bool = true) -> [NSView] {
        TranscriptRenderModel.groupedItems(messages: messages, collapseCompletedTools: collapseCompletedTools).map { item in
            switch item {
            case .message(let message):
                return addRow(for: message)
            case .editGroup(let changes):
                return addEditGroupRow(changes)
            case .shellGroup(let shellMessages):
                return addShellGroupRow(shellMessages)
            }
        }
    }

    @discardableResult
    private func addShellGroupRow(_ messages: [ChatMessage]) -> NSView {
        let items = messages.map { m -> ShellGroupItem in
            let summary = TranscriptToolFormatter.shellSummary(m)
            return ShellGroupItem(title: TranscriptToolFormatter.shellTitle(m, summary: summary), output: summary.output, done: m.toolDone)
        }
        let title = TranscriptToolFormatter.shellGroupTitle(messages.map(TranscriptToolFormatter.shellSummary))
        let group = ShellGroupView(title: title, items: items)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(group)
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: container.topAnchor),
            group.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            group.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        if !bulkLoading { pinShimmerToBottom() }
        return container
    }

    @discardableResult
    private func addEditGroupRow(_ changes: [EditToolChange]) -> NSView {
        let group = EditGroupView(changes: changes)
        group.onOpenChange = { [weak self] change, anchor in
            self?.showEditPopover(changes: [change], anchor: anchor)
        }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(group)
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: container.topAnchor),
            group.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            group.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        if !bulkLoading { pinShimmerToBottom() }
        return container
    }

    @discardableResult
    private func addWorkDivider(duration: Double?, collapsed: Bool = true, active: Bool = false) -> WorkDivider {
        let divider = WorkDivider(duration: duration, collapsed: collapsed, active: active)
        transcript.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        pinShimmerToBottom()
        return divider
    }

    private func ensureLiveWorkDivider(for c: Conversation) -> WorkDivider {
        if let existing = liveWorkDividerByConversationId[c.id] { return existing }
        let startedAt = activeTurnStartedAt(for: c) ?? turnStart.timeIntervalSince1970
        let divider = addWorkDivider(duration: Date().timeIntervalSince1970 - startedAt, collapsed: false, active: true)
        liveWorkDividerByConversationId[c.id] = divider
        return divider
    }

    private func isActiveConversation(_ c: Conversation) -> Bool {
        streamingConversationIds.contains(c.id) || c.status == .thinking || c.status == .running
    }

    private func activeTurnStartedAt(for c: Conversation) -> Double? {
        TranscriptTurnModel.activeStartedAt(messages: c.messages, fallbackUpdatedAt: c.updatedAt)
    }

    /// Copy button + timestamp under a turn's final assistant message.
    private func addFinalFooter(for m: ChatMessage) {
        let footer = TranscriptRowChrome.finalFooter(
            text: m.text,
            timestamp: m.timestamp,
            target: self,
            copyAction: #selector(copyFinal(_:))
        )
        let copy = footer.copyButton
        copyText[ObjectIdentifier(copy)] = m.text
        let container = footer.view
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
    }

    @objc private func copyFinal(_ sender: NSButton) {
        guard let t = copyText[ObjectIdentifier(sender)] else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
    }

    private func updateEmptyState() {
        let isEmpty = conversation?.messages.isEmpty ?? true
        if let workspace = conversation?.workspace, !workspace.isEmpty {
            emptySub.stringValue = (workspace as NSString).lastPathComponent
        } else {
            emptySub.stringValue = "Workspace"
        }
        emptyStack.isHidden = !isEmpty
        cardBottomConstraint?.isActive = !isEmpty
        cardCenterYConstraint?.isActive = isEmpty
    }

    // MARK: - Sending

    @objc private func send() {
        guard let c = conversation else { return }
        let typedText = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = messageTextWithAttachments(typedText)
        if text.isEmpty {
            if streaming { stop() }   // empty + streaming => the button is a Stop button
            return
        }
        composer.string = ""
        attachments.removeAll()
        renderAttachments()
        clearComposerDraft(for: c)
        textDidChange(Notification(name: NSText.didChangeNotification))

        // Steering: while a turn streams, inject the message. Codex steers natively (turn/steer);
        // DynAgent queues it for delivery on the next turn.
        if streaming {
            if c.harness == .codex, let tid = c.codexThreadId {
                addSteerNotice(to: c, text: text)
                Task { [weak self, weak c] in
                    guard let self, let c else { return }
                    do {
                        try await self.client.codexSteer(threadId: tid, text: text)
                    } catch {
                        await MainActor.run { self.addInlineError(error.localizedDescription, to: c) }
                    }
                }
            } else {
                c.steerQueue.append(text)
                addSteerNotice(to: c, text: text)
            }
            scrollToBottom()
            return
        }
        startTurn(text, on: c)
    }

    private func messageTextWithAttachments(_ text: String) -> String {
        ComposerModel.messageText(typedText: text, attachmentPaths: ComposerModel.normalizedAttachmentPaths(attachments))
    }

    private func stop() {
        guard let c = conversation else { return }
        stopping = true
        c.steerQueue.removeAll()
        if c.harness == .codex, let tid = c.codexThreadId {
            Task { await client.codexCancel(threadId: tid) }
        }
        client.cancel(streamTasks[c.id])
        hideThinking(); finalizeAssistant(for: c)
        c.status = .idle
        finish(c)
    }

    private func startTurn(_ text: String, on c: Conversation, appendUser: Bool = true) {
        if selectedHarness == .codex { ensureSelectedCodexModelIsSupported() }
        // Lock the conversation to the selected harness/model and remember as defaults.
        c.harness = selectedHarness
        c.model = selectedModel
        Store.saveLast(harness: selectedHarness, model: selectedModel)
        let startedAt = Date().timeIntervalSince1970
        if appendUser { turnStart = Date(timeIntervalSince1970: startedAt) }

        if appendUser {
            let user = ChatMessage(role: .user, text: text)
            user.turnStartedAt = startedAt
            user.turnStatus = "running"
            c.messages.append(user); addRow(for: user)
        }
        if conversation === c { syncComposerMenus() }
        updateEmptyState()

        let isFirstMessage = c.messages.filter { $0.role == .user }.count == 1

        setStreaming(true, for: c)
        c.status = .thinking
        c.updatedAt = Date().timeIntervalSince1970
        if conversation === c {
            _ = ensureLiveWorkDivider(for: c)
            showThinking()
        }
        emitActivity(c, force: true)

        if isFirstMessage { generateTitle(for: c, prompt: text) }

        assistantByConversationId[c.id] = nil
        if conversation === c { currentAssistant = nil }
        let handler: (AgentClient.Event) -> Void = { [weak self, weak c] ev in
            guard let self, let c else { return }
            let isVisible = self.conversation === c
            switch ev {
            case .thread(let id):
                c.codexThreadId = id
            case .text(let t):
                self.markOpenToolsCompleted(in: c)
                let assistant: ChatMessage
                if let existing = self.assistantByConversationId[c.id] {
                    assistant = existing
                } else {
                    let assistant = ChatMessage(role: .assistant, text: "")
                    c.messages.append(assistant)
                    self.assistantByConversationId[c.id] = assistant
                    if isVisible {
                        _ = self.ensureLiveWorkDivider(for: c)
                        self.addRow(for: assistant)
                        self.currentAssistant = assistant
                    }
                    assistant.text += t
                    if isVisible { self.renderLiveAssistant(assistant) }
                    self.emitActivity(c)
                    break
                }
                assistant.text += t
                if isVisible { self.renderLiveAssistant(assistant) }
                self.emitActivity(c)
            case .steer:
                self.addSteerNotice(to: c)
            case .tool(let n, let d):
                self.markOpenToolsCompleted(in: c)
                c.status = .running
                c.updatedAt = Date().timeIntervalSince1970
                self.emitActivity(c)
                if isVisible { self.finalizeAssistant(for: c) }
                self.assistantByConversationId[c.id] = nil
                if isVisible { self.currentAssistant = nil }
                let tool = ChatMessage(role: .tool, text: "", toolName: n, toolDetail: d)
                tool.turnStartedAt = self.activeTurnStartedAt(for: c)
                tool.turnStatus = "running"
                c.messages.append(tool)
                if isVisible {
                    let divider = self.ensureLiveWorkDivider(for: c)
                    let row = self.addRow(for: tool)
                    row.isHidden = true
                    divider.rows.append(row)
                    divider.refresh()
                }
            case .toolResult(let n, let d):
                if let t = c.messages.last(where: { $0.role == .tool && $0.toolName == n && !$0.toolDone }) {
                    t.toolDone = true
                    t.turnStatus = "completed"
                    if let d, !d.isEmpty { t.toolDetail = (t.toolDetail.map { $0 + "\n\n" } ?? "") + d }
                    if isVisible {
                        self.labels[ObjectIdentifier(t)]?.setRich(TranscriptToolFormatter.toolString(t))
                        if t.toolName == "edit", let stats = self.editStatsByMessage[ObjectIdentifier(t)] {
                            let summary = TranscriptToolFormatter.editSummary(t)
                            stats.isHidden = summary.added == 0 && summary.deleted == 0
                            stats.setValues(added: summary.added, deleted: summary.deleted)
                        }
                        if t.toolName == "edit" || t.toolName == "shell" {
                            self.scheduleToolRefresh(for: c)
                        }
                    }
                    self.emitActivity(c, force: true)
                }
            case .error(let e):
                if isVisible { self.hideThinking() }
                if self.stopping { self.stopping = false; return }   // user-initiated stop, not a real error
                let assistant: ChatMessage
                if let existing = self.assistantByConversationId[c.id] {
                    assistant = existing
                } else {
                    let assistant = ChatMessage(role: .assistant, text: "")
                    assistant.turnStartedAt = self.activeTurnStartedAt(for: c)
                    assistant.turnStatus = "running"
                    c.messages.append(assistant)
                    self.assistantByConversationId[c.id] = assistant
                    if isVisible {
                        _ = self.ensureLiveWorkDivider(for: c)
                        self.addRow(for: assistant)
                        self.currentAssistant = assistant
                    }
                    assistant.text += "⚠︎ " + e
                    if isVisible { self.renderLiveAssistant(assistant) }
                    c.status = .error; self.finish(c)
                    break
                }
                assistant.text += (assistant.text.isEmpty ? "" : "\n") + "⚠︎ " + e
                if isVisible { self.renderLiveAssistant(assistant) }
                c.status = .error; self.finish(c)
            case .done:
                if isVisible { self.hideThinking() }
                if isVisible { self.finalizeAssistant(for: c) }
                if let fa = c.messages.last(where: { $0.role == .assistant }) {
                    fa.timestamp = Date().timeIntervalSince1970
                    let started = self.activeTurnStartedAt(for: c) ?? self.turnStart.timeIntervalSince1970
                    fa.turnDuration = Date().timeIntervalSince1970 - started
                    fa.turnStatus = "completed"
                    fa.isFinal = true
                    ConversationTurnMutationModel.finishLatestPromptTurn(in: c.messages)
                    if isVisible, let divider = self.liveWorkDividerByConversationId[c.id] {
                        divider.finish(duration: fa.turnDuration)
                        self.liveWorkDividerByConversationId[c.id] = nil
                    }
                    if isVisible { self.addFinalFooter(for: fa) }
                }
                c.status = .idle; self.finish(c)
                if isVisible { self.scheduleToolRefresh(for: c) }
            }
            c.updatedAt = Date().timeIntervalSince1970
            if isVisible { self.scrollToBottom() }
        }

        let task: URLSessionDataTask
        if selectedHarness == .codex {
            task = client.codexChat(model: selectedModel, text: text, cwd: c.workspace,
                                    threadId: c.codexThreadId, effort: selectedReasoning, onEvent: handler)
        } else if selectedHarness == .pi {
            task = client.piChat(model: selectedModel, text: text, cwd: c.workspace, sessionId: c.id, onEvent: handler)
        } else {
            task = client.chat(model: selectedModel, conversationId: c.id, cwd: c.workspace, messages: c.history, onEvent: handler)
        }
        streamTasks[c.id] = task
    }

    private func finish(_ c: Conversation) {
        ConversationTurnMutationModel.finishLatestPromptTurn(in: c.messages)
        setStreaming(false, for: c)
        streamTasks[c.id] = nil
        assistantByConversationId[c.id] = nil
        if conversation === c { currentAssistant = nil }
        emitActivity(c, force: true)
        // Deliver any messages queued while streaming (steering) as the next turn.
        if !c.steerQueue.isEmpty {
            let joined = c.steerQueue.joined(separator: "\n\n")
            c.steerQueue.removeAll()
            startTurn(joined, on: c, appendUser: false)
        }
    }

    private func markOpenToolsCompleted(in c: Conversation) {
        ConversationTurnMutationModel.markOpenToolsCompleted(in: c.messages)
    }

    private func addSteerNotice(to c: Conversation, text: String? = nil) {
        let result = ConversationTurnMutationModel.applySteerEvent(to: c, text: text)
        switch result {
        case .none:
            return
        case .completedPending:
            if conversation === c { show(c) }
            return
        case .appended:
            break
        }
        guard conversation === c else { return }
        let divider = ensureLiveWorkDivider(for: c)
        let row = addRow(for: c.messages.last!)
        divider.rows.append(row)
        divider.refresh()
    }

    private func emitActivity(_ c: Conversation, force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force, now - (lastActivityEmit[c.id] ?? 0) < 2.0 { return }
        lastActivityEmit[c.id] = now
        onActivity?(c)
    }

    private func scheduleToolRefresh(for c: Conversation) {
        guard conversation === c else { return }
        guard !isActiveConversation(c) else { return }
        pendingToolRefreshByConversationId[c.id]?.cancel()
        let item = DispatchWorkItem { [weak self, weak c] in
            guard let self, let c, self.conversation === c else { return }
            self.show(c)
        }
        pendingToolRefreshByConversationId[c.id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    /// Re-render the active assistant message as markdown once its text is final.
    private func finalizeAssistant(for c: Conversation) {
        guard let a = assistantByConversationId[c.id] ?? (conversation === c ? currentAssistant : nil),
              let label = labels[ObjectIdentifier(a)] else { return }
        label.setRich(Self.markdown(a.text))
    }

    /// Full Markdown rendering with a consistent base font.
    static func markdown(_ s: String) -> NSAttributedString {
        MarkdownRenderer.render(s)
    }

    @objc private func harnessDidChange() {
        reasoningPopup.isHidden = selectedHarness == .codex
        syncComposerMenus()
        onHarnessChanged?(selectedHarness)
    }

    @objc private func menuDidChange() {
        syncComposerMenus()
    }

    @objc private func codexModelPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        selectedCodexModel = id
        installCodexModelMenu(codexModelIds.isEmpty ? [id] : codexModelIds)
    }

    @objc private func codexEffortPicked(_ sender: NSMenuItem) {
        guard let effort = sender.representedObject as? String else { return }
        selectedCodexEffort = effort
        installCodexModelMenu(codexModelIds.isEmpty ? [selectedCodexModel] : codexModelIds)
    }

    private func setStreaming(_ on: Bool, for c: Conversation) {
        if on { streamingConversationIds.insert(c.id) }
        else { streamingConversationIds.remove(c.id) }
        if conversation === c { updateSendButton() }
    }

    /// The action button is "Stop" while streaming with an empty composer, else "Send".
    private func updateSendButton() {
        let state = ComposerModel.sendState(
            streaming: streaming,
            trimmedText: composer.string.trimmingCharacters(in: .whitespacesAndNewlines),
            hasAttachments: !attachments.isEmpty
        )
        sendButton.image = NSImage(systemSymbolName: state.symbol,
                                   accessibilityDescription: state.accessibilityDescription)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        sendButton.contentTintColor = .black
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

    private func addInlineError(_ message: String, to c: Conversation) {
        let text = "⚠︎ " + message
        let assistant = ChatMessage(role: .assistant, text: text)
        c.messages.append(assistant)
        c.status = .error
        guard conversation === c else { return }
        hideThinking()
        _ = ensureLiveWorkDivider(for: c)
        addRow(for: assistant)
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
        updateSendButton()
        scheduleComposerDraftSave()
    }

    // MARK: - Row rendering

    @discardableResult
    private func addRow(for m: ChatMessage) -> NSView {
        let built = TranscriptRowFactory.makeRow(for: m, markdown: Self.markdown)
        let container = built.container
        if let content = built.label {
            labels[ObjectIdentifier(m)] = content
        }
        if let editStats = built.editStats {
            editStatsByMessage[ObjectIdentifier(m)] = editStats
        }
        if let row = built.clickableToolView {
            toolByView[ObjectIdentifier(row)] = m
            row.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toolClicked(_:))))
        }
        transcript.addArrangedSubview(container)
        if let spacing = built.customSpacingAfter {
            transcript.setCustomSpacing(spacing, after: container)
        }
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        // Keep the "Thinking" shimmer pinned to the bottom while streaming.
        if !bulkLoading { pinShimmerToBottom() }
        // Smooth fade-in for live (streamed) rows.
        if !bulkLoading {
            container.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.22; container.animator().alphaValue = 1 }
        }
        return container
    }

    private func addLargeThreadNotice(hiddenCount: Int) {
        let container = TranscriptRowFactory.largeThreadNotice(
            maxRenderedMessages: maxRenderedMessages,
            hiddenCount: hiddenCount
        )
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
    }

    private func renderLiveAssistant(_ assistant: ChatMessage, force: Bool = false) {
        let key = ObjectIdentifier(assistant)
        guard let label = labels[key] else { return }
        let now = Date().timeIntervalSince1970
        guard TranscriptLiveUpdateModel.shouldRenderMarkdown(
            force: force,
            now: now,
            lastRenderAt: lastLiveMarkdownRender[key]
        ) else { return }
        lastLiveMarkdownRender[key] = now
        label.setRich(Self.markdown(assistant.text))
    }

    private func pinShimmerToBottom() {
        guard let s = shimmerView, let sc = s.superview else { return }
        transcript.removeArrangedSubview(sc)
        transcript.addArrangedSubview(sc)
    }

    /// Show a popover with the full tool name + detail when a tool pill is clicked.
    @objc private func toolClicked(_ g: NSClickGestureRecognizer) {
        guard let view = g.view, let m = toolByView[ObjectIdentifier(view)] else { return }
        if m.toolName == "edit" {
            showEditPopover(changes: TranscriptToolFormatter.editSummary(m).changes, anchor: view)
            return
        }
        let content = TranscriptPopoverChrome.toolDetail(name: m.toolName, done: m.toolDone, detail: m.toolDetail)
        // Anchor a small rect at the click point so the popover appears next to the tool label.
        let p = g.location(in: view)
        TranscriptPopoverChrome.show(
            content,
            in: toolPopover,
            relativeTo: NSRect(x: p.x - 4, y: view.bounds.minY, width: 8, height: view.bounds.height),
            of: view
        )
    }

    private func showEditPopover(changes: [EditToolChange], anchor: NSView) {
        let content = TranscriptPopoverChrome.editDiff(changes: changes)
        TranscriptPopoverChrome.show(
            content,
            in: toolPopover,
            relativeTo: anchor.bounds.isEmpty ? NSRect(x: 0, y: 0, width: 1, height: 1) : anchor.bounds,
            of: anchor
        )
    }

    private func scrollToBottom() {
        let now = Date().timeIntervalSince1970
        if TranscriptLiveUpdateModel.shouldThrottleScroll(
            streaming: streaming,
            now: now,
            lastScrollAt: lastScrollToBottomAt
        ) {
            guard !pendingScrollToBottom else { return }
            pendingScrollToBottom = true
            DispatchQueue.main.asyncAfter(deadline: .now() + TranscriptLiveUpdateModel.scrollInterval) { [weak self] in
                guard let self else { return }
                self.pendingScrollToBottom = false
                self.scrollToBottom()
            }
            return
        }
        lastScrollToBottomAt = now
        if !streaming {
            view.layoutSubtreeIfNeeded()
        }
        guard let doc = scroll.documentView else { return }
        let y = max(0, doc.bounds.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
