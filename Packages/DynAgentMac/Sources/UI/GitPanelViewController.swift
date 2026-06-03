import AppKit

final class GitActionPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

final class GitDiffHeaderView: NSView {
    private var info: GitDiffHeaderInfo?
    private let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    private let statFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    func setInfo(_ info: GitDiffHeaderInfo?) {
        self.info = info
        isHidden = info == nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let info else { return }
        GitDiffDocumentView.drawFileHeader(info, in: bounds, visibleX: 0, visibleWidth: bounds.width, titleFont: titleFont, statFont: statFont)
    }

    override func mouseDown(with event: NSEvent) {
        if info != nil { onClick?() }
        else { super.mouseDown(with: event) }
    }
}

final class GitDiffGutterOverlayView: NSView {
    weak var document: GitDiffDocumentView?
    var visibleY: CGFloat = 0

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        document?.drawPinnedGutter(in: bounds, visibleY: visibleY)
    }
}

final class GitDiffHeaderOverlayView: NSView {
    weak var document: GitDiffDocumentView?
    var visibleY: CGFloat = 0

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        document?.drawVisibleFileHeaders(in: bounds, visibleY: visibleY)
    }
}

final class GitDiffTextView: NSTextView {
    weak var diffDocument: GitDiffDocumentView?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if diffDocument?.toggleHeaderIfNeeded(at: point.y) == true { return }
        super.mouseDown(with: event)
    }
}

final class GitDiffDocumentView: NSView {
    private typealias Line = GitDiffLine
    private typealias Section = GitDiffSection

    private let rowHeight: CGFloat = 22
    private let headerHeight: CGFloat = 34
    fileprivate let gutterWidth: CGFloat = 66
    private var rawLines: [Line] = []
    private var lines: [Line] = []
    private var rowTops: [CGFloat] = []
    private var sections: [Section] = []
    private var layoutModel = GitDiffLayoutModel()
    private var collapsedPaths = Set<String>()
    private var preferredDocWidth: CGFloat = 1200
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    fileprivate let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
    private let headerFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    private let statFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private let textView = GitDiffTextView()
    private let gutterOverlay = GitDiffGutterOverlayView()
    private let headerOverlay = GitDiffHeaderOverlayView()
    var onCollapseChanged: (() -> Void)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = false
        translatesAutoresizingMaskIntoConstraints = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.insertionPointColor = .labelColor
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.diffDocument = self
        addSubview(textView)
        gutterOverlay.document = self
        addSubview(gutterOverlay, positioned: .above, relativeTo: textView)
        headerOverlay.document = self
        addSubview(headerOverlay, positioned: .above, relativeTo: gutterOverlay)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        textView.frame = bounds
        updateVisibleOverlays()
    }

    func setDiff(_ diff: String) {
        applyModel(GitDiffModel.parse(diff))
        rebuildDisplayRows()
        needsDisplay = true
    }

    func headerInfo(at y: CGFloat) -> GitDiffHeaderInfo? {
        layoutModel.headerInfo(at: Double(y))
    }

    func updateVisibleOverlays() {
        let visible = visibleRect
        gutterOverlay.frame = NSRect(x: visible.minX, y: visible.minY, width: gutterWidth, height: visible.height)
        gutterOverlay.visibleY = visible.minY
        gutterOverlay.needsDisplay = true
        headerOverlay.frame = NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
        headerOverlay.visibleY = visible.minY
        headerOverlay.needsDisplay = true
    }

    func toggleHeader(at y: CGFloat) {
        guard let info = headerInfo(at: y) else { return }
        toggle(path: info.path)
    }

    @discardableResult
    func toggleHeaderIfNeeded(at y: CGFloat) -> Bool {
        guard let idx = rowIndex(at: y), lines.indices.contains(idx), lines[idx].kind == "F" else { return false }
        let section = lines[idx].section
        guard sections.indices.contains(section) else { return false }
        toggle(path: sections[section].path)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateVisibleOverlays()
        NSColor.windowBackgroundColor.withAlphaComponent(0.38).setFill()
        dirtyRect.fill()
        guard !lines.isEmpty else {
            drawEmpty()
            return
        }
        let visible = visibleRect
        let first = max(0, (rowIndex(at: visible.minY) ?? 0) - 4)
        let last = min(lines.count - 1, (rowIndex(at: visible.maxY) ?? lines.count - 1) + 4)
        guard first <= last else { return }
        for idx in first...last {
            drawLine(lines[idx], index: idx, visibleX: visible.minX, visibleWidth: visible.width)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if toggleHeaderIfNeeded(at: p.y) { return }
        super.mouseDown(with: event)
    }

    private func toggle(path: String) {
        layoutModel.toggle(path: path)
        collapsedPaths = layoutModel.collapsedPaths
        rebuildDisplayRows()
        onCollapseChanged?()
    }

    private func drawEmpty() {
        let attrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: NSColor.tertiaryLabelColor]
        ("No changes." as NSString).draw(at: NSPoint(x: 14, y: 14), withAttributes: attrs)
    }

    private func drawLine(_ line: Line, index: Int, visibleX: CGFloat, visibleWidth: CGFloat) {
        let y = rowTops.indices.contains(index) ? rowTops[index] : 0
        let height = rowHeight(for: line)
        let rect = NSRect(x: visibleX, y: y, width: visibleWidth, height: height)
        switch line.kind {
        case "F":
            guard sections.indices.contains(line.section) else { return }
            let s = sections[line.section]
            let info = GitDiffHeaderInfo(path: s.path, added: s.added, deleted: s.deleted, collapsed: collapsedPaths.contains(s.path))
            Self.drawFileHeader(info, in: rect, visibleX: visibleX, visibleWidth: visibleWidth, titleFont: headerFont, statFont: statFont, drawText: false)
            return
        case "+":
            NSColor.systemGreen.withAlphaComponent(0.20).setFill()
            rect.fill()
        case "-":
            NSColor.systemRed.withAlphaComponent(0.22).setFill()
            rect.fill()
        case "M", "S":
            NSColor.secondaryLabelColor.withAlphaComponent(0.10).setFill()
            rect.fill()
        default:
            NSColor.clear.setFill()
            rect.fill()
            break
        }

        drawGutter(at: y, height: height, visibleX: visibleX, kind: line.kind)
        if line.kind == "+" {
            NSColor.systemGreen.setFill()
            NSRect(x: visibleX, y: y, width: 4, height: height).fill()
        } else if line.kind == "-" {
            NSColor.systemRed.setFill()
            NSRect(x: visibleX, y: y, width: 4, height: height).fill()
        }
        if line.kind != "F", line.kind != "M", line.kind != "S" {
            drawNumber(line.new ?? line.old, x: visibleX + 14, y: y + 4)
        }
    }

    private func drawGutter(at y: CGFloat, height: CGFloat, visibleX: CGFloat, kind: Character) {
        switch kind {
        case "+": NSColor.systemGreen.withAlphaComponent(0.20).setFill()
        case "-": NSColor.systemRed.withAlphaComponent(0.22).setFill()
        default: NSColor.windowBackgroundColor.setFill()
        }
        NSRect(x: visibleX, y: y, width: gutterWidth, height: height).fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSRect(x: visibleX + gutterWidth - 1, y: y, width: 1, height: height).fill()
    }

    fileprivate func drawNumber(_ value: Int?, x: CGFloat, y: CGFloat) {
        let text = value.map(String.init) ?? ""
        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: x + 32 - size.width, y: y), withAttributes: attrs)
    }

    fileprivate func drawPinnedGutter(in rect: NSRect, visibleY: CGFloat) {
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        guard !lines.isEmpty else { return }
        let first = max(0, (rowIndex(at: visibleY) ?? 0) - 4)
        let last = min(lines.count - 1, (rowIndex(at: visibleY + rect.height) ?? lines.count - 1) + 4)
        guard first <= last else { return }
        for idx in first...last {
            let line = lines[idx]
            let rowY = (rowTops.indices.contains(idx) ? rowTops[idx] : 0) - visibleY
            let height = rowHeight(for: line)
            switch line.kind {
            case "+":
                NSColor.systemGreen.withAlphaComponent(0.20).setFill()
                NSRect(x: 0, y: rowY, width: rect.width, height: height).fill()
                NSColor.systemGreen.setFill()
                NSRect(x: 0, y: rowY, width: 4, height: height).fill()
            case "-":
                NSColor.systemRed.withAlphaComponent(0.22).setFill()
                NSRect(x: 0, y: rowY, width: rect.width, height: height).fill()
                NSColor.systemRed.setFill()
                NSRect(x: 0, y: rowY, width: 4, height: height).fill()
            case "M", "S":
                NSColor.secondaryLabelColor.withAlphaComponent(0.10).setFill()
                NSRect(x: 0, y: rowY, width: rect.width, height: height).fill()
            case "F":
                if sections.indices.contains(line.section) {
                    let s = sections[line.section]
                    let chevron = collapsedPaths.contains(s.path) ? "▸" : "▾"
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                    let size = (chevron as NSString).size(withAttributes: attrs)
                    (chevron as NSString).draw(at: NSPoint(x: 13, y: rowY + height / 2 - size.height / 2), withAttributes: attrs)
                }
            default:
                break
            }
            if line.kind != "F", line.kind != "M", line.kind != "S" {
                drawNumber(line.new ?? line.old, x: 14, y: rowY + 4)
            }
        }
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
    }

    fileprivate func drawVisibleFileHeaders(in rect: NSRect, visibleY: CGFloat) {
        guard !lines.isEmpty else { return }
        let first = max(0, (rowIndex(at: visibleY) ?? 0) - 4)
        let last = min(lines.count - 1, (rowIndex(at: visibleY + rect.height) ?? lines.count - 1) + 4)
        guard first <= last else { return }
        for idx in first...last {
            let line = lines[idx]
            guard line.kind == "F", sections.indices.contains(line.section) else { continue }
            let s = sections[line.section]
            let rowY = (rowTops.indices.contains(idx) ? rowTops[idx] : 0) - visibleY
            let info = GitDiffHeaderInfo(path: s.path, added: s.added, deleted: s.deleted, collapsed: collapsedPaths.contains(s.path))
            Self.drawFileHeader(info, in: NSRect(x: 0, y: rowY, width: rect.width, height: rowHeight(for: line)), visibleX: 0, visibleWidth: rect.width, titleFont: headerFont, statFont: statFont)
        }
    }

    private func highlighted(_ text: String, kind: Character) -> NSAttributedString {
        let baseColor: NSColor = {
            switch kind {
            case "F": return .labelColor
            case "M", "S": return .secondaryLabelColor
            default: return .labelColor
            }
        }()
        let out = NSMutableAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: kind == "F" ? headerFont : codeFont,
            .foregroundColor: baseColor,
        ])
        if kind == "M" || kind == "S" { return out }
        if let re = try? NSRegularExpression(pattern: #"\b(let|var|func|final|class|struct|enum|if|else|for|while|guard|return|private|public|import|const|async|await|switch|case)\b"#) {
            let ns = out.string as NSString
            for m in re.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
                out.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: m.range)
            }
        }
        if let re = try? NSRegularExpression(pattern: #""[^"\n]*"|'[^'\n]*'"#) {
            let ns = out.string as NSString
            for m in re.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
                out.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: m.range)
            }
        }
        return out
    }

    private func applyModel(_ model: GitDiffModel) {
        rawLines = model.lines
        lines.removeAll(keepingCapacity: true)
        rowTops.removeAll(keepingCapacity: true)
        sections = model.sections
        preferredDocWidth = 1200
        for line in rawLines {
            preferredDocWidth = max(preferredDocWidth, gutterWidth + (line.text as NSString).size(withAttributes: [.font: codeFont]).width + 80)
        }
    }

    private func rebuildDisplayRows() {
        layoutModel = GitDiffLayoutModel(diff: GitDiffModel(lines: rawLines, sections: sections), collapsedPaths: collapsedPaths)
        lines = layoutModel.lines
        rowTops = layoutModel.rowTops.map { CGFloat($0) }
        setFrameSize(NSSize(width: preferredDocWidth, height: CGFloat(layoutModel.documentHeight)))
        rebuildSelectableText()
        textView.frame = bounds
        updateVisibleOverlays()
        needsDisplay = true
    }

    private func rebuildSelectableText() {
        let text = NSMutableAttributedString()
        for line in lines {
            let lineHeight = rowHeight(for: line)
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
            style.lineBreakMode = .byClipping
            let before = text.length
            switch line.kind {
            case "F":
                style.firstLineHeadIndent = 0
                style.headIndent = 0
                text.append(NSAttributedString(string: " ", attributes: [
                    .font: headerFont,
                    .foregroundColor: NSColor.clear,
                ]))
            case "M", "S":
                style.firstLineHeadIndent = gutterWidth + 14
                style.headIndent = gutterWidth + 14
                text.append(NSAttributedString(string: line.text, attributes: [
                    .font: codeFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            default:
                style.firstLineHeadIndent = gutterWidth + 14
                style.headIndent = gutterWidth + 14
                text.append(highlighted(line.text, kind: line.kind))
            }
            text.append(NSAttributedString(string: "\n", attributes: [.font: codeFont]))
            text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: before, length: text.length - before))
        }
        textView.textStorage?.setAttributedString(text)
    }

    private func rowHeight(for line: Line) -> CGFloat {
        line.kind == "F" ? headerHeight : rowHeight
    }

    private func rowIndex(at y: CGFloat) -> Int? {
        layoutModel.rowIndex(at: Double(y))
    }

    static func drawFileHeader(_ info: GitDiffHeaderInfo, in rect: NSRect, visibleX: CGFloat, visibleWidth: CGFloat, titleFont: NSFont, statFont: NSFont, drawText: Bool = true) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        rect.fill()

        let chevron = info.collapsed ? "▸" : "▾"
        let chevronAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let chevronSize = (chevron as NSString).size(withAttributes: chevronAttrs)
        (chevron as NSString).draw(at: NSPoint(x: visibleX + 13, y: rect.midY - chevronSize.height / 2), withAttributes: chevronAttrs)
        guard drawText else { return }

        let title = (info.path as NSString).lastPathComponent
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let statY = rect.midY - ("0" as NSString).size(withAttributes: [.font: statFont]).height / 2
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let titleX = visibleX + 30
        (title as NSString).draw(at: NSPoint(x: titleX, y: rect.midY - titleSize.height / 2), withAttributes: titleAttrs)
        var x = titleX + titleSize.width + 8
        let add = "+\(info.added)" as NSString
        let addAttrs: [NSAttributedString.Key: Any] = [
            .font: statFont,
            .foregroundColor: NSColor.systemGreen,
        ]
        add.draw(at: NSPoint(x: x, y: statY), withAttributes: addAttrs)
        x += add.size(withAttributes: addAttrs).width + 10
        ("-\(info.deleted)" as NSString).draw(at: NSPoint(x: x, y: statY), withAttributes: [
            .font: statFont,
            .foregroundColor: NSColor.systemRed,
        ])
    }
}

/// Right pane: git branch, changed files, diff, commit/push/PR actions.
final class GitPanelViewController: NSViewController {
    var client: AgentClient!
    private(set) var workspace = ""

    private let branchLabel = NSTextField(labelWithString: "—")
    private let scopeControl = NSSegmentedControl(labels: ["All", "Staged"], trackingMode: .selectOne, target: nil, action: nil)
    private let diffScroll = NSScrollView()
    private let diffDocument = GitDiffDocumentView()
    private let diffHeader = GitDiffHeaderView()
    private let commitField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let prBox = NSBox()
    private let prLabel = NSTextField(wrappingLabelWithString: "")
    private var worktreeRow = NSStackView()
    private weak var gitActionSheet: NSWindow?
    private var gitActionOutsideMonitor: Any?
    private var showingStaged = false
    var isWorktree = false { didSet { worktreeRow.isHidden = !isWorktree } }
    var scopeToolbarView: NSSegmentedControl { scopeControl }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let title = NSTextField(labelWithString: "Changes")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        branchLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        branchLabel.textColor = .secondaryLabelColor
        branchLabel.translatesAutoresizingMaskIntoConstraints = false
        let header = NSVisualEffectView()
        header.material = .contentBackground
        header.blendingMode = .withinWindow
        header.state = .active
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        header.addSubview(branchLabel)
        scopeControl.selectedSegment = 0
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.controlSize = .small
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        let headerBorder = NSBox()
        headerBorder.boxType = .separator
        headerBorder.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerBorder)

        diffScroll.hasVerticalScroller = true
        diffScroll.hasHorizontalScroller = true
        diffScroll.autohidesScrollers = true
        diffScroll.scrollerStyle = .overlay
        diffScroll.documentView = diffDocument
        diffScroll.borderType = .noBorder
        diffScroll.drawsBackground = false
        diffScroll.automaticallyAdjustsContentInsets = false
        diffScroll.contentInsets = NSEdgeInsets(top: 54, left: 0, bottom: 0, right: 0)
        diffScroll.contentView.postsBoundsChangedNotifications = true
        diffDocument.onCollapseChanged = { [weak self] in self?.updateDiffHeader() }
        diffHeader.onClick = { [weak self] in
            guard let self else { return }
            self.diffDocument.toggleHeader(at: self.diffScroll.contentView.bounds.minY + 34)
            self.updateDiffHeader()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(diffScrolled(_:)), name: NSView.boundsDidChangeNotification, object: diffScroll.contentView)
        diffHeader.translatesAutoresizingMaskIntoConstraints = false
        diffHeader.isHidden = true

        commitField.placeholderString = "Commit message (blank = auto-generate)"
        commitField.font = .systemFont(ofSize: 13)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor

        prBox.titlePosition = .noTitle
        prBox.contentView = prLabel
        prLabel.font = .systemFont(ofSize: 12)
        prLabel.textColor = .secondaryLabelColor
        prBox.isHidden = true

        let insets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        let stack = NSStackView(views: [diffScroll, prBox, statusLabel] as [NSView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.edgeInsets = insets
        stack.translatesAutoresizingMaskIntoConstraints = false
        diffScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Make full-width non-diff elements span the panel with matching horizontal padding.
        for v in [prBox] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
        diffScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let root = NSView()
        root.addSubview(stack)
        root.addSubview(header)
        root.addSubview(diffHeader)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 54),
            diffHeader.topAnchor.constraint(equalTo: header.bottomAnchor),
            diffHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            diffHeader.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            diffHeader.heightAnchor.constraint(equalToConstant: 34),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            branchLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            branchLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            title.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -14),
            headerBorder.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerBorder.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerBorder.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        view = root
    }

    @objc private func diffScrolled(_ note: Notification) {
        diffDocument.updateVisibleOverlays()
        diffDocument.needsDisplay = true
        updateDiffHeader()
    }

    private func updateDiffHeader() {
        diffHeader.setInfo(diffDocument.headerInfo(at: diffScroll.contentView.bounds.minY + 34))
    }

    @objc private func scopeChanged() {
        showingStaged = scopeControl.selectedSegment == 1
        reload()
    }

    @objc func showGitActions() {
        guard let window = view.window else { return }
        let panel = GitActionPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: isWorktree ? 302 : 220),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Git Actions"
        panel.isReleasedWhenClosed = false
        panel.onDismiss = { [weak self] in self?.dismissGitActions() }

        let title = NSTextField(labelWithString: "Commit changes")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        let branchIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage())
        branchIcon.contentTintColor = .secondaryLabelColor
        branchIcon.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = NSTextField(labelWithString: branchLabel.stringValue)
        subtitle.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        let branchRow = NSStackView(views: [branchIcon, subtitle])
        branchRow.orientation = .horizontal
        branchRow.alignment = .centerY
        branchRow.spacing = 6
        branchRow.translatesAutoresizingMaskIntoConstraints = false

        commitField.placeholderString = "Commit message (blank = auto-generate)"
        commitField.font = .systemFont(ofSize: 14)
        commitField.isBordered = false
        commitField.drawsBackground = false
        commitField.usesSingleLineMode = false
        commitField.lineBreakMode = .byWordWrapping
        commitField.translatesAutoresizingMaskIntoConstraints = false
        let inputBox = NSVisualEffectView()
        inputBox.material = .contentBackground
        inputBox.blendingMode = .withinWindow
        inputBox.state = .active
        inputBox.wantsLayer = true
        inputBox.layer?.cornerRadius = 10
        inputBox.translatesAutoresizingMaskIntoConstraints = false
        inputBox.addSubview(commitField)

        let commitBtn = makeBtn("Commit", #selector(doCommit))
        let commitPushBtn = makeBtn("Commit & Push", #selector(doCommitPush))
        let pushBtn = makeBtn("Push", #selector(doPush))
        let buttons = NSStackView(views: [commitBtn, commitPushBtn, pushBtn])
        buttons.orientation = .vertical
        buttons.spacing = 8
        buttons.alignment = .width

        var arranged: [NSView] = [title, branchRow, inputBox, buttons]
        if isWorktree {
            let divider = NSBox()
            divider.boxType = .separator
            let branchBtn = makeBtn("New Branch", #selector(doCreateBranch))
            let prBtn = makeBtn("Create PR", #selector(doCreatePR))
            let worktreeButtons = NSStackView(views: [branchBtn, prBtn])
            worktreeButtons.orientation = .vertical
            worktreeButtons.spacing = 8
            worktreeButtons.alignment = .width
            arranged.append(contentsOf: [divider, worktreeButtons])
        }

        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            branchIcon.widthAnchor.constraint(equalToConstant: 16),
            branchIcon.heightAnchor.constraint(equalToConstant: 16),
            inputBox.heightAnchor.constraint(equalToConstant: 82),
            commitField.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 11),
            commitField.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -11),
            commitField.topAnchor.constraint(equalTo: inputBox.topAnchor, constant: 9),
            commitField.bottomAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: -9),
        ])
        panel.contentView = root
        gitActionSheet = panel
        gitActionOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismissGitActions()
                return nil
            }
            if event.type == .leftMouseDown, event.window !== panel {
                self.dismissGitActions()
            }
            return event
        }
        window.beginSheet(panel) { [weak self] _ in
            if let monitor = self?.gitActionOutsideMonitor {
                NSEvent.removeMonitor(monitor)
                self?.gitActionOutsideMonitor = nil
            }
            self?.gitActionSheet = nil
        }
        panel.makeFirstResponder(commitField)
    }

    private func dismissGitActions() {
        guard let sheet = gitActionSheet, let parent = sheet.sheetParent else { return }
        parent.endSheet(sheet)
    }

    private func makeBtn(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.alignment = .center
        b.font = .systemFont(ofSize: 13.5, weight: .semibold)
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        b.layer?.backgroundColor = NSColor.controlColor.withAlphaComponent(0.70).cgColor
        b.contentTintColor = .labelColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return b
    }

    func show(workspace: String) { self.workspace = workspace; reload() }

    @objc func reload() {
        guard !workspace.isEmpty else { return }
        Task { @MainActor in
            guard let s = try? await client.gitStatus(workspace, staged: showingStaged) else { return }
            if let err = s.error {
                branchLabel.stringValue = err; diffDocument.setDiff(""); updateDiffHeader(); statusLabel.stringValue = ""; prBox.isHidden = true; return
            }
            branchLabel.stringValue = s.branch ?? "—"
            if let diff = s.diff, !diff.isEmpty {
                diffDocument.setDiff(diff)
            } else {
                diffDocument.setDiff("")
            }
            updateDiffHeader()
            let n = s.files?.count ?? 0
            statusLabel.stringValue = n == 0 ? "" : "\(n) changed file\(n == 1 ? "" : "s")"
            loadPRInfo()
        }
    }

    private func loadPRInfo() {
        Task { @MainActor in
            guard let pr = try? await client.prInfo(workspace) else { prBox.isHidden = true; return }
            if pr.none == true { prBox.isHidden = true; return }
            guard let title = pr.title, let url = pr.url else { prBox.isHidden = true; return }
            let state = pr.state ?? "?"
            let review = pr.reviewDecision ?? "PENDING"
            prLabel.stringValue = "PR #\(pr.number ?? 0): \(title)\n\(state) | \(review) | +\(pr.additions ?? 0) -\(pr.deletions ?? 0)\n\(url)"
            prBox.isHidden = false
        }
    }

    private func splitDiffFiles(_ diff: String) -> [(path: String, diff: String, added: Int, deleted: Int)] {
        var files: [(String, [String], Int, Int)] = []
        var path = "Changes"
        var lines: [String] = []
        var added = 0
        var deleted = 0
        func flush() {
            guard !lines.isEmpty else { return }
            files.append((path, lines, added, deleted))
            lines.removeAll(); added = 0; deleted = 0
        }
        for line in diff.components(separatedBy: .newlines) {
            if line.hasPrefix("diff --git") {
                flush()
                path = line.split(separator: " ").last.map { String($0).replacingOccurrences(of: "b/", with: "") } ?? "Changes"
                continue
            }
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("index ") { continue }
            if line.hasPrefix("+") { added += 1 }
            if line.hasPrefix("-") { deleted += 1 }
            if lines.count < 400 { lines.append(line) }
        }
        flush()
        return files.map { ($0.0, $0.1.joined(separator: "\n"), $0.2, $0.3) }
    }

    // MARK: - Proper diff renderer (diffshub-style)

    private func renderDiff(_ diff: String) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        let result = NSMutableAttributedString()
        var newLine = 0
        var oldLine = 0

        let addBg = NSColor(red: 0.85, green: 1.0, blue: 0.85, alpha: 1.0)
        let delBg = NSColor(red: 1.0, green: 0.88, blue: 0.88, alpha: 1.0)
        let addBgDark = NSColor(red: 0.12, green: 0.22, blue: 0.14, alpha: 1.0)
        let delBgDark = NSColor(red: 0.25, green: 0.12, blue: 0.12, alpha: 1.0)
        let hunkBg = NSColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 1.0)
        let hunkBgDark = NSColor(red: 0.15, green: 0.16, blue: 0.25, alpha: 1.0)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            // File header
            if line.hasPrefix("diff --git") {
                let file = line.split(separator: " ").last.map { String($0).replacingOccurrences(of: "b/", with: "") } ?? ""
                result.append(NSAttributedString(string: "\n  \(file)\n", attributes: [
                    .font: monoBold, .foregroundColor: NSColor.labelColor,
                    .backgroundColor: isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.03)
                ]))
                continue
            }

            if line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") { continue }

            if line.hasPrefix("@@") {
                let parts = line.split(separator: " ")
                if parts.count >= 3, let plus = parts.first(where: { $0.hasPrefix("+") }) {
                    let nums = plus.dropFirst().split(separator: ",")
                    newLine = Int(nums.first ?? "0") ?? 0
                }
                if parts.count >= 2, let minus = parts.first(where: { $0.hasPrefix("-") }) {
                    let nums = minus.dropFirst().split(separator: ",")
                    oldLine = Int(nums.first ?? "0") ?? 0
                }
                result.append(NSAttributedString(string: "  \(line)\n", attributes: [
                    .font: mono, .foregroundColor: NSColor.systemIndigo,
                    .backgroundColor: isDark ? hunkBgDark : hunkBg
                ]))
                continue
            }

            if line.hasPrefix("+") {
                let ln = String(format: "%4d", newLine)
                newLine += 1
                result.append(NSAttributedString(string: "  \(ln)  + \(line.dropFirst())\n", attributes: [
                    .font: mono, .foregroundColor: isDark ? NSColor.systemGreen : NSColor(red: 0.1, green: 0.45, blue: 0.1, alpha: 1),
                    .backgroundColor: isDark ? addBgDark : addBg
                ]))
            } else if line.hasPrefix("-") {
                let ln = String(format: "%4d", oldLine)
                oldLine += 1
                result.append(NSAttributedString(string: "  \(ln)  - \(line.dropFirst())\n", attributes: [
                    .font: mono, .foregroundColor: isDark ? NSColor.systemRed : NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1),
                    .backgroundColor: isDark ? delBgDark : delBg
                ]))
            } else {
                let ln = String(format: "%4d", newLine)
                oldLine += 1; newLine += 1
                result.append(NSAttributedString(string: "  \(ln)    \(line)\n", attributes: [
                    .font: mono, .foregroundColor: NSColor.labelColor
                ]))
            }
        }
        return result
    }

    // MARK: Actions

    @objc private func doCommit() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = msg.isEmpty ? "generating commit message..." : "committing..."
        dismissGitActions()
        Task { @MainActor in
            var body: [String: Any] = ["cwd": workspace]
            if !msg.isEmpty { body["message"] = msg }
            let r = try? await client.postJSON("git/commit", body)
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "committed: \(r?["message"] as? String ?? "")"; commitField.stringValue = "" }
            reload()
        }
    }

    @objc private func doCommitPush() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = msg.isEmpty ? "generating message & pushing..." : "committing & pushing..."
        dismissGitActions()
        Task { @MainActor in
            var body: [String: Any] = ["cwd": workspace]
            if !msg.isEmpty { body["message"] = msg }
            let r = try? await client.postJSON("git/commit-push", body)
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "pushed: \(r?["message"] as? String ?? "")"; commitField.stringValue = "" }
            reload()
        }
    }

    @objc private func doPush() {
        statusLabel.stringValue = "pushing..."
        dismissGitActions()
        Task { @MainActor in
            let r = try? await client.postJSON("git/push", ["cwd": workspace])
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "pushed" }
        }
    }

    @objc private func doCreateBranch() {
        let a = NSAlert(); a.messageText = "New Branch"; a.informativeText = "Branch name:"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        tf.placeholderString = "feature/my-branch"; a.accessoryView = tf
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let branch = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }
        dismissGitActions()
        Task { @MainActor in
            let r = try? await client.postJSON("git/create-branch", ["cwd": workspace, "branch": branch])
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else { statusLabel.stringValue = "on branch: \(branch)"; reload() }
        }
    }

    @objc private func doCreatePR() {
        let a = NSAlert(); a.messageText = "Create Pull Request"
        a.informativeText = "Title (blank = use branch name):"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.placeholderString = "PR title"; a.accessoryView = tf
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        statusLabel.stringValue = "creating PR..."
        dismissGitActions()
        Task { @MainActor in
            var body: [String: Any] = ["cwd": workspace]
            let title = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { body["title"] = title }
            let r = try? await client.postJSON("git/create-pr", body)
            if let err = r?["error"] as? String { statusLabel.stringValue = err }
            else if let url = r?["url"] as? String { statusLabel.stringValue = "PR: \(url)"; loadPRInfo() }
        }
    }
}
