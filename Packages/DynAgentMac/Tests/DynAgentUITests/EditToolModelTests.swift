import XCTest
@testable import DynAgentUI

final class EditToolModelTests: XCTestCase {
    func testParsesChangesArrayJSON() {
        let detail = """
        running

        {"status":"running","changes":[{"path":"/tmp/App.swift","added":6,"deleted":4,"diff":"@@ -1 +1 @@"}]}
        """

        let summary = EditToolModel.summary(from: detail, done: false)

        XCTAssertEqual(summary.status, "running")
        XCTAssertEqual(summary.added, 6)
        XCTAssertEqual(summary.deleted, 4)
        XCTAssertEqual(summary.changes, [
            EditToolChange(path: "/tmp/App.swift", added: 6, deleted: 4, diff: "@@ -1 +1 @@")
        ])
    }

    func testParsesSingleFileJSONWithAdditionAliases() {
        let detail = #"{"path":"/tmp/ViewController.swift","additions":2,"deletions":1,"diff":"diff text"}"#

        let summary = EditToolModel.summary(from: detail, done: true)

        XCTAssertEqual(summary.status, "completed")
        XCTAssertEqual(summary.changes, [
            EditToolChange(path: "/tmp/ViewController.swift", added: 2, deleted: 1, diff: "diff text")
        ])
    }

    func testFallsBackToPathListAndIgnoresStatuses() {
        let detail = "completed: completed, /tmp/A.swift, done, Sources/B.swift"

        let summary = EditToolModel.summary(from: detail, done: true)

        XCTAssertEqual(summary.changes.map(\.path), ["/tmp/A.swift", "Sources/B.swift"])
        XCTAssertEqual(summary.added, 0)
        XCTAssertEqual(summary.deleted, 0)
    }

    func testTitlesUseDoneAndCounts() {
        XCTAssertEqual(EditToolModel.title(done: false, changeCount: 1), "Editing 1 file")
        XCTAssertEqual(EditToolModel.title(done: true, changeCount: 2), "Edited 2 files")
        XCTAssertEqual(EditToolModel.title(done: true, changeCount: 0), "Edited files")
    }
}
