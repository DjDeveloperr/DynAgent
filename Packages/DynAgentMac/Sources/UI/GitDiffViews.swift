import AppKit

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
        let point = convert(event.locationInWindow, from: nil)
        if toggleHeaderIfNeeded(at: point.y) { return }
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
            let section = sections[line.section]
            let info = GitDiffHeaderInfo(path: section.path, added: section.added, deleted: section.deleted, collapsed: collapsedPaths.contains(section.path))
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
                    let section = sections[line.section]
                    let chevron = collapsedPaths.contains(section.path) ? "▸" : "▾"
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
            let section = sections[line.section]
            let rowY = (rowTops.indices.contains(idx) ? rowTops[idx] : 0) - visibleY
            let info = GitDiffHeaderInfo(path: section.path, added: section.added, deleted: section.deleted, collapsed: collapsedPaths.contains(section.path))
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
        if let regex = try? NSRegularExpression(pattern: #"\b(let|var|func|final|class|struct|enum|if|else|for|while|guard|return|private|public|import|const|async|await|switch|case)\b"#) {
            let ns = out.string as NSString
            for match in regex.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
                out.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #""[^"\n]*"|'[^'\n]*'"#) {
            let ns = out.string as NSString
            for match in regex.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
                out.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: match.range)
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
