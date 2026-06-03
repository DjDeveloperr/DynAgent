import XCTest
@testable import DynAgentUI

final class GitPanelModelTests: XCTestCase {
    func testStatusPresentationFormatsCleanStatus() {
        let presentation = GitPanelModel.statusPresentation(GitStatusInput(
            branch: "main",
            fileCount: 2,
            diff: "diff --git",
            error: nil
        ))

        XCTAssertEqual(presentation.branchLabel, "main")
        XCTAssertEqual(presentation.diff, "diff --git")
        XCTAssertEqual(presentation.statusLabel, "2 changed files")
        XCTAssertFalse(presentation.hidesPR)
    }

    func testStatusPresentationHandlesErrorAndSingularFileCount() {
        let error = GitPanelModel.statusPresentation(GitStatusInput(
            branch: "main",
            fileCount: 1,
            diff: "ignored",
            error: "not a git repo"
        ))

        XCTAssertEqual(error.branchLabel, "not a git repo")
        XCTAssertEqual(error.diff, "")
        XCTAssertEqual(error.statusLabel, "")
        XCTAssertTrue(error.hidesPR)

        let single = GitPanelModel.statusPresentation(GitStatusInput(
            branch: nil,
            fileCount: 1,
            diff: nil,
            error: nil
        ))
        XCTAssertEqual(single.branchLabel, "—")
        XCTAssertEqual(single.statusLabel, "1 changed file")
    }

    func testPRPresentationHidesMissingOrNonePRs() {
        XCTAssertTrue(GitPanelModel.prPresentation(nil).isHidden)
        XCTAssertTrue(GitPanelModel.prPresentation(GitPRInput(
            number: nil,
            title: nil,
            state: nil,
            url: nil,
            additions: nil,
            deletions: nil,
            reviewDecision: nil,
            none: true
        )).isHidden)
    }

    func testPRPresentationFormatsVisiblePR() {
        let presentation = GitPanelModel.prPresentation(GitPRInput(
            number: 12,
            title: "Polish git panel",
            state: "OPEN",
            url: "https://example.com/pr/12",
            additions: 10,
            deletions: 3,
            reviewDecision: "APPROVED",
            none: false
        ))

        XCTAssertFalse(presentation.isHidden)
        XCTAssertEqual(
            presentation.label,
            "PR #12: Polish git panel\nOPEN | APPROVED | +10 -3\nhttps://example.com/pr/12"
        )
    }
}
