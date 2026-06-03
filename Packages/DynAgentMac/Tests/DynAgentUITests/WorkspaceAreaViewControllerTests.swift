import AppKit
@testable import DynAgentUI
import XCTest

final class WorkspaceAreaViewControllerTests: XCTestCase {
    func testPrimaryChatTileTracksWorkspaceBoundsAfterResize() {
        let workspace = WorkspaceAreaViewController()
        let chat = NSView()
        chat.translatesAutoresizingMaskIntoConstraints = false

        workspace.loadView()
        workspace.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 780)
        workspace.setPrimary(chat, title: "")

        assertPrimaryTile(in: workspace, width: 1200, height: 780)
        XCTAssertEqual(chat.frame.width, 1200, accuracy: 0.5)
        XCTAssertEqual(chat.frame.height, 780, accuracy: 0.5)

        workspace.view.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        workspace.forceLayoutToBounds()

        assertPrimaryTile(in: workspace, width: 900, height: 640)
        XCTAssertEqual(chat.frame.width, 900, accuracy: 0.5)
        XCTAssertEqual(chat.frame.height, 640, accuracy: 0.5)
    }

    private func assertPrimaryTile(
        in workspace: WorkspaceAreaViewController,
        width: Double,
        height: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let metrics = workspace.layoutMetrics
        guard let workspaceViewWidth = metrics["workspaceViewWidth"] as? Double,
              let workspaceRootWidth = metrics["workspaceRootWidth"] as? Double,
              let frames = metrics["workspaceRootSubviewFrames"] as? [[String: Any]],
              let frame = frames.first,
              let primaryWidth = frame["width"] as? Double,
              let primaryHeight = frame["height"] as? Double else {
            XCTFail("Missing workspace layout metrics", file: file, line: line)
            return
        }
        XCTAssertEqual(workspaceViewWidth, width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(workspaceRootWidth, width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(primaryWidth, width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(primaryHeight, height, accuracy: 0.5, file: file, line: line)
    }
}
