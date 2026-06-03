@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class TranscriptTurnRendererTests: XCTestCase {
    func testExpandedPlanAppendsMessagesOnly() {
        let user = ChatMessage(role: .user, text: "prompt")
        let assistant = ChatMessage(role: .assistant, text: "answer")
        var added: [ChatMessage] = []
        var dividerCount = 0

        TranscriptTurnRenderer.render(
            plan: .expanded(messages: [user, assistant]),
            now: 10,
            hooks: HooksSpy(
                addedMessages: { added.append($0) },
                addDivider: { _, _, _ in
                    dividerCount += 1
                    return WorkDivider(duration: nil)
                }
            ).hooks
        )

        XCTAssertTrue(added[0] === user)
        XCTAssertTrue(added[1] === assistant)
        XCTAssertEqual(dividerCount, 0)
    }

    func testCollapsedPlanHidesIntermediateRowsAndAddsFooter() {
        let user = ChatMessage(role: .user, text: "prompt")
        let tool = ChatMessage(role: .tool, toolName: "shell")
        let final = ChatMessage(role: .assistant, text: "done")
        final.turnDuration = 12
        let groupedRows = [NSView(), NSView()]
        var added: [ChatMessage] = []
        var groupedMessages: [ChatMessage] = []
        var collapseCompletedTools: Bool?
        var dividerArgs: (duration: Double?, collapsed: Bool, active: Bool)?
        var divider: WorkDivider?
        var footer: ChatMessage?

        TranscriptTurnRenderer.render(
            plan: .collapsed(userMessages: [user], middleMessages: [tool], finalMessage: final),
            now: 20,
            hooks: HooksSpy(
                addedMessages: { added.append($0) },
                groupedRows: { messages, collapse in
                    groupedMessages = messages
                    collapseCompletedTools = collapse
                    return groupedRows
                },
                addDivider: { duration, collapsed, active in
                    dividerArgs = (duration, collapsed, active)
                    let created = WorkDivider(duration: duration, collapsed: collapsed, active: active)
                    divider = created
                    return created
                },
                addFooter: { footer = $0 }
            ).hooks
        )

        XCTAssertTrue(added[0] === user)
        XCTAssertTrue(added[1] === final)
        XCTAssertTrue(groupedMessages.first === tool)
        XCTAssertEqual(collapseCompletedTools, true)
        XCTAssertEqual(dividerArgs?.duration, 12)
        XCTAssertEqual(dividerArgs?.collapsed, true)
        XCTAssertEqual(dividerArgs?.active, false)
        XCTAssertTrue(divider?.messages.first === tool)
        XCTAssertTrue(groupedRows.allSatisfy(\.isHidden))
        XCTAssertTrue(footer === final)
    }

    func testActivePlanUsesLiveDividerAndKeepsIntermediateRowsVisible() {
        let user = ChatMessage(role: .user, text: "prompt")
        let tool = ChatMessage(role: .tool, toolName: "edit")
        let groupedRows = [NSView(), NSView()]
        var added: [ChatMessage] = []
        var groupedMessages: [ChatMessage] = []
        var collapseCompletedTools: Bool?
        var dividerArgs: (duration: Double?, collapsed: Bool, active: Bool)?
        var liveDivider: WorkDivider?
        var createdDivider: WorkDivider?

        TranscriptTurnRenderer.render(
            plan: .active(startedAt: 90, userMessages: [user], middleMessages: [tool]),
            now: 100,
            hooks: HooksSpy(
                addedMessages: { added.append($0) },
                groupedRows: { messages, collapse in
                    groupedMessages = messages
                    collapseCompletedTools = collapse
                    return groupedRows
                },
                addDivider: { duration, collapsed, active in
                    dividerArgs = (duration, collapsed, active)
                    let created = WorkDivider(duration: duration, collapsed: collapsed, active: active)
                    createdDivider = created
                    return created
                },
                setLiveDivider: { liveDivider = $0 }
            ).hooks
        )

        XCTAssertTrue(added.first === user)
        XCTAssertTrue(groupedMessages.first === tool)
        XCTAssertEqual(collapseCompletedTools, false)
        XCTAssertEqual(dividerArgs?.duration, 10)
        XCTAssertEqual(dividerArgs?.collapsed, false)
        XCTAssertEqual(dividerArgs?.active, true)
        XCTAssertNotNil(liveDivider)
        XCTAssertTrue(liveDivider === createdDivider)
        XCTAssertTrue(liveDivider?.messages.first === tool)
        XCTAssertTrue(groupedRows.allSatisfy { !$0.isHidden })
    }

    func testRenderBuildsPlanBeforeApplyingHooks() {
        let assistant = ChatMessage(role: .assistant, text: "working")
        var dividerArgs: (duration: Double?, collapsed: Bool, active: Bool)?

        TranscriptTurnRenderer.render(
            turn: [assistant],
            allowCollapse: true,
            isConversationActive: false,
            forceActive: true,
            fallbackActiveStartedAt: 40,
            now: 55,
            hooks: HooksSpy(
                addDivider: { duration, collapsed, active in
                    dividerArgs = (duration, collapsed, active)
                    return WorkDivider(duration: duration, collapsed: collapsed, active: active)
                }
            ).hooks
        )

        XCTAssertEqual(dividerArgs?.duration, 15)
        XCTAssertEqual(dividerArgs?.collapsed, false)
        XCTAssertEqual(dividerArgs?.active, true)
    }
}

@MainActor
private struct HooksSpy {
    var addedMessages: (ChatMessage) -> Void = { _ in }
    var groupedRows: ([ChatMessage], Bool) -> [NSView] = { _, _ in [] }
    var addDivider: (Double?, Bool, Bool) -> WorkDivider = { duration, collapsed, active in
        WorkDivider(duration: duration, collapsed: collapsed, active: active)
    }
    var setLiveDivider: (WorkDivider) -> Void = { _ in }
    var addFooter: (ChatMessage) -> Void = { _ in }

    var hooks: TranscriptTurnRenderer.Hooks {
        TranscriptTurnRenderer.Hooks(
            addMessageRow: addedMessages,
            addGroupedRows: groupedRows,
            addWorkDivider: addDivider,
            setLiveDivider: setLiveDivider,
            addFinalFooter: addFooter
        )
    }
}
