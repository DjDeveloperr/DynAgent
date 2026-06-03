import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class TranscriptRowRegistryTests: XCTestCase {
    func testRegistersRowLookupStateAndClearsItOnReset() {
        let registry = TranscriptRowRegistry()
        let message = ChatMessage(role: .tool, text: "", toolName: "edit", toolDetail: "changed")
        let label = MessageTextView()
        let toolView = NSView()
        let stats = EditStatsView(added: 1, deleted: 2)

        registry.register(TranscriptRowBuildResult(
            container: NSView(),
            label: label,
            clickableToolView: toolView,
            editStats: stats,
            customSpacingAfter: nil
        ), for: message)

        XCTAssertIdentical(registry.label(for: message), label)
        XCTAssertIdentical(registry.toolMessage(for: toolView), message)
        XCTAssertIdentical(registry.editStats(for: message), stats)

        registry.reset()

        XCTAssertNil(registry.label(for: message))
        XCTAssertNil(registry.toolMessage(for: toolView))
        XCTAssertNil(registry.editStats(for: message))
    }

    func testCopyTextIsButtonScopedAndResettable() {
        let registry = TranscriptRowRegistry()
        let first = NSButton()
        let second = NSButton()

        registry.registerCopyText("alpha", for: first)
        registry.registerCopyText("beta", for: second)

        XCTAssertEqual(registry.copyText(for: first), "alpha")
        XCTAssertEqual(registry.copyText(for: second), "beta")

        registry.reset()

        XCTAssertNil(registry.copyText(for: first))
        XCTAssertNil(registry.copyText(for: second))
    }

    func testLiveMarkdownRenderSlotHonorsThrottleAndForce() {
        let registry = TranscriptRowRegistry()
        let message = ChatMessage(role: .assistant, text: "streaming")

        XCTAssertTrue(registry.consumeLiveMarkdownRenderSlot(for: message, force: false, now: 10))
        XCTAssertFalse(registry.consumeLiveMarkdownRenderSlot(for: message, force: false, now: 10.02))
        XCTAssertTrue(registry.consumeLiveMarkdownRenderSlot(for: message, force: true, now: 10.03))
        XCTAssertFalse(registry.consumeLiveMarkdownRenderSlot(for: message, force: false, now: 10.04))
        XCTAssertTrue(registry.consumeLiveMarkdownRenderSlot(
            for: message,
            force: false,
            now: 10.03 + TranscriptLiveUpdateModel.markdownRenderInterval + 0.01
        ))
    }
}
