import AppKit
@testable import DynAgentUI
import XCTest

@MainActor
final class ChatComposerChromeTests: XCTestCase {
    func testConfigureInputWiresComposerAndScrollContainer() {
        let composer = ComposerTextView()
        let delegate = TextDelegate()
        var sent = false
        var pasted: [URL] = []

        let scroll = ChatComposerChrome.configureInput(
            composer: composer,
            delegate: delegate,
            onSend: { sent = true },
            onPasteAttachments: { pasted = $0 }
        )

        XCTAssertTrue(composer.delegate === delegate)
        XCTAssertEqual(composer.font, .systemFont(ofSize: 15))
        XCTAssertFalse(composer.drawsBackground)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertTrue(scroll.documentView === composer)
        composer.onSend?()
        composer.onPasteAttachments?([URL(fileURLWithPath: "/tmp/a.png")])
        XCTAssertTrue(sent)
        XCTAssertEqual(pasted.map(\.path), ["/tmp/a.png"])
    }

    func testConfigureMenusUsesExpectedItemsTargetsAndChrome() {
        let target = Target()
        let harnessPopup = NSPopUpButton()
        let modelPopup = NSPopUpButton()
        let reasoningPopup = NSPopUpButton()

        let menus = ChatComposerChrome.configureMenus(
            harnessPopup: harnessPopup,
            modelPopup: modelPopup,
            reasoningPopup: reasoningPopup,
            target: target,
            harnessAction: #selector(Target.harnessChanged),
            menuAction: #selector(Target.menuChanged)
        )

        XCTAssertEqual(harnessPopup.itemTitles, Harness.allCases.map(\.rawValue))
        XCTAssertTrue(harnessPopup.target === target)
        XCTAssertEqual(harnessPopup.action, #selector(Target.harnessChanged))
        XCTAssertTrue(modelPopup.target === target)
        XCTAssertEqual(modelPopup.action, #selector(Target.menuChanged))
        XCTAssertEqual(reasoningPopup.itemTitles, ["high", "medium", "low", "xhigh"])
        XCTAssertEqual(reasoningPopup.titleOfSelectedItem, "high")
        XCTAssertTrue(reasoningPopup.target === target)
        XCTAssertEqual(reasoningPopup.action, #selector(Target.menuChanged))
        XCTAssertTrue(menus.harness.popup === harnessPopup)
        XCTAssertTrue(menus.model.popup === modelPopup)
        XCTAssertTrue(menus.reasoning.popup === reasoningPopup)
    }

    func testConfigureFooterReturnsStableFooterAndActionTargets() {
        let target = Target()
        let menus = ChatComposerMenus(
            harness: ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 82),
            model: ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 58),
            reasoning: ComposerMenuChrome(popup: NSPopUpButton(), minWidth: 70)
        )
        let spinner = NSProgressIndicator()
        let sendButton = NSButton()
        let addAttachmentButton = NSButton()
        let contextRing = ContextRing()

        let footer = ChatComposerChrome.configureFooter(
            spinner: spinner,
            sendButton: sendButton,
            addAttachmentButton: addAttachmentButton,
            menus: menus,
            contextRing: contextRing,
            target: target,
            sendAction: #selector(Target.send),
            addAttachmentAction: #selector(Target.addAttachment)
        )

        XCTAssertTrue(sendButton.target === target)
        XCTAssertEqual(sendButton.action, #selector(Target.send))
        XCTAssertTrue(addAttachmentButton.target === target)
        XCTAssertEqual(addAttachmentButton.action, #selector(Target.addAttachment))
        XCTAssertEqual(footer.sendContainer.layer?.cornerRadius, ComposerChrome.sendButtonCornerRadius)
        XCTAssertTrue(footer.footer.arrangedSubviews.contains(contextRing))
        XCTAssertTrue(footer.footer.arrangedSubviews.contains(footer.sendContainer))
    }

    func testInstallSurfaceCreatesAttachmentHeightAndComposerSurfaceConstraints() {
        let card = NSGlassEffectView()
        let content = NSView()
        let composerScroll = NSScrollView()
        composerScroll.translatesAutoresizingMaskIntoConstraints = false
        let placeholder = NSTextField(labelWithString: "")
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        let attachmentScroll = NSScrollView()
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let surface = ChatComposerChrome.installSurface(
            card: card,
            content: content,
            composerScroll: composerScroll,
            placeholder: placeholder,
            attachmentScroll: attachmentScroll,
            footer: footer
        )

        XCTAssertEqual(surface.attachmentHeight.constant, 0)
        XCTAssertTrue(surface.constraints.contains { $0 === surface.attachmentHeight })
        XCTAssertEqual(card.cornerRadius, ComposerSurfaceChrome.cornerRadius)
        XCTAssertTrue(card.contentView === content)
        XCTAssertTrue(content.subviews.contains(composerScroll))
        XCTAssertTrue(content.subviews.contains(placeholder))
        XCTAssertTrue(content.subviews.contains(attachmentScroll))
        XCTAssertTrue(content.subviews.contains(footer))
    }
}

private final class TextDelegate: NSObject, NSTextViewDelegate {}

private final class Target: NSObject {
    @objc func harnessChanged() {}
    @objc func menuChanged() {}
    @objc func send() {}
    @objc func addAttachment() {}
}
