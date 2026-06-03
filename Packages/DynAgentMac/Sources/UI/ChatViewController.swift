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
    private var cardWidthConstraint: NSLayoutConstraint?
    private var transcriptWidthConstraint: NSLayoutConstraint?
    private var attachmentHeightConstraint: NSLayoutConstraint?
    private let streamRegistry = ChatStreamRegistry<URLSessionDataTask>()
    private var turnStart = Date()
    private let transcriptCoordinator = ChatTranscriptCoordinator()
    private let streamEventCoordinator = ChatStreamEventCoordinator()
    private let maxRenderedMessages = 240
    private let activityCoordinator = ChatActivityCoordinator()
    private var renderSession = TranscriptRenderSessionState()
    private lazy var composerSessionCoordinator = ChatComposerSessionCoordinator(
        composer: composer,
        placeholder: placeholder,
        attachmentStack: attachmentStack,
        attachmentScroll: attachmentScroll,
        attachmentHeightConstraint: attachmentHeightConstraint,
        removeTarget: self,
        removeAction: #selector(removeAttachment(_:))
    )
    private lazy var titleGenerationCoordinator = ChatTitleGenerationCoordinator(client: client)
    private lazy var composerMenuCoordinator = ComposerMenuCoordinator(
        modelPopup: modelPopup,
        harnessPopup: harnessPopup,
        reasoningPopup: reasoningPopup,
        placeholder: placeholder,
        harnessMenu: harnessMenu,
        modelMenu: modelMenu,
        reasoningMenu: reasoningMenu,
        menuTarget: self,
        modelAction: #selector(codexModelPicked(_:)),
        effortAction: #selector(codexEffortPicked(_:))
    )

    private var streaming: Bool {
        guard let conversation else { return false }
        return isActiveConversation(conversation)
    }

    func hasLocalStream(for c: Conversation) -> Bool {
        streamRegistry.isActive(c.id)
    }

    var selectedModel: String {
        composerMenuCoordinator.selectedModel
    }
    var selectedHarness: Harness {
        composerMenuCoordinator.selectedHarness
    }
    var selectedReasoning: String {
        composerMenuCoordinator.selectedReasoning
    }
    var onHarnessChanged: ((Harness) -> Void)?
    var onChatMenu: ((NSButton) -> Void)?
    /// Sync the composer's harness picker to a conversation, reloading models if it changed.
    func setHarness(_ h: Harness, preferredModel: String? = nil) {
        applyHarnessSyncPlan(for: h, preferredModel: preferredModel, mode: .rememberPreferred)
    }

    /// Apply remembered harness+model as the composer defaults (used for new chats on launch).
    func applyDefaults(harness: Harness, model: String?) {
        applyHarnessSyncPlan(for: harness, preferredModel: model, mode: .applyDefault)
    }

    private func applyHarnessSyncPlan(
        for harness: Harness,
        preferredModel: String?,
        mode: ComposerHarnessSyncMode
    ) {
        let harnessChanged = composerMenuCoordinator.applyHarnessSyncPlan(
            for: harness,
            preferredModel: preferredModel,
            mode: mode,
            conversation: conversation
        )
        if harnessChanged {
            onHarnessChanged?(harness)
        }
    }

    func setModels(_ ids: [String]) {
        composerMenuCoordinator.setModels(ids, conversation: conversation)
    }

    func setContext(_ percent: Double?) {
        let state = ComposerModel.contextState(percent: percent)
        contextRing.fraction = state.fraction
        contextRing.toolTip = state.tooltip
        contextRing.isHidden = false
    }

    func setHeaderTitle(_ title: String) {
        headerTitle.stringValue = ChatTitleModel.displayTitle(title)
    }

    var layoutMetrics: [String: Any] {
        ChatViewportMetricsChrome.payload(
            root: view,
            scroll: scroll,
            transcript: transcript,
            composer: card
        )
    }

    override func loadView() {
        TranscriptViewportChrome.configureTranscript(transcript)
        let doc = TranscriptViewportChrome.makeDocument(containing: transcript)
        TranscriptViewportChrome.configureScroll(scroll, document: doc)

        ChatHeaderChrome.configureTitle(headerTitle)
        ChatHeaderChrome.configureMenuButton(headerMenuButton, target: self, action: #selector(showHeaderMenu(_:)))

        let composerScroll = ChatComposerChrome.configureInput(
            composer: composer,
            delegate: self,
            onSend: { [weak self] in self?.send() },
            onPasteAttachments: { [weak self] urls in self?.addAttachments(urls) }
        )

        ComposerChrome.configurePlaceholder(placeholder)

        ComposerChrome.configureAttachmentStrip(stack: attachmentStack, scroll: attachmentScroll)

        let composerMenus = ChatComposerChrome.configureMenus(
            harnessPopup: harnessPopup,
            modelPopup: modelPopup,
            reasoningPopup: reasoningPopup,
            target: self,
            harnessAction: #selector(harnessDidChange),
            menuAction: #selector(menuDidChange)
        )
        composerMenus.model.displayProvider = { [weak self] in
            guard let self, self.selectedHarness == .codex else { return nil }
            return ComposerChrome.codexMenuTitle(
                model: self.composerMenuCoordinator.selectedCodexModel,
                effort: self.composerMenuCoordinator.selectedCodexEffort
            )
        }
        harnessMenu = composerMenus.harness
        modelMenu = composerMenus.model
        reasoningMenu = composerMenus.reasoning

        let composerFooter = ChatComposerChrome.configureFooter(
            spinner: spinner,
            sendButton: sendButton,
            addAttachmentButton: addAttachmentButton,
            menus: composerMenus,
            contextRing: contextRing,
            target: self,
            sendAction: #selector(send),
            addAttachmentAction: #selector(addAttachmentClicked)
        )

        let composerSurface = ChatComposerChrome.installSurface(
            card: card,
            content: cardContent,
            composerScroll: composerScroll,
            placeholder: placeholder,
            attachmentScroll: attachmentScroll,
            footer: composerFooter.footer
        )
        attachmentHeightConstraint = composerSurface.attachmentHeight

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

        let topBorder = ChatViewChrome.makeTopBorder()
        let root = ChatViewChrome.makeRoot(
            scroll: scroll,
            headerTitle: headerTitle,
            headerMenuButton: headerMenuButton,
            composerCard: card,
            emptyStack: emptyStack,
            topBorder: topBorder
        )
        let composerLayout = ChatViewChrome.composerConstraints(root: root, card: card)
        let transcriptLayout = TranscriptViewportChrome.constraints(
            scroll: scroll,
            root: root,
            document: doc,
            transcript: transcript
        )
        cardBottomConstraint = composerLayout.bottom
        cardCenterYConstraint = composerLayout.centerY
        cardWidthConstraint = composerLayout.width
        transcriptWidthConstraint = transcriptLayout.transcriptWidth

        NSLayoutConstraint.activate(composerSurface.constraints + transcriptLayout.all + ComposerChrome.footerControlConstraints(
            addAttachmentButton: addAttachmentButton,
            sendContainer: composerFooter.sendContainer,
            sendButton: sendButton,
            spinner: spinner
        ) + composerLayout.all + ChatViewChrome.emptyStateConstraints(
            emptyStack: emptyStack,
            scroll: scroll,
            card: card
        ) + ChatHeaderChrome.constraints(
            title: headerTitle,
            menuButton: headerMenuButton,
            root: root
        ) + ChatViewChrome.topBorderConstraints(topBorder: topBorder, root: root))
        view = root
    }

    @objc private func showHeaderMenu(_ sender: NSButton) {
        onChatMenu?(sender)
    }

    /// Keep the transcript clear of the floating composer: bottom inset tracks the composer height.
    override func viewDidLayout() {
        super.viewDidLayout()
        let readableWidth = ChatLayoutModel.readableWidth(for: view.bounds.width)
        if abs((cardWidthConstraint?.constant ?? 0) - readableWidth) > 0.5 {
            cardWidthConstraint?.constant = readableWidth
        }
        if abs((transcriptWidthConstraint?.constant ?? 0) - readableWidth) > 0.5 {
            transcriptWidthConstraint?.constant = readableWidth
        }
        bottomInsetCache = ChatViewportLayoutChrome.apply(
            root: view,
            scroll: scroll,
            composer: card,
            bottomInsetCache: bottomInsetCache
        )
    }

    private func syncComposerMenus() {
        composerMenuCoordinator.syncMenus(conversation: conversation)
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
        guard composerSessionCoordinator.addAttachments(urls, conversation: conversation) else { return }
        updateSendButton()
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        guard composerSessionCoordinator.removeAttachment(sender: sender, conversation: conversation) else { return }
        updateSendButton()
    }

    func saveComposerDraft() {
        composerSessionCoordinator.saveDraft(for: conversation)
    }

    private func scheduleComposerDraftSave() {
        composerSessionCoordinator.scheduleDraftSave(conversationProvider: { [weak self] in self?.conversation })
    }

    private func restoreComposerDraft(for c: Conversation) {
        composerSessionCoordinator.restoreDraft(for: c)
    }

    private func adoptComposerSelection(for c: Conversation) {
        composerMenuCoordinator.adoptConversation(c)
    }

    func show(_ c: Conversation) {
        saveComposerDraft()
        let wasShowingSameConversation = conversation === c
        conversation = c
        adoptComposerSelection(for: c)
        let renderStart = TranscriptRenderSessionModel.beginShow(
            state: renderSession,
            conversation: c,
            wasShowingSameConversation: wasShowingSameConversation,
            isActive: isActiveConversation(c),
            maxRenderedMessages: maxRenderedMessages
        )
        renderSession = renderStart.state
        if renderStart.shouldReuse {
            restoreComposerDraft(for: c)
            updateEmptyState()
            updateSendButton()
            view.window?.makeFirstResponder(composer)
            return
        }
        transcriptCoordinator.reset()
        streamEventCoordinator.adoptVisibleAssistant(for: c)
        transcriptCoordinator.clearRows(from: transcript)
        // Render each turn: prompt + work divider + final answer.
        let plan = TranscriptTurnModel.plan(
            messages: c.messages,
            maxRenderedMessages: maxRenderedMessages,
            isActive: isActiveConversation(c),
            updatedAt: c.updatedAt
        )
        if plan.hiddenCount > 0 {
            transcriptCoordinator.appendLargeThreadNotice(
                maxRenderedMessages: maxRenderedMessages,
                hiddenCount: plan.hiddenCount,
                to: transcript
            )
        }
        restoreComposerDraft(for: c)
        updateEmptyState()
        updateSendButton()
        view.window?.makeFirstResponder(composer)
        renderTurnsAsync(plan.turns, conversation: c, generation: renderStart.generation)
    }

    func showShell(_ c: Conversation) {
        saveComposerDraft()
        renderSession = TranscriptRenderSessionModel.beginLoadingShell(state: renderSession)
        conversation = c
        adoptComposerSelection(for: c)
        transcriptCoordinator.reset()
        streamEventCoordinator.adoptVisibleAssistant(for: c)
        transcriptCoordinator.clearRows(from: transcript)
        transcriptCoordinator.appendLoadingShell(text: ChatPresentationModel.loadingText(needsLoad: c.needsLoad), to: transcript)
        emptyStack.isHidden = true
        cardBottomConstraint?.isActive = true
        cardCenterYConstraint?.isActive = false
        restoreComposerDraft(for: c)
        updateSendButton()
        view.window?.makeFirstResponder(composer)
    }

    private func renderTurnsAsync(_ turns: [TranscriptRenderTurn], conversation c: Conversation, generation: Int, startIndex: Int = 0) {
        guard TranscriptRenderSessionModel.shouldContinue(
            state: renderSession,
            generation: generation,
            visibleConversation: conversation,
            expectedConversation: c
        ) else { return }
        if let range = TranscriptRenderSessionModel.batchRange(totalCount: turns.count, startIndex: startIndex) {
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

        renderSession = TranscriptRenderSessionModel.finishBulkLoading(state: renderSession)
        if isActiveConversation(c) { showThinking() }
        updateEmptyState()
        scrollToBottom()
        onLayoutChanged?()
    }

    /// Render one turn with its work divider above the final assistant response.
    private func renderTurn(_ turn: [ChatMessage], conversation c: Conversation, allowCollapse: Bool, forceActive: Bool = false) {
        TranscriptTurnRenderer.render(
            turn: turn,
            allowCollapse: allowCollapse,
            isConversationActive: isActiveConversation(c),
            forceActive: forceActive,
            fallbackActiveStartedAt: activeTurnStartedAt(for: c),
            now: Date().timeIntervalSince1970,
            hooks: TranscriptTurnRenderer.Hooks(
                addMessageRow: { [unowned self] message in
                    _ = addRow(for: message)
                },
                addGroupedRows: { [unowned self] messages, collapseCompletedTools in
                    addRowsGrouped(messages, collapseCompletedTools: collapseCompletedTools)
                },
                addWorkDivider: { [unowned self] duration, collapsed, active in
                    addWorkDivider(duration: duration, collapsed: collapsed, active: active)
                },
                setLiveDivider: { [unowned self, weak c] divider in
                    guard let c else { return }
                    transcriptCoordinator.setLiveDivider(divider, for: c.id)
                },
                addFinalFooter: { [unowned self] message in
                    transcriptCoordinator.appendFinalFooter(for: message, to: transcript)
                }
            )
        )
    }

    private func addRowsGrouped(_ messages: [ChatMessage], collapseCompletedTools: Bool = true) -> [NSView] {
        transcriptCoordinator.appendRowsGrouped(
            messages,
            collapseCompletedTools: collapseCompletedTools,
            to: transcript,
            markdown: Self.markdown,
            bulkLoading: renderSession.bulkLoading
        )
    }

    @discardableResult
    private func addWorkDivider(duration: Double?, collapsed: Bool = true, active: Bool = false) -> WorkDivider {
        transcriptCoordinator.addWorkDivider(
            duration: duration,
            collapsed: collapsed,
            active: active,
            to: transcript
        )
    }

    private func ensureLiveWorkDivider(for c: Conversation) -> WorkDivider {
        let startedAt = activeTurnStartedAt(for: c) ?? turnStart.timeIntervalSince1970
        return transcriptCoordinator.ensureLiveDivider(
            for: c.id,
            startedAt: startedAt,
            now: Date().timeIntervalSince1970,
            transcript: transcript
        )
    }

    private func isActiveConversation(_ c: Conversation) -> Bool {
        streamRegistry.isActive(c.id) || c.status == .thinking || c.status == .running
    }

    private func activeTurnStartedAt(for c: Conversation) -> Double? {
        TranscriptTurnModel.activeStartedAt(messages: c.messages, fallbackUpdatedAt: c.updatedAt)
    }

    private func updateEmptyState() {
        let state = ChatPresentationModel.emptyState(
            messages: conversation?.messages ?? [],
            workspace: conversation?.workspace
        )
        emptySub.stringValue = state.subtitle
        emptyStack.isHidden = state.isHidden
        cardBottomConstraint?.isActive = state.isHidden
        cardCenterYConstraint?.isActive = !state.isHidden
    }

    // MARK: - Sending

    @objc private func send() {
        guard let c = conversation else { return }
        let action = ChatSendModel.action(
            typedText: composer.string,
            attachmentPaths: composerSessionCoordinator.attachmentPaths,
            streaming: streaming,
            harness: c.harness,
            codexThreadId: c.codexThreadId
        )

        guard action.clearsComposer else {
            if action == .stop { stop() }
            return
        }

        composerSessionCoordinator.clearAfterSend(for: c)
        textDidChange(Notification(name: NSText.didChangeNotification))

        switch action {
        case .none, .stop:
            return
        case .sendCodexSteer(let tid, let text):
            addSteerNotice(to: c, text: text)
            Task { [weak self, weak c] in
                guard let self, let c else { return }
                do {
                    try await self.client.codexSteer(threadId: tid, text: text)
                } catch {
                    await MainActor.run { self.addInlineError(error.localizedDescription, to: c) }
                }
            }
            scrollToBottom()
        case .queueSteer(let text):
            c.steerQueue.append(text)
            addSteerNotice(to: c, text: text)
            scrollToBottom()
        case .startTurn(let text):
            startTurn(text, on: c)
        }
    }

    private func stop() {
        guard let c = conversation else { return }
        streamRegistry.markStopping(c.id)
        c.steerQueue.removeAll()
        if c.harness == .codex, let tid = c.codexThreadId {
            Task { await client.codexCancel(threadId: tid) }
        }
        client.cancel(streamRegistry.task(for: c.id))
        hideThinking(); finalizeAssistant(for: c)
        c.status = .idle
        finish(c, preservingStopFlag: true)
    }

    private func startTurn(_ text: String, on c: Conversation, appendUser: Bool = true) {
        if selectedHarness == .codex {
            composerMenuCoordinator.ensureSelectedCodexModelIsSupported(conversation: conversation)
        }
        Store.saveLast(harness: selectedHarness, model: selectedModel)
        let startedAt = Date().timeIntervalSince1970
        let start = ChatStreamStartModel.prepareTurn(
            text: text,
            conversation: c,
            harness: selectedHarness,
            model: selectedModel,
            appendUser: appendUser,
            now: startedAt
        )
        if appendUser { turnStart = Date(timeIntervalSince1970: start.startedAt) }
        if let user = start.userMessage {
            addRow(for: user)
        }
        if conversation === c { syncComposerMenus() }
        updateEmptyState()

        setStreaming(true, for: c)
        if conversation === c {
            _ = ensureLiveWorkDivider(for: c)
            showThinking()
        }
        emitActivity(c, force: true)

        if start.shouldGenerateTitle { generateTitle(for: c, prompt: text) }

        streamEventCoordinator.clearAssistant(for: c, visible: conversation === c)
        let handler: (AgentClient.Event) -> Void = { [weak self, weak c] ev in
            guard let self, let c else { return }
            let isVisible = self.conversation === c
            let started = self.activeTurnStartedAt(for: c) ?? self.turnStart.timeIntervalSince1970
            let outcome = self.streamEventCoordinator.handle(
                ev,
                conversation: c,
                isVisible: isVisible,
                activeStartedAt: started,
                consumeStoppingError: { self.streamRegistry.consumeStopping(c.id) }
            )
            if outcome.suppressedStoppingError { return }
            if outcome.shouldEmitActivity {
                self.emitActivity(c, force: outcome.forceActivity)
            }
            if !isVisible, outcome.shouldFinishConversation {
                self.finish(c)
            }
            guard isVisible else { return }
            self.applyVisibleStreamOutcome(outcome, conversation: c)
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
        streamRegistry.setTask(task, id: c.id)
    }
    private func finish(_ c: Conversation, preservingStopFlag: Bool = false) {
        ConversationTurnMutationModel.finishLatestPromptTurn(in: c.messages)
        setStreaming(false, for: c)
        streamRegistry.finish(c.id, preservingStopFlag: preservingStopFlag)
        streamEventCoordinator.clearAssistant(for: c, visible: conversation === c)
        emitActivity(c, force: true)
        // Deliver any messages queued while streaming (steering) as the next turn.
        if let joined = ChatSendModel.queuedSteerTurnText(c.steerQueue) {
            c.steerQueue.removeAll()
            startTurn(joined, on: c, appendUser: false)
        }
    }

    private func applyVisibleStreamOutcome(_ outcome: ChatStreamEventOutcome, conversation c: Conversation) {
        if outcome.shouldHideThinking { hideThinking() }
        if outcome.shouldFinalizeAssistant { finalizeAssistant(for: c) }
        if outcome.receivedSteer { addSteerNotice(to: c) }
        if let assistant = outcome.createdAssistant {
            _ = ensureLiveWorkDivider(for: c)
            addRow(for: assistant)
        }
        if let assistant = outcome.assistantToRender {
            renderLiveAssistant(assistant)
        }
        if let tool = outcome.appendedTool {
            let divider = ensureLiveWorkDivider(for: c)
            let row = addRow(for: tool)
            row.isHidden = true
            divider.messages.append(tool)
            divider.rows.append(row)
            divider.refresh()
        }
        if let tool = outcome.completedTool {
            transcriptCoordinator.refreshCompletedTool(tool)
        }
        if let trigger = outcome.completedToolRefresh {
            scheduleToolRefresh(for: c, trigger: trigger)
        }
        if let final = outcome.finalAssistant {
            transcriptCoordinator.finishAndRegroupLiveDivider(
                for: c.id,
                duration: final.turnDuration,
                transcript: transcript,
                markdown: Self.markdown
            )
            transcriptCoordinator.appendFinalFooter(for: final, to: transcript)
        }
        if outcome.shouldFinishConversation {
            finish(c)
        }
        if outcome.shouldScheduleStreamDoneRefresh {
            scheduleToolRefresh(for: c, trigger: .streamDone)
        }
        if outcome.shouldScroll {
            scrollToBottom()
        }
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
        divider.messages.append(c.messages.last!)
        divider.rows.append(row)
        divider.refresh()
    }

    private func emitActivity(_ c: Conversation, force: Bool = false) {
        activityCoordinator.emitActivity(
            for: c,
            force: force,
            onActivity: onActivity
        )
    }

    private func scheduleToolRefresh(for c: Conversation, trigger: ChatToolRefreshTrigger) {
        activityCoordinator.scheduleToolRefresh(
            for: c,
            trigger: trigger,
            isVisible: conversation === c,
            isActive: isActiveConversation(c),
            shouldRefresh: { [weak self, weak c] in
                guard let self, let c else { return false }
                return self.conversation === c
            },
            refresh: { [weak self] conversation in
                self?.show(conversation)
            }
        )
    }

    /// Re-render the active assistant message as markdown once its text is final.
    private func finalizeAssistant(for c: Conversation) {
        guard let a = streamEventCoordinator.finalizableAssistant(for: c, visible: conversation === c) else { return }
        transcriptCoordinator.finalizeAssistant(a, markdown: Self.markdown)
    }

    /// Full Markdown rendering with a consistent base font.
    static func markdown(_ s: String) -> NSAttributedString {
        MarkdownRenderer.render(s)
    }

    @objc private func harnessDidChange() {
        onHarnessChanged?(composerMenuCoordinator.harnessDidChange(conversation: conversation))
    }

    @objc private func menuDidChange() {
        composerMenuCoordinator.syncMenus(conversation: conversation)
    }

    @objc private func codexModelPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        composerMenuCoordinator.pickCodexModel(id, conversation: conversation)
    }

    @objc private func codexEffortPicked(_ sender: NSMenuItem) {
        guard let effort = sender.representedObject as? String else { return }
        composerMenuCoordinator.pickCodexEffort(effort, conversation: conversation)
    }

    private func setStreaming(_ on: Bool, for c: Conversation) {
        streamRegistry.setActive(on, id: c.id)
        if conversation === c { updateSendButton() }
    }

    /// The action button is "Stop" while streaming with an empty composer, else "Send".
    private func updateSendButton() {
        let state = ComposerModel.sendState(
            streaming: streaming,
            trimmedText: composer.string.trimmingCharacters(in: .whitespacesAndNewlines),
            hasAttachments: composerSessionCoordinator.hasAttachments
        )
        ComposerChrome.applySendState(state, to: sendButton)
    }

    // MARK: - Thinking shimmer

    private func showThinking() {
        transcriptCoordinator.showThinking(in: transcript)
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
        transcriptCoordinator.hideThinking()
    }

    // MARK: - Title generation

    private func generateTitle(for c: Conversation, prompt: String) {
        Task { @MainActor in
            await titleGenerationCoordinator.generate(
                for: c,
                prompt: prompt,
                model: selectedModel,
                onTitleGenerated: onTitleGenerated
            )
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
        transcriptCoordinator.appendRow(
            for: m,
            to: transcript,
            markdown: Self.markdown,
            bulkLoading: renderSession.bulkLoading
        )
    }

    private func renderLiveAssistant(_ assistant: ChatMessage, force: Bool = false) {
        transcriptCoordinator.renderLiveAssistant(assistant, markdown: Self.markdown, force: force)
    }

    private func scrollToBottom() {
        transcriptCoordinator.scrollToBottom(
            streaming: streaming,
            root: view,
            scroll: scroll
        )
    }
}
