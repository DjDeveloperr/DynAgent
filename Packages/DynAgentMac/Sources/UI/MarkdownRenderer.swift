import AppKit

enum MarkdownRenderer {
    /// Full Markdown rendering with a consistent base font.
    static func render(_ source: String) -> NSAttributedString {
        renderMarkdown(renderDirectives(source))
    }

    /// Turn `::git-push{cwd="x" branch="main"}` into a clean inline-code token.
    private static func renderDirectives(_ source: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "::([\\w-]+)\\{([^}]*)\\}") else { return source }
        let ns = source as NSString
        let out = NSMutableString(string: source)
        for match in re.matches(in: source, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: match.range(at: 1))
            let args = ns.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "  ", with: " ")
                .replacingOccurrences(of: " ", with: " - ")
            let token = args.isEmpty ? "`action \(name)`" : "`action \(name) - \(args)`"
            out.replaceCharacters(in: match.range, with: token)
        }
        return out as String
    }

    private static func renderMarkdown(_ source: String) -> NSAttributedString {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let out = NSMutableAttributedString()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inFence = false
        var codeBuffer: [String] = []

        func appendCodeBlock(_ lines: [String]) {
            guard !lines.isEmpty else { return }
            let text = lines.joined(separator: "\n")
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 10
            let block = NSMutableAttributedString(string: text + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.10),
                .paragraphStyle: paragraph,
            ])
            out.append(block)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    appendCodeBlock(codeBuffer)
                    codeBuffer.removeAll()
                    inFence = false
                } else {
                    inFence = true
                }
                continue
            }
            if inFence {
                codeBuffer.append(line)
                continue
            }

            let renderedLine: NSAttributedString
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = trimmed.isEmpty ? 6 : 4
            if let match = line.range(of: #"^\s*[-*]\s+(.+)$"#, options: .regularExpression) {
                let text = String(line[match])
                let body = text.replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "", options: .regularExpression)
                paragraph.firstLineHeadIndent = 0
                paragraph.headIndent = 18
                renderedLine = inlineMarkdown("• " + body, paragraph: paragraph)
            } else if let match = line.range(of: #"^\s*\d+\.\s+(.+)$"#, options: .regularExpression) {
                let text = String(line[match])
                paragraph.firstLineHeadIndent = 0
                paragraph.headIndent = 22
                renderedLine = inlineMarkdown(text.trimmingCharacters(in: .whitespaces), paragraph: paragraph)
            } else {
                renderedLine = inlineMarkdown(line, paragraph: paragraph)
            }
            out.append(renderedLine)
            out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
        }
        if inFence { appendCodeBlock(codeBuffer) }
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    private static func inlineMarkdown(_ text: String, paragraph: NSParagraphStyle) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 15)
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        replaceInlineGroups(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#, in: out) { groups in
            let title = groups.first ?? ""
            let target = groups.dropFirst().first ?? ""
            var attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.controlAccentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraph,
            ]
            if let url = URL(string: target) { attrs[.link] = url }
            return NSAttributedString(string: title, attributes: attrs)
        }
        replaceInline(pattern: #"`([^`\n]+)`"#, in: out) { inner in
            NSAttributedString(string: inner, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
                .paragraphStyle: paragraph,
            ])
        }
        replaceInline(pattern: #"\*\*([^*\n]+)\*\*"#, in: out) { inner in
            NSAttributedString(string: inner, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
        }
        replaceInline(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: out) { inner in
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            return NSAttributedString(string: inner, attributes: [
                .font: italic,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
        }
        return out
    }

    private static func replaceInline(pattern: String, in text: NSMutableAttributedString, replacement: (String) -> NSAttributedString) {
        replaceInlineGroups(pattern: pattern, in: text) { groups in replacement(groups.first ?? "") }
    }

    private static func replaceInlineGroups(pattern: String, in text: NSMutableAttributedString, replacement: ([String]) -> NSAttributedString) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let source = text.string as NSString
        let full = NSRange(location: 0, length: source.length)
        for match in re.matches(in: text.string, range: full).reversed() {
            let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return source.substring(with: range)
            }
            text.replaceCharacters(in: match.range, with: replacement(groups))
        }
    }
}
