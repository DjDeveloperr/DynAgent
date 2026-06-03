import AppKit

/// Frame-managed container for split/detail roots. It must not let loaded content
/// advertise a preferred width back up to NSSplitView.
class FlexibleContainerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        .zero
    }
}

/// View whose origin is top-left so transcript/sidebar/search content grows downward.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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

/// Animated thinking/working label with shimmer effect.
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

    required init?(coder: NSCoder) { fatalError() }

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
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [0, 0.0, 0.1, 0.2, 0.3]
        animation.toValue = [0.7, 0.8, 0.9, 1.0, 1.0]
        animation.duration = 1.5
        animation.repeatCount = .infinity
        gradient.add(animation, forKey: "shimmer")
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

    deinit {
        timer?.invalidate()
    }

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
        label.stringValue = WorkDividerModel.label(seconds: duration, active: active, collapsed: collapsed)
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

    deinit {
        timer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
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
                timer.invalidate()
            }
        }
    }

    private func configure(_ label: NSTextField, color: NSColor) {
        label.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = color
    }
}

enum TranscriptRowChrome {
    static func installAssistantContent(_ content: NSView, in container: NSView) {
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    static func installUserBubble(text: String, in container: NSView) {
        let bubble = roundedBox(
            userTextLabel(text),
            bg: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
            topInset: 9,
            bottomInset: 9,
            horizontalInset: 12,
            radius: 10
        )
        container.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: container.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 110),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.72),
        ])
    }

    static func installSteerBubble(text: String, pending: Bool, in container: NSView) {
        let title = NSTextField(labelWithString: pending ? "Steering conversation…" : "Steered conversation")
        title.font = .systemFont(ofSize: 13, weight: .regular)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let bubble = roundedBox(
            userTextLabel(text),
            bg: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
            topInset: 9,
            bottomInset: 9,
            horizontalInset: 12,
            radius: 10
        )
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
    }

    static func installSteerNotice(detail: String, pending: Bool, in container: NSView) {
        let label = pending ? "Steering conversation…" : "Steered conversation"
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
    }

    static func largeThreadNotice(maxRenderedMessages: Int, hiddenCount: Int) -> NSView {
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
        return container
    }

    static func finalFooter(text _: String, timestamp: Double?, target: AnyObject, copyAction: Selector) -> (view: NSView, copyButton: NSButton) {
        let copy = NSButton(
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy") ?? NSImage(),
            target: target,
            action: copyAction
        )
        copy.isBordered = false
        copy.contentTintColor = .tertiaryLabelColor
        copy.toolTip = "Copy"

        let ts = NSTextField(labelWithString: timestamp.map(formatTime) ?? "")
        ts.font = .systemFont(ofSize: 11)
        ts.textColor = .tertiaryLabelColor

        let row = NSStackView(views: [copy, ts] as [NSView])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return (container, copy)
    }

    static func roundedBox(_ content: NSView, bg: NSColor, inset: CGFloat, radius: CGFloat) -> NSView {
        roundedBox(content, bg: bg, topInset: inset, bottomInset: inset, horizontalInset: inset + 2, radius: radius)
    }

    static func roundedBox(_ content: NSView, bg: NSColor, topInset: CGFloat, bottomInset: CGFloat, horizontalInset: CGFloat, radius: CGFloat) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = bg.cgColor
        view.layer?.cornerRadius = radius
        view.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottomInset),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalInset),
        ])
        return view
    }

    static func userTextLabel(_ text: String) -> NSTextField {
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

    static func formatTime(_ epoch: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}
