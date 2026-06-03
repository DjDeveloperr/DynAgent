import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class ComposerAttachmentCoordinatorTests: XCTestCase {
    func testAddRenderAndRemoveThroughRenderedButtonMapping() throws {
        let coordinator = ComposerAttachmentCoordinator(drafts: ComposerDraftCoordinator(store: testStore()))
        let fixture = AttachmentStripFixture()

        XCTAssertTrue(coordinator.add([
            URL(fileURLWithPath: "/tmp/App.swift"),
            URL(fileURLWithPath: "/tmp/App.swift"),
            URL(fileURLWithPath: "/tmp/Notes.md"),
        ]))
        XCTAssertFalse(coordinator.add([URL(fileURLWithPath: "/tmp/App.swift")]))

        coordinator.render(
            into: fixture.stack,
            inside: fixture.scroll,
            heightConstraint: fixture.height,
            target: fixture.target,
            removeAction: #selector(AttachmentRemoveTarget.remove(_:))
        )

        XCTAssertEqual(coordinator.attachmentPaths, ["/tmp/App.swift", "/tmp/Notes.md"])
        XCTAssertTrue(coordinator.hasAttachments)
        XCTAssertFalse(fixture.stack.isHidden)
        XCTAssertFalse(fixture.scroll.isHidden)
        XCTAssertEqual(fixture.height.constant, ComposerAttachmentStripChrome.visibleHeight)
        XCTAssertEqual(fixture.stack.arrangedSubviews.count, 2)

        let removeButton = try XCTUnwrap(fixture.removeButtons.first)
        XCTAssertTrue(coordinator.remove(sender: removeButton))
        XCTAssertEqual(coordinator.attachmentPaths, ["/tmp/Notes.md"])
        XCTAssertFalse(coordinator.remove(sender: NSButton()))

        coordinator.render(
            into: fixture.stack,
            inside: fixture.scroll,
            heightConstraint: fixture.height,
            target: fixture.target,
            removeAction: #selector(AttachmentRemoveTarget.remove(_:))
        )
        XCTAssertEqual(fixture.stack.arrangedSubviews.count, 1)
    }

    func testSaveRestoreScheduleAndClearDraftThroughCoordinator() {
        let suite = "ComposerAttachmentCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ComposerDraftStore(defaults: defaults, prefix: "TestDraft.")
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)

        let saved = ComposerAttachmentCoordinator(drafts: ComposerDraftCoordinator(store: store))
        _ = saved.add([
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/missing.swift"),
        ])
        saved.save(text: "keep this", for: conversation)

        let restored = ComposerAttachmentCoordinator(drafts: ComposerDraftCoordinator(store: store))
        let state = restored.restore(for: conversation) { $0.hasSuffix("a.png") }

        XCTAssertEqual(state.text, "keep this")
        XCTAssertEqual(restored.attachmentPaths, ["/tmp/a.png"])

        var latestText = "first"
        restored.scheduleSave(textProvider: { latestText }, conversationProvider: { conversation })
        latestText = "second"
        restored.scheduleSave(textProvider: { latestText }, conversationProvider: { conversation })

        let expectation = expectation(description: "draft saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(store.snapshot(for: conversation)?.text, "second")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(restored.clear(for: conversation), .empty)
        XCTAssertFalse(restored.hasAttachments)
        XCTAssertNil(store.snapshot(for: conversation))
    }

    private func testStore() -> ComposerDraftStore {
        ComposerDraftStore(
            defaults: UserDefaults(suiteName: "ComposerAttachmentCoordinatorTests.\(UUID().uuidString)")!,
            prefix: "TestDraft."
        )
    }
}

@MainActor
private final class AttachmentStripFixture {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 66))
    let stack = NSStackView()
    let height: NSLayoutConstraint
    let target = AttachmentRemoveTarget()

    init() {
        stack.orientation = .horizontal
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        height = scroll.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
    }

    var removeButtons: [NSButton] {
        stack.descendantButtons().filter { $0.action == #selector(AttachmentRemoveTarget.remove(_:)) }
    }
}

private final class AttachmentRemoveTarget: NSObject {
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
