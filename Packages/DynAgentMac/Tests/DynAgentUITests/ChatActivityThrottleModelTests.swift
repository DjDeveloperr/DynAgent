@testable import DynAgentUI
import XCTest

final class ChatActivityThrottleModelTests: XCTestCase {
    func testFirstEmitIsAllowedAndRecorded() {
        let result = ChatActivityThrottleModel.planEmit(
            conversationId: "thread-a",
            force: false,
            now: 100,
            state: ChatActivityThrottleState(),
            interval: 2
        )

        XCTAssertTrue(result.shouldEmit)
        XCTAssertEqual(result.state.lastEmitByConversationId["thread-a"], 100)
    }

    func testRepeatedEmitIsThrottledUntilIntervalPasses() {
        let initial = ChatActivityThrottleState(lastEmitByConversationId: ["thread-a": 100])

        let early = ChatActivityThrottleModel.planEmit(
            conversationId: "thread-a",
            force: false,
            now: 101.99,
            state: initial,
            interval: 2
        )
        XCTAssertFalse(early.shouldEmit)
        XCTAssertEqual(early.state, initial)

        let ready = ChatActivityThrottleModel.planEmit(
            conversationId: "thread-a",
            force: false,
            now: 102,
            state: initial,
            interval: 2
        )
        XCTAssertTrue(ready.shouldEmit)
        XCTAssertEqual(ready.state.lastEmitByConversationId["thread-a"], 102)
    }

    func testForceBypassesThrottleAndUpdatesTimestamp() {
        let initial = ChatActivityThrottleState(lastEmitByConversationId: ["thread-a": 100])

        let result = ChatActivityThrottleModel.planEmit(
            conversationId: "thread-a",
            force: true,
            now: 100.1,
            state: initial,
            interval: 2
        )

        XCTAssertTrue(result.shouldEmit)
        XCTAssertEqual(result.state.lastEmitByConversationId["thread-a"], 100.1)
    }

    func testThrottleIsScopedPerConversation() {
        let initial = ChatActivityThrottleState(lastEmitByConversationId: ["thread-a": 100])

        let result = ChatActivityThrottleModel.planEmit(
            conversationId: "thread-b",
            force: false,
            now: 100.1,
            state: initial,
            interval: 2
        )

        XCTAssertTrue(result.shouldEmit)
        XCTAssertEqual(result.state.lastEmitByConversationId["thread-a"], 100)
        XCTAssertEqual(result.state.lastEmitByConversationId["thread-b"], 100.1)
    }
}
