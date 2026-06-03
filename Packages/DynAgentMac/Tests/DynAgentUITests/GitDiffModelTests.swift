@testable import DynAgentUI
import XCTest

final class GitDiffModelTests: XCTestCase {
    func testParsesFileSectionsAndStatsWithoutMetadataRows() {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,2 +1,3 @@
         import AppKit
        -let old = true
        +let old = false
        +let added = true
        deleted file mode 100644
        """

        let model = GitDiffModel.parse(diff)

        XCTAssertEqual(model.sections.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(model.sections.first?.added, 2)
        XCTAssertEqual(model.sections.first?.deleted, 1)
        XCTAssertFalse(model.lines.contains { $0.text.contains("deleted file mode") })
        XCTAssertEqual(model.lines.first?.kind, "F")
    }

    func testResetsLineNumbersPerFile() {
        let diff = """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -10,1 +10,1 @@
        -oldA
        +newA
        diff --git a/B.swift b/B.swift
        --- a/B.swift
        +++ b/B.swift
        @@ -1,1 +1,1 @@
        -oldB
        +newB
        """

        let model = GitDiffModel.parse(diff)
        let deleted = model.lines.filter { $0.kind == "-" }
        let added = model.lines.filter { $0.kind == "+" }

        XCTAssertEqual(model.sections.map(\.path), ["A.swift", "B.swift"])
        XCTAssertEqual(deleted.map(\.old), [10, 1])
        XCTAssertEqual(added.map(\.new), [10, 1])
    }

    func testAddsUnmodifiedSeparatorBetweenHunks() {
        let diff = """
        diff --git a/App.swift b/App.swift
        --- a/App.swift
        +++ b/App.swift
        @@ -1,1 +1,1 @@
        -a
        +b
        @@ -8,1 +8,1 @@
        -c
        +d
        """

        let model = GitDiffModel.parse(diff)

        XCTAssertTrue(model.lines.contains { $0.kind == "S" && $0.text == "6 unmodified lines" })
    }
}
