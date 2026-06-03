import AppKit

enum TranscriptTurnRenderer {
    struct Hooks {
        var addMessageRow: (ChatMessage) -> Void
        var addGroupedRows: (_ messages: [ChatMessage], _ collapseCompletedTools: Bool) -> [NSView]
        var addWorkDivider: (_ duration: Double?, _ collapsed: Bool, _ active: Bool) -> WorkDivider
        var setLiveDivider: (WorkDivider) -> Void
        var addFinalFooter: (ChatMessage) -> Void
    }

    static func render(
        turn: [ChatMessage],
        allowCollapse: Bool,
        isConversationActive: Bool,
        forceActive: Bool,
        fallbackActiveStartedAt: Double?,
        now: Double,
        hooks: Hooks
    ) {
        let plan = TranscriptTurnRenderModel.plan(
            turn: turn,
            allowCollapse: allowCollapse,
            isConversationActive: isConversationActive,
            forceActive: forceActive,
            fallbackActiveStartedAt: fallbackActiveStartedAt,
            now: now
        )
        render(plan: plan, now: now, hooks: hooks)
    }

    static func render(plan: TranscriptTurnRenderPlan, now: Double, hooks: Hooks) {
        switch plan {
        case .expanded(let messages):
            messages.forEach(hooks.addMessageRow)
        case .collapsed(let userMessages, let middleMessages, let finalMessage):
            userMessages.forEach(hooks.addMessageRow)
            let divider = hooks.addWorkDivider(finalMessage.turnDuration, true, false)
            divider.messages = middleMessages
            divider.rows = hooks.addGroupedRows(middleMessages, true).map { row in
                row.isHidden = true
                return row
            }
            divider.refresh()
            hooks.addMessageRow(finalMessage)
            hooks.addFinalFooter(finalMessage)
        case .active(let startedAt, let userMessages, let middleMessages):
            userMessages.forEach(hooks.addMessageRow)
            let divider = hooks.addWorkDivider(max(0, now - startedAt), false, true)
            hooks.setLiveDivider(divider)
            divider.messages = middleMessages
            divider.rows = hooks.addGroupedRows(middleMessages, false)
            divider.refresh()
        }
    }
}
