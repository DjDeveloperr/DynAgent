import AppKit

struct InlineToolRowChrome {
    let view: NSView
    let editStats: EditStatsView?
}

enum TranscriptInlineToolChrome {
    static func make(label: MessageTextView, message: ChatMessage) -> InlineToolRowChrome {
        let isEdit = message.toolName == "edit"
        let icon = NSImageView(image: NSImage(
            systemSymbolName: TranscriptToolFormatter.toolIconName(message.toolName),
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let status = NSTextField(labelWithString: message.toolDone ? "" : "Running")
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = message.toolDone ? .tertiaryLabelColor : .secondaryLabelColor
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
        let summary = isEdit ? TranscriptToolFormatter.editSummary(message) : nil
        if isEdit && !message.toolDone {
            label.isHidden = true
            let name = summary?.changes.first.map { TranscriptToolFormatter.fileName($0.path) }
            textStack.addArrangedSubview(ShimmerLabel(text: name.map { "Editing \($0)" } ?? "Editing"))
        }

        let editStats = isEdit ? EditStatsView(added: summary?.added ?? 0, deleted: summary?.deleted ?? 0) : nil
        if let editStats {
            editStats.isHidden = (summary?.added ?? 0) == 0 && (summary?.deleted ?? 0) == 0
        }

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)
        row.addSubview(textStack)
        if let editStats { row.addSubview(editStats) }
        if !isEdit { row.addSubview(chevron) }
        if !message.toolDone && !isEdit { row.addSubview(status) }
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
        } else if message.toolDone {
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
        return InlineToolRowChrome(view: row, editStats: editStats)
    }
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

struct ShellGroupItem {
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
        let content = TranscriptPopoverChrome.shellOutput(output)
        TranscriptPopoverChrome.show(content, in: outputPopover, relativeTo: bounds, of: self)
    }
}

final class ShellGroupView: NSView {
    private let chevron = NSImageView()
    private let body = NSStackView()
    private var collapsed = true

    init(title: NSAttributedString, items: [ShellGroupItem]) {
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
