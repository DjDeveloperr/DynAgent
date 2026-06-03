import AppKit

struct ChatComposerMenus {
    var harness: ComposerMenuChrome
    var model: ComposerMenuChrome
    var reasoning: ComposerMenuChrome
}

struct ChatComposerFooterChrome {
    var sendContainer: NSView
    var footer: NSStackView
}

struct ChatComposerSurfaceChrome {
    var attachmentHeight: NSLayoutConstraint
    var constraints: [NSLayoutConstraint]
}

enum ChatComposerChrome {
    static func configureInput(
        composer: ComposerTextView,
        delegate: NSTextViewDelegate,
        onSend: @escaping () -> Void,
        onPasteAttachments: @escaping ([URL]) -> Void
    ) -> NSScrollView {
        composer.delegate = delegate
        composer.onSend = onSend
        composer.onPasteAttachments = onPasteAttachments
        ComposerChrome.configureTextView(composer)
        return ComposerSurfaceChrome.makeComposerScroll(containing: composer)
    }

    static func configureMenus(
        harnessPopup: NSPopUpButton,
        modelPopup: NSPopUpButton,
        reasoningPopup: NSPopUpButton,
        target: AnyObject,
        harnessAction: Selector,
        menuAction: Selector
    ) -> ChatComposerMenus {
        ComposerChrome.configurePopup(harnessPopup)
        harnessPopup.addItems(withTitles: Harness.allCases.map(\.rawValue))
        harnessPopup.target = target
        harnessPopup.action = harnessAction

        ComposerChrome.configurePopup(modelPopup)
        modelPopup.target = target
        modelPopup.action = menuAction

        ComposerChrome.configurePopup(reasoningPopup)
        reasoningPopup.addItems(withTitles: ["high", "medium", "low", "xhigh"])
        reasoningPopup.selectItem(withTitle: "high")
        reasoningPopup.target = target
        reasoningPopup.action = menuAction

        return ChatComposerMenus(
            harness: ComposerMenuChrome(popup: harnessPopup, minWidth: 82),
            model: ComposerMenuChrome(popup: modelPopup, minWidth: 58),
            reasoning: ComposerMenuChrome(popup: reasoningPopup, minWidth: 70)
        )
    }

    static func configureFooter(
        spinner: NSProgressIndicator,
        sendButton: NSButton,
        addAttachmentButton: NSButton,
        menus: ChatComposerMenus,
        contextRing: ContextRing,
        target: AnyObject,
        sendAction: Selector,
        addAttachmentAction: Selector
    ) -> ChatComposerFooterChrome {
        ComposerChrome.configureSpinner(spinner)
        ComposerChrome.configureSendButton(sendButton, target: target, action: sendAction)
        ComposerChrome.configureAttachmentButton(addAttachmentButton, target: target, action: addAttachmentAction)
        let sendContainer = ComposerChrome.makeSendContainer(button: sendButton, spinner: spinner)
        let footer = ComposerChrome.makeFooter(
            addAttachmentButton: addAttachmentButton,
            harnessMenu: menus.harness,
            modelMenu: menus.model,
            reasoningMenu: menus.reasoning,
            contextRing: contextRing,
            sendContainer: sendContainer
        )
        return ChatComposerFooterChrome(sendContainer: sendContainer, footer: footer)
    }

    static func installSurface(
        card: NSGlassEffectView,
        content: NSView,
        composerScroll: NSScrollView,
        placeholder: NSTextField,
        attachmentScroll: NSScrollView,
        footer: NSView
    ) -> ChatComposerSurfaceChrome {
        let attachmentHeight = attachmentScroll.heightAnchor.constraint(equalToConstant: 0)
        return ChatComposerSurfaceChrome(
            attachmentHeight: attachmentHeight,
            constraints: ComposerSurfaceChrome.install(
                card: card,
                content: content,
                composerScroll: composerScroll,
                placeholder: placeholder,
                attachmentScroll: attachmentScroll,
                footer: footer,
                attachmentHeightConstraint: attachmentHeight
            )
        )
    }
}
