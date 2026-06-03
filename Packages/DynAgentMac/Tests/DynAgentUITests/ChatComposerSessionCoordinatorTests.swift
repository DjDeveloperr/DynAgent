@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class ChatComposerSessionCoordinatorTests: XCTestCase {
    func testAddRemoveAndSaveDraftThroughRenderedAttachmentStrip() throws {
        let suite = "ChatComposerSessionCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ComposerDraftStore(defaults: defaults, prefix: "TestDraft.")
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        let fixture = ComposerSessionFixture(store: store)
        fixture.composer.string = "keep draft"

        XCTAssertTrue(fixture.coordinator.addAttachments([
            URL(fileURLWithPath: "/tmp/App.swift"),
            URL(fileURLWithPath: "/tmp/App.swift"),
            URL(fileURLWithPath: "/tmp/Image.png"),
        ], conversation: conversation))

        XCTAssertEqual(fixture.coordinator.attachmentPaths, ["/tmp/App.swift", "/tmp/Image.png"])
        XCTAssertEqual(store.snapshot(for: conversation)?.text, "keep draft")
        XCTAssertEqual(store.snapshot(for: conversation)?.attachments, ["/tmp/App.swift", "/tmp/Image.png"])
        XCTAssertFalse(fixture.attachmentScroll.isHidden)
        XCTAssertEqual(fixture.attachmentHeight.constant, ComposerAttachmentStripChrome.visibleHeight)

        let remove = try XCTUnwrap(fixture.removeButtons.first)
        XCTAssertTrue(fixture.coordinator.removeAttachment(sender: remove, conversation: conversation))
        XCTAssertEqual(fixture.coordinator.attachmentPaths, ["/tmp/Image.png"])
        XCTAssertEqual(store.snapshot(for: conversation)?.attachments, ["/tmp/Image.png"])
        XCTAssertFalse(fixture.coordinator.removeAttachment(sender: NSButton(), conversation: conversation))
    }

    func testRestoreDraftAppliesTextPlaceholderAndExistingAttachmentsOnly() {
        let suite = "ChatComposerSessionCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ComposerDraftStore(defaults: defaults, prefix: "TestDraft.")
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        store.save(text: "resume this", attachments: [
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/a.png")),
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/missing.swift")),
        ], for: conversation)
        let fixture = ComposerSessionFixture(store: store)

        fixture.coordinator.restoreDraft(for: conversation) { $0.hasSuffix("a.png") }

        XCTAssertEqual(fixture.composer.string, "resume this")
        XCTAssertTrue(fixture.placeholder.isHidden)
        XCTAssertEqual(fixture.coordinator.attachmentPaths, ["/tmp/a.png"])
        XCTAssertEqual(fixture.attachmentStack.arrangedSubviews.count, 1)
    }

    func testClearAfterSendClearsTextAttachmentsAndPlaceholder() {
        let store = ComposerDraftStore(
            defaults: UserDefaults(suiteName: "ChatComposerSessionCoordinatorTests.\(UUID().uuidString)")!,
            prefix: "TestDraft."
        )
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        let fixture = ComposerSessionFixture(store: store)

        fixture.composer.string = "send me"
        _ = fixture.coordinator.addAttachments([URL(fileURLWithPath: "/tmp/App.swift")], conversation: conversation)
        fixture.coordinator.clearAfterSend(for: conversation)

        XCTAssertEqual(fixture.composer.string, "")
        XCTAssertFalse(fixture.placeholder.isHidden)
        XCTAssertFalse(fixture.coordinator.hasAttachments)
        XCTAssertEqual(fixture.attachmentHeight.constant, 0)
        XCTAssertNil(store.snapshot(for: conversation))
    }
}

@MainActor
private final class ComposerSessionFixture {
    let composer = ComposerTextView()
    let placeholder = NSTextField(labelWithString: "Ask Codex")
    let attachmentScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 66))
    let attachmentStack = NSStackView()
    let attachmentHeight: NSLayoutConstraint
    let target = ComposerSessionRemoveTarget()
    let coordinator: ChatComposerSessionCoordinator

    init(store: ComposerDraftStore) {
        attachmentStack.orientation = .horizontal
        attachmentStack.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.documentView = attachmentStack
        attachmentHeight = attachmentScroll.heightAnchor.constraint(equalToConstant: 0)
        attachmentHeight.isActive = true
        coordinator = ChatComposerSessionCoordinator(
            attachments: ComposerAttachmentCoordinator(
                drafts: ComposerDraftCoordinator(store: store)
            ),
            composer: composer,
            placeholder: placeholder,
            attachmentStack: attachmentStack,
            attachmentScroll: attachmentScroll,
            attachmentHeightConstraint: attachmentHeight,
            removeTarget: target,
            removeAction: #selector(ComposerSessionRemoveTarget.remove(_:))
        )
    }

    var removeButtons: [NSButton] {
        attachmentStack.descendantButtons().filter { $0.action == #selector(ComposerSessionRemoveTarget.remove(_:)) }
    }
}

private final class ComposerSessionRemoveTarget: NSObject {
    @objc func remove(_ sender: NSButton) {}
}

private extension NSView {
    func descendantButtons() -> [NSButton] {
        var buttons: [NSButton] = []
        for subview in subviews {
            if let button = subview as? NSButton {
                buttons.append(button)
            }
            buttons.append(contentsOf: subview.descendantButtons())
        }
        return buttons
    }
}
