import AppKit

struct TranscriptToolPopoverPlan {
    enum Kind: Equatable {
        case editDiff
        case toolDetail
    }

    var kind: Kind
    var content: TranscriptPopoverContent
    var anchorRect: NSRect
}

enum TranscriptToolPopoverPresenter {
    static func plan(for message: ChatMessage, clickPoint: NSPoint?, anchorBounds: NSRect) -> TranscriptToolPopoverPlan {
        if message.toolName == "edit" {
            return TranscriptToolPopoverPlan(
                kind: .editDiff,
                content: TranscriptPopoverChrome.editDiff(changes: TranscriptToolFormatter.editSummary(message).changes),
                anchorRect: normalizedAnchor(anchorBounds)
            )
        }

        return TranscriptToolPopoverPlan(
            kind: .toolDetail,
            content: TranscriptPopoverChrome.toolDetail(
                name: message.toolName,
                done: message.toolDone,
                detail: message.toolDetail
            ),
            anchorRect: clickAnchor(clickPoint, in: anchorBounds)
        )
    }

    static func editPlan(changes: [EditToolChange], anchorBounds: NSRect) -> TranscriptToolPopoverPlan {
        TranscriptToolPopoverPlan(
            kind: .editDiff,
            content: TranscriptPopoverChrome.editDiff(changes: changes),
            anchorRect: normalizedAnchor(anchorBounds)
        )
    }

    private static func normalizedAnchor(_ bounds: NSRect) -> NSRect {
        guard !bounds.isEmpty else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
        return bounds
    }

    private static func clickAnchor(_ clickPoint: NSPoint?, in bounds: NSRect) -> NSRect {
        let safe = normalizedAnchor(bounds)
        let x = min(max((clickPoint?.x ?? safe.midX) - 4, safe.minX), max(safe.maxX - 8, safe.minX))
        return NSRect(x: x, y: safe.minY, width: 8, height: safe.height)
    }
}
