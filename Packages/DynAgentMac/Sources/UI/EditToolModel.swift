import Foundation

struct EditToolChange: Equatable {
    var path: String
    var added: Int
    var deleted: Int
    var diff: String
}

struct EditToolSummary: Equatable {
    var status: String
    var changes: [EditToolChange]

    var added: Int { changes.reduce(0) { $0 + $1.added } }
    var deleted: Int { changes.reduce(0) { $0 + $1.deleted } }
}

enum EditToolModel {
    static func summary(from detail: String?, done: Bool) -> EditToolSummary {
        guard let detail, !detail.isEmpty else {
            return EditToolSummary(status: done ? "completed" : "running", changes: [])
        }

        if let json = jsonObject(from: detail) {
            var changes = (json["changes"] as? [[String: Any]] ?? []).compactMap(change(from:))
            if changes.isEmpty, let change = change(from: json) {
                changes.append(change)
            }
            return EditToolSummary(status: json["status"] as? String ?? (done ? "completed" : "running"),
                                   changes: changes)
        }

        let changes = fallbackPaths(from: detail).map {
            EditToolChange(path: $0, added: 0, deleted: 0, diff: "")
        }
        return EditToolSummary(status: done ? "completed" : "running", changes: changes)
    }

    static func title(done: Bool, changeCount count: Int) -> String {
        if count > 0 {
            let noun = "file" + (count == 1 ? "" : "s")
            return done ? "Edited \(count) \(noun)" : "Editing \(count) \(noun)"
        }
        return done ? "Edited files" : "Editing files"
    }

    static func fallbackPaths(from detail: String) -> [String] {
        if let json = jsonObject(from: detail) {
            let changes = (json["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            if !changes.isEmpty { return changes }
            if let path = json["path"] as? String { return [path] }
            return []
        }

        let afterStatus = detail.split(separator: ":", maxSplits: 1).last.map(String.init) ?? detail
        let ignored = Set(["completed", "complete", "running", "done", "success", "failed"])
        return afterStatus.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                guard !value.isEmpty else { return false }
                if ignored.contains(value.lowercased()) { return false }
                return value.contains("/") || value.contains(".")
            }
    }

    static func jsonObject(from detail: String) -> [String: Any]? {
        let chunks = detail.components(separatedBy: "\n\n")
        for chunk in chunks.reversed() {
            guard let start = chunk.firstIndex(of: "{") else { continue }
            let candidate = String(chunk[start...])
            if let json = decodeObject(candidate) { return json }
        }
        return decodeObject(detail)
    }

    private static func change(from item: [String: Any]) -> EditToolChange? {
        guard let path = item["path"] as? String else { return nil }
        return EditToolChange(
            path: path,
            added: int(item["added"]) ?? int(item["additions"]) ?? 0,
            deleted: int(item["deleted"]) ?? int(item["deletions"]) ?? 0,
            diff: item["diff"] as? String ?? ""
        )
    }

    private static func decodeObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let double as Double: return Int(double)
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }
}
