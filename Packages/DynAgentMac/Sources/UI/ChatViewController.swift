import AppKit

/// View whose origin is top-left so transcript content grows downward.
final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// NSTextView that sends on Return and inserts a newline on Shift+Return.
final class ComposerTextView: NSTextView {
    var onSend: (() -> Void)?
    var onPasteAttachments: (([URL]) -> Void)?
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 36, !e.modifierFlags.contains(.shift) { onSend?(); return }
        super.keyDown(with: e)
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

private struct ComposerAttachment: Equatable {
    let id = UUID()
    let url: URL
}

private struct ComposerDraftSnapshot: Codable {
    var text: String
    var attachments: [String]
}

private extension URL {
    var isImageFile: Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"].contains(pathExtension.lowercased())
    }
}

/// Non-editable, selectable rich text view that keeps Markdown attributes during selection.
final class MessageTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else { return super.intrinsicContentSize }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isRichText = true
        textContainerInset = .zero
        isHorizontallyResizable = false
        isVerticallyResizable = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func setPlain(_ text: String) {
        string = text
        font = .systemFont(ofSize: 15)
        textColor = .labelColor
        invalidateIntrinsicContentSize()
    }

    func setRich(_ text: NSAttributedString) {
        textStorage?.setAttributedString(text)
        invalidateIntrinsicContentSize()
    }
}

/// Animated "Thinking" label with shimmer effect.
final class ShimmerLabel: NSView {
    private let label = NSTextField(labelWithString: "Thinking")
    private let gradient = CAGradientLayer()

    override var intrinsicContentSize: NSSize {
        label.intrinsicContentSize
    }

    init(text: String = "Thinking") {
        super.init(frame: .zero)
        configure(text: text)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure(text: "Thinking")
    }

    private func configure(text: String) {
        label.stringValue = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        setupShimmer()
    }

    private func setupShimmer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        label.textColor = isDark ? NSColor.white : NSColor.labelColor
        gradient.frame = bounds.insetBy(dx: -bounds.width, dy: 0)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        let base = NSColor.black.withAlphaComponent(isDark ? 0.42 : 0.32).cgColor
        let highlight = NSColor.black.withAlphaComponent(isDark ? 1.0 : 0.82).cgColor
        gradient.colors = [base, base, highlight, base, base]
        gradient.locations = [0, 0.35, 0.5, 0.65, 1.0]
        layer?.mask = gradient

        guard gradient.animation(forKey: "shimmer") == nil else { return }
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [0, 0.0, 0.1, 0.2, 0.3]
        anim.toValue = [0.7, 0.8, 0.9, 1.0, 1.0]
        anim.duration = 1.5
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: "shimmer")
    }
}

/// Codex-style work divider that can expand/collapse intermediate steps.
final class WorkDivider: NSView {
    var rows: [NSView] = []
    private var collapsed: Bool
    private var active: Bool
    private let label = NSTextField(labelWithString: "")
    private let rule = NSBox()
    private var timer: Timer?
    var duration: Double? { didSet { refresh() } }
    init(duration: Double?, collapsed: Bool = true, active: Bool = false) {
        self.duration = duration
        self.collapsed = collapsed
        self.active = active
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(rule)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 128),
            rule.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))
        if active {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.duration = (self.duration ?? 0) + 0.5
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    @objc private func toggle() {
        guard !active else { return }
        collapsed.toggle()
        refresh()
    }
    func finish(duration: Double?) {
        active = false
        timer?.invalidate()
        timer = nil
        self.duration = duration
        collapsed = true
        refresh()
    }
    func refresh() {
        if active { collapsed = false }
        rows.forEach { $0.isHidden = collapsed }
        label.stringValue = active ? Self.formatDuration(duration ?? 0, active: true) : "\(collapsed ? "▸" : "▾")  " + Self.formatDuration(duration ?? 0, active: false)
    }

    private static func formatDuration(_ seconds: Double, active: Bool) -> String {
        let total = max(0, Int(seconds.rounded()))
        let verb = active ? "Working for" : "Worked for"
        if total < 60 { return "\(verb) \(total)s" }
        return "\(verb) \(total / 60)m \(total % 60)s"
    }
}

/// Small ring that fills to show context usage; exact % shown on hover.
final class ContextRing: NSView {    var fraction: Double = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 27, height: 27) }
    override func draw(_ r: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 4)
        NSColor.secondaryLabelColor.withAlphaComponent(0.42).setStroke()
        let bg = NSBezierPath(ovalIn: rect); bg.lineWidth = 2.3; bg.stroke()
        guard fraction > 0 else { return }
        let c = NSPoint(x: rect.midX, y: rect.midY); let radius = rect.width / 2
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(min(fraction, 1)), clockwise: true)
        NSColor.controlAccentColor.setStroke(); p.lineWidth = 2.3; p.stroke()
    }
}

final class ComposerMenuChrome: NSView {
    let popup: NSPopUpButton
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold)) ?? NSImage())
    private let minWidth: CGFloat
    var displayProvider: (() -> NSAttributedString?)?

    init(popup: NSPopUpButton, minWidth: CGFloat) {
        self.popup = popup
        self.minWidth = minWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        popup.alphaValue = 0.01
        popup.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        chevron.contentTintColor = .secondaryLabelColor
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(popup)
        addSubview(label)
        chevron.isHidden = true
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            popup.leadingAnchor.constraint(equalTo: leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: trailingAnchor),
            popup.topAnchor.constraint(equalTo: topAnchor),
            popup.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let labelWidth = max(label.intrinsicContentSize.width, 1)
        return NSSize(width: max(minWidth, labelWidth + 4), height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        popup.performClick(self)
    }

    func refresh() {
        if let display = displayProvider?() {
            label.attributedStringValue = display
        } else {
            label.stringValue = popup.titleOfSelectedItem ?? ""
        }
        invalidateIntrinsicContentSize()
    }
}

final class EditStatsView: NSView {
    private let addLabel = NSTextField(labelWithString: "+0")
    private let delLabel = NSTextField(labelWithString: "-0")
    private var added = 0
    private var deleted = 0
    private var timer: Timer?

    init(added: Int, deleted: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(addLabel, color: .systemGreen)
        configure(delLabel, color: .systemRed)
        let stack = NSStackView(views: [addLabel, delLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        alphaValue = 0
        setValues(added: added, deleted: deleted, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            animator().alphaValue = 1
        }
    }

    func setValues(added targetAdded: Int, deleted targetDeleted: Int, animated: Bool = true) {
        guard animated else {
            added = targetAdded
            deleted = targetDeleted
            addLabel.stringValue = "+\(targetAdded)"
            delLabel.stringValue = "-\(targetDeleted)"
            return
        }
        timer?.invalidate()
        let startAdded = added
        let startDeleted = deleted
        let frames = 18
        var frame = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            frame += 1
            let progress = min(1, Double(frame) / Double(frames))
            let eased = 1 - pow(1 - progress, 3)
            self.added = startAdded + Int((Double(targetAdded - startAdded) * eased).rounded())
            self.deleted = startDeleted + Int((Double(targetDeleted - startDeleted) * eased).rounded())
            self.addLabel.stringValue = "+\(self.added)"
            self.delLabel.stringValue = "-\(self.deleted)"
            if frame >= frames {
                self.added = targetAdded
                self.deleted = targetDeleted
                self.addLabel.stringValue = "+\(targetAdded)"
                self.delLabel.stringValue = "-\(targetDeleted)"
                t.invalidate()
            }
        }
    }

    private func configure(_ label: NSTextField, color: NSColor) {
        label.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = color
    }
}

struct EditToolChange {
    var path: String
    var added: Int
    var deleted: Int
    var diff: String
}

final class DiffFileBlock: NSView {
    private let body = NSStackView()
    private let chevron = NSImageView()
    private var collapsed = false
    private let diff: String
    private var didBuildBody = false

    init(path: String, diff: String, added: Int, deleted: Int, initiallyCollapsed: Bool = true) {
        self.diff = diff
        self.collapsed = initiallyCollapsed
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        title.toolTip = path
        title.translatesAutoresizingMaskIntoConstraints = false
        let stats = EditStatsView(added: added, deleted: deleted)
        header.addSubview(chevron)
        header.addSubview(title)
        header.addSubview(stats)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 32),
            chevron.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            title.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            stats.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            stats.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            stats.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 0
        body.translatesAutoresizingMaskIntoConstraints = false
        body.isHidden = initiallyCollapsed
        chevron.image = NSImage(systemSymbolName: initiallyCollapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        if !initiallyCollapsed { buildBodyIfNeeded() }

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        header.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        collapsed.toggle()
        if !collapsed { buildBodyIfNeeded() }
        body.isHidden = collapsed
        chevron.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
    }

    private func buildBodyIfNeeded() {
        guard !didBuildBody else { return }
        didBuildBody = true
        let canvas = DiffCanvasView(rows: Self.diffRows(diff), maxRows: 300)
        body.addArrangedSubview(canvas)
        canvas.widthAnchor.constraint(greaterThanOrEqualToConstant: canvas.preferredWidth).isActive = true
    }

    fileprivate struct DiffRow { var old: Int?; var new: Int?; var text: String; var kind: Character }

    private static func diffRows(_ diff: String) -> [DiffRow] {
        var oldLine = 0
        var newLine = 0
        var rows: [DiffRow] = []
        for line in diff.components(separatedBy: .newlines) {
            if line.hasPrefix("@@") {
                if let match = line.range(of: #"@@ -(\d+)(?:,\d+)? \+(\d+)"#, options: .regularExpression) {
                    let text = String(line[match])
                    let nums = text.split { !$0.isNumber }.compactMap { Int($0) }
                    if nums.count >= 2 { oldLine = nums[0]; newLine = nums[1] }
                }
                rows.append(DiffRow(old: nil, new: nil, text: line, kind: "@"))
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                rows.append(DiffRow(old: nil, new: newLine, text: String(line.dropFirst()), kind: "+"))
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                rows.append(DiffRow(old: oldLine, new: nil, text: String(line.dropFirst()), kind: "-"))
                oldLine += 1
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                rows.append(DiffRow(old: oldLine > 0 ? oldLine : nil, new: newLine > 0 ? newLine : nil, text: text, kind: " "))
                if oldLine > 0 { oldLine += 1 }
                if newLine > 0 { newLine += 1 }
            }
        }
        return rows
    }

    fileprivate static func highlighted(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        let keywords = #"\b(let|var|func|final|class|struct|enum|if|else|for|while|guard|return|private|public|import|const|async|await|switch|case)\b"#
        if let re = try? NSRegularExpression(pattern: keywords) {
            let ns = out.string as NSString
            for m in re.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
                out.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: m.range)
            }
        }
        if let re = try? NSRegularExpression(pattern: #""[^"\n]*"|'[^'\n]*'"#) {
            let ns = out.string as NSString
            for m in re.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
                out.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: m.range)
            }
        }
        return out
    }
}

final class DiffCanvasView: NSView {
    private let rows: [DiffFileBlock.DiffRow]
    private let rowHeight: CGFloat = 22
    private let gutterWidth: CGFloat = 102
    let preferredWidth: CGFloat

    fileprivate init(rows: [DiffFileBlock.DiffRow], maxRows: Int) {
        self.rows = Array(rows.prefix(maxRows))
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let maxText = self.rows.map { CGFloat(($0.text as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 400
        preferredWidth = max(1200, gutterWidth + maxText + 60)
        super.init(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: CGFloat(self.rows.count) * rowHeight))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: CGFloat(self.rows.count) * rowHeight).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * rowHeight
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: rowHeight)
            switch row.kind {
            case "+": NSColor.systemGreen.withAlphaComponent(0.16).setFill()
            case "-": NSColor.systemRed.withAlphaComponent(0.18).setFill()
            case "@": NSColor.secondaryLabelColor.withAlphaComponent(0.11).setFill()
            default: NSColor.clear.setFill()
            }
            rect.fill()
            drawNumber(row.old, x: 8, y: y + 4, attrs: numberAttrs)
            drawNumber(row.new, x: 54, y: y + 4, attrs: numberAttrs)
            DiffFileBlock.highlighted(row.text).draw(at: NSPoint(x: gutterWidth + 8, y: y + 3))
        }
    }

    private func drawNumber(_ value: Int?, x: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let text = value.map(String.init) ?? ""
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: x + 34 - size.width, y: y), withAttributes: attrs)
    }
}

final class EditGroupView: NSView {
    private let body = NSStackView()
    private let changes: [EditToolChange]
    private let title = NSTextField(labelWithString: "")
    private let chevron = NSTextField(labelWithString: "▸")
    private var collapsed = true
    private var didBuild = false
    var onOpenChange: ((EditToolChange, NSView) -> Void)?

    init(changes: [EditToolChange]) {
        self.changes = changes
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        title.attributedStringValue = Self.headerTitle(for: changes)
        title.translatesAutoresizingMaskIntoConstraints = false
        chevron.font = .systemFont(ofSize: 11, weight: .semibold)
        chevron.textColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(icon)
        header.addSubview(title)
        header.addSubview(chevron)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 30),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 5),
            chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: -0.5),
            chevron.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -4),
        ])

        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 0
        body.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        body.isHidden = true
        body.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        header.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        collapsed.toggle()
        if !collapsed { buildIfNeeded() }
        body.isHidden = collapsed
        chevron.stringValue = collapsed ? "▸" : "▾"
    }

    private func buildIfNeeded() {
        guard !didBuild else { return }
        didBuild = true
        for change in changes {
            let row = EditFileSummaryRow(change: change)
            row.onOpen = { [weak self, weak row] change in
                guard let row else { return }
                self?.onOpenChange?(change, row)
            }
            body.addArrangedSubview(row)
        }
    }

    private static func headerTitle(for changes: [EditToolChange]) -> NSAttributedString {
        NSAttributedString(string: "Edited \(changes.count) file\(changes.count == 1 ? "" : "s")", attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}

final class EditFileSummaryRow: NSView {
    private let change: EditToolChange
    var onOpen: ((EditToolChange) -> Void)?

    init(change: EditToolChange) {
        self.change = change
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        let label = NSMutableAttributedString(string: "Edited ", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        label.append(NSAttributedString(string: (change.path as NSString).lastPathComponent, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.36, green: 0.58, blue: 0.86, alpha: 1),
        ]))
        label.append(NSAttributedString(string: "  +\(change.added)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.systemGreen,
        ]))
        label.append(NSAttributedString(string: "  -\(change.deleted)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.systemRed,
        ]))

        let tf = NSTextField(labelWithAttributedString: label)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.maximumNumberOfLines = 1
        tf.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tf)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: leadingAnchor),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func open() {
        onOpen?(change)
    }
}

private struct ShellGroupItem {
    let title: NSAttributedString
    let output: String
    let done: Bool
}

final class ShellToolView: NSView {
    private let body = MessageTextView()
    private let chevron = NSImageView()
    private let output: String
    private let outputPopover = NSPopover()
    private var collapsed = true

    init(title: NSAttributedString, output: String, done: Bool) {
        self.output = output
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithAttributedString: title)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.isHidden = true
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for v in [titleLabel, chevron] { header.addSubview(v) }
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -4),
        ])

        if !done {
            titleLabel.isHidden = true
            let shimmer = ShimmerLabel(text: title.string)
            header.addSubview(shimmer)
            NSLayoutConstraint.activate([
                shimmer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                shimmer.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            ])
        }

        body.setPlain(output.isEmpty ? "No output" : String(output.prefix(12000)))
        body.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        body.textColor = .secondaryLabelColor
        body.isHidden = false
        body.translatesAutoresizingMaskIntoConstraints = false
        let bodyContainer = NSView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(body)
        bodyContainer.isHidden = true
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            body.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            body.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])

        let stack = NSStackView(views: [header, bodyContainer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if !output.isEmpty {
            header.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        guard !output.isEmpty else { return }
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = output.isEmpty ? "No output" : output
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 360))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = text
        text.frame = scroll.bounds
        text.autoresizingMask = [.width]
        let vc = NSViewController()
        vc.view = scroll
        outputPopover.close()
        outputPopover.contentViewController = vc
        outputPopover.contentSize = NSSize(width: 620, height: 360)
        outputPopover.behavior = .transient
        outputPopover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }
}

final class ShellGroupView: NSView {
    private let chevron = NSImageView()
    private let body = NSStackView()
    private var collapsed = true

    fileprivate init(title: NSAttributedString, items: [ShellGroupItem]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        chevron.isHidden = true
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithAttributedString: title)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for v in [titleLabel, chevron] { header.addSubview(v) }
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -4),
        ])
        header.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))

        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 2
        body.isHidden = true
        body.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            body.addArrangedSubview(ShellToolView(title: item.title, output: item.output, done: item.done))
        }

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        collapsed.toggle()
        body.isHidden = collapsed
    }
}

/// Detail pane: a centered transcript (user / assistant / tool rows) and a composer card.
final class ChatViewController: NSViewController, NSTextViewDelegate {
    var client: AgentClient!
    var onActivity: ((Conversation) -> Void)?
    var onTitleGenerated: ((Conversation, String) -> Void)?
    var onAddWorkspace: (() -> Void)?
    var onNewWorktree: (() -> Void)?

    private(set) var conversation: Conversation?
    private let transcript = NSStackView()
    private let scroll = NSScrollView()
    private let headerTitle = NSTextField(labelWithString: "New Chat")
    private let headerMenuButton = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Chat actions")!, target: nil, action: nil)
    private let composer = ComposerTextView()
    private let placeholder = NSTextField(labelWithString: "Message the agent…  (⏎ to send, ⇧⏎ for newline)")
    private let modelPopup = NSPopUpButton()
    private let harnessPopup = NSPopUpButton()
    private let reasoningPopup = NSPopUpButton()
    private let addAttachmentButton = NSButton()
    private let attachmentScroll = NSScrollView()
    private let attachmentStack = NSStackView()
    private var modelMenu: ComposerMenuChrome?
    private var harnessMenu: ComposerMenuChrome?
    private var reasoningMenu: ComposerMenuChrome?
    private let contextRing = ContextRing()
    private let sendButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let card = NSGlassEffectView()
    private let cardContent = NSView()
    private var bottomInsetCache: CGFloat = 0
    private let emptyTitle = NSTextField(labelWithString: "Start a conversation")
    private let emptySub = NSTextField(labelWithString: "Workspace")
    private let emptyStack = NSStackView()
    private let emptyActions = NSStackView()
    private var cardBottomConstraint: NSLayoutConstraint?
    private var cardCenterYConstraint: NSLayoutConstraint?
    private var attachmentHeightConstraint: NSLayoutConstraint?
    private var labels: [ObjectIdentifier: MessageTextView] = [:]
    private var toolByView: [ObjectIdentifier: ChatMessage] = [:]
    private var editStatsByMessage: [ObjectIdentifier: EditStatsView] = [:]
    private let toolPopover = NSPopover()
    private var streamingConversationIds = Set<String>()
    private var streamTasks: [String: URLSessionDataTask] = [:]
    private var stopping = false
    private var bulkLoading = false
    private var turnStart = Date()
    private var copyText: [ObjectIdentifier: String] = [:]
    private let maxColumn: CGFloat = 1240
    private var shimmerView: ShimmerLabel?
    private var liveWorkDividerByConversationId: [String: WorkDivider] = [:]
    /// The current assistant message being streamed into (for proper interleaving).
    private var currentAssistant: ChatMessage?
    private var assistantByConversationId: [String: ChatMessage] = [:]
    private let maxRenderedMessages = 240
    private var codexModelIds: [String] = []
    private var selectedCodexModel = "gpt-5.5"
    private var selectedCodexEffort = "high"
    private var attachments: [ComposerAttachment] = []
    private var attachmentRemoveIds: [ObjectIdentifier: UUID] = [:]
    private var lastLiveMarkdownRender: [ObjectIdentifier: TimeInterval] = [:]
    private var lastActivityEmit: [String: TimeInterval] = [:]
    private var pendingToolRefreshByConversationId: [String: DispatchWorkItem] = [:]
    private var lastScrollToBottomAt: TimeInterval = 0
    private var pendingScrollToBottom = false
    private var restoringComposerDraft = false
    private var draftSaveWorkItem: DispatchWorkItem?
    private let composerDraftPrefix = "DynAgentComposerDraft."

    private var streaming: Bool {
        guard let conversation else { return false }
        return isActiveConversation(conversation)
    }

    func hasLocalStream(for c: Conversation) -> Bool {
        streamingConversationIds.contains(c.id)
    }

    var selectedModel: String {
        if selectedHarness == .codex { return resolvedCodexModel(selectedCodexModel) }
        return modelPopup.titleOfSelectedItem ?? "auto"
    }
    var selectedHarness: Harness { Harness(rawValue: harnessPopup.titleOfSelectedItem ?? "") ?? .dynagent }
    var selectedReasoning: String {
        if selectedHarness == .codex { return selectedCodexEffort }
        return reasoningPopup.titleOfSelectedItem ?? "high"
    }
    var onHarnessChanged: ((Harness) -> Void)?
    var onChatMenu: ((NSButton) -> Void)?
    /// Model to auto-select once a (possibly async) model list arrives.
    private var desiredModel: String?

    /// Sync the composer's harness picker to a conversation, reloading models if it changed.
    func setHarness(_ h: Harness, preferredModel: String? = nil) {
        if let preferredModel { desiredModel = preferredModel }
        let changed = selectedHarness != h
        if changed {
            harnessPopup.selectItem(withTitle: h.rawValue)
            reasoningPopup.isHidden = h == .codex
            installModelFallback(for: h, preferred: preferredModel)
            syncComposerMenus()
            onHarnessChanged?(h)
        } else if let preferredModel, modelPopup.itemTitles.contains(preferredModel) {
            modelPopup.selectItem(withTitle: preferredModel)
            syncComposerMenus()
        } else if modelPopup.numberOfItems == 0 {
            installModelFallback(for: h, preferred: preferredModel)
        } else {
            syncComposerMenus()
        }
    }

    /// Apply remembered harness+model as the composer defaults (used for new chats on launch).
    func applyDefaults(harness: Harness, model: String?) {
        desiredModel = model
        if harnessPopup.titleOfSelectedItem != harness.rawValue {
            harnessPopup.selectItem(withTitle: harness.rawValue)
            reasoningPopup.isHidden = harness == .codex
            installModelFallback(for: harness, preferred: model)
            syncComposerMenus()
            onHarnessChanged?(harness)
        } else if let model, modelPopup.itemTitles.contains(model) {
            modelPopup.selectItem(withTitle: model)
            syncComposerMenus()
        } else if modelPopup.numberOfItems == 0 {
            installModelFallback(for: harness, preferred: model)
        } else {
            syncComposerMenus()
        }
    }

    func setModels(_ ids: [String]) {
        guard !ids.isEmpty else {
            installModelFallback(for: selectedHarness, preferred: desiredModel)
            return
        }
        if selectedHarness == .codex {
            installCodexModelMenu(ids)
            return
        }
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: ids)
        let icon = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        for i in modelPopup.itemArray.indices { modelPopup.item(at: i)?.image = icon }
        if let want = desiredModel, ids.contains(want) {
            modelPopup.selectItem(withTitle: want)
        } else if let i = ids.firstIndex(where: { $0 != "auto" }) {
            modelPopup.selectItem(at: i)
        }
        syncComposerMenus()
    }

    private func installModelFallback(for harness: Harness, preferred: String?) {
        let fallback = preferred?.nilIfEmpty ?? {
            switch harness {
            case .dynagent: return "auto"
            case .codex: return "gpt-5.5"
            case .pi: return "kiro::kiro/claude-opus-4.8"
            }
        }()
        if harness == .codex { selectedCodexModel = fallback }
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: fallback)
        modelPopup.selectItem(withTitle: fallback)
        reasoningPopup.isHidden = harness == .codex
        syncComposerMenus()
    }

    private func resolvedCodexModel(_ preferred: String?) -> String {
        if let preferred = preferred?.nilIfEmpty {
            if codexModelIds.isEmpty || codexModelIds.contains(preferred) { return preferred }
        }
        return codexModelIds.first ?? "gpt-5.5"
    }

    private func ensureSelectedCodexModelIsSupported() {
        let resolved = resolvedCodexModel(selectedCodexModel)
        guard resolved != selectedCodexModel else { return }
        selectedCodexModel = resolved
        if !codexModelIds.isEmpty { installCodexModelMenu(codexModelIds) }
    }

    private func installCodexModelMenu(_ ids: [String]) {
        codexModelIds = ids
        if let desired = desiredModel?.nilIfEmpty, ids.contains(desired) {
            selectedCodexModel = desired
        } else if !ids.contains(selectedCodexModel) {
            selectedCodexModel = ids.first ?? "gpt-5.5"
        }
        let modelMenu = NSMenu()
        for id in ids {
            let item = NSMenuItem(title: shortCodexModelName(id), action: #selector(codexModelPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = id == selectedCodexModel ? .on : .off
            modelMenu.addItem(item)
        }
        let effortMenu = NSMenu()
        for (title, value) in [("Low", "low"), ("Medium", "medium"), ("High", "high"), ("Extra High", "xhigh")] {
            let item = NSMenuItem(title: title, action: #selector(codexEffortPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = value == selectedCodexEffort ? .on : .off
            effortMenu.addItem(item)
        }
        let menu = NSMenu()
        let modelParent = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelParent.submenu = modelMenu
        let effortParent = NSMenuItem(title: "Reasoning", action: nil, keyEquivalent: "")
        effortParent.submenu = effortMenu
        menu.addItem(modelParent)
        menu.addItem(effortParent)
        modelPopup.menu = menu
        reasoningPopup.isHidden = true
        syncComposerMenus()
    }

    private func shortCodexModelName(_ id: String) -> String {
        id.replacingOccurrences(of: "gpt-", with: "")
            .replacingOccurrences(of: "-codex-spark", with: " Codex Spark")
            .replacingOccurrences(of: "-codex", with: " Codex")
            .replacingOccurrences(of: "-mini", with: " Mini")
    }
    func setContext(_ percent: Double?) {
        let f = (percent ?? 0) / 100
        contextRing.fraction = f
        contextRing.toolTip = percent.map { "context \(Int($0))%" } ?? "context 0%"
        contextRing.isHidden = false
    }

    func setHeaderTitle(_ title: String) {
        headerTitle.stringValue = title.nilIfEmpty ?? "New Chat"
    }

    override func loadView() {
        transcript.orientation = .vertical
        transcript.alignment = .leading
        transcript.spacing = 14
        transcript.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.addSubview(transcript)
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 96, right: 0)
        scroll.documentView = doc
        scroll.translatesAutoresizingMaskIntoConstraints = false

        headerTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        headerTitle.textColor = .labelColor
        headerTitle.lineBreakMode = .byTruncatingTail
        headerTitle.maximumNumberOfLines = 1
        headerTitle.isHidden = true
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerMenuButton.isBordered = false
        headerMenuButton.contentTintColor = .secondaryLabelColor
        headerMenuButton.isHidden = true
        headerMenuButton.target = self
        headerMenuButton.action = #selector(showHeaderMenu(_:))
        headerMenuButton.translatesAutoresizingMaskIntoConstraints = false

        // Composer card
        composer.delegate = self
        composer.onSend = { [weak self] in self?.send() }
        composer.onPasteAttachments = { [weak self] urls in self?.addAttachments(urls) }
        composer.font = .systemFont(ofSize: 15)
        composer.isRichText = false
        composer.drawsBackground = false
        composer.textContainerInset = NSSize(width: 2, height: 8)
        composer.textContainer?.lineFragmentPadding = 0
        composer.isVerticallyResizable = true
        composer.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        composer.autoresizingMask = [.width]
        let composerScroll = NSScrollView()
        composerScroll.drawsBackground = false
        composerScroll.documentView = composer
        composerScroll.translatesAutoresizingMaskIntoConstraints = false

        placeholder.stringValue = "Ask Codex"
        placeholder.textColor = .placeholderTextColor
        placeholder.font = .systemFont(ofSize: 15.5)
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        attachmentStack.orientation = .horizontal
        attachmentStack.alignment = .centerY
        attachmentStack.spacing = 6
        attachmentStack.translatesAutoresizingMaskIntoConstraints = false
        attachmentStack.isHidden = true
        attachmentScroll.drawsBackground = false
        attachmentScroll.hasVerticalScroller = false
        attachmentScroll.hasHorizontalScroller = true
        attachmentScroll.autohidesScrollers = true
        attachmentScroll.scrollerStyle = .overlay
        attachmentScroll.documentView = attachmentStack
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.isHidden = true

        // Composer footer: harness + model selector + context usage on the left, send on the right.
        stylePopup(harnessPopup)
        harnessPopup.addItems(withTitles: Harness.allCases.map(\.rawValue))
        harnessPopup.target = self
        harnessPopup.action = #selector(harnessDidChange)
        stylePopup(modelPopup)
        modelPopup.target = self
        modelPopup.action = #selector(menuDidChange)
        stylePopup(reasoningPopup)
        reasoningPopup.addItems(withTitles: ["high", "medium", "low", "xhigh"])
        reasoningPopup.selectItem(withTitle: "high")
        reasoningPopup.target = self
        reasoningPopup.action = #selector(menuDidChange)
        contextRing.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        sendButton.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        sendButton.isBordered = false
        sendButton.imagePosition = .imageOnly
        sendButton.target = self
        sendButton.action = #selector(send)
        addAttachmentButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add attachment")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        addAttachmentButton.isBordered = false
        addAttachmentButton.imagePosition = .imageOnly
        addAttachmentButton.contentTintColor = .secondaryLabelColor
        addAttachmentButton.target = self
        addAttachmentButton.action = #selector(addAttachmentClicked)
        addAttachmentButton.translatesAutoresizingMaskIntoConstraints = false
        let sendStack = NSView()
        sendStack.wantsLayer = true
        sendStack.layer?.backgroundColor = NSColor.white.cgColor
        sendStack.layer?.cornerRadius = 15
        sendStack.layer?.masksToBounds = true
        sendStack.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendStack.addSubview(sendButton)
        sendStack.addSubview(spinner)

        let harnessMenu = ComposerMenuChrome(popup: harnessPopup, minWidth: 82)
        let modelMenu = ComposerMenuChrome(popup: modelPopup, minWidth: 58)
        let reasoningMenu = ComposerMenuChrome(popup: reasoningPopup, minWidth: 70)
        modelMenu.displayProvider = { [weak self] in self?.modelMenuTitle() }
        self.harnessMenu = harnessMenu
        self.modelMenu = modelMenu
        self.reasoningMenu = reasoningMenu

        let ringSpacer = NSView()
        ringSpacer.translatesAutoresizingMaskIntoConstraints = false
        ringSpacer.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let footer = NSStackView(views: [
            addAttachmentButton,
            harnessMenu,
            NSView(),
            modelMenu,
            reasoningMenu,
            contextRing,
            ringSpacer,
            sendStack
        ] as [NSView])
        footer.orientation = .horizontal
        footer.spacing = 2
        footer.setCustomSpacing(4, after: modelMenu)
        footer.setCustomSpacing(4, after: reasoningMenu)
        footer.translatesAutoresizingMaskIntoConstraints = false

        card.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        attachmentHeightConstraint = attachmentScroll.heightAnchor.constraint(equalToConstant: 0)
        cardContent.addSubview(composerScroll)
        cardContent.addSubview(placeholder)
        cardContent.addSubview(attachmentScroll)
        cardContent.addSubview(footer)
        card.contentView = cardContent

        emptyTitle.font = .systemFont(ofSize: 22, weight: .semibold)
        emptyTitle.alignment = .center
        emptySub.font = .systemFont(ofSize: 13)
        emptySub.textColor = .secondaryLabelColor
        emptySub.alignment = .center
        emptySub.lineBreakMode = .byWordWrapping
        emptySub.maximumNumberOfLines = 3
        emptySub.preferredMaxLayoutWidth = 420
        emptyStack.orientation = .vertical
        emptyStack.spacing = 10
        emptyStack.addArrangedSubview(emptyTitle)
        emptyStack.addArrangedSubview(emptySub)
        emptyActions.orientation = .horizontal
        emptyActions.alignment = .centerY
        emptyActions.spacing = 10
        emptyActions.addArrangedSubview(emptyAction("New Worktree", symbol: "arrow.triangle.branch", action: #selector(newWorktreeClicked)))
        emptyActions.addArrangedSubview(emptyAction("Add Workspace", symbol: "folder.badge.plus", action: #selector(addWorkspaceClicked)))
        emptyStack.addArrangedSubview(emptyActions)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scroll)
        root.addSubview(headerTitle)
        root.addSubview(headerMenuButton)
        root.addSubview(card)
        root.addSubview(emptyStack)

        // Hairline at the very top of the transcript area.
        let topBorder = NSBox()
        topBorder.boxType = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(topBorder)

        cardBottomConstraint = card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        cardCenterYConstraint = card.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 88)
        cardCenterYConstraint?.isActive = false

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            // Centered, max-width transcript column.
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            transcript.topAnchor.constraint(equalTo: doc.topAnchor, constant: 20),
            transcript.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -12),
            transcript.centerXAnchor.constraint(equalTo: doc.centerXAnchor),
            transcript.widthAnchor.constraint(lessThanOrEqualToConstant: maxColumn),
            transcript.leadingAnchor.constraint(greaterThanOrEqualTo: doc.leadingAnchor, constant: 14),
            column(transcript.widthAnchor.constraint(equalTo: doc.widthAnchor, constant: -28)),

            // Composer column (matches transcript width).
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: maxColumn),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 14),
            column(card.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28)),
            cardBottomConstraint!,

            attachmentScroll.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 10),
            attachmentScroll.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 12),
            attachmentScroll.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -12),
            attachmentHeightConstraint!,

            composerScroll.topAnchor.constraint(equalTo: attachmentScroll.bottomAnchor, constant: 6),
            composerScroll.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 12),
            composerScroll.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -12),
            composerScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            composerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),
            composerScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            placeholder.leadingAnchor.constraint(equalTo: composerScroll.leadingAnchor, constant: 2),
            placeholder.topAnchor.constraint(equalTo: composerScroll.topAnchor, constant: 8),

            footer.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -12),
            addAttachmentButton.widthAnchor.constraint(equalToConstant: 32),
            addAttachmentButton.heightAnchor.constraint(equalToConstant: 30),
            sendStack.widthAnchor.constraint(equalToConstant: 30),
            sendStack.heightAnchor.constraint(equalToConstant: 30),
            sendButton.centerXAnchor.constraint(equalTo: sendStack.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendStack.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            spinner.centerXAnchor.constraint(equalTo: sendStack.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sendStack.centerYAnchor),

            emptyStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStack.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -24),
            emptyStack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),

            headerTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            headerTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 15),
            headerTitle.trailingAnchor.constraint(lessThanOrEqualTo: headerMenuButton.leadingAnchor, constant: -4),
            headerMenuButton.leadingAnchor.constraint(equalTo: headerTitle.trailingAnchor, constant: 6),
            headerMenuButton.centerYAnchor.constraint(equalTo: headerTitle.centerYAnchor),
            headerMenuButton.widthAnchor.constraint(equalToConstant: 24),
            headerMenuButton.heightAnchor.constraint(equalToConstant: 22),

            topBorder.topAnchor.constraint(equalTo: root.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
    }

    @objc private func showHeaderMenu(_ sender: NSButton) {
        onChatMenu?(sender)
    }

    /// Keep the transcript clear of the floating composer: bottom inset tracks the composer height.
    override func viewDidLayout() {
        super.viewDidLayout()
        let inset = card.frame.height + 28
        if abs(inset - bottomInsetCache) > 1 {
            bottomInsetCache = inset
            scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
        }
    }

    /// Lower the priority of a "preferred width" constraint so the column can shrink.
    private func column(_ c: NSLayoutConstraint) -> NSLayoutConstraint {
        c.priority = .defaultHigh
        return c
    }

    private func stylePopup(_ popup: NSPopUpButton) {
        popup.controlSize = .large
        popup.font = .systemFont(ofSize: 15, weight: .medium)
        popup.bezelStyle = .shadowlessSquare
        popup.isBordered = false
        popup.imagePosition = .imageLeft
        popup.translatesAutoresizingMaskIntoConstraints = false
    }

    private func syncComposerMenus() {
        harnessMenu?.refresh()
        modelMenu?.refresh()
        reasoningMenu?.refresh()
        let agent = conversation?.harness.rawValue ?? selectedHarness.rawValue
        placeholder.stringValue = "Ask \(agent)"
        let editableAgent = conversation?.messages.isEmpty ?? true
        let lockedToCodex = conversation?.codexThreadId != nil
        harnessMenu?.isHidden = !editableAgent || lockedToCodex
        reasoningMenu?.isHidden = selectedHarness == .codex || reasoningPopup.isHidden
    }

    private func modelMenuTitle() -> NSAttributedString? {
        guard selectedHarness == .codex else { return nil }
        let title = NSMutableAttributedString(string: shortCodexModelName(selectedCodexModel), attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        title.append(NSAttributedString(string: " \(effortDisplayName(selectedCodexEffort))", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    private func effortDisplayName(_ effort: String) -> String {
        switch effort {
        case "low": return "Low"
        case "medium": return "Medium"
        case "xhigh": return "Extra High"
        default: return "High"
        }
    }

    private func sizedControl(_ control: NSView, minWidth: CGFloat) -> NSView {
        let shell = NSView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(control)
        NSLayoutConstraint.activate([
            shell.heightAnchor.constraint(equalToConstant: 30),
            shell.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            control.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: shell.centerYAnchor),
        ])
        return shell
    }

    private func glassControl(_ control: NSView, minWidth: CGFloat) -> NSView {
        let shell = NSVisualEffectView()
        shell.material = .menu
        shell.blendingMode = .withinWindow
        shell.state = .active
        shell.wantsLayer = true
        shell.layer?.cornerRadius = 13
        shell.layer?.masksToBounds = true
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(control)
        NSLayoutConstraint.activate([
            shell.heightAnchor.constraint(equalToConstant: 30),
            shell.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            control.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 10),
            control.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -8),
            control.centerYAnchor.constraint(equalTo: shell.centerYAnchor),
        ])
        return shell
    }

    private func emptyAction(_ title: String, symbol: String, action: Selector) -> NSView {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return glassControl(button, minWidth: title == "New Worktree" ? 142 : 150)
    }

    @objc private func addWorkspaceClicked() {
        onAddWorkspace?()
    }

    @objc private func newWorktreeClicked() {
        onNewWorktree?()
    }

    @objc private func addAttachmentClicked() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.addAttachments(panel.urls)
        }
    }

    private func addAttachments(_ urls: [URL]) {
        let existing = Set(attachments.map { $0.url.standardizedFileURL.path })
        let additions = urls
            .map { $0.standardizedFileURL }
            .filter { !existing.contains($0.path) }
            .map { ComposerAttachment(url: $0) }
        guard !additions.isEmpty else { return }
        attachments.append(contentsOf: additions)
        renderAttachments()
        updateSendButton()
        saveComposerDraft()
    }

    private func renderAttachments() {
        attachmentStack.arrangedSubviews.forEach { view in
            attachmentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        attachmentRemoveIds.removeAll()
        attachmentStack.isHidden = attachments.isEmpty
        attachmentScroll.isHidden = attachments.isEmpty
        attachmentHeightConstraint?.constant = attachments.isEmpty ? 0 : 66
        for attachment in attachments {
            attachmentStack.addArrangedSubview(attachmentChip(attachment))
        }
        attachmentStack.layoutSubtreeIfNeeded()
        let size = attachmentStack.fittingSize
        attachmentStack.frame = NSRect(x: 0, y: 0, width: max(size.width, attachmentScroll.contentView.bounds.width), height: max(66, size.height))
    }

    private func attachmentChip(_ attachment: ComposerAttachment) -> NSView {
        let iconOrPreview: NSView
        if attachment.url.isImageFile, let image = NSImage(contentsOf: attachment.url) {
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

        let button = NSButton(title: attachment.url.lastPathComponent, target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = attachment.url.path
        button.lineBreakMode = .byTruncatingMiddle

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove attachment")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold)) ?? NSImage(), target: self, action: #selector(removeAttachment(_:)))
        close.isBordered = false
        close.contentTintColor = .tertiaryLabelColor
        attachmentRemoveIds[ObjectIdentifier(close)] = attachment.id

        let stack = NSStackView(views: [iconOrPreview, button, close])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: attachment.url.isImageFile ? 5 : 6, left: 8, bottom: attachment.url.isImageFile ? 5 : 6, right: 5)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        stack.toolTip = attachment.url.path
        button.widthAnchor.constraint(lessThanOrEqualToConstant: attachment.url.isImageFile ? 150 : 190).isActive = true
        return stack
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        guard let id = attachmentRemoveIds[ObjectIdentifier(sender)] else { return }
        attachments.removeAll { $0.id == id }
        renderAttachments()
        updateSendButton()
        saveComposerDraft()
    }

    func saveComposerDraft() {
        guard !restoringComposerDraft, let c = conversation else { return }
        draftSaveWorkItem?.cancel()
        draftSaveWorkItem = nil
        let snapshot = ComposerDraftSnapshot(
            text: composer.string,
            attachments: attachments.map { $0.url.standardizedFileURL.path }
        )
        let key = composerDraftKey(for: c)
        if snapshot.text.isEmpty && snapshot.attachments.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func scheduleComposerDraftSave() {
        guard !restoringComposerDraft else { return }
        draftSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveComposerDraft() }
        draftSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func restoreComposerDraft(for c: Conversation) {
        let key = composerDraftKey(for: c)
        let data = UserDefaults.standard.data(forKey: key)
        let snapshot = data.flatMap { try? JSONDecoder().decode(ComposerDraftSnapshot.self, from: $0) }
        restoringComposerDraft = true
        composer.string = snapshot?.text ?? ""
        attachments = (snapshot?.attachments ?? [])
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ComposerAttachment(url: $0) }
        renderAttachments()
        restoringComposerDraft = false
        placeholder.isHidden = !composer.string.isEmpty
    }

    private func clearComposerDraft(for c: Conversation) {
        UserDefaults.standard.removeObject(forKey: composerDraftKey(for: c))
    }

    private func composerDraftKey(for c: Conversation) -> String {
        if let threadId = c.codexThreadId, !threadId.isEmpty {
            return composerDraftPrefix + "codex:" + threadId
        }
        if c.messages.isEmpty {
            return composerDraftPrefix + "new:" + (c.workspace.nilIfEmpty ?? "projectless")
        }
        return composerDraftPrefix + "local:" + c.id
    }

    func show(_ c: Conversation) {
        saveComposerDraft()
        conversation = c
        desiredModel = c.model
        if c.harness == .codex {
            selectedCodexModel = c.model.nilIfEmpty ?? selectedCodexModel
            if !codexModelIds.isEmpty { installCodexModelMenu(codexModelIds) }
        } else if modelPopup.itemTitles.contains(c.model) {
            modelPopup.selectItem(withTitle: c.model)
        }
        syncComposerMenus()
        shimmerView = nil
        currentAssistant = assistantByConversationId[c.id]
        labels.removeAll()
        toolByView.removeAll()
        editStatsByMessage.removeAll()
        liveWorkDividerByConversationId.removeValue(forKey: c.id)
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bulkLoading = true
        // Render each turn: prompt + work divider + final answer.
        let allMessages = c.messages
        let trimmedCount = max(0, allMessages.count - maxRenderedMessages)
        let msgs = trimmedCount > 0 ? Array(allMessages.suffix(maxRenderedMessages)) : allMessages
        if trimmedCount > 0 { addLargeThreadNotice(hiddenCount: trimmedCount) }
        var i = 0
        while i < msgs.count {
            var j = i + 1
            while j < msgs.count && !(msgs[j].role == .user && msgs[j].isSteer != true) { j += 1 }
            let turn = Array(msgs[i..<j])
            let isLastTurn = j >= msgs.count
            let turnComplete = turn.contains { $0.isFinal == true }
                || turn.contains { $0.role == .assistant && $0.turnStatus == nil && ($0.timestamp != nil || $0.turnDuration != nil) }
                || (!isLastTurn && turn.allSatisfy { $0.turnStatus == nil })
            if let final = turn.last(where: { $0.isFinal == true }), final.timestamp == nil {
                final.timestamp = c.updatedAt > 0 ? c.updatedAt : Date().timeIntervalSince1970
            }
            let streamingLastTurn = isLastTurn && isActiveConversation(c)
            renderTurn(turn, conversation: c, allowCollapse: turnComplete && !streamingLastTurn, forceActive: streamingLastTurn)
            i = j
        }
        bulkLoading = false
        if isActiveConversation(c) { showThinking() }
        restoreComposerDraft(for: c)
        updateEmptyState()
        updateSendButton()
        view.window?.makeFirstResponder(composer)
        scrollToBottom()
    }

    func showShell(_ c: Conversation) {
        saveComposerDraft()
        conversation = c
        desiredModel = c.model
        if c.harness == .codex {
            selectedCodexModel = c.model.nilIfEmpty ?? selectedCodexModel
            if !codexModelIds.isEmpty { installCodexModelMenu(codexModelIds) }
        } else if modelPopup.itemTitles.contains(c.model) {
            modelPopup.selectItem(withTitle: c.model)
        }
        shimmerView = nil
        currentAssistant = assistantByConversationId[c.id]
        labels.removeAll()
        toolByView.removeAll()
        editStatsByMessage.removeAll()
        liveWorkDividerByConversationId.removeValue(forKey: c.id)
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let loading = NSTextField(labelWithString: c.needsLoad ? "Loading latest thread..." : "Loading conversation...")
        loading.font = .systemFont(ofSize: 12.5, weight: .medium)
        loading.textColor = .tertiaryLabelColor
        loading.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loading.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            loading.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        emptyStack.isHidden = true
        cardBottomConstraint?.isActive = true
        cardCenterYConstraint?.isActive = false
        syncComposerMenus()
        restoreComposerDraft(for: c)
        updateSendButton()
        view.window?.makeFirstResponder(composer)
    }

    /// Render one turn with its work divider above the final assistant response.
    private func renderTurn(_ turn: [ChatMessage], conversation c: Conversation, allowCollapse: Bool, forceActive: Bool = false) {
        let activeTurn = forceActive || (!allowCollapse && turn.contains { $0.turnStatus != nil && $0.turnStatus != "completed" })
        if activeTurn {
            renderActiveTurn(turn, conversation: c)
            return
        }
        let finalIdx = allowCollapse ? turn.lastIndex { ($0.isFinal == true) || ($0.isFinal == nil && $0.role == .assistant && !$0.text.isEmpty) } : nil
        guard let finalIdx else {
            for m in turn { addRow(for: m) }
            return
        }
        var middle: [ChatMessage] = []
        for (k, m) in turn.enumerated() {
            if m.role == .user && m.isSteer != true { addRow(for: m) }
            else if k == finalIdx { continue }
            else { middle.append(m) }
        }
        let divider = addWorkDivider(duration: turn[finalIdx].turnDuration)
        divider.rows = addRowsGrouped(middle).map { row in row.isHidden = true; return row }
        divider.refresh()
        addRow(for: turn[finalIdx])
        addFinalFooter(for: turn[finalIdx])
    }

    private func renderActiveTurn(_ turn: [ChatMessage], conversation c: Conversation) {
        let started = turn.compactMap(\.turnStartedAt).first ?? activeTurnStartedAt(for: c) ?? Date().timeIntervalSince1970
        var middle: [ChatMessage] = []
        for m in turn {
            if m.role == .user && m.isSteer != true { addRow(for: m) }
            else { middle.append(m) }
        }
        let divider = addWorkDivider(duration: Date().timeIntervalSince1970 - started, collapsed: false, active: true)
        liveWorkDividerByConversationId[c.id] = divider
        divider.rows = addRowsGrouped(middle, collapseCompletedTools: false)
        divider.refresh()
    }

    private func addRowsGrouped(_ messages: [ChatMessage], collapseCompletedTools: Bool = true) -> [NSView] {
        var rows: [NSView] = []
        var i = 0
        while i < messages.count {
            let m = messages[i]
            if m.role == .tool, m.toolName == "edit" {
                if !m.toolDone {
                    rows.append(addRow(for: m))
                    i += 1
                    continue
                }
                var changes: [EditToolChange] = []
                var j = i
                while j < messages.count,
                      messages[j].role == .tool,
                      messages[j].toolName == "edit",
                      messages[j].toolDone {
                    changes.append(contentsOf: editSummary(messages[j]).changes)
                    j += 1
                }
                if !changes.isEmpty {
                    rows.append(addEditGroupRow(changes))
                } else {
                    rows.append(addRow(for: m))
                }
                i = j
            } else if !collapseCompletedTools {
                rows.append(addRow(for: m))
                i += 1
            } else if m.role == .tool, m.toolName == "shell" {
                var shellMessages: [ChatMessage] = []
                var j = i
                while j < messages.count,
                      messages[j].role == .tool,
                      messages[j].toolName == "shell" {
                    shellMessages.append(messages[j])
                    j += 1
                }
                if let running = shellMessages.last(where: { !$0.toolDone }) {
                    rows.append(addRow(for: running))
                } else if shellMessages.count > 1 {
                    rows.append(addShellGroupRow(shellMessages))
                } else if let only = shellMessages.first {
                    rows.append(addRow(for: only))
                }
                i = j
            } else {
                rows.append(addRow(for: m))
                i += 1
            }
        }
        return rows
    }

    @discardableResult
    private func addShellGroupRow(_ messages: [ChatMessage]) -> NSView {
        let items = messages.map { m -> ShellGroupItem in
            let summary = shellSummary(m)
            return ShellGroupItem(title: shellToolTitle(m, summary: summary), output: summary.output, done: m.toolDone)
        }
        let title = shellGroupTitle(messages.map(shellSummary))
        let group = ShellGroupView(title: title, items: items)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(group)
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: container.topAnchor),
            group.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            group.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        if !bulkLoading { pinShimmerToBottom() }
        return container
    }

    private func shellGroupTitle(_ summaries: [ShellSummary]) -> NSAttributedString {
        let parts = summaries.map { shellTitleParts(command: $0.command, done: true) }
        let commonCategory = parts.first?.category
        let sameCategory = commonCategory != nil && parts.allSatisfy { $0.category == commonCategory }
        let text: String
        switch sameCategory ? commonCategory : nil {
        case "read": text = summaries.count == 1 ? "Read file" : "Read \(summaries.count) files"
        case "search": text = summaries.count == 1 ? "Searched files" : "Searched \(summaries.count) times"
        case "list": text = "Listed files"
        case "diff": text = summaries.count == 1 ? "Read diff" : "Read diffs"
        case "git": text = summaries.count == 1 ? "Ran git" : "Ran \(summaries.count) git commands"
        default: text = summaries.count == 1 ? "Ran command" : "Ran \(summaries.count) commands"
        }
        let title = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let details = parts.compactMap(\.detail)
        if summaries.count == 1, let detail = details.first, !detail.isEmpty {
            title.append(NSAttributedString(string: "  \(detail)", attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        } else if summaries.count > 1, let first = details.first, !first.isEmpty {
            title.append(NSAttributedString(string: "  \(first) +\(summaries.count - 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return title
    }

    @discardableResult
    private func addEditGroupRow(_ changes: [EditToolChange]) -> NSView {
        let group = EditGroupView(changes: changes)
        group.onOpenChange = { [weak self] change, anchor in
            self?.showEditPopover(changes: [change], anchor: anchor)
        }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(group)
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: container.topAnchor),
            group.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            group.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        if !bulkLoading { pinShimmerToBottom() }
        return container
    }

    @discardableResult
    private func addWorkDivider(duration: Double?, collapsed: Bool = true, active: Bool = false) -> WorkDivider {
        let divider = WorkDivider(duration: duration, collapsed: collapsed, active: active)
        transcript.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        pinShimmerToBottom()
        return divider
    }

    private func ensureLiveWorkDivider(for c: Conversation) -> WorkDivider {
        if let existing = liveWorkDividerByConversationId[c.id] { return existing }
        let startedAt = activeTurnStartedAt(for: c) ?? turnStart.timeIntervalSince1970
        let divider = addWorkDivider(duration: Date().timeIntervalSince1970 - startedAt, collapsed: false, active: true)
        liveWorkDividerByConversationId[c.id] = divider
        return divider
    }

    private func isActiveConversation(_ c: Conversation) -> Bool {
        streamingConversationIds.contains(c.id) || c.status == .thinking || c.status == .running
    }

    private func activeTurnStartedAt(for c: Conversation) -> Double? {
        if let started = c.messages.reversed().compactMap(\.turnStartedAt).first {
            return started
        }
        if c.updatedAt > 0 { return c.updatedAt }
        return nil
    }

    /// Copy button + timestamp under a turn's final assistant message.
    private func addFinalFooter(for m: ChatMessage) {
        let copy = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!, target: self, action: #selector(copyFinal(_:)))
        copy.isBordered = false; copy.contentTintColor = .tertiaryLabelColor; copy.toolTip = "Copy"
        copyText[ObjectIdentifier(copy)] = m.text
        let ts = NSTextField(labelWithString: m.timestamp.map(Self.formatTime) ?? "")
        ts.font = .systemFont(ofSize: 11); ts.textColor = .tertiaryLabelColor
        let row = NSStackView(views: [copy, ts] as [NSView])
        row.orientation = .horizontal; row.spacing = 6; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(); container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
    }

    @objc private func copyFinal(_ sender: NSButton) {
        guard let t = copyText[ObjectIdentifier(sender)] else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
    }

    private static func formatTime(_ epoch: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }

    private func updateEmptyState() {
        let isEmpty = conversation?.messages.isEmpty ?? true
        if let workspace = conversation?.workspace, !workspace.isEmpty {
            emptySub.stringValue = (workspace as NSString).lastPathComponent
        } else {
            emptySub.stringValue = "Workspace"
        }
        emptyStack.isHidden = !isEmpty
        cardBottomConstraint?.isActive = !isEmpty
        cardCenterYConstraint?.isActive = isEmpty
    }

    // MARK: - Sending

    @objc private func send() {
        guard let c = conversation else { return }
        let typedText = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = messageTextWithAttachments(typedText)
        if text.isEmpty {
            if streaming { stop() }   // empty + streaming => the button is a Stop button
            return
        }
        composer.string = ""
        attachments.removeAll()
        renderAttachments()
        clearComposerDraft(for: c)
        textDidChange(Notification(name: NSText.didChangeNotification))

        // Steering: while a turn streams, inject the message. Codex steers natively (turn/steer);
        // DynAgent queues it for delivery on the next turn.
        if streaming {
            if c.harness == .codex, let tid = c.codexThreadId {
                addSteerNotice(to: c, text: text)
                Task { [weak self, weak c] in
                    guard let self, let c else { return }
                    do {
                        try await self.client.codexSteer(threadId: tid, text: text)
                    } catch {
                        await MainActor.run { self.addInlineError(error.localizedDescription, to: c) }
                    }
                }
            } else {
                c.steerQueue.append(text)
                addSteerNotice(to: c, text: text)
            }
            scrollToBottom()
            return
        }
        startTurn(text, on: c)
    }

    private func messageTextWithAttachments(_ text: String) -> String {
        guard !attachments.isEmpty else { return text }
        let attachmentLines = attachments.map { "- \($0.url.path)" }.joined(separator: "\n")
        let block = "Attached files:\n\(attachmentLines)"
        return text.isEmpty ? block : "\(text)\n\n\(block)"
    }

    private func stop() {
        guard let c = conversation else { return }
        stopping = true
        c.steerQueue.removeAll()
        if c.harness == .codex, let tid = c.codexThreadId {
            Task { await client.codexCancel(threadId: tid) }
        }
        client.cancel(streamTasks[c.id])
        hideThinking(); finalizeAssistant(for: c)
        c.status = .idle
        finish(c)
    }

    private func startTurn(_ text: String, on c: Conversation, appendUser: Bool = true) {
        if selectedHarness == .codex { ensureSelectedCodexModelIsSupported() }
        // Lock the conversation to the selected harness/model and remember as defaults.
        c.harness = selectedHarness
        c.model = selectedModel
        Store.saveLast(harness: selectedHarness, model: selectedModel)
        let startedAt = Date().timeIntervalSince1970
        if appendUser { turnStart = Date(timeIntervalSince1970: startedAt) }

        if appendUser {
            let user = ChatMessage(role: .user, text: text)
            user.turnStartedAt = startedAt
            user.turnStatus = "running"
            c.messages.append(user); addRow(for: user)
        }
        if conversation === c { syncComposerMenus() }
        updateEmptyState()

        let isFirstMessage = c.messages.filter { $0.role == .user }.count == 1

        setStreaming(true, for: c)
        c.status = .thinking
        c.updatedAt = Date().timeIntervalSince1970
        if conversation === c {
            _ = ensureLiveWorkDivider(for: c)
            showThinking()
        }
        emitActivity(c, force: true)

        if isFirstMessage { generateTitle(for: c, prompt: text) }

        assistantByConversationId[c.id] = nil
        if conversation === c { currentAssistant = nil }
        let handler: (AgentClient.Event) -> Void = { [weak self, weak c] ev in
            guard let self, let c else { return }
            let isVisible = self.conversation === c
            switch ev {
            case .thread(let id):
                c.codexThreadId = id
            case .text(let t):
                let assistant: ChatMessage
                if let existing = self.assistantByConversationId[c.id] {
                    assistant = existing
                } else {
                    let assistant = ChatMessage(role: .assistant, text: "")
                    c.messages.append(assistant)
                    self.assistantByConversationId[c.id] = assistant
                    if isVisible {
                        _ = self.ensureLiveWorkDivider(for: c)
                        self.addRow(for: assistant)
                        self.currentAssistant = assistant
                    }
                    assistant.text += t
                    if isVisible { self.renderLiveAssistant(assistant) }
                    self.emitActivity(c)
                    break
                }
                assistant.text += t
                if isVisible { self.renderLiveAssistant(assistant) }
                self.emitActivity(c)
            case .steer:
                self.addSteerNotice(to: c)
            case .tool(let n, let d):
                c.status = .running
                c.updatedAt = Date().timeIntervalSince1970
                self.emitActivity(c)
                if isVisible { self.finalizeAssistant(for: c) }
                self.assistantByConversationId[c.id] = nil
                if isVisible { self.currentAssistant = nil }
                let tool = ChatMessage(role: .tool, text: "", toolName: n, toolDetail: d)
                tool.turnStartedAt = self.activeTurnStartedAt(for: c)
                tool.turnStatus = "running"
                c.messages.append(tool)
                if isVisible {
                    let divider = self.ensureLiveWorkDivider(for: c)
                    let row = self.addRow(for: tool)
                    row.isHidden = true
                    divider.rows.append(row)
                    divider.refresh()
                }
            case .toolResult(let n, let d):
                if let t = c.messages.last(where: { $0.role == .tool && $0.toolName == n && !$0.toolDone }) {
                    t.toolDone = true
                    t.turnStatus = "completed"
                    if let d, !d.isEmpty { t.toolDetail = (t.toolDetail.map { $0 + "\n\n" } ?? "") + d }
                    if isVisible {
                        self.labels[ObjectIdentifier(t)]?.setRich(self.toolString(t))
                        if t.toolName == "edit", let stats = self.editStatsByMessage[ObjectIdentifier(t)] {
                            let summary = self.editSummary(t)
                            stats.isHidden = summary.added == 0 && summary.deleted == 0
                            stats.setValues(added: summary.added, deleted: summary.deleted)
                        }
                        if t.toolName == "edit" || t.toolName == "shell" {
                            self.scheduleToolRefresh(for: c)
                        }
                    }
                    self.emitActivity(c, force: true)
                }
            case .error(let e):
                if isVisible { self.hideThinking() }
                if self.stopping { self.stopping = false; return }   // user-initiated stop, not a real error
                let assistant: ChatMessage
                if let existing = self.assistantByConversationId[c.id] {
                    assistant = existing
                } else {
                    let assistant = ChatMessage(role: .assistant, text: "")
                    assistant.turnStartedAt = self.activeTurnStartedAt(for: c)
                    assistant.turnStatus = "running"
                    c.messages.append(assistant)
                    self.assistantByConversationId[c.id] = assistant
                    if isVisible {
                        _ = self.ensureLiveWorkDivider(for: c)
                        self.addRow(for: assistant)
                        self.currentAssistant = assistant
                    }
                    assistant.text += "⚠︎ " + e
                    if isVisible { self.renderLiveAssistant(assistant) }
                    c.status = .error; self.finish(c)
                    break
                }
                assistant.text += (assistant.text.isEmpty ? "" : "\n") + "⚠︎ " + e
                if isVisible { self.renderLiveAssistant(assistant) }
                c.status = .error; self.finish(c)
            case .done:
                if isVisible { self.hideThinking() }
                if isVisible { self.finalizeAssistant(for: c) }
                if let fa = c.messages.last(where: { $0.role == .assistant }) {
                    fa.timestamp = Date().timeIntervalSince1970
                    let started = self.activeTurnStartedAt(for: c) ?? self.turnStart.timeIntervalSince1970
                    fa.turnDuration = Date().timeIntervalSince1970 - started
                    fa.turnStatus = "completed"
                    fa.isFinal = true
                    if let promptIndex = c.messages.lastIndex(where: { $0.role == .user && !($0.isSteer ?? false) }) {
                        for msg in c.messages[promptIndex...] {
                            if msg.turnStatus != nil { msg.turnStatus = "completed" }
                            if msg.role == .tool { msg.toolDone = true }
                        }
                    }
                    if isVisible, let divider = self.liveWorkDividerByConversationId[c.id] {
                        divider.finish(duration: fa.turnDuration)
                        self.liveWorkDividerByConversationId[c.id] = nil
                    }
                    if isVisible { self.addFinalFooter(for: fa) }
                }
                c.status = .idle; self.finish(c)
                if isVisible { self.scheduleToolRefresh(for: c) }
            }
            c.updatedAt = Date().timeIntervalSince1970
            if isVisible { self.scrollToBottom() }
        }

        let task: URLSessionDataTask
        if selectedHarness == .codex {
            task = client.codexChat(model: selectedModel, text: text, cwd: c.workspace,
                                    threadId: c.codexThreadId, effort: selectedReasoning, onEvent: handler)
        } else if selectedHarness == .pi {
            task = client.piChat(model: selectedModel, text: text, cwd: c.workspace, sessionId: c.id, onEvent: handler)
        } else {
            task = client.chat(model: selectedModel, conversationId: c.id, cwd: c.workspace, messages: c.history, onEvent: handler)
        }
        streamTasks[c.id] = task
    }

    private func finish(_ c: Conversation) {
        if let promptIndex = c.messages.lastIndex(where: { $0.role == .user && !($0.isSteer ?? false) }) {
            for msg in c.messages[promptIndex...] {
                if msg.turnStatus != nil { msg.turnStatus = "completed" }
                if msg.role == .tool { msg.toolDone = true }
            }
        }
        setStreaming(false, for: c)
        streamTasks[c.id] = nil
        assistantByConversationId[c.id] = nil
        if conversation === c { currentAssistant = nil }
        emitActivity(c, force: true)
        // Deliver any messages queued while streaming (steering) as the next turn.
        if !c.steerQueue.isEmpty {
            let joined = c.steerQueue.joined(separator: "\n\n")
            c.steerQueue.removeAll()
            startTurn(joined, on: c, appendUser: false)
        }
    }

    private func addSteerNotice(to c: Conversation, text: String? = nil) {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if c.messages.last?.isSteer == true && c.messages.last?.text == text { return }
            let steer = ChatMessage(role: .user, text: text)
            steer.isSteer = true
            steer.toolDetail = "pending"
            steer.toolDone = false
            c.messages.append(steer)
        } else {
            if let pending = c.messages.last(where: { $0.isSteer == true && $0.toolDetail == "pending" }) {
                pending.toolDetail = nil
                pending.toolDone = true
                if conversation === c { show(c) }
                return
            }
            if c.messages.last?.toolName == "steer" || c.messages.last?.isSteer == true { return }
            let notice = ChatMessage(role: .tool, text: "", toolName: "steer", toolDetail: "Steered conversation")
            notice.toolDone = true
            c.messages.append(notice)
        }
        guard conversation === c else { return }
        let divider = ensureLiveWorkDivider(for: c)
        let row = addRow(for: c.messages.last!)
        divider.rows.append(row)
        divider.refresh()
    }

    private func emitActivity(_ c: Conversation, force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force, now - (lastActivityEmit[c.id] ?? 0) < 2.0 { return }
        lastActivityEmit[c.id] = now
        onActivity?(c)
    }

    private func scheduleToolRefresh(for c: Conversation) {
        guard conversation === c else { return }
        guard !isActiveConversation(c) else { return }
        pendingToolRefreshByConversationId[c.id]?.cancel()
        let item = DispatchWorkItem { [weak self, weak c] in
            guard let self, let c, self.conversation === c else { return }
            self.show(c)
        }
        pendingToolRefreshByConversationId[c.id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    /// Re-render the active assistant message as markdown once its text is final.
    private func finalizeAssistant(for c: Conversation) {
        guard let a = assistantByConversationId[c.id] ?? (conversation === c ? currentAssistant : nil),
              let label = labels[ObjectIdentifier(a)] else { return }
        label.setRich(Self.markdown(a.text))
    }

    /// Full Markdown rendering with a consistent base font.
    static func markdown(_ s: String) -> NSAttributedString {
        renderMarkdown(renderDirectives(s))
    }

    /// Turn `::git-push{cwd="x" branch="main"}` into a clean inline-code token.
    private static func renderDirectives(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "::([\\w-]+)\\{([^}]*)\\}") else { return s }
        let ns = s as NSString
        let out = NSMutableString(string: s)
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: m.range(at: 1))
            let args = ns.substring(with: m.range(at: 2))
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "  ", with: " ")
                .replacingOccurrences(of: " ", with: " - ")
            let token = args.isEmpty ? "`action \(name)`" : "`action \(name) - \(args)`"
            out.replaceCharacters(in: m.range, with: token)
        }
        return out as String
    }

    private static func renderMarkdown(_ s: String) -> NSAttributedString {
        let normalized = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let out = NSMutableAttributedString()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inFence = false
        var codeBuffer: [String] = []

        func appendCodeBlock(_ lines: [String]) {
            guard !lines.isEmpty else { return }
            let text = lines.joined(separator: "\n")
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 10
            let block = NSMutableAttributedString(string: text + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.10),
                .paragraphStyle: paragraph,
            ])
            out.append(block)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    appendCodeBlock(codeBuffer)
                    codeBuffer.removeAll()
                    inFence = false
                } else {
                    inFence = true
                }
                continue
            }
            if inFence {
                codeBuffer.append(line)
                continue
            }

            let renderedLine: NSAttributedString
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = trimmed.isEmpty ? 6 : 4
            if let match = line.range(of: #"^\s*[-*]\s+(.+)$"#, options: .regularExpression) {
                let text = String(line[match])
                let body = text.replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "", options: .regularExpression)
                paragraph.firstLineHeadIndent = 0
                paragraph.headIndent = 18
                renderedLine = inlineMarkdown("• " + body, paragraph: paragraph)
            } else if let match = line.range(of: #"^\s*\d+\.\s+(.+)$"#, options: .regularExpression) {
                let text = String(line[match])
                paragraph.firstLineHeadIndent = 0
                paragraph.headIndent = 22
                renderedLine = inlineMarkdown(text.trimmingCharacters(in: .whitespaces), paragraph: paragraph)
            } else {
                renderedLine = inlineMarkdown(line, paragraph: paragraph)
            }
            out.append(renderedLine)
            out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
        }
        if inFence { appendCodeBlock(codeBuffer) }
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    private static func inlineMarkdown(_ text: String, paragraph: NSParagraphStyle) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 15)
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        replaceInlineGroups(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#, in: out) { groups in
            let title = groups.first ?? ""
            let target = groups.dropFirst().first ?? ""
            var attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.controlAccentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraph,
            ]
            if let url = URL(string: target) { attrs[.link] = url }
            return NSAttributedString(string: title, attributes: attrs)
        }
        replaceInline(pattern: #"`([^`\n]+)`"#, in: out) { inner in
            NSAttributedString(string: inner, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
                .paragraphStyle: paragraph,
            ])
        }
        replaceInline(pattern: #"\*\*([^*\n]+)\*\*"#, in: out) { inner in
            NSAttributedString(string: inner, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
        }
        replaceInline(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: out) { inner in
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            return NSAttributedString(string: inner, attributes: [
                .font: italic,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
        }
        return out
    }

    private static func replaceInline(pattern: String, in text: NSMutableAttributedString, replacement: (String) -> NSAttributedString) {
        replaceInlineGroups(pattern: pattern, in: text) { groups in replacement(groups.first ?? "") }
    }

    private static func replaceInlineGroups(pattern: String, in text: NSMutableAttributedString, replacement: ([String]) -> NSAttributedString) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let source = text.string as NSString
        let full = NSRange(location: 0, length: source.length)
        for match in re.matches(in: text.string, range: full).reversed() {
            let groups = (1..<match.numberOfRanges).compactMap { i -> String? in
                let range = match.range(at: i)
                guard range.location != NSNotFound else { return nil }
                return source.substring(with: range)
            }
            text.replaceCharacters(in: match.range, with: replacement(groups))
        }
    }

    @objc private func harnessDidChange() {
        reasoningPopup.isHidden = selectedHarness == .codex
        syncComposerMenus()
        onHarnessChanged?(selectedHarness)
    }

    @objc private func menuDidChange() {
        syncComposerMenus()
    }

    @objc private func codexModelPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        selectedCodexModel = id
        installCodexModelMenu(codexModelIds.isEmpty ? [id] : codexModelIds)
    }

    @objc private func codexEffortPicked(_ sender: NSMenuItem) {
        guard let effort = sender.representedObject as? String else { return }
        selectedCodexEffort = effort
        installCodexModelMenu(codexModelIds.isEmpty ? [selectedCodexModel] : codexModelIds)
    }

    private func setStreaming(_ on: Bool, for c: Conversation) {
        if on { streamingConversationIds.insert(c.id) }
        else { streamingConversationIds.remove(c.id) }
        if conversation === c { updateSendButton() }
    }

    /// The action button is "Stop" while streaming with an empty composer, else "Send".
    private func updateSendButton() {
        let hasText = !composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isStop = streaming && !hasText && attachments.isEmpty
        sendButton.image = NSImage(systemSymbolName: isStop ? "stop.fill" : "arrow.up",
                                   accessibilityDescription: isStop ? "Stop" : "Send")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        sendButton.contentTintColor = .black
    }

    // MARK: - Thinking shimmer

    private func showThinking() {
        guard shimmerView == nil else { return }
        let s = ShimmerLabel()
        shimmerView = s
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(s)
        NSLayoutConstraint.activate([
            s.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            s.topAnchor.constraint(equalTo: container.topAnchor),
            s.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        scrollToBottom()
    }

    private func addInlineError(_ message: String, to c: Conversation) {
        let text = "⚠︎ " + message
        let assistant = ChatMessage(role: .assistant, text: text)
        c.messages.append(assistant)
        c.status = .error
        guard conversation === c else { return }
        hideThinking()
        _ = ensureLiveWorkDivider(for: c)
        addRow(for: assistant)
        scrollToBottom()
    }

    private func hideThinking() {
        guard let s = shimmerView else { return }
        s.superview?.removeFromSuperview()
        shimmerView = nil
    }

    // MARK: - Title generation

    private func generateTitle(for c: Conversation, prompt: String) {
        Task { @MainActor in
            let title = await client.generateTitle(prompt: prompt, model: selectedModel)
            if !title.isEmpty && title != "New Chat" {
                c.title = title
                onTitleGenerated?(c, title)
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !composer.string.isEmpty
        updateSendButton()
        scheduleComposerDraftSave()
    }

    // MARK: - Row rendering

    @discardableResult
    private func addRow(for m: ChatMessage) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let content = MessageTextView()
        content.isSelectable = true
        content.translatesAutoresizingMaskIntoConstraints = false

        switch m.role {
        case .assistant:
            content.setRich(Self.markdown(m.text))
            container.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
                content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        case .user:
            if m.isSteer == true {
                let pending = m.toolDetail == "pending"
                let title = NSTextField(labelWithString: pending ? "Steering conversation…" : "Steered conversation")
                title.font = .systemFont(ofSize: 13, weight: .regular)
                title.textColor = .secondaryLabelColor
                title.translatesAutoresizingMaskIntoConstraints = false
                let steerText = userTextLabel(m.text)
                let bubble = box(steerText, bg: NSColor.secondaryLabelColor.withAlphaComponent(0.12), topInset: 9, bottomInset: 9, horizontalInset: 12, radius: 10)
                container.addSubview(title)
                container.addSubview(bubble)
                NSLayoutConstraint.activate([
                    title.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
                    title.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
                    title.trailingAnchor.constraint(lessThanOrEqualTo: bubble.trailingAnchor),
                    bubble.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
                    bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 110),
                    bubble.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.72),
                ])
                break
            }
            let userText = userTextLabel(m.text)
            let bubble = box(userText, bg: NSColor.secondaryLabelColor.withAlphaComponent(0.12), topInset: 9, bottomInset: 9, horizontalInset: 12, radius: 10)
            container.addSubview(bubble)
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: container.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 110),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.72),
            ])
        case .tool:
            if m.toolName == "steer" {
                let detail = m.toolDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let label = m.toolDetail == "pending" ? "Steering conversation…" : "Steered conversation"
                let noticeText = detail.isEmpty || detail == "Steered conversation" ? label : "\(label)\n\(detail)"
                let notice = NSTextField(wrappingLabelWithString: noticeText)
                notice.font = .systemFont(ofSize: 13, weight: .regular)
                notice.textColor = .secondaryLabelColor
                notice.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(notice)
                NSLayoutConstraint.activate([
                    notice.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
                    notice.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
                    notice.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                    notice.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                ])
                break
            }
            if m.toolName == "shell" {
                let summary = shellSummary(m)
                let row = ShellToolView(title: shellToolTitle(m, summary: summary), output: summary.output, done: m.toolDone)
                container.addSubview(row)
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(equalTo: container.topAnchor),
                    row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                ])
                break
            }
            content.isSelectable = false
            content.setRich(toolString(m))
            let row = toolInlineRow(content, for: m)
            toolByView[ObjectIdentifier(row)] = m
            row.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toolClicked(_:))))
            container.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: container.topAnchor),
                row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        labels[ObjectIdentifier(m)] = content
        transcript.addArrangedSubview(container)
        if m.role == .tool {
            transcript.setCustomSpacing(6, after: container)
        }
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
        // Keep the "Thinking" shimmer pinned to the bottom while streaming.
        if !bulkLoading { pinShimmerToBottom() }
        // Smooth fade-in for live (streamed) rows.
        if !bulkLoading {
            container.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.22; container.animator().alphaValue = 1 }
        }
        return container
    }

    private func userTextLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 15)
        label.textColor = .labelColor
        label.isSelectable = true
        label.lineBreakMode = .byWordWrapping
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func addLargeThreadNotice(hiddenCount: Int) {
        let label = NSTextField(labelWithString: "Showing latest \(maxRenderedMessages) messages. \(hiddenCount) older messages skipped for performance.")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        transcript.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: transcript.widthAnchor).isActive = true
    }

    private func renderLiveAssistant(_ assistant: ChatMessage, force: Bool = false) {
        let key = ObjectIdentifier(assistant)
        guard let label = labels[key] else { return }
        let now = Date().timeIntervalSince1970
        if !force, let last = lastLiveMarkdownRender[key], now - last < 0.45 { return }
        lastLiveMarkdownRender[key] = now
        label.setRich(Self.markdown(assistant.text))
    }

    private func pinShimmerToBottom() {
        guard let s = shimmerView, let sc = s.superview else { return }
        transcript.removeArrangedSubview(sc)
        transcript.addArrangedSubview(sc)
    }

    private struct EditSummary {
        var status: String
        var changes: [EditToolChange]
        var added: Int { changes.reduce(0) { $0 + $1.added } }
        var deleted: Int { changes.reduce(0) { $0 + $1.deleted } }
    }

    private struct ShellSummary {
        var command: String
        var exitCode: String?
        var output: String
    }

    private struct ShellTitleParts {
        var action: String
        var detail: String?
        var monospacedDetail = false
        var category = "command"
    }

    private func shellSummary(_ m: ChatMessage) -> ShellSummary {
        let detail = m.toolDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !detail.isEmpty else { return ShellSummary(command: "command", exitCode: nil, output: "") }
        let lines = detail.components(separatedBy: .newlines)
        if let commandIndex = lines.lastIndex(where: { $0.hasPrefix("$ ") }) {
            let command = String(lines[commandIndex].dropFirst(2))
            var exitCode: String?
            var outputStart = commandIndex + 1
            if lines.indices.contains(outputStart), lines[outputStart].hasPrefix("exit ") {
                exitCode = String(lines[outputStart].dropFirst(5))
                outputStart += 1
            }
            while lines.indices.contains(outputStart), lines[outputStart].isEmpty { outputStart += 1 }
            let output = outputStart < lines.count ? lines[outputStart...].joined(separator: "\n") : ""
            return ShellSummary(command: command, exitCode: exitCode, output: output)
        }
        let command = lines.first ?? detail
        let output = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellSummary(command: command, exitCode: nil, output: output)
    }

    private func shellToolTitle(_ m: ChatMessage, summary: ShellSummary) -> NSAttributedString {
        let command = summary.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = shellTitleParts(command: command, done: m.toolDone)
        let title = NSMutableAttributedString(string: parts.action, attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        if let detail = parts.detail, !detail.isEmpty {
            title.append(NSAttributedString(string: "  \(detail)", attributes: [
                .font: parts.monospacedDetail ? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular) : NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return title
    }

    private func shellTitleParts(command: String, done: Bool) -> ShellTitleParts {
        guard !command.isEmpty else {
            return ShellTitleParts(action: done ? "Ran command" : "Running command")
        }
        let normalized = innerShellCommand(command) ?? command
        let words = shellWords(normalized)
        guard let executable = words.first?.split(separator: "/").last.map(String.init) else {
            return ShellTitleParts(action: done ? "Ran command" : "Running command")
        }
        let args = Array(words.dropFirst())
        switch executable {
        case "ls", "tree":
            return ShellTitleParts(action: done ? "Listed files" : "Listing files", detail: shellPathDetail(args).map { "in \($0)" }, category: "list")
        case "find", "fd":
            return ShellTitleParts(action: done ? "Searched files" : "Searching files", detail: shellPathDetail(args).map { "in \($0)" }, category: "search")
        case "rg", "grep", "ag":
            return ShellTitleParts(action: done ? "Searched for" : "Searching for", detail: shellSearchQuery(args), category: "search")
        case "cat", "sed", "head", "tail", "nl":
            return ShellTitleParts(action: done ? "Read" : "Reading", detail: shellPathDetail(args), category: "read")
        case "pwd":
            return ShellTitleParts(action: done ? "Checked working directory" : "Checking working directory")
        case "git":
            if args.first == "status" {
                return ShellTitleParts(action: done ? "Checked git status" : "Checking git status", category: "git")
            }
            if args.first == "diff" || args.first == "show" {
                return ShellTitleParts(action: done ? "Read diff" : "Reading diff", category: "diff")
            }
            if args.first == "grep" {
                return ShellTitleParts(action: done ? "Searched for" : "Searching for", detail: shellSearchQuery(Array(args.dropFirst())), category: "search")
            }
            return ShellTitleParts(action: done ? "Ran git" : "Running git", detail: args.first, category: "git")
        default:
            return ShellTitleParts(action: done ? "Ran command" : "Running command", detail: normalized, monospacedDetail: true)
        }
    }

    private func innerShellCommand(_ command: String) -> String? {
        let words = shellWords(command)
        guard let executable = words.first?.split(separator: "/").last.map(String.init),
              ["zsh", "bash", "sh", "fish"].contains(executable) else { return nil }
        for i in words.indices {
            let arg = words[i]
            guard arg == "-c" || arg == "-lc" || arg == "-lic" else { continue }
            let next = words.index(after: i)
            if words.indices.contains(next) { return words[next] }
        }
        return nil
    }

    private func shellWords(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for ch in command {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if let q = quote {
                if ch == q { quote = nil }
                else { current.append(ch) }
                continue
            }
            if ch == "'" || ch == "\"" {
                quote = ch
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private func shellSearchQuery(_ args: [String]) -> String? {
        for arg in args where !arg.hasPrefix("-") && arg != "." {
            return arg
        }
        return nil
    }

    private func shellPathDetail(_ args: [String]) -> String? {
        let ignoredOptionsWithValues: Set<String> = ["-n", "-m", "-C", "-A", "-B", "--max-count", "--context", "--after-context", "--before-context"]
        var skipNext = false
        var candidates: [String] = []
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if ignoredOptionsWithValues.contains(arg) {
                skipNext = true
                continue
            }
            if arg.hasPrefix("-") { continue }
            candidates.append(arg)
        }
        return candidates.last
    }

    private func editSummary(_ m: ChatMessage) -> EditSummary {
        guard let detail = m.toolDetail, !detail.isEmpty else { return EditSummary(status: m.toolDone ? "completed" : "running", changes: []) }
        if let json = editSummaryJSON(from: detail) {
            var changes = (json["changes"] as? [[String: Any]] ?? []).compactMap { item -> EditToolChange? in
                guard let path = item["path"] as? String else { return nil }
                return EditToolChange(
                    path: path,
                    added: item["added"] as? Int ?? 0,
                    deleted: item["deleted"] as? Int ?? 0,
                    diff: item["diff"] as? String ?? ""
                )
            }
            if changes.isEmpty, let path = json["path"] as? String {
                changes.append(EditToolChange(
                    path: path,
                    added: json["added"] as? Int ?? json["additions"] as? Int ?? 0,
                    deleted: json["deleted"] as? Int ?? json["deletions"] as? Int ?? 0,
                    diff: json["diff"] as? String ?? ""
                ))
            }
            return EditSummary(status: json["status"] as? String ?? "completed", changes: changes)
        }
        return EditSummary(status: m.toolDone ? "completed" : "running", changes: editPaths(m).map {
            EditToolChange(path: $0, added: 0, deleted: 0, diff: "")
        })
    }

    private func editSummaryJSON(from detail: String) -> [String: Any]? {
        let chunks = detail.components(separatedBy: "\n\n")
        for chunk in chunks.reversed() {
            guard let start = chunk.firstIndex(of: "{") else { continue }
            let candidate = String(chunk[start...])
            guard let data = candidate.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return json
        }
        if let data = detail.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return nil
    }

    private func toolString(_ m: ChatMessage) -> NSAttributedString {
        if m.toolName == "edit" { return editToolString(m) }
        let out = NSMutableAttributedString(
            string: toolTitle(m),
            attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor])
        let preview = toolPreview(m)
        if !preview.isEmpty {
            out.append(NSAttributedString(string: "\n\(preview)",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return out
    }

    private func editToolString(_ m: ChatMessage) -> NSAttributedString {
        let summary = editSummary(m)
        let out = NSMutableAttributedString(string: editTitle(m), attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        if let file = summary.changes.first?.path {
            out.append(NSAttributedString(string: "  \(fileName(file))", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(calibratedRed: 0.36, green: 0.58, blue: 0.86, alpha: 1),
            ]))
        }
        return out
    }

    private func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func toolTitle(_ m: ChatMessage) -> String {
        switch m.toolName {
        case "shell": return m.toolDone ? "Ran command" : "Running command"
        case "edit": return editTitle(m)
        case "web_search": return m.toolDone ? "Searched web" : "Searching web"
        default:
            let name = (m.toolName ?? "tool").replacingOccurrences(of: "_", with: " ")
            return (m.toolDone ? "Completed " : "Running ") + name
        }
    }

    private func toolIcon(_ name: String?) -> String {
        switch name {
        case "shell": return "terminal"
        case "edit": return "pencil"
        case "web_search": return "magnifyingglass"
        default: return "hammer"
        }
    }

    private func editTitle(_ m: ChatMessage) -> String {
        let count = editSummary(m).changes.count
        if count > 0 { return m.toolDone ? "Edited \(count) file\(count == 1 ? "" : "s")" : "Editing \(count) file\(count == 1 ? "" : "s")" }
        return m.toolDone ? "Edited files" : "Editing files"
    }

    private func editPaths(_ m: ChatMessage) -> [String] {
        guard let detail = m.toolDetail, !detail.isEmpty else { return [] }
        if let json = editSummaryJSON(from: detail) {
            return (json["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
        }
        let afterStatus = detail.split(separator: ":", maxSplits: 1).last.map(String.init) ?? detail
        let ignored = Set(["completed", "complete", "running", "done", "success", "failed"])
        return afterStatus.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                guard !value.isEmpty else { return false }
                if ignored.contains(value.lowercased()) { return false }
                return value.contains("/") || value.contains(".")
            }
    }

    private func toolPreview(_ m: ChatMessage) -> String {
        guard let detail = m.toolDetail, !detail.isEmpty else {
            return m.toolDone ? "Finished" : "In progress"
        }
        if m.toolName == "shell" {
            let lines = detail.components(separatedBy: .newlines)
            let command = lines.first?.replacingOccurrences(of: "$ ", with: "") ?? detail
            let exit = lines.dropFirst().first(where: { $0.hasPrefix("exit ") })
            let output = lines.dropFirst().dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(2).joined(separator: "\n")
            return ([command, exit, output].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }).joined(separator: "\n")
        }
        if m.toolName == "edit" {
            let paths = editSummary(m).changes.map(\.path)
            if !paths.isEmpty {
                let names = paths.prefix(3).map { fileName($0) }
                return names.joined(separator: ", ")
            }
        }
        let clean = detail.replacingOccurrences(of: "\n\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > 260 ? String(clean.prefix(260)) + "..." : clean
    }

    private func toolInlineRow(_ label: MessageTextView, for m: ChatMessage) -> NSView {
        let isEdit = m.toolName == "edit"
        let icon = NSImageView(image: NSImage(systemSymbolName: toolIcon(m.toolName), accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let status = NSTextField(labelWithString: m.toolDone ? "" : "Running")
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = m.toolDone ? .tertiaryLabelColor : .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) ?? NSImage())
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [label])
        textStack.orientation = .vertical
        textStack.alignment = .width
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        if isEdit && !m.toolDone {
            label.isHidden = true
            textStack.addArrangedSubview(ShimmerLabel(text: "Editing"))
        }
        let summary = isEdit ? editSummary(m) : nil
        let editStats = isEdit ? EditStatsView(added: summary?.added ?? 0, deleted: summary?.deleted ?? 0) : nil
        if let editStats {
            editStats.isHidden = (summary?.added ?? 0) == 0 && (summary?.deleted ?? 0) == 0
            editStatsByMessage[ObjectIdentifier(m)] = editStats
        }

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)
        row.addSubview(textStack)
        if let editStats { row.addSubview(editStats) }
        if !isEdit { row.addSubview(chevron) }
        if !m.toolDone && !isEdit { row.addSubview(status) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
            icon.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 820),
        ])
        if !isEdit {
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        }
        if isEdit {
            if let editStats {
                NSLayoutConstraint.activate([
                    editStats.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 12),
                    editStats.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
                    editStats.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -4),
                ])
            } else {
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -4).isActive = true
            }
        } else if m.toolDone {
            NSLayoutConstraint.activate([
                chevron.widthAnchor.constraint(equalToConstant: 10),
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
                chevron.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            ])
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12).isActive = true
        } else {
            NSLayoutConstraint.activate([
                chevron.widthAnchor.constraint(equalToConstant: 10),
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
                chevron.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
                status.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
                status.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -12),
            ])
        }
        return row
    }

    /// Show a popover with the full tool name + detail when a tool pill is clicked.
    @objc private func toolClicked(_ g: NSClickGestureRecognizer) {
        guard let view = g.view, let m = toolByView[ObjectIdentifier(view)] else { return }
        if m.toolName == "edit" {
            return
        }
        let text = NSTextView()
        text.isEditable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.string = "\(m.toolName ?? "tool")\(m.toolDone ? "  ✓" : "")\n\n\(m.toolDetail ?? "(no details)")"
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        scroll.hasVerticalScroller = true
        scroll.documentView = text
        text.frame = scroll.bounds
        text.autoresizingMask = [.width]
        let vc = NSViewController()
        vc.view = scroll
        toolPopover.contentViewController = vc
        toolPopover.contentSize = NSSize(width: 440, height: 220)
        toolPopover.behavior = .transient
        // Anchor a small rect at the click point so the popover appears next to the tool label.
        let p = g.location(in: view)
        toolPopover.show(relativeTo: NSRect(x: p.x - 4, y: view.bounds.minY, width: 8, height: view.bounds.height), of: view, preferredEdge: .maxY)
    }

    private func showEditPopover(changes: [EditToolChange], anchor: NSView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for change in changes {
            stack.addArrangedSubview(DiffFileBlock(path: change.path, diff: change.diff, added: change.added, deleted: change.deleted, initiallyCollapsed: false))
        }
        if changes.isEmpty {
            let empty = NSTextField(labelWithString: "No diff details available.")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        }
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        let vc = NSViewController()
        vc.view = scroll
        toolPopover.close()
        toolPopover.contentViewController = vc
        toolPopover.contentSize = NSSize(width: 760, height: 520)
        toolPopover.behavior = .transient
        toolPopover.show(relativeTo: anchor.bounds.isEmpty ? NSRect(x: 0, y: 0, width: 1, height: 1) : anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// A rounded, padded background box hugging its content.
    private func box(_ content: NSView, bg: NSColor, inset: CGFloat, radius: CGFloat) -> NSView {
        box(content, bg: bg, topInset: inset, bottomInset: inset, horizontalInset: inset + 2, radius: radius)
    }

    private func box(_ content: NSView, bg: NSColor, topInset: CGFloat, bottomInset: CGFloat, horizontalInset: CGFloat, radius: CGFloat) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = bg.cgColor
        v.layer?.cornerRadius = radius
        v.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: v.topAnchor, constant: topInset),
            content.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -bottomInset),
            content.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -horizontalInset),
        ])
        return v
    }

    private func scrollToBottom() {
        let now = Date().timeIntervalSince1970
        if streaming && now - lastScrollToBottomAt < 0.25 {
            guard !pendingScrollToBottom else { return }
            pendingScrollToBottom = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                self.pendingScrollToBottom = false
                self.scrollToBottom()
            }
            return
        }
        lastScrollToBottomAt = now
        if !streaming {
            view.layoutSubtreeIfNeeded()
        }
        guard let doc = scroll.documentView else { return }
        let y = max(0, doc.bounds.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
