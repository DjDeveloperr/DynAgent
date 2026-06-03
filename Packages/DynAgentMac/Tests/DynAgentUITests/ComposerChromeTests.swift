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

    func testApplyMenuStateRefreshesMenusAndUpdatesVisibility() {
        let placeholder = NSTextField(labelWithString: "")
        let harnessMenu = ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 82)
        let modelMenu = ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 58)
        let reasoningMenu = ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 70)

        ComposerChrome.applyMenuState(
            ComposerMenuState(
                placeholder: "Ask Codex",
                showsHarnessMenu: false,
                showsReasoningMenu: false
            ),
            placeholder: placeholder,
            harnessMenu: harnessMenu,
            modelMenu: modelMenu,
            reasoningMenu: reasoningMenu
        )

        XCTAssertEqual(placeholder.stringValue, "Ask Codex")
        XCTAssertTrue(harnessMenu.isHidden)
        XCTAssertTrue(reasoningMenu.isHidden)

        ComposerChrome.applyMenuState(
            ComposerMenuState(
                placeholder: "Ask DynAgent",
                showsHarnessMenu: true,
                showsReasoningMenu: true
            ),
            placeholder: placeholder,
            harnessMenu: harnessMenu,
            modelMenu: modelMenu,
            reasoningMenu: reasoningMenu
        )

        XCTAssertEqual(placeholder.stringValue, "Ask DynAgent")
        XCTAssertFalse(harnessMenu.isHidden)
        XCTAssertFalse(modelMenu.isHidden)
        XCTAssertFalse(reasoningMenu.isHidden)
    }

    func testApplySendStateUsesComposerSendIconAndTint() {
        let button = NSButton()

        ComposerChrome.applySendState(
            ComposerSendState(symbol: "stop.fill", accessibilityDescription: "Stop", isStop: true),
            to: button
        )

        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.image?.accessibilityDescription, "Stop")
        XCTAssertEqual(button.contentTintColor, .black)

        ComposerChrome.applySendState(
            ComposerSendState(symbol: "arrow.up", accessibilityDescription: "Send", isStop: false),
            to: button
        )

        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.image?.accessibilityDescription, "Send")
        XCTAssertEqual(button.contentTintColor, .black)
    }

    func testCodexMenuTitleUsesPrimaryModelAndSecondaryEffortText() {
        let title = ComposerChrome.codexMenuTitle(model: "gpt-5.5-codex", effort: "xhigh")

        XCTAssertEqual(title.string, "5.5 Codex Extra High")
        let modelColor = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let effortColor = title.attribute(.foregroundColor, at: "5.5 Codex ".count, effectiveRange: nil) as? NSColor
        XCTAssertEqual(modelColor, NSColor.labelColor)
        XCTAssertEqual(effortColor, NSColor.secondaryLabelColor)
    }

    func testCodexNestedMenuBuildsModelAndReasoningSubmenus() throws {
        let target = AttachmentRemoveTarget()
        let model = ComposerCodexMenuModel(
            selectedModel: "gpt-5.5",
            modelItems: [
                ComposerMenuItemModel(title: "5.5", representedValue: "gpt-5.5", isSelected: true),
                ComposerMenuItemModel(title: "5.5 Mini", representedValue: "gpt-5.5-mini", isSelected: false),
            ],
            effortItems: [
                ComposerMenuItemModel(title: "High", representedValue: "high", isSelected: false),
                ComposerMenuItemModel(title: "Extra High", representedValue: "xhigh", isSelected: true),
            ]
        )

        let menu = ComposerChrome.codexNestedMenu(
            model: model,
            target: target,
            modelAction: #selector(AttachmentRemoveTarget.remove(_:)),
            effortAction: #selector(AttachmentRemoveTarget.remove(_:))
        )

        XCTAssertEqual(menu.items.map(\.title), ["Model", "Reasoning"])
        let modelMenu = try XCTUnwrap(menu.item(at: 0)?.submenu)
        let effortMenu = try XCTUnwrap(menu.item(at: 1)?.submenu)
        XCTAssertEqual(modelMenu.items.map(\.title), ["5.5", "5.5 Mini"])
        XCTAssertEqual(effortMenu.items.map(\.title), ["High", "Extra High"])
        XCTAssertTrue((modelMenu.item(at: 0)?.target as AnyObject?) === target)
        XCTAssertEqual(modelMenu.item(at: 0)?.representedObject as? String, "gpt-5.5")
        XCTAssertEqual(modelMenu.item(at: 0)?.state, .on)
        XCTAssertEqual(modelMenu.item(at: 1)?.state, .off)
        XCTAssertEqual(effortMenu.item(at: 1)?.representedObject as? String, "xhigh")
        XCTAssertEqual(effortMenu.item(at: 1)?.state, .on)
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
