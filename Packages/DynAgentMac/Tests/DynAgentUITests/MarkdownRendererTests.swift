import AppKit
@testable import DynAgentUI
import XCTest

final class MarkdownRendererTests: XCTestCase {
    func testPreservesNewlinesAndBullets() {
        let rendered = MarkdownRenderer.render("Intro\n- first\n- second\n\nDone")

        XCTAssertEqual(rendered.string, "Intro\n• first\n• second\n\nDone")
    }

    func testRendersInlineCodeAndLinks() {
        let rendered = MarkdownRenderer.render("Changed [File.swift](/tmp/File.swift:12) with `apply_patch`")
        let source = rendered.string as NSString

        XCTAssertEqual(rendered.string, "Changed File.swift with apply_patch")
        let linkRange = source.range(of: "File.swift")
        XCTAssertEqual(rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL, URL(string: "/tmp/File.swift:12"))

        let codeRange = source.range(of: "apply_patch")
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil))
        XCTAssertTrue(rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) is NSFont)
    }

    func testRendersCodexDirectiveAsInlineCodeToken() {
        let rendered = MarkdownRenderer.render(#"::git-push{cwd="/repo" branch="main"}"#)

        XCTAssertEqual(rendered.string, "action git-push - cwd=/repo - branch=main")
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }
}
