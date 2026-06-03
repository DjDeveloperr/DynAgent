@testable import DynAgentUI
import AppKit
import XCTest

@MainActor
final class ComposerChromeTests: XCTestCase {
    func testPopupChromeMatchesComposerMenuStyle() {
        let popup = NSPopUpButton()

        ComposerChrome.configurePopup(popup)

        XCTAssertEqual(popup.controlSize, .large)
        XCTAssertEqual(popup.font, .systemFont(ofSize: 15, weight: .medium))
        XCTAssertEqual(popup.bezelStyle, .shadowlessSquare)
        XCTAssertFalse(popup.isBordered)
        XCTAssertEqual(popup.imagePosition, .imageLeft)
        XCTAssertFalse(popup.translatesAutoresizingMaskIntoConstraints)
    }

    func testSendContainerAndFooterUseStableComposerSizing() {
        let target = AttachmentRemoveTarget()
        let sendButton = NSButton()
        let spinner = NSProgressIndicator()
        let addAttachment = NSButton()
        let harnessMenu = ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 82)
        let modelMenu = ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 58)
        let reasoningMenu = ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 70)
        let contextRing = ContextRing()

        ComposerChrome.configureSendButton(sendButton, target: target, action: #selector(AttachmentRemoveTarget.remove(_:)))
        ComposerChrome.configureSpinner(spinner)
        ComposerChrome.configureAttachmentButton(addAttachment, target: target, action: #selector(AttachmentRemoveTarget.remove(_:)))
        let sendContainer = ComposerChrome.makeSendContainer(button: sendButton, spinner: spinner)
        let footer = ComposerChrome.makeFooter(
            addAttachmentButton: addAttachment,
            harnessMenu: harnessMenu,
            modelMenu: modelMenu,
            reasoningMenu: reasoningMenu,
            contextRing: contextRing,
            sendContainer: sendContainer
        )
        let constraints = ComposerChrome.footerControlConstraints(
            addAttachmentButton: addAttachment,
            sendContainer: sendContainer,
            sendButton: sendButton,
            spinner: spinner
        )
        NSLayoutConstraint.activate(constraints)

        XCTAssertEqual(sendContainer.layer?.cornerRadius, ComposerChrome.sendButtonCornerRadius)
        XCTAssertTrue(sendContainer.layer?.masksToBounds ?? false)
        XCTAssertEqual(footer.orientation, .horizontal)
        XCTAssertEqual(footer.spacing, ComposerChrome.footerSpacing)
        XCTAssertEqual(footer.arrangedSubviews.count, 8)
        XCTAssertTrue(footer.arrangedSubviews[0] === addAttachment)
        XCTAssertTrue(footer.arrangedSubviews[1] === harnessMenu)
        XCTAssertTrue(footer.arrangedSubviews[3] === modelMenu)
        XCTAssertTrue(footer.arrangedSubviews[4] === reasoningMenu)
        XCTAssertTrue(footer.arrangedSubviews[5] === contextRing)
        XCTAssertTrue(footer.arrangedSubviews[7] === sendContainer)
        XCTAssertEqual(footer.customSpacing(after: modelMenu), ComposerChrome.menuSpacing)
        XCTAssertEqual(footer.customSpacing(after: reasoningMenu), ComposerChrome.menuSpacing)
        XCTAssertTrue(constraints.contains { $0.firstAnchor == addAttachment.widthAnchor && $0.constant == ComposerChrome.attachmentButtonSize.width })
        XCTAssertTrue(constraints.contains { $0.firstAnchor == sendContainer.widthAnchor && $0.constant == ComposerChrome.sendButtonSize })
    }

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
