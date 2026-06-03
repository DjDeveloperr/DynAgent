import AppKit

struct ChatComposerLayoutConstraints {
    var bottom: NSLayoutConstraint
    var centerY: NSLayoutConstraint
    var width: NSLayoutConstraint
    var all: [NSLayoutConstraint]
}

enum ChatViewChrome {
    static let composerBottomInset: CGFloat = 16
    static let composerEmptyStateCenterYOffset: CGFloat = 88
    static let emptyStackMaxWidth: CGFloat = 440
    static let emptyStackToComposerSpacing: CGFloat = 24

    static func makeRoot(
        scroll: NSView,
        headerTitle: NSView,
        headerMenuButton: NSView,
        composerCard: NSView,
        emptyStack: NSView,
        topBorder: NSView
    ) -> FlexibleContainerView {
        let root = FlexibleContainerView()
        root.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for view in [scroll, headerTitle, headerMenuButton, composerCard, emptyStack, topBorder] {
            root.addSubview(view)
        }
        return root
    }

    static func makeTopBorder() -> NSBox {
        let topBorder = NSBox()
        topBorder.boxType = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        return topBorder
    }

    static func composerConstraints(root: NSView, card: NSView) -> ChatComposerLayoutConstraints {
        let bottom = card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -composerBottomInset)
        let centerY = card.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: composerEmptyStateCenterYOffset)
        centerY.isActive = false
        let width = card.widthAnchor.constraint(equalToConstant: ChatLayoutModel.maxReadableWidth)
        return ChatComposerLayoutConstraints(
            bottom: bottom,
            centerY: centerY,
            width: width,
            all: [
                card.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: ChatLayoutModel.horizontalInset),
                card.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -ChatLayoutModel.horizontalInset),
                card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                width,
                bottom,
            ]
        )
    }

    static func emptyStateConstraints(emptyStack: NSView, scroll: NSView, card: NSView) -> [NSLayoutConstraint] {
        [
            emptyStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStack.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -emptyStackToComposerSpacing),
            emptyStack.widthAnchor.constraint(lessThanOrEqualToConstant: emptyStackMaxWidth),
        ]
    }

    static func topBorderConstraints(topBorder: NSView, root: NSView) -> [NSLayoutConstraint] {
        [
            topBorder.topAnchor.constraint(equalTo: root.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ]
    }
}
