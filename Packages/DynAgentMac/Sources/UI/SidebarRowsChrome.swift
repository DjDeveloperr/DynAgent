import AppKit

struct SidebarSectionHeaderRow {
    var row: SidebarRow
    var addButton: NSButton?
}

enum SidebarRowsChrome {
    static func singleLineLabel(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        DesignSystem.label(
            text,
            style: .init(font: .systemFont(ofSize: size, weight: weight), color: color)
        )
    }

    static func actionRow(symbol: String, title: String, action: @escaping () -> Void) -> SidebarRow {
        SidebarRow(height: 36, onClick: action) { container in
            let icon = DesignSystem.symbolImageView(
                symbol,
                accessibilityDescription: title,
                pointSize: DesignSystem.Symbol.sidebarActionPointSize,
                tint: .labelColor
            )
            let label = DesignSystem.label(title, style: DesignSystem.Text.sidebarAction)
            for view in [icon, label] {
                container.addSubview(view)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
    }

    static func sectionHeader(
        title: String,
        expanded: Bool,
        addSymbol: String? = nil,
        addToolTip: String? = nil,
        addTarget: AnyObject? = nil,
        addAction: Selector? = nil,
        toggle: @escaping () -> Void
    ) -> SidebarSectionHeaderRow {
        var hoverViews: [NSView] = []
        weak var addButton: NSButton?
        let row = SidebarRow(height: 30, onClick: toggle, showsHoverBackground: false, onHoverChanged: { hovering in
            hoverViews.forEach { $0.isHidden = !hovering }
        }) { container in
            let label = DesignSystem.label(title, style: DesignSystem.Text.sidebarSection)
            let chevron = DesignSystem.symbolImageView(
                expanded ? "chevron.down" : "chevron.right",
                pointSize: DesignSystem.Symbol.sidebarSectionChevronPointSize,
                weight: .semibold,
                tint: .tertiaryLabelColor
            )
            chevron.isHidden = true
            hoverViews.append(chevron)
            for view in [label, chevron] {
                container.addSubview(view)
            }
            if let addSymbol, let addAction {
                let button = DesignSystem.iconButton(
                    symbol: addSymbol,
                    accessibilityDescription: addToolTip,
                    tint: .tertiaryLabelColor,
                    target: addTarget,
                    action: addAction
                )
                button.toolTip = addToolTip
                button.isHidden = true
                hoverViews.append(button)
                addButton = button
                container.addSubview(button)
                NSLayoutConstraint.activate([
                    button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                    button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                ])
            }
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
                chevron.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
        return SidebarSectionHeaderRow(row: row, addButton: addButton)
    }

    static func workspaceHeader(
        model: SidebarWorkspaceRowModel,
        onClick: @escaping () -> Void,
        onNewChat: @escaping () -> Void,
        onHoverChanged: @escaping (Bool, SidebarRow) -> Void
    ) -> SidebarRow {
        var hoverViews: [NSView] = []
        weak var rowRef: SidebarRow?
        let row = SidebarRow(height: 34, onClick: onClick, onHoverChanged: { hovering in
            hoverViews.forEach { $0.isHidden = !hovering }
            guard let row = rowRef else { return }
            onHoverChanged(hovering, row)
        }) { container in
            let icon = DesignSystem.symbolImageView(
                "folder",
                pointSize: DesignSystem.Symbol.sidebarWorkspacePointSize,
                tint: .secondaryLabelColor
            )
            let label = DesignSystem.label(model.name, style: DesignSystem.Text.sidebarWorkspace)
            let newChat = SidebarActionButton(symbol: "square.and.pencil", tooltip: "New chat")
            newChat.isHidden = true
            newChat.handler = { _ in onNewChat() }
            hoverViews.append(newChat)
            for view in [icon, label, newChat] {
                container.addSubview(view)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(lessThanOrEqualTo: newChat.leadingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                newChat.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                newChat.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                newChat.widthAnchor.constraint(equalToConstant: 24),
                newChat.heightAnchor.constraint(equalToConstant: 24),
            ])
        }
        rowRef = row
        return row
    }

    static func emptyWorkspaceRow() -> SidebarRow {
        SidebarRow(height: 26, onClick: {}, showsHoverBackground: false) { container in
            let label = DesignSystem.label("No chats", style: DesignSystem.Text.sidebarEmpty)
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 34),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
    }

    static func moreToggleRow(title: String, action: @escaping () -> Void) -> SidebarRow {
        SidebarRow(height: 26, onClick: action) { container in
            let label = DesignSystem.label(title, style: DesignSystem.Text.sidebarMore)
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
    }
}
