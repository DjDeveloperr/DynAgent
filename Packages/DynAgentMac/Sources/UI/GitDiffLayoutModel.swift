import Foundation

struct GitDiffHeaderInfo: Equatable {
    var path: String
    var added: Int
    var deleted: Int
    var collapsed: Bool = false
}

struct GitDiffLayoutModel: Equatable {
    static let codeRowHeight: Double = 22
    static let fileHeaderHeight: Double = 34

    private(set) var rawLines: [GitDiffLine] = []
    private(set) var lines: [GitDiffLine] = []
    private(set) var rowTops: [Double] = []
    private(set) var sections: [GitDiffSection] = []
    private(set) var collapsedPaths = Set<String>()

    init(diff: GitDiffModel = GitDiffModel(lines: [], sections: []), collapsedPaths: Set<String> = []) {
        rawLines = diff.lines
        sections = diff.sections
        self.collapsedPaths = collapsedPaths
        rebuildDisplayRows()
    }

    var documentHeight: Double {
        guard let lastTop = rowTops.last, let lastLine = lines.last else { return 80 }
        return max(80, lastTop + rowHeight(for: lastLine))
    }

    mutating func apply(_ diff: GitDiffModel) {
        rawLines = diff.lines
        sections = diff.sections
        collapsedPaths = collapsedPaths.filter { path in sections.contains { $0.path == path } }
        rebuildDisplayRows()
    }

    mutating func toggle(path: String) {
        if collapsedPaths.contains(path) { collapsedPaths.remove(path) }
        else { collapsedPaths.insert(path) }
        rebuildDisplayRows()
    }

    @discardableResult
    mutating func toggleHeaderIfNeeded(at y: Double) -> Bool {
        guard let idx = rowIndex(at: y), lines.indices.contains(idx), lines[idx].kind == "F" else { return false }
        let section = lines[idx].section
        guard sections.indices.contains(section) else { return false }
        toggle(path: sections[section].path)
        return true
    }

    func headerInfo(at y: Double) -> GitDiffHeaderInfo? {
        guard !sections.isEmpty, !lines.isEmpty else { return nil }
        let row = rowIndex(at: max(0, y)) ?? 0
        let sectionIndex = lines.indices.contains(row) ? lines[row].section : sections.indices.last ?? 0
        guard sections.indices.contains(sectionIndex) else { return nil }
        let section = sections[sectionIndex]
        guard !collapsedPaths.contains(section.path) else { return nil }
        return GitDiffHeaderInfo(
            path: section.path,
            added: section.added,
            deleted: section.deleted,
            collapsed: collapsedPaths.contains(section.path)
        )
    }

    func rowHeight(for line: GitDiffLine) -> Double {
        line.kind == "F" ? Self.fileHeaderHeight : Self.codeRowHeight
    }

    func rowIndex(at y: Double) -> Int? {
        guard !rowTops.isEmpty else { return nil }
        var low = 0
        var high = rowTops.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let top = rowTops[mid]
            let bottom = top + rowHeight(for: lines[mid])
            if y < top { high = mid - 1 }
            else if y >= bottom { low = mid + 1 }
            else { return mid }
        }
        return min(max(low, 0), rowTops.count - 1)
    }

    private mutating func rebuildDisplayRows() {
        lines = rawLines.filter { line in
            guard sections.indices.contains(line.section) else { return true }
            return line.kind == "F" || !collapsedPaths.contains(sections[line.section].path)
        }
        rowTops.removeAll(keepingCapacity: true)
        var y: Double = 0
        for line in lines {
            rowTops.append(y)
            y += rowHeight(for: line)
        }
    }
}
