import AppKit

/// NSTextView that sends on Return, inserts a newline on Shift+Return, and extracts pasted attachments.
final class ComposerTextView: NSTextView {
    var onSend: (() -> Void)?
    var onPasteAttachments: (([URL]) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let urls = Self.attachmentURLs(from: NSPasteboard.general)
        if !urls.isEmpty {
            onPasteAttachments?(urls)
            if NSPasteboard.general.string(forType: .string) == nil { return }
        }
        super.paste(sender)
    }

    private static func attachmentURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        if let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls.append(contentsOf: items)
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let url = savePastedImage(data: data, ext: pasteboard.data(forType: .png) != nil ? "png" : "tiff") {
            urls.append(url)
        }
        return urls
    }

    private static func savePastedImage(data: Data, ext: String) -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dynagent")
            .appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// Small ring that fills to show context usage; exact percentage is shown in its tooltip.
final class ContextRing: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 27, height: 27)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 4)
        NSColor.secondaryLabelColor.withAlphaComponent(0.42).setStroke()
        let background = NSBezierPath(ovalIn: rect)
        background.lineWidth = 2.3
        background.stroke()

        guard fraction > 0 else { return }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: rect.width / 2,
            startAngle: 90,
            endAngle: 90 - 360 * CGFloat(min(fraction, 1)),
            clockwise: true
        )
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2.3
        path.stroke()
    }
}

enum ComposerChrome {
    static let attachmentButtonSize = NSSize(width: 32, height: 30)
    static let sendButtonSize: CGFloat = 30
    static let sendButtonCornerRadius: CGFloat = 15
    static let footerSpacing: CGFloat = 2
    static let menuSpacing: CGFloat = 4
    static let contextRingTrailingSpacerWidth: CGFloat = 18

    static func configureTextView(_ composer: ComposerTextView) {
        composer.font = .systemFont(ofSize: 15)
        composer.isRichText = false
        composer.drawsBackground = false
        composer.textContainerInset = NSSize(width: 2, height: 8)
        composer.textContainer?.lineFragmentPadding = 0
        composer.isVerticallyResizable = true
        composer.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        composer.autoresizingMask = [.width]
    }

    static func configurePlaceholder(_ placeholder: NSTextField) {
        placeholder.stringValue = "Ask Codex"
        placeholder.textColor = .placeholderTextColor
        placeholder.font = .systemFont(ofSize: 15.5)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configurePopup(_ popup: NSPopUpButton) {
        popup.controlSize = .large
        popup.font = .systemFont(ofSize: 15, weight: .medium)
        popup.bezelStyle = .shadowlessSquare
        popup.isBordered = false
        popup.imagePosition = .imageLeft
        popup.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configureAttachmentStrip(stack: NSStackView, scroll: NSScrollView) {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.isHidden = true
    }

    static func configureSendButton(_ button: NSButton, target: AnyObject, action: Selector) {
        button.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configureSpinner(_ spinner: NSProgressIndicator) {
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configureAttachmentButton(_ button: NSButton, target: AnyObject, action: Selector) {
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add attachment")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    static func makeSendContainer(button: NSButton, spinner: NSProgressIndicator) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = sendButtonCornerRadius
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        container.addSubview(spinner)
        return container
    }

    static func makeFooter(
        addAttachmentButton: NSButton,
        harnessMenu: ComposerMenuChrome,
        modelMenu: ComposerMenuChrome,
        reasoningMenu: ComposerMenuChrome,
        contextRing: ContextRing,
        sendContainer: NSView
    ) -> NSStackView {
        contextRing.translatesAutoresizingMaskIntoConstraints = false
        let ringSpacer = NSView()
        ringSpacer.translatesAutoresizingMaskIntoConstraints = false
        ringSpacer.widthAnchor.constraint(equalToConstant: contextRingTrailingSpacerWidth).isActive = true
        let footer = NSStackView(views: [
            addAttachmentButton,
            harnessMenu,
            NSView(),
            modelMenu,
            reasoningMenu,
            contextRing,
            ringSpacer,
            sendContainer,
        ] as [NSView])
        footer.orientation = .horizontal
        footer.spacing = footerSpacing
        footer.setCustomSpacing(menuSpacing, after: modelMenu)
        footer.setCustomSpacing(menuSpacing, after: reasoningMenu)
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }

    static func footerControlConstraints(
        addAttachmentButton: NSButton,
        sendContainer: NSView,
        sendButton: NSButton,
        spinner: NSProgressIndicator
    ) -> [NSLayoutConstraint] {
        [
            addAttachmentButton.widthAnchor.constraint(equalToConstant: attachmentButtonSize.width),
            addAttachmentButton.heightAnchor.constraint(equalToConstant: attachmentButtonSize.height),
            sendContainer.widthAnchor.constraint(equalToConstant: sendButtonSize),
            sendContainer.heightAnchor.constraint(equalToConstant: sendButtonSize),
            sendButton.centerXAnchor.constraint(equalTo: sendContainer.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: sendButtonSize),
            spinner.centerXAnchor.constraint(equalTo: sendContainer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sendContainer.centerYAnchor),
        ]
    }
}

enum ComposerAttachmentChip {
    static func make(
        attachment: ComposerAttachment,
        target: AnyObject,
        removeAction: Selector
    ) -> (view: NSView, removeButton: NSButton) {
        let isImage = ComposerModel.isImageFile(attachment.url)
        let iconOrPreview: NSView
        if isImage, let image = NSImage(contentsOf: attachment.url) {
            let preview = NSImageView(image: image)
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.wantsLayer = true
            preview.layer?.cornerRadius = 7
            preview.layer?.masksToBounds = true
            preview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                preview.widthAnchor.constraint(equalToConstant: 48),
                preview.heightAnchor.constraint(equalToConstant: 48),
            ])
            iconOrPreview = preview
        } else {
            let icon = NSImageView(image: NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
            ])
            iconOrPreview = icon
        }

        let label = NSButton(title: attachment.url.lastPathComponent, target: nil, action: nil)
        label.isBordered = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.contentTintColor = .secondaryLabelColor
        label.toolTip = attachment.url.path
        label.lineBreakMode = .byTruncatingMiddle

        let close = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove attachment")?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold)) ?? NSImage(),
            target: target,
            action: removeAction
        )
        close.isBordered = false
        close.contentTintColor = .tertiaryLabelColor

        let stack = NSStackView(views: [iconOrPreview, label, close])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: isImage ? 5 : 6, left: 8, bottom: isImage ? 5 : 6, right: 5)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        stack.toolTip = attachment.url.path
        label.widthAnchor.constraint(lessThanOrEqualToConstant: isImage ? 150 : 190).isActive = true
        return (stack, close)
    }
}

enum ComposerAttachmentStripChrome {
    static let visibleHeight: CGFloat = 66

    static func render(
        attachments: [ComposerAttachment],
        into stack: NSStackView,
        inside scroll: NSScrollView,
        heightConstraint: NSLayoutConstraint?,
        target: AnyObject,
        removeAction: Selector
    ) -> [ObjectIdentifier: UUID] {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stack.isHidden = attachments.isEmpty
        scroll.isHidden = attachments.isEmpty
        heightConstraint?.constant = attachments.isEmpty ? 0 : visibleHeight

        var removeIds: [ObjectIdentifier: UUID] = [:]
        for attachment in attachments {
            let chip = ComposerAttachmentChip.make(
                attachment: attachment,
                target: target,
                removeAction: removeAction
            )
            removeIds[ObjectIdentifier(chip.removeButton)] = attachment.id
            stack.addArrangedSubview(chip.view)
        }

        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: max(size.width, scroll.contentView.bounds.width),
            height: max(visibleHeight, size.height)
        )
        return removeIds
    }
}
