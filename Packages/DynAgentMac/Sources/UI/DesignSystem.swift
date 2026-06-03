import AppKit

enum DesignSystem {
    enum Font {
        static let chatBody = NSFont.systemFont(ofSize: 15)
        static let chatBodyBold = NSFont.systemFont(ofSize: 15, weight: .semibold)
        static let inlineCode = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        static let codeBlock = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    enum Color {
        static var primaryText: NSColor { .labelColor }
        static var linkText: NSColor { .controlAccentColor }
        static var subtleFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.10) }
        static var inlineCodeFill: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
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
