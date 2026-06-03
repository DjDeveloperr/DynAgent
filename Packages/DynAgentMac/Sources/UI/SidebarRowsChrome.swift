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
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func actionRow(symbol: String, title: String, action: @escaping () -> Void) -> SidebarRow {
        SidebarRow(height: 36, onClick: action) { container in
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage())
            icon.contentTintColor = .labelColor
            let label = singleLineLabel(title, size: 15, weight: .regular)
            for view in [icon, label] {
                view.translatesAutoresizingMaskIntoConstraints = false
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
            let label = singleLineLabel(title, size: 12.5, weight: .semibold, color: .tertiaryLabelColor)
            let chevron = NSImageView(image: NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) ?? NSImage())
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.isHidden = true
            hoverViews.append(chevron)
            for view in [label, chevron] {
                view.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(view)
            }
            if let addSymbol, let addAction {
                let button = NSButton(image: NSImage(systemSymbolName: addSymbol, accessibilityDescription: addToolTip) ?? NSImage(), target: addTarget, action: addAction)
                button.isBordered = false
                button.contentTintColor = .tertiaryLabelColor
                button.toolTip = addToolTip
                button.isHidden = true
                button.translatesAutoresizingMaskIntoConstraints = false
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
            let icon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            let label = singleLineLabel(model.name, size: 14.5, weight: .regular, color: .secondaryLabelColor)
            let newChat = SidebarActionButton(symbol: "square.and.pencil", tooltip: "New chat")
            newChat.isHidden = true
            newChat.handler = { _ in onNewChat() }
            hoverViews.append(newChat)
            for view in [icon, label, newChat] {
                view.translatesAutoresizingMaskIntoConstraints = false
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
            let label = singleLineLabel("No chats", size: 13, weight: .regular, color: .tertiaryLabelColor)
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
            let label = singleLineLabel(title, size: 12, weight: .medium, color: .tertiaryLabelColor)
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
    }
}
