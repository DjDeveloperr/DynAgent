import AppKit
import XCTest
@testable import DynAgentUI

final class GitActionChromeTests: XCTestCase {
    func testPanelUsesModelSizeAndConfiguredCommitField() {
        let field = NSTextField()
        let panel = GitActionSheetChrome.makePanel(
            branch: "main",
            isWorktree: true,
            commitField: field,
            target: Target(),
            selectors: selectors
        )

        let contentRect = panel.contentRect(forFrameRect: panel.frame)
        XCTAssertEqual(contentRect.width, GitActionSheetModel.panelWidth, accuracy: 0.001)
        XCTAssertEqual(contentRect.height, GitActionSheetModel.panelHeight(isWorktree: true), accuracy: 0.001)
        XCTAssertEqual(field.placeholderString, GitActionSheetModel.commitPlaceholder)
        XCTAssertFalse(field.isBordered)
        XCTAssertFalse(field.usesSingleLineMode)
        XCTAssertNotNil(panel.contentView)
    }

    func testButtonChromeUsesActionTitleTargetAndSelector() {
        let target = Target()
        let button = GitActionSheetChrome.makeButton(.commitPush, target: target, selector: #selector(Target.action))

        XCTAssertEqual(button.title, "Commit & Push")
        XCTAssertTrue(button.target === target)
        XCTAssertEqual(button.action, #selector(Target.action))
        XCTAssertFalse(button.isBordered)
    }

    private var selectors: GitActionSelectors {
        GitActionSelectors(
            commit: #selector(Target.action),
            commitPush: #selector(Target.action),
            push: #selector(Target.action),
            createBranch: #selector(Target.action),
            createPR: #selector(Target.action)
        )
    }

    private final class Target: NSObject {
        @objc func action() {}
    }
}
