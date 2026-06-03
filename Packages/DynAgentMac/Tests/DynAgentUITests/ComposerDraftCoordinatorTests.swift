@testable import DynAgentUI
import XCTest

final class ComposerDraftCoordinatorTests: XCTestCase {
    func testAddRemoveAndNormalizedAttachmentPaths() {
        let coordinator = ComposerDraftCoordinator(store: testStore())
        let first = coordinator.addAttachments([
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/b.swift"),
        ])

        XCTAssertTrue(first.didChange)
        XCTAssertEqual(coordinator.attachmentPaths, ["/tmp/a.png", "/tmp/b.swift"])
        XCTAssertTrue(coordinator.hasAttachments)

        let removed = coordinator.removeAttachment(id: first.state.attachments[0].id)
        XCTAssertTrue(removed.didChange)
        XCTAssertEqual(coordinator.attachmentPaths, ["/tmp/b.swift"])

        let missing = coordinator.removeAttachment(id: UUID())
        XCTAssertFalse(missing.didChange)
        XCTAssertEqual(coordinator.attachmentPaths, ["/tmp/b.swift"])
    }

    func testSaveRestoreAndClearRoundTripThroughDraftStore() {
        let suite = "DynAgentComposerDraftCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ComposerDraftStore(defaults: defaults, prefix: "TestDraft.")
        let conversation = Conversation(model: "gpt", workspace: "/repo", harness: .codex)

        let saved = ComposerDraftCoordinator(store: store)
        _ = saved.addAttachments([URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/missing.swift")])
        saved.save(text: "keep this", for: conversation)

        let restored = ComposerDraftCoordinator(store: store)
        let state = restored.restore(for: conversation) { $0.hasSuffix("a.png") }

        XCTAssertEqual(state.text, "keep this")
        XCTAssertEqual(restored.attachmentPaths, ["/tmp/a.png"])

        let cleared = restored.clear(for: conversation)
        XCTAssertEqual(cleared, .empty)
        XCTAssertNil(store.snapshot(for: conversation))
        XCTAssertFalse(restored.hasAttachments)
    }

    func testScheduledSaveUsesLatestTextAndCancelsEarlierSave() {
        let suite = "DynAgentComposerDraftCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ComposerDraftStore(defaults: defaults, prefix: "TestDraft.")
        let conversation = Conversation(model: "gpt", workspace: "/repo", harness: .codex)
        let coordinator = ComposerDraftCoordinator(store: store)
        var text = "first"

        coordinator.scheduleSave(textProvider: { text }, conversationProvider: { conversation })
        text = "second"
        coordinator.scheduleSave(textProvider: { text }, conversationProvider: { conversation })

        let expectation = expectation(description: "draft saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(store.snapshot(for: conversation)?.text, "second")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    private func testStore() -> ComposerDraftStore {
        ComposerDraftStore(
            defaults: UserDefaults(suiteName: "DynAgentComposerDraftCoordinatorTests.\(UUID().uuidString)")!,
            prefix: "TestDraft."
        )
    }
}
