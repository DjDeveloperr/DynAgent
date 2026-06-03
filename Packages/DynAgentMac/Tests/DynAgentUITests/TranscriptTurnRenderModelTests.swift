@testable import DynAgentUI
import XCTest

final class TranscriptTurnRenderModelTests: XCTestCase {
    func testCollapsedPlanSplitsPromptMiddleAndFinalResponse() {
        let prompt = ChatMessage(role: .user, text: "prompt")
        let steer = ChatMessage(role: .user, text: "steer")
        steer.isSteer = true
        let tool = ChatMessage(role: .tool, toolName: "shell", toolDetail: "ls")
        let final = ChatMessage(role: .assistant, text: "done")
        final.isFinal = true
        final.turnDuration = 3

        let plan = TranscriptTurnRenderModel.plan(
            turn: [prompt, steer, tool, final],
            allowCollapse: true,
            isConversationActive: false,
            forceActive: false,
            fallbackActiveStartedAt: nil,
            now: 50
        )

        guard case .collapsed(let userMessages, let middleMessages, let finalMessage) = plan else {
            return XCTFail("Expected collapsed plan")
        }
        XCTAssertTrue(userMessages.first === prompt)
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertTrue(middleMessages[0] === steer)
        XCTAssertTrue(middleMessages[1] === tool)
        XCTAssertEqual(middleMessages.count, 2)
        XCTAssertTrue(finalMessage === final)
    }

    func testExpandedPlanWhenCollapseDisabledOrNoFinalResponse() {
        let prompt = ChatMessage(role: .user, text: "prompt")
        let assistant = ChatMessage(role: .assistant, text: "draft")

        let disabled = TranscriptTurnRenderModel.plan(
            turn: [prompt, assistant],
            allowCollapse: false,
            isConversationActive: false,
            forceActive: false,
            fallbackActiveStartedAt: nil,
            now: 10
        )
        guard case .expanded(let disabledMessages) = disabled else {
            return XCTFail("Expected expanded plan")
        }
        XCTAssertTrue(disabledMessages[0] === prompt)
        XCTAssertTrue(disabledMessages[1] === assistant)

        let noFinal = TranscriptTurnRenderModel.plan(
            turn: [prompt],
            allowCollapse: true,
            isConversationActive: false,
            forceActive: false,
            fallbackActiveStartedAt: nil,
            now: 10
        )
        guard case .expanded(let noFinalMessages) = noFinal else {
            return XCTFail("Expected expanded plan")
        }
        XCTAssertTrue(noFinalMessages[0] === prompt)
    }

    func testActivePlanUsesTurnStartAndKeepsSteersInMiddle() {
        let prompt = ChatMessage(role: .user, text: "prompt")
        prompt.turnStartedAt = 100
        let steer = ChatMessage(role: .user, text: "steer")
        steer.isSteer = true
        let tool = ChatMessage(role: .tool, toolName: "shell")
        tool.turnStatus = "running"

        let plan = TranscriptTurnRenderModel.plan(
            turn: [prompt, steer, tool],
            allowCollapse: false,
            isConversationActive: true,
            forceActive: false,
            fallbackActiveStartedAt: 90,
            now: 120
        )

        guard case .active(let startedAt, let userMessages, let middleMessages) = plan else {
            return XCTFail("Expected active plan")
        }
        XCTAssertEqual(startedAt, 100)
        XCTAssertTrue(userMessages.first === prompt)
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertTrue(middleMessages[0] === steer)
        XCTAssertTrue(middleMessages[1] === tool)
    }

    func testForceActiveUsesFallbackThenNowWhenNoMessageStartExists() {
        let assistant = ChatMessage(role: .assistant, text: "working")

        let fallback = TranscriptTurnRenderModel.plan(
            turn: [assistant],
            allowCollapse: true,
            isConversationActive: false,
            forceActive: true,
            fallbackActiveStartedAt: 44,
            now: 55
        )
        guard case .active(let fallbackStartedAt, _, _) = fallback else {
            return XCTFail("Expected active fallback plan")
        }
        XCTAssertEqual(fallbackStartedAt, 44)

        let now = TranscriptTurnRenderModel.plan(
            turn: [assistant],
            allowCollapse: true,
            isConversationActive: false,
            forceActive: true,
            fallbackActiveStartedAt: nil,
            now: 55
        )
        guard case .active(let nowStartedAt, _, _) = now else {
            return XCTFail("Expected active now plan")
        }
        XCTAssertEqual(nowStartedAt, 55)
    }
}
