import AppKit

enum DesignSystem {
    struct TextStyle {
        var font: NSFont
        var color: NSColor
        var lineBreakMode: NSLineBreakMode
        var maximumNumberOfLines: Int
        var singleLine: Bool
        var horizontalCompressionResistance: NSLayoutConstraint.Priority
        var horizontalHugging: NSLayoutConstraint.Priority

        init(
            font: NSFont,
            color: NSColor = .labelColor,
            lineBreakMode: NSLineBreakMode = .byTruncatingTail,
            maximumNumberOfLines: Int = 1,
            singleLine: Bool = true,
            horizontalCompressionResistance: NSLayoutConstraint.Priority = .defaultLow,
            horizontalHugging: NSLayoutConstraint.Priority = .defaultLow
        ) {
            self.font = font
            self.color = color
            self.lineBreakMode = lineBreakMode
            self.maximumNumberOfLines = maximumNumberOfLines
            self.singleLine = singleLine
            self.horizontalCompressionResistance = horizontalCompressionResistance
            self.horizontalHugging = horizontalHugging
        }
    }

    enum Font {
        static let chatBody = NSFont.systemFont(ofSize: 15)
        static let chatBodyBold = NSFont.systemFont(ofSize: 15, weight: .semibold)
        static let controlLabel = NSFont.systemFont(ofSize: 15, weight: .medium)
        static let controlSmall = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        static let actionButton = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let emptyStateTitle = NSFont.systemFont(ofSize: 22, weight: .semibold)
        static let emptyStateSubtitle = NSFont.systemFont(ofSize: 13)
        static let overlaySearch = NSFont.systemFont(ofSize: 18, weight: .regular)
        static let overlayRowTitle = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let overlayRowDetail = NSFont.systemFont(ofSize: 11.5)
        static let inlineCode = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        static let codeBlock = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        static let sidebarSection = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        static let sidebarWorkspace = NSFont.systemFont(ofSize: 14.5, weight: .regular)
        static let sidebarEmpty = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let sidebarMore = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let chatHeaderTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let workspacePanelTitle = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let gitPanelTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let gitPanelBranch = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        static let panelStatus = NSFont.systemFont(ofSize: 11)
        static let panelBody = NSFont.systemFont(ofSize: 12)
    }

    enum Color {
        static var primaryText: NSColor { .labelColor }
        static var linkText: NSColor { .controlAccentColor }
        static var subtleFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.10) }
        static var inlineCodeFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
        static var selectedSidebarFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
        static var hoverSidebarFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.06) }
        static var attachmentFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
        static func backdrop(alpha: CGFloat) -> NSColor { NSColor.black.withAlphaComponent(alpha) }
    }

    enum Radius {
        static let sidebarRow: CGFloat = 7
        static let attachmentChip: CGFloat = 8
        static let popover: CGFloat = 12
        static let compactGlassControl: CGFloat = 13
        static let floatingPill: CGFloat = 14
        static let overlayCard: CGFloat = 18
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 10
        static let xLarge: CGFloat = 18
    }

    enum Paragraph {
        static func chatLine(empty: Bool) -> NSMutableParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = empty ? 6 : 4
            return paragraph
        }

        static func codeBlock() -> NSMutableParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 10
            return paragraph
        }
    }

    enum Text {
        static let sidebarAction = TextStyle(font: NSFont.systemFont(ofSize: 15, weight: .regular))
        static let sidebarSection = TextStyle(font: Font.sidebarSection, color: .tertiaryLabelColor)
        static let sidebarWorkspace = TextStyle(font: Font.sidebarWorkspace, color: .secondaryLabelColor)
        static let sidebarEmpty = TextStyle(font: Font.sidebarEmpty, color: .tertiaryLabelColor)
        static let sidebarMore = TextStyle(font: Font.sidebarMore, color: .tertiaryLabelColor)
        static let chatHeaderTitle = TextStyle(font: Font.chatHeaderTitle)
        static let workspacePanelTitle = TextStyle(font: Font.workspacePanelTitle, color: .secondaryLabelColor)
        static let gitPanelTitle = TextStyle(font: Font.gitPanelTitle)
        static let gitPanelBranch = TextStyle(font: Font.gitPanelBranch, color: .secondaryLabelColor)
        static let panelStatus = TextStyle(font: Font.panelStatus, color: .tertiaryLabelColor)
        static let panelBodySecondary = TextStyle(
            font: Font.panelBody,
            color: .secondaryLabelColor,
            lineBreakMode: .byWordWrapping,
            maximumNumberOfLines: 0,
            singleLine: false
        )
    }

    enum Symbol {
        static let sidebarActionPointSize: CGFloat = 15
        static let sidebarWorkspacePointSize: CGFloat = 15
        static let sidebarSectionChevronPointSize: CGFloat = 10
        static let toolbarPointSize: CGFloat = 14
    }

    static func configureLabel(_ label: NSTextField, style: TextStyle) {
        label.font = style.font
        label.textColor = style.color
        label.lineBreakMode = style.lineBreakMode
        label.maximumNumberOfLines = style.maximumNumberOfLines
        if style.singleLine {
            label.cell?.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
        }
        label.setContentCompressionResistancePriority(style.horizontalCompressionResistance, for: .horizontal)
        label.setContentHuggingPriority(style.horizontalHugging, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    static func label(_ text: String, style: TextStyle) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        configureLabel(label, style: style)
        return label
    }

    static func symbolImage(
        _ symbol: String,
        accessibilityDescription: String? = nil,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage {
        NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) ?? NSImage()
    }

    static func symbolImageView(
        _ symbol: String,
        accessibilityDescription: String? = nil,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular,
        tint: NSColor
    ) -> NSImageView {
        let imageView = NSImageView(image: symbolImage(
            symbol,
            accessibilityDescription: accessibilityDescription,
            pointSize: pointSize,
            weight: weight
        ))
        imageView.contentTintColor = tint
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }

    static func iconButton(
        symbol: String,
        accessibilityDescription: String? = nil,
        tint: NSColor? = nil,
        target: AnyObject?,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(
            image: symbolImage(
                symbol,
                accessibilityDescription: accessibilityDescription,
                pointSize: Symbol.toolbarPointSize
            ),
            target: target,
            action: action
        )
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        if let tint {
            button.contentTintColor = tint
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
