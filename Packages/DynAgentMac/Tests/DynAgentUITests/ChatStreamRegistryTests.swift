@testable import DynAgentUI
import XCTest

final class ChatStreamRegistryTests: XCTestCase {
    func testActiveAndTaskTrackingAreScopedByConversationId() {
        let registry = ChatStreamRegistry<String>()

        registry.setActive(true, id: "a")
        registry.setTask("task-a", id: "a")
        registry.setTask("task-b", id: "b")

        XCTAssertTrue(registry.isActive("a"))
        XCTAssertFalse(registry.isActive("b"))
        XCTAssertEqual(registry.task(for: "a"), "task-a")
        XCTAssertEqual(registry.task(for: "b"), "task-b")

        registry.finish("a")

        XCTAssertFalse(registry.isActive("a"))
        XCTAssertNil(registry.task(for: "a"))
        XCTAssertEqual(registry.task(for: "b"), "task-b")
    }

    func testStopFlagCanBePreservedAcrossStopDrivenFinishAndConsumedOnce() {
        let registry = ChatStreamRegistry<String>()

        registry.setActive(true, id: "thread")
        registry.setTask("task", id: "thread")
        registry.markStopping("thread")
        registry.finish("thread", preservingStopFlag: true)

        XCTAssertFalse(registry.isActive("thread"))
        XCTAssertNil(registry.task(for: "thread"))
        XCTAssertTrue(registry.consumeStopping("thread"))
        XCTAssertFalse(registry.consumeStopping("thread"))
    }

    func testNormalFinishClearsStopFlag() {
        let registry = ChatStreamRegistry<String>()

        registry.markStopping("thread")
        registry.finish("thread")

        XCTAssertFalse(registry.consumeStopping("thread"))
    }
}
