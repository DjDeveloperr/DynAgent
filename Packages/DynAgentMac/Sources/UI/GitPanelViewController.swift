import AppKit

/// Right pane: git branch, changed files, diff, commit/push/PR actions.
final class GitPanelViewController: NSViewController {
    var client: AgentClient!
    private(set) var workspace = ""

    private let branchLabel = NSTextField(labelWithString: "—")
    private let scopeControl = NSSegmentedControl(labels: ["All", "Staged"], trackingMode: .selectOne, target: nil, action: nil)
    private let diffScroll = NSScrollView()
    private let diffDocument = GitDiffDocumentView()
    private let diffHeader = GitDiffHeaderView()
    private let commitField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let prBox = NSBox()
    private let prLabel = NSTextField(wrappingLabelWithString: "")
    private var worktreeRow = NSStackView()
    private weak var gitActionSheet: NSWindow?
    private var gitActionOutsideMonitor: Any?
    private var showingStaged = false
    var isWorktree = false { didSet { worktreeRow.isHidden = !isWorktree } }
    var scopeToolbarView: NSSegmentedControl { scopeControl }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let header = GitPanelChrome.makeHeader(branchLabel: branchLabel)
        GitPanelChrome.configureScopeControl(scopeControl, target: self, action: #selector(scopeChanged))
        GitPanelChrome.configureDiffScroll(diffScroll, document: diffDocument)
        diffDocument.onCollapseChanged = { [weak self] in self?.updateDiffHeader() }
        diffHeader.onClick = { [weak self] in
            guard let self else { return }
            self.diffDocument.toggleHeader(at: self.diffScroll.contentView.bounds.minY + 34)
            self.updateDiffHeader()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(diffScrolled(_:)), name: NSView.boundsDidChangeNotification, object: diffScroll.contentView)
        diffHeader.translatesAutoresizingMaskIntoConstraints = false
        diffHeader.isHidden = true

        commitField.placeholderString = "Commit message (blank = auto-generate)"
        commitField.font = .systemFont(ofSize: 13)

        GitPanelChrome.configureStatusLabel(statusLabel)
        GitPanelChrome.configurePRBox(prBox, label: prLabel)
        let stack = GitPanelChrome.makeContentStack(diffScroll: diffScroll, prBox: prBox, statusLabel: statusLabel)

        let root = NSView()
        root.addSubview(stack)
        root.addSubview(header.view)
        root.addSubview(diffHeader)
        NSLayoutConstraint.activate(GitPanelChrome.rootConstraints(
            root: root,
            stack: stack,
            header: header,
            diffHeader: diffHeader,
            branchLabel: branchLabel
        ))
        view = root
    }

    @objc private func diffScrolled(_ note: Notification) {
        diffDocument.updateVisibleOverlays()
        diffDocument.needsDisplay = true
        updateDiffHeader()
    }

    private func updateDiffHeader() {
        diffHeader.setInfo(diffDocument.headerInfo(at: diffScroll.contentView.bounds.minY + 34))
    }

    @objc private func scopeChanged() {
        showingStaged = scopeControl.selectedSegment == 1
        reload()
    }

    @objc func showGitActions() {
        guard let window = view.window else { return }
        let panel = GitActionSheetChrome.makePanel(
            branch: branchLabel.stringValue,
            isWorktree: isWorktree,
            commitField: commitField,
            target: self,
            selectors: GitActionSelectors(
                commit: #selector(doCommit),
                commitPush: #selector(doCommitPush),
                push: #selector(doPush),
                createBranch: #selector(doCreateBranch),
                createPR: #selector(doCreatePR)
            )
        )
        panel.onDismiss = { [weak self] in self?.dismissGitActions() }
        gitActionSheet = panel
        gitActionOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismissGitActions()
                return nil
            }
            if event.type == .leftMouseDown, event.window !== panel {
                self.dismissGitActions()
            }
            return event
        }
        window.beginSheet(panel) { [weak self] _ in
            if let monitor = self?.gitActionOutsideMonitor {
                NSEvent.removeMonitor(monitor)
                self?.gitActionOutsideMonitor = nil
            }
            self?.gitActionSheet = nil
        }
        panel.makeFirstResponder(commitField)
    }

    private func dismissGitActions() {
        guard let sheet = gitActionSheet, let parent = sheet.sheetParent else { return }
        parent.endSheet(sheet)
    }

    func show(workspace: String) { self.workspace = workspace; reload() }

    @objc func reload() {
        guard !workspace.isEmpty else { return }
        Task { @MainActor in
            guard let s = try? await client.gitStatus(workspace, staged: showingStaged) else { return }
            let presentation = GitPanelModel.statusPresentation(GitStatusInput(
                branch: s.branch,
                fileCount: s.files?.count ?? 0,
                diff: s.diff,
                error: s.error
            ))
            branchLabel.stringValue = presentation.branchLabel
            diffDocument.setDiff(presentation.diff)
            updateDiffHeader()
            statusLabel.stringValue = presentation.statusLabel
            if presentation.hidesPR {
                prBox.isHidden = true
                return
            }
            loadPRInfo()
        }
    }

    private func loadPRInfo() {
        Task { @MainActor in
            let pr = try? await client.prInfo(workspace)
            let presentation = GitPanelModel.prPresentation(pr.map {
                GitPRInput(
                    number: $0.number,
                    title: $0.title,
                    state: $0.state,
                    url: $0.url,
                    additions: $0.additions,
                    deletions: $0.deletions,
                    reviewDecision: $0.reviewDecision,
                    none: $0.none
                )
            })
            prLabel.stringValue = presentation.label
            prBox.isHidden = presentation.isHidden
        }
    }

    // MARK: Actions

    @objc private func doCommit() {
        let msg = GitActionSheetModel.trimmedMessage(commitField.stringValue)
        statusLabel.stringValue = GitActionKind.commit.pendingStatus(hasMessage: !msg.isEmpty)
        dismissGitActions()
        Task { @MainActor in
            let r = try? await client.postJSON("git/commit", GitActionSheetModel.commitBody(cwd: workspace, message: msg))
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "committed: \(r?["message"] as? String ?? "")"; commitField.stringValue = "" }
            reload()
        }
    }

    @objc private func doCommitPush() {
        let msg = GitActionSheetModel.trimmedMessage(commitField.stringValue)
        statusLabel.stringValue = GitActionKind.commitPush.pendingStatus(hasMessage: !msg.isEmpty)
        dismissGitActions()
        Task { @MainActor in
            let r = try? await client.postJSON("git/commit-push", GitActionSheetModel.commitBody(cwd: workspace, message: msg))
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "pushed: \(r?["message"] as? String ?? "")"; commitField.stringValue = "" }
            reload()
        }
    }

    @objc private func doPush() {
        statusLabel.stringValue = GitActionKind.push.pendingStatus(hasMessage: false)
        dismissGitActions()
        Task { @MainActor in
            let r = try? await client.postJSON("git/push", ["cwd": workspace])
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "pushed" }
        }
    }

    @objc private func doCreateBranch() {
        let a = NSAlert(); a.messageText = "New Branch"; a.informativeText = "Branch name:"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        tf.placeholderString = "feature/my-branch"; a.accessoryView = tf
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let branch = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }
        dismissGitActions()
        Task { @MainActor in
            let r = try? await client.postJSON("git/create-branch", ["cwd": workspace, "branch": branch])
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "on branch: \(branch)"; reload() }
        }
    }

    @objc private func doCreatePR() {
        let a = NSAlert(); a.messageText = "Create Pull Request"
        a.informativeText = "Title (blank = use branch name):"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.placeholderString = "PR title"; a.accessoryView = tf
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        statusLabel.stringValue = "creating PR..."
        dismissGitActions()
        Task { @MainActor in
            var body: [String: Any] = ["cwd": workspace]
            let title = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { body["title"] = title }
            let r = try? await client.postJSON("git/create-pr", body)
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else if let url = r?["url"] as? String { statusLabel.stringValue = "PR: \(url)"; loadPRInfo() }
        }
    }
}
