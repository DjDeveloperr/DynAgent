import Foundation

enum WorkDividerModel {
    static func durationText(seconds: Double?, active: Bool) -> String {
        let total = max(0, Int((seconds ?? 0).rounded()))
        let verb = active ? "Working for" : "Worked for"
        if total < 60 { return "\(verb) \(total)s" }
        return "\(verb) \(total / 60)m \(total % 60)s"
    }

    static func label(seconds: Double?, active: Bool, collapsed: Bool) -> String {
        if active { return durationText(seconds: seconds, active: true) }
        return "\(collapsed ? "▸" : "▾")  \(durationText(seconds: seconds, active: false))"
    }
}
