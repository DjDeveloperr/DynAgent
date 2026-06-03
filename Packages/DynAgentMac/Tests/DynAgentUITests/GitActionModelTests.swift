import XCTest
@testable import DynAgentUI

final class GitActionModelTests: XCTestCase {
    func testPanelHeightAndActionsReflectWorktreeState() {
        XCTAssertEqual(GitActionSheetModel.panelHeight(isWorktree: false), 220)
        XCTAssertEqual(GitActionSheetModel.panelHeight(isWorktree: true), 302)
        XCTAssertEqual(GitActionSheetModel.primaryActions(isWorktree: false), [.commit, .commitPush, .push])
        XCTAssertEqual(GitActionSheetModel.primaryActions(isWorktree: true), [.commit, .commitPush, .push, .createBranch, .createPR])
    }

    func testCommitBodyTrimsMessageAndOmitsBlankMessage() {
        let withMessage = GitActionSheetModel.commitBody(cwd: "/repo", message: "  Ship it \n")
        XCTAssertEqual(withMessage["cwd"] as? String, "/repo")
        XCTAssertEqual(withMessage["message"] as? String, "Ship it")

        let blank = GitActionSheetModel.commitBody(cwd: "/repo", message: "  \n")
        XCTAssertEqual(blank["cwd"] as? String, "/repo")
        XCTAssertNil(blank["message"])
    }

    func testPendingStatusesMatchActionAndMessageState() {
        XCTAssertEqual(GitActionKind.commit.pendingStatus(hasMessage: false), "generating commit message...")
        XCTAssertEqual(GitActionKind.commit.pendingStatus(hasMessage: true), "committing...")
        XCTAssertEqual(GitActionKind.commitPush.pendingStatus(hasMessage: false), "generating message & pushing...")
        XCTAssertEqual(GitActionKind.commitPush.pendingStatus(hasMessage: true), "committing & pushing...")
        XCTAssertEqual(GitActionKind.push.pendingStatus(hasMessage: false), "pushing...")
    }
}
