import AppKit

/// Right pane: git branch, changed files, and the diff for the active workspace,
/// with refresh and commit actions.
final class GitPanelViewController: NSViewController {
    var client: AgentClient!
    private(set) var workspace = ""

    private let branchLabel = NSTextField(labelWithString: "—")
    private let diffView = NSTextView()
    private let commitField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

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
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = diffView
        scroll.borderType = .noBorder

        commitField.placeholderString = "Commit message…"
        let commit = NSButton(title: "Commit All", target: self, action: #selector(doCommit))
        commit.bezelStyle = .rounded
        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = .tertiaryLabelColor
        let commitRow = NSStackView(views: [commitField, commit] as [NSView])
        commitRow.orientation = .horizontal
        commitField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [top, scroll, commitRow, statusLabel] as [NSView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

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

    func show(workspace: String) {
        self.workspace = workspace
        reload()
    }

    @objc func reload() {
        guard !workspace.isEmpty else { return }
        Task { @MainActor in
            guard let s = try? await client.gitStatus(workspace) else { return }
            branchLabel.stringValue = s.error == nil ? (s.branch ?? "—") : "not a git repo"
            diffView.string = s.diff?.isEmpty == false ? s.diff! : (s.error ?? "No changes.")
            let n = s.files?.count ?? 0
            statusLabel.stringValue = n == 0 ? "" : "\(n) changed file\(n == 1 ? "" : "s")"
        }
    }

    @objc private func doCommit() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !workspace.isEmpty else { return }
        Task { @MainActor in
            let r = try? await client.post("git/commit", ["cwd": workspace, "message": msg])
            statusLabel.stringValue = (r?["error"] as? String) ?? "committed"
            commitField.stringValue = ""
            reload()
        }
    }
}
