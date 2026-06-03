import AppKit

final class GitActionPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

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
        let title = NSTextField(labelWithString: "Changes")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        branchLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        branchLabel.textColor = .secondaryLabelColor
        branchLabel.translatesAutoresizingMaskIntoConstraints = false
        let header = NSVisualEffectView()
        header.material = .contentBackground
        header.blendingMode = .withinWindow
        header.state = .active
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        header.addSubview(branchLabel)
        scopeControl.selectedSegment = 0
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.controlSize = .small
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        let headerBorder = NSBox()
        headerBorder.boxType = .separator
        headerBorder.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerBorder)

        diffScroll.hasVerticalScroller = true
        diffScroll.hasHorizontalScroller = true
        diffScroll.autohidesScrollers = true
        diffScroll.scrollerStyle = .overlay
        diffScroll.documentView = diffDocument
        diffScroll.borderType = .noBorder
        diffScroll.drawsBackground = false
        diffScroll.automaticallyAdjustsContentInsets = false
        diffScroll.contentInsets = NSEdgeInsets(top: 54, left: 0, bottom: 0, right: 0)
        diffScroll.contentView.postsBoundsChangedNotifications = true
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

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor

        prBox.titlePosition = .noTitle
        prBox.contentView = prLabel
        prLabel.font = .systemFont(ofSize: 12)
        prLabel.textColor = .secondaryLabelColor
        prBox.isHidden = true

        let insets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        let stack = NSStackView(views: [diffScroll, prBox, statusLabel] as [NSView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.edgeInsets = insets
        stack.translatesAutoresizingMaskIntoConstraints = false
        diffScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Make full-width non-diff elements span the panel with matching horizontal padding.
        for v in [prBox] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
        diffScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let root = NSView()
        root.addSubview(stack)
        root.addSubview(header)
        root.addSubview(diffHeader)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 54),
            diffHeader.topAnchor.constraint(equalTo: header.bottomAnchor),
            diffHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            diffHeader.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            diffHeader.heightAnchor.constraint(equalToConstant: 34),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            branchLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            branchLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            title.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -14),
            headerBorder.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerBorder.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerBorder.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
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
        let panel = GitActionPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: isWorktree ? 302 : 220),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Git Actions"
        panel.isReleasedWhenClosed = false
        panel.onDismiss = { [weak self] in self?.dismissGitActions() }

        let title = NSTextField(labelWithString: "Commit changes")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        let branchIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage())
        branchIcon.contentTintColor = .secondaryLabelColor
        branchIcon.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = NSTextField(labelWithString: branchLabel.stringValue)
        subtitle.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        let branchRow = NSStackView(views: [branchIcon, subtitle])
        branchRow.orientation = .horizontal
        branchRow.alignment = .centerY
        branchRow.spacing = 6
        branchRow.translatesAutoresizingMaskIntoConstraints = false

        commitField.placeholderString = "Commit message (blank = auto-generate)"
        commitField.font = .systemFont(ofSize: 14)
        commitField.isBordered = false
        commitField.drawsBackground = false
        commitField.usesSingleLineMode = false
        commitField.lineBreakMode = .byWordWrapping
        commitField.translatesAutoresizingMaskIntoConstraints = false
        let inputBox = NSVisualEffectView()
        inputBox.material = .contentBackground
        inputBox.blendingMode = .withinWindow
        inputBox.state = .active
        inputBox.wantsLayer = true
        inputBox.layer?.cornerRadius = 10
        inputBox.translatesAutoresizingMaskIntoConstraints = false
        inputBox.addSubview(commitField)

        let commitBtn = makeBtn("Commit", #selector(doCommit))
        let commitPushBtn = makeBtn("Commit & Push", #selector(doCommitPush))
        let pushBtn = makeBtn("Push", #selector(doPush))
        let buttons = NSStackView(views: [commitBtn, commitPushBtn, pushBtn])
        buttons.orientation = .vertical
        buttons.spacing = 8
        buttons.alignment = .width

        var arranged: [NSView] = [title, branchRow, inputBox, buttons]
        if isWorktree {
            let divider = NSBox()
            divider.boxType = .separator
            let branchBtn = makeBtn("New Branch", #selector(doCreateBranch))
            let prBtn = makeBtn("Create PR", #selector(doCreatePR))
            let worktreeButtons = NSStackView(views: [branchBtn, prBtn])
            worktreeButtons.orientation = .vertical
            worktreeButtons.spacing = 8
            worktreeButtons.alignment = .width
            arranged.append(contentsOf: [divider, worktreeButtons])
        }

        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            branchIcon.widthAnchor.constraint(equalToConstant: 16),
            branchIcon.heightAnchor.constraint(equalToConstant: 16),
            inputBox.heightAnchor.constraint(equalToConstant: 82),
            commitField.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 11),
            commitField.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -11),
            commitField.topAnchor.constraint(equalTo: inputBox.topAnchor, constant: 9),
            commitField.bottomAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: -9),
        ])
        panel.contentView = root
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

    private func makeBtn(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.alignment = .center
        b.font = .systemFont(ofSize: 13.5, weight: .semibold)
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        b.layer?.backgroundColor = NSColor.controlColor.withAlphaComponent(0.70).cgColor
        b.contentTintColor = .labelColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return b
    }

    func show(workspace: String) { self.workspace = workspace; reload() }

    @objc func reload() {
        guard !workspace.isEmpty else { return }
        Task { @MainActor in
            guard let s = try? await client.gitStatus(workspace, staged: showingStaged) else { return }
            if let err = s.error {
                branchLabel.stringValue = err; diffDocument.setDiff(""); updateDiffHeader(); statusLabel.stringValue = ""; prBox.isHidden = true; return
            }
            branchLabel.stringValue = s.branch ?? "—"
            if let diff = s.diff, !diff.isEmpty {
                diffDocument.setDiff(diff)
            } else {
                diffDocument.setDiff("")
            }
            updateDiffHeader()
            let n = s.files?.count ?? 0
            statusLabel.stringValue = n == 0 ? "" : "\(n) changed file\(n == 1 ? "" : "s")"
            loadPRInfo()
        }
    }

    private func loadPRInfo() {
        Task { @MainActor in
            guard let pr = try? await client.prInfo(workspace) else { prBox.isHidden = true; return }
            if pr.none == true { prBox.isHidden = true; return }
            guard let title = pr.title, let url = pr.url else { prBox.isHidden = true; return }
            let state = pr.state ?? "?"
            let review = pr.reviewDecision ?? "PENDING"
            prLabel.stringValue = "PR #\(pr.number ?? 0): \(title)\n\(state) | \(review) | +\(pr.additions ?? 0) -\(pr.deletions ?? 0)\n\(url)"
            prBox.isHidden = false
        }
    }

    // MARK: Actions

    @objc private func doCommit() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = msg.isEmpty ? "generating commit message..." : "committing..."
        dismissGitActions()
        Task { @MainActor in
            var body: [String: Any] = ["cwd": workspace]
            if !msg.isEmpty { body["message"] = msg }
            let r = try? await client.postJSON("git/commit", body)
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "committed: \(r?["message"] as? String ?? "")"; commitField.stringValue = "" }
            reload()
        }
    }

    @objc private func doCommitPush() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = msg.isEmpty ? "generating message & pushing..." : "committing & pushing..."
        dismissGitActions()
        Task { @MainActor in
            var body: [String: Any] = ["cwd": workspace]
            if !msg.isEmpty { body["message"] = msg }
            let r = try? await client.postJSON("git/commit-push", body)
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "pushed: \(r?["message"] as? String ?? "")"; commitField.stringValue = "" }
            reload()
        }
    }

    @objc private func doPush() {
        statusLabel.stringValue = "pushing..."
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
