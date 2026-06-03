import AppKit

final class SidebarConversationRowChromeState {
    let row: SidebarRow
    let model: SidebarConversationRowModel
    weak var pinButton: SidebarActionButton?
    weak var archiveButton: SidebarActionButton?
    weak var timeLabel: NSTextField?
    weak var worktreeIcon: NSImageView?
    weak var spinnerView: Spinner?
    var titleToTime: NSLayoutConstraint?
    var titleToActions: NSLayoutConstraint?

    init(
        row: SidebarRow,
        model: SidebarConversationRowModel,
        pinButton: SidebarActionButton?,
        archiveButton: SidebarActionButton?,
        timeLabel: NSTextField?,
        worktreeIcon: NSImageView?,
        spinnerView: Spinner?,
        titleToTime: NSLayoutConstraint?,
        titleToActions: NSLayoutConstraint?
    ) {
        self.row = row
        self.model = model
        self.pinButton = pinButton
        self.archiveButton = archiveButton
        self.timeLabel = timeLabel
        self.worktreeIcon = worktreeIcon
        self.spinnerView = spinnerView
        self.titleToTime = titleToTime
        self.titleToActions = titleToActions
    }

    func applyHover(_ hovering: Bool, confirming: Bool) {
        pinButton?.isHidden = !hovering || confirming
        archiveButton?.isHidden = !hovering && !confirming
        timeLabel?.isHidden = model.isWorking || hovering || confirming
        worktreeIcon?.isHidden = !model.isWorktree || model.isWorking || hovering || confirming
        spinnerView?.isHidden = !model.isWorking || hovering || confirming
        titleToTime?.isActive = !hovering && !confirming
        titleToActions?.isActive = hovering || confirming
    }
}

enum SidebarConversationRowChrome {
    static func make(
        model: SidebarConversationRowModel,
        indent: CGFloat,
        onClick: @escaping () -> Void,
        menu: @escaping () -> NSMenu,
        onPin: @escaping () -> Void,
        onArchive: @escaping (SidebarActionButton, SidebarActionButton?) -> Void,
        onHoverChanged: @escaping (Bool, SidebarConversationRowChromeState) -> Void
    ) -> SidebarConversationRowChromeState {
        weak var pinButton: SidebarActionButton?
        weak var archiveButton: SidebarActionButton?
        weak var timeLabel: NSTextField?
        weak var worktreeIcon: NSImageView?
        weak var spinnerView: Spinner?
        var titleToTime: NSLayoutConstraint?
        var titleToActions: NSLayoutConstraint?
        var state: SidebarConversationRowChromeState?

        let row = SidebarRow(height: 32, onClick: onClick, menu: menu, onHoverChanged: { hovering in
            guard let state else { return }
            onHoverChanged(hovering, state)
        }) { container in
            let title = SidebarRowsChrome.singleLineLabel(model.title, size: 14.5)
            let time = timeText(model)
            let branchIcon = worktreeIconView(hidden: !model.isWorktree || model.isWorking)
            let pin = SidebarActionButton(symbol: model.isPinned ? "pin.slash" : "pin", tooltip: model.isPinned ? "Unpin" : "Pin")
            pin.isHidden = true
            pin.handler = { _ in onPin() }
            let archive = SidebarActionButton(symbol: "archivebox", tooltip: "Archive")
            archive.isHidden = true
            archive.handler = { [weak pin] button in onArchive(button, pin) }

            pinButton = pin
            archiveButton = archive
            timeLabel = time
            worktreeIcon = branchIcon

            for view in [title, branchIcon, time, pin, archive] {
                container.addSubview(view)
            }

            titleToTime = title.trailingAnchor.constraint(
                lessThanOrEqualTo: model.isWorktree ? branchIcon.leadingAnchor : time.leadingAnchor,
                constant: -8
            )
            titleToActions = title.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -8)
            titleToActions?.isActive = false
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent),
                title.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                archive.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                archive.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                archive.heightAnchor.constraint(equalToConstant: 24),
                archive.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
                pin.trailingAnchor.constraint(equalTo: archive.leadingAnchor, constant: -2),
                pin.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                pin.widthAnchor.constraint(equalToConstant: 24),
                pin.heightAnchor.constraint(equalToConstant: 24),
                time.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                time.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                branchIcon.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -4),
                branchIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                branchIcon.widthAnchor.constraint(equalToConstant: 12),
                branchIcon.heightAnchor.constraint(equalToConstant: 12),
                titleToTime!,
            ])

            if model.isUnread {
                addUnreadDot(to: container)
            }
            if model.isWorking {
                let spinner = Spinner()
                spinnerView = spinner
                container.addSubview(spinner)
                time.isHidden = true
                NSLayoutConstraint.activate([
                    spinner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                    spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    spinner.widthAnchor.constraint(equalToConstant: 14),
                    spinner.heightAnchor.constraint(equalToConstant: 14),
                    title.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -6),
                ])
            }
        }

        let built = SidebarConversationRowChromeState(
            row: row,
            model: model,
            pinButton: pinButton,
            archiveButton: archiveButton,
            timeLabel: timeLabel,
            worktreeIcon: worktreeIcon,
            spinnerView: spinnerView,
            titleToTime: titleToTime,
            titleToActions: titleToActions
        )
        state = built
        return built
    }

    private static func timeText(_ model: SidebarConversationRowModel) -> NSTextField {
        let time = NSTextField(labelWithString: model.timeLabel)
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.textColor = model.isWorking ? .secondaryLabelColor : .tertiaryLabelColor
        time.lineBreakMode = .byTruncatingTail
        time.maximumNumberOfLines = 1
        time.cell?.usesSingleLineMode = true
        time.cell?.truncatesLastVisibleLine = true
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.translatesAutoresizingMaskIntoConstraints = false
        return time
    }

    private static func worktreeIconView(hidden: Bool) -> NSImageView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Worktree")?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .regular)) ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        icon.isHidden = hidden
        icon.translatesAutoresizingMaskIntoConstraints = false
        return icon
    }

    private static func addUnreadDot(to container: NSView) {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
        ])
    }
}
