import AppKit

struct TranscriptPopoverContent {
    var controller: NSViewController
    var size: NSSize

    func install(in popover: NSPopover) {
        popover.close()
        popover.contentViewController = controller
        popover.contentSize = size
        popover.behavior = .transient
    }
}

enum TranscriptPopoverChrome {
    static func show(_ content: TranscriptPopoverContent,
                     in popover: NSPopover,
                     relativeTo rect: NSRect,
                     of view: NSView,
                     preferredEdge: NSRectEdge = .maxY) {
        content.install(in: popover)
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    static func toolDetail(name: String?, done: Bool, detail: String?) -> TranscriptPopoverContent {
        selectableText(
            "\(name ?? "tool")\(done ? "  ✓" : "")\n\n\(detail ?? "(no details)")",
            size: NSSize(width: 440, height: 220),
            horizontalScroller: false
        )
    }

    static func shellOutput(_ output: String) -> TranscriptPopoverContent {
        selectableText(
            output.isEmpty ? "No output" : output,
            size: NSSize(width: 620, height: 360),
            horizontalScroller: true
        )
    }

    static func editDiff(changes: [EditToolChange]) -> TranscriptPopoverContent {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for change in changes {
            stack.addArrangedSubview(DiffFileBlock(
                path: change.path,
                diff: change.diff,
                added: change.added,
                deleted: change.deleted,
                initiallyCollapsed: false
            ))
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

        let controller = NSViewController()
        controller.view = scroll
        return TranscriptPopoverContent(controller: controller, size: NSSize(width: 760, height: 520))
    }

    private static func selectableText(_ string: String, size: NSSize, horizontalScroller: Bool) -> TranscriptPopoverContent {
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = string

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = horizontalScroller
        scroll.drawsBackground = false
        scroll.documentView = text
        text.frame = scroll.bounds
        text.autoresizingMask = horizontalScroller ? [.height] : [.width]
        text.isHorizontallyResizable = horizontalScroller
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = !horizontalScroller
        if horizontalScroller {
            text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        let controller = NSViewController()
        controller.view = scroll
        return TranscriptPopoverContent(controller: controller, size: size)
    }
}
