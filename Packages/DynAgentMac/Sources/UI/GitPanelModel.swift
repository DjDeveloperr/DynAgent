import Foundation

struct GitStatusInput: Equatable {
    var branch: String?
    var fileCount: Int
    var diff: String?
    var error: String?
}

struct GitStatusPresentation: Equatable {
    var branchLabel: String
    var diff: String
    var statusLabel: String
    var hidesPR: Bool
}

struct GitPRInput: Equatable {
    var number: Int?
    var title: String?
    var state: String?
    var url: String?
    var additions: Int?
    var deletions: Int?
    var reviewDecision: String?
    var none: Bool?
}

struct GitPRPresentation: Equatable {
    var label: String
    var isHidden: Bool
}

enum GitPanelModel {
    static func statusPresentation(_ input: GitStatusInput) -> GitStatusPresentation {
        if let error = input.error, !error.isEmpty {
            return GitStatusPresentation(
                branchLabel: error,
                diff: "",
                statusLabel: "",
                hidesPR: true
            )
        }

        let fileCount = max(0, input.fileCount)
        return GitStatusPresentation(
            branchLabel: input.branch ?? "—",
            diff: input.diff ?? "",
            statusLabel: fileCount == 0 ? "" : "\(fileCount) changed file\(fileCount == 1 ? "" : "s")",
            hidesPR: false
        )
    }

    static func prPresentation(_ input: GitPRInput?) -> GitPRPresentation {
        guard let input, input.none != true else {
            return GitPRPresentation(label: "", isHidden: true)
        }
        guard let title = input.title, let url = input.url else {
            return GitPRPresentation(label: "", isHidden: true)
        }

        let label = [
            "PR #\(input.number ?? 0): \(title)",
            "\(input.state ?? "?") | \(input.reviewDecision ?? "PENDING") | +\(input.additions ?? 0) -\(input.deletions ?? 0)",
            url,
        ].joined(separator: "\n")
        return GitPRPresentation(label: label, isHidden: false)
    }
}
