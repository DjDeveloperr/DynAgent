import AppKit

enum SidebarChrome {
    static func makeNativeRoot(containing scroll: NSScrollView) -> NSVisualEffectView {
        let root = NSVisualEffectView()
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }
}

/// A fully custom sidebar row with explicit clear/hover/selected states and right-click menu.
/// Avoids NSOutlineView's selection styling quirks.
final class SidebarRow: NSView {
    private let onClick: () -> Void
    private let menuProvider: (() -> NSMenu)?
    private let onHoverChanged: ((Bool) -> Void)?
    private let showsHoverBackground: Bool
    var onHoverStart: ((SidebarRow) -> Void)?
    var selected = false { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }

    init(height: CGFloat, onClick: @escaping () -> Void, menu: (() -> NSMenu)? = nil, showsHoverBackground: Bool = true, onHoverChanged: ((Bool) -> Void)? = nil, build: (NSView) -> Void) {
        self.onClick = onClick
        self.menuProvider = menu
        self.onHoverChanged = onHoverChanged
        self.showsHoverBackground = showsHoverBackground
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        build(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverStart?(self)
        hovering = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { clearHover() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func clearHover() {
        if hovering { hovering = false }
    }

    private func refresh() {
        let color: NSColor = selected ? .secondaryLabelColor.withAlphaComponent(0.12)
            : (hovering && showsHoverBackground) ? .secondaryLabelColor.withAlphaComponent(0.06) : .clear
        layer?.backgroundColor = color.cgColor
        onHoverChanged?(hovering)
    }
}

final class SidebarScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?()
    }
}

/// A smooth non-stepped indeterminate spinner: a rotating accent arc.
final class Spinner: NSView {
    private let ring = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        ring.strokeColor = NSColor.secondaryLabelColor.cgColor
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.lineCap = .round
        layer?.addSublayer(ring)
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -2 * Double.pi
        animation.duration = 0.9
        animation.repeatCount = .infinity
        ring.add(animation, forKey: "spin")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 2, dy: 2)
        ring.frame = bounds
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
            radius: rect.width / 2,
            startAngle: 90,
            endAngle: -150,
            clockwise: true
        )
        ring.path = path.cgPath
    }
}

final class SidebarHoverTipWindow: NSPanel {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 52),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.transient, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.borderWidth = 0
        effect.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        for label in [titleLabel, detailLabel] { label.translatesAutoresizingMaskIntoConstraints = false }

        effect.addSubview(titleLabel)
        effect.addSubview(detailLabel)
        contentView = effect
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 7),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func show(title: String, detail: String, near row: NSView) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        guard let window = row.window else { return }
        let rectInWindow = row.convert(row.bounds, to: nil)
        let rect = window.convertToScreen(rectInWindow)
        let detailWidth = (detail as NSString).size(withAttributes: [.font: detailLabel.font!]).width
        let width = min(max(detailWidth + 24, 220), 360)
        setFrame(NSRect(x: rect.minX + 8, y: rect.maxY + 4, width: width, height: 52), display: false)
        orderFront(nil)
    }
}
