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
