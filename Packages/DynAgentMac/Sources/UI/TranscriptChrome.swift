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
