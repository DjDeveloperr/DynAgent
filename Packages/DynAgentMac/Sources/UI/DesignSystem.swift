import AppKit

enum DesignSystem {
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
}
