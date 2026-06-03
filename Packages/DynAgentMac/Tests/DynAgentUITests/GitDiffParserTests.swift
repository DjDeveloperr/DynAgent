@testable import DynAgentUI
import XCTest

final class GitDiffParserTests: XCTestCase {
    func testParsesFileSectionsAndSkipsModeMetadata() {
        let diff = """
        diff --git a/Old.swift b/Old.swift
        deleted file mode 100644
        index abc..000 100644
        --- a/Old.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -import AppKit
        -let value = 1
        diff --git a/New.swift b/New.swift
        new file mode 100644
        index 000..def 100644
        --- /dev/null
        +++ b/New.swift
        @@ -0,0 +1,2 @@
        +import Foundation
        +let value = 2
        """

        let parsed = GitDiffModel.parse(diff)

        XCTAssertEqual(parsed.sections.map(\.path), ["Old.swift", "New.swift"])
        XCTAssertFalse(parsed.lines.contains { $0.text.contains("deleted file mode") || $0.text.contains("new file mode") })
        XCTAssertEqual(parsed.sections[0].deleted, 2)
        XCTAssertEqual(parsed.sections[1].added, 2)
        XCTAssertEqual(parsed.lines.filter { $0.kind == "F" }.map(\.text), ["Old.swift", "New.swift"])
    }

    func testAddsUnmodifiedLineSeparatorBetweenHunks() {
        let diff = """
        diff --git a/File.swift b/File.swift
        index abc..def 100644
        --- a/File.swift
        +++ b/File.swift
        @@ -1,1 +1,1 @@
        -let a = 1
        +let a = 2
        @@ -10,1 +10,1 @@
        -let b = 1
        +let b = 2
        """

        let parsed = GitDiffModel.parse(diff)
        let separators = parsed.lines.filter { $0.kind == "S" }

        XCTAssertEqual(separators.map(\.text), ["8 unmodified lines"])
        XCTAssertEqual(parsed.sections[0].startRow, 0)
    }
}
