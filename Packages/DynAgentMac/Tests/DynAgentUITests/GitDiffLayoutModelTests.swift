@testable import DynAgentUI
import XCTest

final class GitDiffLayoutModelTests: XCTestCase {
    func testBuildsRowsWithFileHeaderHeightsAndBinaryLookup() {
        let layout = GitDiffLayoutModel(diff: GitDiffModel.parse(diff))

        XCTAssertEqual(layout.lines.first?.kind, "F")
        XCTAssertEqual(layout.rowTops.prefix(4), [0, 34, 56, 78])
        XCTAssertEqual(layout.rowIndex(at: 0), 0)
        XCTAssertEqual(layout.rowIndex(at: 33), 0)
        XCTAssertEqual(layout.rowIndex(at: 34), 1)
        XCTAssertEqual(layout.rowIndex(at: 56), 2)
    }

    func testHeaderInfoTracksSectionAtVisibleOffset() {
        let layout = GitDiffLayoutModel(diff: GitDiffModel.parse(diff))

        XCTAssertEqual(layout.headerInfo(at: 0)?.path, "A.swift")
        XCTAssertEqual(layout.headerInfo(at: 110)?.path, "B.swift")
        XCTAssertEqual(layout.headerInfo(at: 110)?.added, 1)
        XCTAssertEqual(layout.headerInfo(at: 110)?.deleted, 1)
    }

    func testCollapsingFileKeepsHeaderAndHidesBodyRows() {
        var layout = GitDiffLayoutModel(diff: GitDiffModel.parse(diff))

        layout.toggle(path: "A.swift")

        XCTAssertTrue(layout.collapsedPaths.contains("A.swift"))
        XCTAssertEqual(layout.lines.map(\.kind), ["F", "F", "-", "+"])
        XCTAssertNil(layout.headerInfo(at: 0))
        XCTAssertEqual(layout.headerInfo(at: 35)?.path, "B.swift")
    }

    func testToggleHeaderIfNeededOnlyTogglesFileRows() {
        var layout = GitDiffLayoutModel(diff: GitDiffModel.parse(diff))

        XCTAssertFalse(layout.toggleHeaderIfNeeded(at: 34))
        XCTAssertTrue(layout.toggleHeaderIfNeeded(at: 0))
        XCTAssertTrue(layout.collapsedPaths.contains("A.swift"))
    }

    private let diff = """
    diff --git a/A.swift b/A.swift
    --- a/A.swift
    +++ b/A.swift
    @@ -1,1 +1,1 @@
    -oldA
    +newA
    diff --git a/B.swift b/B.swift
    --- a/B.swift
    +++ b/B.swift
    @@ -4,1 +4,1 @@
    -oldB
    +newB
    """
}
