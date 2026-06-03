@testable import DynAgentUI
import XCTest

final class ComposerDraftStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ComposerDraftStore!

    override func setUp() {
        super.setUp()
        suiteName = "ComposerDraftStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = ComposerDraftStore(defaults: defaults, prefix: "TestDraft.")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSavesAndRestoresDraftSnapshotForConversation() throws {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        let attachments = [ComposerAttachment(url: URL(fileURLWithPath: "/repo/a.png"))]

        store.save(text: "keep this prompt", attachments: attachments, for: conversation)

        let snapshot = try XCTUnwrap(store.snapshot(for: conversation))
        XCTAssertEqual(snapshot.text, "keep this prompt")
        XCTAssertEqual(snapshot.attachments, ["/repo/a.png"])
        XCTAssertEqual(store.restoredAttachments(for: conversation) { $0.hasSuffix("a.png") }.map(\.url.path), ["/repo/a.png"])
    }

    func testEmptyDraftRemovesStoredValue() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)

        store.save(snapshot: ComposerDraftSnapshot(text: "old", attachments: []), for: conversation)
        XCTAssertNotNil(store.snapshot(for: conversation))

        store.save(snapshot: ComposerDraftSnapshot(text: "", attachments: []), for: conversation)

        XCTAssertNil(store.snapshot(for: conversation))
    }

    func testClearRemovesConversationDraft() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        store.save(snapshot: ComposerDraftSnapshot(text: "draft", attachments: []), for: conversation)

        store.clear(for: conversation)

        XCTAssertNil(store.snapshot(for: conversation))
    }

    func testUsesThreadKeyForCodexThreads() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.codexThreadId = "thread-123"

        XCTAssertEqual(store.key(for: conversation), "TestDraft.codex:thread-123")
    }
}
