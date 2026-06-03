@testable import DynAgentUI
import XCTest

final class EditToolModelTests: XCTestCase {
    func testParsesMultiChangeJSONSummary() {
        let detail = """
        {"status":"completed","changes":[
          {"path":"/repo/Sources/App.swift","added":6,"deleted":4,"diff":"@@ -1 +1 @@\\n-old\\n+new"},
          {"path":"/repo/Sources/View.swift","additions":"2","deletions":"1","diff":"@@ -4 +4 @@"}
        ]}
        """

        let summary = EditToolModel.summary(from: detail, done: true)

        XCTAssertEqual(summary.status, "completed")
        XCTAssertEqual(summary.changes.count, 2)
        XCTAssertEqual(summary.added, 8)
        XCTAssertEqual(summary.deleted, 5)
        XCTAssertEqual(summary.changes.map(\.path), ["/repo/Sources/App.swift", "/repo/Sources/View.swift"])
    }

    func testParsesLastJSONObjectFromStreamedDetail() {
        let detail = """
        Editing /repo/App.swift

        intermediate text

        {"path":"/repo/App.swift","added":3,"deleted":0,"diff":"+line"}
        trailing status text
        """

        let summary = EditToolModel.summary(from: detail, done: true)

        XCTAssertEqual(summary.changes, [
            EditToolChange(path: "/repo/App.swift", added: 3, deleted: 0, diff: "+line"),
        ])
    }

    func testFallbackPathListIgnoresStatusWords() {
        let paths = EditToolModel.fallbackPaths(from: "completed: done, /repo/A.swift, success, B/View.swift")

        XCTAssertEqual(paths, ["/repo/A.swift", "B/View.swift"])
    }

    func testTitleMatchesCodexStyleCounts() {
        XCTAssertEqual(EditToolModel.title(done: false, changeCount: 1), "Editing 1 file")
        XCTAssertEqual(EditToolModel.title(done: true, changeCount: 2), "Edited 2 files")
        XCTAssertEqual(EditToolModel.title(done: true, changeCount: 0), "Edited files")
    }
}
