@testable import DynAgentUI
import XCTest

final class ComposerSessionModelTests: XCTestCase {
    func testAddingAttachmentsNormalizesDeduplicatesAndReportsChange() {
        let existing = [
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/a.png"))
        ]

        let first = ComposerSessionModel.addingAttachments(
            [
                URL(fileURLWithPath: "/tmp/a.png"),
                URL(fileURLWithPath: "/tmp/b.swift"),
                URL(fileURLWithPath: "/tmp/b.swift"),
            ],
            to: existing
        )
        let second = ComposerSessionModel.addingAttachments(
            [URL(fileURLWithPath: "/tmp/a.png")],
            to: existing
        )

        XCTAssertTrue(first.didChange)
        XCTAssertEqual(first.attachments.map { $0.url.path }, ["/tmp/a.png", "/tmp/b.swift"])
        XCTAssertFalse(second.didChange)
        XCTAssertEqual(second.attachments, existing)
    }

    func testRemovingAttachmentReportsWhetherStateChanged() {
        let keep = ComposerAttachment(url: URL(fileURLWithPath: "/tmp/keep.swift"), id: UUID())
        let remove = ComposerAttachment(url: URL(fileURLWithPath: "/tmp/remove.swift"), id: UUID())

        let removed = ComposerSessionModel.removingAttachment(id: remove.id, from: [keep, remove])
        let missing = ComposerSessionModel.removingAttachment(id: UUID(), from: [keep])

        XCTAssertTrue(removed.didChange)
        XCTAssertEqual(removed.attachments, [keep])
        XCTAssertFalse(missing.didChange)
        XCTAssertEqual(missing.attachments, [keep])
    }

    func testRestoredStateFiltersMissingAttachmentsAndControlsPlaceholder() {
        let snapshot = ComposerDraftSnapshot(
            text: "continue this",
            attachments: ["/tmp/a.png", "/tmp/missing.swift"]
        )

        let state = ComposerSessionModel.restoredState(from: snapshot) { $0.hasSuffix("a.png") }
        let empty = ComposerSessionModel.restoredState(from: nil) { _ in true }

        XCTAssertEqual(state.text, "continue this")
        XCTAssertEqual(state.attachments.map { $0.url.path }, ["/tmp/a.png"])
        XCTAssertTrue(state.placeholderHidden)
        XCTAssertEqual(empty, .empty)
        XCTAssertFalse(empty.placeholderHidden)
    }

    func testClearedAfterSendRemovesTextAndAttachments() {
        XCTAssertEqual(ComposerSessionModel.clearedAfterSend(), .empty)
    }
}
