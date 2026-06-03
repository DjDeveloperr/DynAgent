@testable import DynAgentUI
import XCTest

final class AppLayoutMetricsCoordinatorTests: XCTestCase {
    func testWritePayloadCreatesMetricsFileInDirectory() throws {
        let dir = try temporaryDirectory()
        let coordinator = AppLayoutMetricsCoordinator(directory: dir)

        coordinator.write(payload: [
            "reason": "codex-history-render",
            "windowWidth": 1472,
            "workspaceWidthSlack": 0,
        ])

        let data = try Data(contentsOf: dir.appendingPathComponent(AppLayoutMetricsCoordinator.defaultFileName))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["reason"] as? String, "codex-history-render")
        XCTAssertEqual(json["windowWidth"] as? Int, 1472)
        XCTAssertEqual(json["workspaceWidthSlack"] as? Int, 0)
    }

    func testWriteSnapshotUsesWindowLayoutMetricsPayload() throws {
        let dir = try temporaryDirectory()
        let coordinator = AppLayoutMetricsCoordinator(directory: dir)

        coordinator.write(snapshot: WindowLayoutMetricsSnapshot(
            reason: "loaded-thread",
            windowWidth: 1472,
            windowHeight: 780,
            contentViewWidth: 1472,
            contentViewHeight: 780,
            contentControllerWidth: 1472,
            contentControllerHeight: 780,
            contentLayoutWidth: 1472,
            contentLayoutHeight: 740,
            rootSplitViewWidth: 1472,
            rootSplitViewHeight: 780,
            splitViewWidth: 1472,
            splitViewHeight: 780,
            splitViewX: 0,
            splitViewClass: "NSSplitView",
            rootSubviews: [
                WindowLayoutViewFrame(index: 0, className: "NSSplitView", x: 0, width: 1472, height: 780),
            ],
            requestedFrameWidth: 1472,
            requestedFrameHeight: 780,
            appliedFrameWidth: 1472,
            appliedFrameHeight: 780,
            screenVisibleWidth: 1512,
            screenVisibleHeight: 949,
            sidebarCollapsed: false,
            gitCollapsed: true,
            splitFrames: [
                WindowLayoutViewFrame(index: 0, className: "Sidebar", x: 0, width: 284, height: 780),
                WindowLayoutViewFrame(index: 1, className: "Main", x: 284, width: 1188, height: 780),
            ],
            chatViewWidth: 1188,
            chatViewHeight: 780,
            workspaceWidth: 1188,
            workspaceHeight: 780,
            mainSplitItemWidth: 1188,
            chatMetrics: ["documentWidth": 1188],
            workspaceMetrics: ["workspaceRootWidth": 1188]
        ))

        let data = try Data(contentsOf: dir.appendingPathComponent(AppLayoutMetricsCoordinator.defaultFileName))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chat = try XCTUnwrap(json["chat"] as? [String: Any])
        XCTAssertEqual(json["reason"] as? String, "loaded-thread")
        XCTAssertEqual(json["workspaceWidthSlack"] as? Int, 0)
        XCTAssertEqual(chat["documentWidth"] as? Int, 1188)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
