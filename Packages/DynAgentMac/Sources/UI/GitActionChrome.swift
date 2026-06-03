import AppKit

final class GitActionPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

struct GitActionSelectors {
    var commit: Selector
    var commitPush: Selector
    var push: Selector
    var createBranch: Selector
    var createPR: Selector

    func selector(for action: GitActionKind) -> Selector {
        switch action {
        case .commit: return commit
        case .commitPush: return commitPush
        case .push: return push
        case .createBranch: return createBranch
        case .createPR: return createPR
        }
    }
}

enum GitActionSheetChrome {
    static func makePanel(
        branch: String,
        isWorktree: Bool,
        commitField: NSTextField,
        target: AnyObject,
        selectors: GitActionSelectors
    ) -> GitActionPanel {
        let panel = GitActionPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: GitActionSheetModel.panelWidth,
                height: GitActionSheetModel.panelHeight(isWorktree: isWorktree)
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Git Actions"
        panel.isReleasedWhenClosed = false
        panel.contentView = makeContent(
            branch: branch,
            isWorktree: isWorktree,
            commitField: commitField,
            target: target,
            selectors: selectors
        )
        return panel
    }

    static func makeContent(
        branch: String,
        isWorktree: Bool,
        commitField: NSTextField,
        target: AnyObject,
        selectors: GitActionSelectors
    ) -> NSView {
        let title = NSTextField(labelWithString: "Commit changes")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        let branchIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage())
        branchIcon.contentTintColor = .secondaryLabelColor
        branchIcon.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: branch)
        subtitle.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle

        let branchRow = NSStackView(views: [branchIcon, subtitle])
        branchRow.orientation = .horizontal
        branchRow.alignment = .centerY
        branchRow.spacing = 6
        branchRow.translatesAutoresizingMaskIntoConstraints = false

        configureCommitField(commitField)
        let inputBox = inputContainer(containing: commitField)

        let primaryButtons = NSStackView(views: [.commit, .commitPush, .push].map {
            makeButton($0, target: target, selector: selectors.selector(for: $0))
        })
        primaryButtons.orientation = .vertical
        primaryButtons.spacing = 8
        primaryButtons.alignment = .width

        var arranged: [NSView] = [title, branchRow, inputBox, primaryButtons]
        if isWorktree {
            let divider = NSBox()
            divider.boxType = .separator
            let worktreeButtons = NSStackView(views: [GitActionKind.createBranch, .createPR].map {
                makeButton($0, target: target, selector: selectors.selector(for: $0))
            })
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
        return root
    }

    static func configureCommitField(_ commitField: NSTextField) {
        commitField.placeholderString = GitActionSheetModel.commitPlaceholder
        commitField.font = .systemFont(ofSize: 14)
        commitField.isBordered = false
        commitField.drawsBackground = false
        commitField.usesSingleLineMode = false
        commitField.lineBreakMode = .byWordWrapping
        commitField.translatesAutoresizingMaskIntoConstraints = false
    }

    static func makeButton(_ action: GitActionKind, target: AnyObject, selector: Selector) -> NSButton {
        let button = NSButton(title: action.title, target: target, action: selector)
        button.isBordered = false
        button.alignment = .center
        button.font = .systemFont(ofSize: 13.5, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = NSColor.controlColor.withAlphaComponent(0.70).cgColor
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }

    private static func inputContainer(containing commitField: NSTextField) -> NSVisualEffectView {
        let inputBox = NSVisualEffectView()
        inputBox.material = .contentBackground
        inputBox.blendingMode = .withinWindow
        inputBox.state = .active
        inputBox.wantsLayer = true
        inputBox.layer?.cornerRadius = 10
        inputBox.translatesAutoresizingMaskIntoConstraints = false
        inputBox.addSubview(commitField)
        return inputBox
    }
}
