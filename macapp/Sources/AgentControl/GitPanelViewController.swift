import AppKit

/// Right pane: git branch, changed files, diff, commit/push/PR actions.
final class GitPanelViewController: NSViewController {
    var client: AgentClient!
    private(set) var workspace = ""

    private let branchLabel = NSTextField(labelWithString: "—")
    private let diffScroll = NSScrollView()
    private let diffView = NSTextView()
    private let commitField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let prBox = NSBox()
    private let prLabel = NSTextField(wrappingLabelWithString: "")
    private var worktreeRow = NSStackView()
    var isWorktree = false { didSet { worktreeRow.isHidden = !isWorktree } }

    override func loadView() {
        let header = NSTextField(labelWithString: "Changes")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        branchLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        branchLabel.textColor = .secondaryLabelColor
        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!,
                               target: self, action: #selector(reload))
        refresh.isBordered = false
        let top = NSStackView(views: [header, branchLabel, NSView(), refresh] as [NSView])
        top.orientation = .horizontal

        diffView.isEditable = false
        diffView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diffView.textColor = .labelColor
        diffView.drawsBackground = false
        diffView.textContainerInset = NSSize(width: 4, height: 4)
        diffScroll.hasVerticalScroller = true
        diffScroll.documentView = diffView
        diffScroll.borderType = .noBorder
        diffScroll.drawsBackground = false

        commitField.placeholderString = "Commit message (blank = auto-generate)"
        commitField.font = .systemFont(ofSize: 12)

        let commitBtn = makeBtn("Commit", #selector(doCommit))
        let commitPushBtn = makeBtn("Commit & Push", #selector(doCommitPush))
        let pushBtn = makeBtn("Push", #selector(doPush))
        let branchBtn = makeBtn("New Branch", #selector(doCreateBranch))
        let prBtn = makeBtn("Create PR", #selector(doCreatePR))

        let row1 = NSStackView(views: [commitBtn, commitPushBtn, pushBtn] as [NSView])
        row1.orientation = .horizontal; row1.distribution = .fillEqually; row1.spacing = 6
        worktreeRow = NSStackView(views: [branchBtn, prBtn] as [NSView])
        worktreeRow.orientation = .horizontal; worktreeRow.distribution = .fillEqually; worktreeRow.spacing = 6
        worktreeRow.isHidden = !isWorktree

        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = .tertiaryLabelColor

        prBox.titlePosition = .noTitle
        prBox.contentView = prLabel
        prLabel.font = .systemFont(ofSize: 11)
        prLabel.textColor = .secondaryLabelColor
        prBox.isHidden = true

        let stack = NSStackView(views: [top, diffScroll, prBox, commitField, row1, worktreeRow, statusLabel] as [NSView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        diffScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    private func makeBtn(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded; b.controlSize = .small; b.font = .systemFont(ofSize: 11)
        return b
    }

    func show(workspace: String) { self.workspace = workspace; reload() }

    @objc func reload() {
        guard !workspace.isEmpty else { return }
        Task { @MainActor in
            guard let s = try? await client.gitStatus(workspace) else { return }
            if let err = s.error {
                branchLabel.stringValue = err; diffView.string = ""; statusLabel.stringValue = ""; prBox.isHidden = true; return
            }
            branchLabel.stringValue = s.branch ?? "—"
            if let diff = s.diff, !diff.isEmpty {
                diffView.textStorage?.setAttributedString(renderDiff(diff))
            } else {
                diffView.string = "No changes."
            }
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

    // MARK: - Proper diff renderer (diffshub-style)

    private func renderDiff(_ diff: String) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        let result = NSMutableAttributedString()
        var newLine = 0
        var oldLine = 0

        let addBg = NSColor(red: 0.85, green: 1.0, blue: 0.85, alpha: 1.0)
        let delBg = NSColor(red: 1.0, green: 0.88, blue: 0.88, alpha: 1.0)
        let addBgDark = NSColor(red: 0.12, green: 0.22, blue: 0.14, alpha: 1.0)
        let delBgDark = NSColor(red: 0.25, green: 0.12, blue: 0.12, alpha: 1.0)
        let hunkBg = NSColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 1.0)
        let hunkBgDark = NSColor(red: 0.15, green: 0.16, blue: 0.25, alpha: 1.0)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            // File header
            if line.hasPrefix("diff --git") {
                let file = line.split(separator: " ").last.map { String($0).replacingOccurrences(of: "b/", with: "") } ?? ""
                result.append(NSAttributedString(string: "\n  \(file)\n", attributes: [
                    .font: monoBold, .foregroundColor: NSColor.labelColor,
                    .backgroundColor: isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.03)
                ]))
                continue
            }

            if line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") { continue }

            if line.hasPrefix("@@") {
                let parts = line.split(separator: " ")
                if parts.count >= 3, let plus = parts.first(where: { $0.hasPrefix("+") }) {
                    let nums = plus.dropFirst().split(separator: ",")
                    newLine = Int(nums.first ?? "0") ?? 0
                }
                if parts.count >= 2, let minus = parts.first(where: { $0.hasPrefix("-") }) {
                    let nums = minus.dropFirst().split(separator: ",")
                    oldLine = Int(nums.first ?? "0") ?? 0
                }
                result.append(NSAttributedString(string: "  \(line)\n", attributes: [
                    .font: mono, .foregroundColor: NSColor.systemIndigo,
                    .backgroundColor: isDark ? hunkBgDark : hunkBg
                ]))
                continue
            }

            if line.hasPrefix("+") {
                let ln = String(format: "%4d", newLine)
                newLine += 1
                result.append(NSAttributedString(string: "  \(ln)  + \(line.dropFirst())\n", attributes: [
                    .font: mono, .foregroundColor: isDark ? NSColor.systemGreen : NSColor(red: 0.1, green: 0.45, blue: 0.1, alpha: 1),
                    .backgroundColor: isDark ? addBgDark : addBg
                ]))
            } else if line.hasPrefix("-") {
                let ln = String(format: "%4d", oldLine)
                oldLine += 1
                result.append(NSAttributedString(string: "  \(ln)  - \(line.dropFirst())\n", attributes: [
                    .font: mono, .foregroundColor: isDark ? NSColor.systemRed : NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1),
                    .backgroundColor: isDark ? delBgDark : delBg
                ]))
            } else {
                let ln = String(format: "%4d", newLine)
                oldLine += 1; newLine += 1
                result.append(NSAttributedString(string: "  \(ln)    \(line)\n", attributes: [
                    .font: mono, .foregroundColor: NSColor.labelColor
                ]))
            }
        }
        return result
    }

    // MARK: Actions

    @objc private func doCommit() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = msg.isEmpty ? "generating commit message..." : "committing..."
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
