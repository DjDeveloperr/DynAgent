@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class ComposerChromeTests: XCTestCase {
    func testAttachmentStripHidesAndClearsWhenEmpty() {
        let fixture = AttachmentStripFixture()
        fixture.stack.addArrangedSubview(NSView())

        let removeIds = ComposerAttachmentStripChrome.render(
            attachments: [],
            into: fixture.stack,
            inside: fixture.scroll,
            heightConstraint: fixture.height,
            target: fixture.target,
            removeAction: #selector(AttachmentRemoveTarget.remove(_:))
        )

        XCTAssertTrue(removeIds.isEmpty)
        XCTAssertTrue(fixture.stack.isHidden)
        XCTAssertTrue(fixture.scroll.isHidden)
        XCTAssertEqual(fixture.height.constant, 0)
        XCTAssertEqual(fixture.stack.arrangedSubviews.count, 0)
    }

    func testAttachmentStripRendersChipsAndRemoveMappings() {
        let fixture = AttachmentStripFixture()
        let attachments = [
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/App.swift")),
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/Notes.md")),
        ]

        let removeIds = ComposerAttachmentStripChrome.render(
            attachments: attachments,
            into: fixture.stack,
            inside: fixture.scroll,
            heightConstraint: fixture.height,
            target: fixture.target,
            removeAction: #selector(AttachmentRemoveTarget.remove(_:))
        )

        XCTAssertFalse(fixture.stack.isHidden)
        XCTAssertFalse(fixture.scroll.isHidden)
        XCTAssertEqual(fixture.height.constant, ComposerAttachmentStripChrome.visibleHeight)
        XCTAssertEqual(fixture.stack.arrangedSubviews.count, 2)
        XCTAssertEqual(Set(removeIds.values), Set(attachments.map(\.id)))
        XCTAssertGreaterThanOrEqual(fixture.stack.frame.width, fixture.scroll.contentView.bounds.width)
        XCTAssertGreaterThanOrEqual(fixture.stack.frame.height, ComposerAttachmentStripChrome.visibleHeight)
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
}

private final class AttachmentRemoveTarget: NSObject {
    @objc func remove(_ sender: NSButton) {}
}
