import AppKit

enum TranscriptToolFormatter {
    static func shellSummary(_ message: ChatMessage) -> ShellToolSummary {
        ShellToolModel.summary(from: message.toolDetail)
    }

    static func editSummary(_ message: ChatMessage) -> EditToolSummary {
        EditToolModel.summary(from: message.toolDetail, done: message.toolDone)
    }

    static func shellTitle(_ message: ChatMessage, summary: ShellToolSummary) -> NSAttributedString {
        let command = summary.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = ShellToolModel.title(command: command, done: message.toolDone)
        let title = NSMutableAttributedString(string: parts.action, attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        if let detail = parts.detail, !detail.isEmpty {
            title.append(NSAttributedString(string: "  \(detail)", attributes: [
                .font: parts.monospacedDetail
                    ? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
                    : NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return title
    }

    static func shellGroupTitle(_ summaries: [ShellToolSummary]) -> NSAttributedString {
        let parts = summaries.map { ShellToolModel.title(command: $0.command, done: true) }
        let commonCategory = parts.first?.category
        let sameCategory = commonCategory != nil && parts.allSatisfy { $0.category == commonCategory }
        let text: String
        switch sameCategory ? commonCategory : nil {
        case "read": text = summaries.count == 1 ? "Read file" : "Read \(summaries.count) files"
        case "search": text = summaries.count == 1 ? "Searched files" : "Searched \(summaries.count) times"
        case "list": text = "Listed files"
        case "diff": text = summaries.count == 1 ? "Read diff" : "Read diffs"
        case "git": text = summaries.count == 1 ? "Ran git" : "Ran \(summaries.count) git commands"
        default: text = summaries.count == 1 ? "Ran command" : "Ran \(summaries.count) commands"
        }
        let title = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let details = parts.compactMap(\.detail)
        if summaries.count == 1, let detail = details.first, !detail.isEmpty {
            title.append(NSAttributedString(string: "  \(detail)", attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        } else if summaries.count > 1, let first = details.first, !first.isEmpty {
            title.append(NSAttributedString(string: "  \(first) +\(summaries.count - 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return title
    }

    static func toolString(_ message: ChatMessage) -> NSAttributedString {
        if message.toolName == "edit" { return editToolString(message) }
        let out = NSMutableAttributedString(
            string: toolTitle(message),
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        let preview = toolPreview(message)
        if !preview.isEmpty {
            out.append(NSAttributedString(string: "\n\(preview)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return out
    }

    static func toolIconName(_ name: String?) -> String {
        switch name {
        case "shell": return "terminal"
        case "edit": return "pencil"
        case "web_search": return "magnifyingglass"
        default: return "hammer"
        }
    }

    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private static func editToolString(_ message: ChatMessage) -> NSAttributedString {
        NSMutableAttributedString(string: editTitle(message), attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private static func toolTitle(_ message: ChatMessage) -> String {
        switch message.toolName {
        case "shell": return message.toolDone ? "Ran command" : "Running command"
        case "edit": return editTitle(message)
        case "web_search": return message.toolDone ? "Searched web" : "Searching web"
        default:
            let name = (message.toolName ?? "tool").replacingOccurrences(of: "_", with: " ")
            return (message.toolDone ? "Completed " : "Running ") + name
        }
    }

    private static func editTitle(_ message: ChatMessage) -> String {
        let count = editSummary(message).changes.count
        return EditToolModel.title(done: message.toolDone, changeCount: count)
    }

    private static func toolPreview(_ message: ChatMessage) -> String {
        guard let detail = message.toolDetail, !detail.isEmpty else {
            return message.toolDone ? "Finished" : "In progress"
        }
        if message.toolName == "shell" {
            let lines = detail.components(separatedBy: .newlines)
            let command = lines.first?.replacingOccurrences(of: "$ ", with: "") ?? detail
            let exit = lines.dropFirst().first(where: { $0.hasPrefix("exit ") })
            let output = lines.dropFirst().dropFirst()
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(2)
                .joined(separator: "\n")
            return ([command, exit, output].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }).joined(separator: "\n")
        }
        if message.toolName == "edit" {
            let paths = editSummary(message).changes.map(\.path)
            if !paths.isEmpty {
                let names = paths.prefix(3).map { fileName($0) }
                return names.joined(separator: ", ")
            }
        }
        let clean = detail.replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > 260 ? String(clean.prefix(260)) + "..." : clean
    }
}
