import Foundation

struct GitDiffLine: Equatable {
    var old: Int?
    var new: Int?
    var text: String
    var kind: Character
    var section: Int
}

struct GitDiffSection: Equatable {
    var path: String
    var added: Int
    var deleted: Int
    var startRow: Int
}

struct GitDiffModel: Equatable {
    var lines: [GitDiffLine]
    var sections: [GitDiffSection]

    static func parse(_ diff: String) -> GitDiffModel {
        var lines: [GitDiffLine] = []
        var sections: [GitDiffSection] = []
        guard !diff.isEmpty else { return GitDiffModel(lines: [], sections: []) }

        var oldLine = 0
        var newLine = 0
        var sectionIndex: Int?
        var added = 0
        var deleted = 0

        func finishSection() {
            guard let index = sectionIndex, sections.indices.contains(index) else { return }
            sections[index].added = added
            sections[index].deleted = deleted
        }

        func startSection(_ path: String, appendHeader: Bool) {
            finishSection()
            oldLine = 0
            newLine = 0
            added = 0
            deleted = 0
            sections.append(GitDiffSection(path: path, added: 0, deleted: 0, startRow: lines.count))
            sectionIndex = sections.count - 1
            if appendHeader, let index = sectionIndex {
                lines.append(GitDiffLine(old: nil, new: nil, text: (path as NSString).lastPathComponent, kind: "F", section: index))
            }
        }

        func ensureDefaultSection() {
            if sectionIndex == nil { startSection("Changes", appendHeader: false) }
        }

        for raw in diff.components(separatedBy: .newlines) {
            if raw.hasPrefix("diff --git") {
                let path = raw.split(separator: " ").last
                    .map { String($0).replacingOccurrences(of: "b/", with: "") } ?? "Changes"
                startSection(path, appendHeader: true)
                continue
            }

            if raw.hasPrefix("+++") || raw.hasPrefix("---") || raw.hasPrefix("index ") { continue }
            if isMetadataLine(raw) { continue }
            ensureDefaultSection()
            guard let currentSection = sectionIndex else { continue }

            if raw.hasPrefix("@@") {
                let previousOld = oldLine
                let previousNew = newLine
                var nextOld = oldLine
                var nextNew = newLine
                if let starts = hunkStarts(in: raw) {
                    nextOld = starts.old
                    nextNew = starts.new
                }
                if previousOld > 0 || previousNew > 0 {
                    let skippedOld = max(0, nextOld - previousOld)
                    let skippedNew = max(0, nextNew - previousNew)
                    let skipped = max(skippedOld, skippedNew)
                    if skipped > 0 {
                        let label = skipped == 1 ? "1 unmodified line" : "\(skipped) unmodified lines"
                        lines.append(GitDiffLine(old: nil, new: nil, text: label, kind: "S", section: currentSection))
                    }
                }
                oldLine = nextOld
                newLine = nextNew
                continue
            }

            let kind: Character
            let text: String
            let old: Int?
            let new: Int?
            if raw.hasPrefix("+") {
                kind = "+"
                text = String(raw.dropFirst())
                old = nil
                new = newLine
                newLine += 1
                added += 1
            } else if raw.hasPrefix("-") {
                kind = "-"
                text = String(raw.dropFirst())
                old = oldLine
                new = nil
                oldLine += 1
                deleted += 1
            } else {
                kind = " "
                text = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
                old = oldLine > 0 ? oldLine : nil
                new = newLine > 0 ? newLine : nil
                if oldLine > 0 { oldLine += 1 }
                if newLine > 0 { newLine += 1 }
            }
            lines.append(GitDiffLine(old: old, new: new, text: text, kind: kind, section: currentSection))
        }

        finishSection()
        return GitDiffModel(lines: lines, sections: sections)
    }

    private static func isMetadataLine(_ line: String) -> Bool {
        line.hasPrefix("deleted file mode")
            || line.hasPrefix("new file mode")
            || line.hasPrefix("old mode")
            || line.hasPrefix("new mode")
            || line.hasPrefix("similarity index")
            || line.hasPrefix("rename from")
            || line.hasPrefix("rename to")
    }

    private static func hunkStarts(in line: String) -> (old: Int, new: Int)? {
        guard let re = try? NSRegularExpression(pattern: #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)?"#) else { return nil }
        let ns = line as NSString
        guard let match = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else { return nil }
        let old = Int(ns.substring(with: match.range(at: 1)))
        let new = Int(ns.substring(with: match.range(at: 2)))
        guard let old, let new else { return nil }
        return (old, new)
    }
}

enum GitDiffParser {
    static func parse(_ diff: String) -> GitDiffModel {
        GitDiffModel.parse(diff)
    }
}
