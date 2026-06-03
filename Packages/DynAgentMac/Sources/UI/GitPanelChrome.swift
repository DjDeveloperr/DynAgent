import AppKit

struct GitPanelHeaderChrome {
    let view: NSVisualEffectView
    let titleLabel: NSTextField
    let border: NSBox
}

enum GitPanelChrome {
    static let headerHeight: CGFloat = 54
    static let stickyHeaderHeight: CGFloat = 34
    static let diffTopInset: CGFloat = 54

    static func makeHeader(branchLabel: NSTextField) -> GitPanelHeaderChrome {
        let title = DesignSystem.label("Changes", style: DesignSystem.Text.gitPanelTitle)

        DesignSystem.configureLabel(branchLabel, style: DesignSystem.Text.gitPanelBranch)

        let header = NSVisualEffectView()
        header.material = .contentBackground
        header.blendingMode = .withinWindow
        header.state = .active
        header.translatesAutoresizingMaskIntoConstraints = false

        let border = NSBox()
        border.boxType = .separator
        border.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(title)
        header.addSubview(branchLabel)
        header.addSubview(border)
        return GitPanelHeaderChrome(view: header, titleLabel: title, border: border)
    }

    static func configureScopeControl(
        _ control: NSSegmentedControl,
        target: AnyObject,
        action: Selector
    ) {
        control.selectedSegment = 0
        control.target = target
        control.action = action
        control.controlSize = .small
        control.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configureDiffScroll(_ scroll: NSScrollView, document: NSView) {
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = document
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: diffTopInset, left: 0, bottom: 0, right: 0)
        scroll.contentView.postsBoundsChangedNotifications = true
    }

    static func configureStatusLabel(_ label: NSTextField) {
        DesignSystem.configureLabel(label, style: DesignSystem.Text.panelStatus)
    }

    static func configurePRBox(_ box: NSBox, label: NSTextField) {
        box.titlePosition = .noTitle
        box.contentView = label
        DesignSystem.configureLabel(label, style: DesignSystem.Text.panelBodySecondary)
        box.isHidden = true
    }

    static func makeContentStack(diffScroll: NSScrollView, prBox: NSBox, statusLabel: NSTextField) -> NSStackView {
        let stack = NSStackView(views: [diffScroll, prBox, statusLabel] as [NSView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        diffScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        diffScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        prBox.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        return stack
    }

    static func rootConstraints(
        root: NSView,
        stack: NSStackView,
        header: GitPanelHeaderChrome,
        diffHeader: NSView,
        branchLabel: NSTextField
    ) -> [NSLayoutConstraint] {
        [
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.view.topAnchor.constraint(equalTo: root.topAnchor),
            header.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.view.heightAnchor.constraint(equalToConstant: headerHeight),
            diffHeader.topAnchor.constraint(equalTo: header.view.bottomAnchor),
            diffHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            diffHeader.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            diffHeader.heightAnchor.constraint(equalToConstant: stickyHeaderHeight),
            header.titleLabel.leadingAnchor.constraint(equalTo: header.view.leadingAnchor, constant: 14),
            header.titleLabel.topAnchor.constraint(equalTo: header.view.topAnchor, constant: 10),
            branchLabel.leadingAnchor.constraint(equalTo: header.titleLabel.leadingAnchor),
            branchLabel.topAnchor.constraint(equalTo: header.titleLabel.bottomAnchor, constant: 2),
            header.titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.view.trailingAnchor, constant: -14),
            header.border.leadingAnchor.constraint(equalTo: header.view.leadingAnchor),
            header.border.trailingAnchor.constraint(equalTo: header.view.trailingAnchor),
            header.border.bottomAnchor.constraint(equalTo: header.view.bottomAnchor),
        ]
    }
}
