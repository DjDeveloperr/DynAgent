import XCTest
@testable import DynAgentUI

final class SidebarModelTests: XCTestCase {
    private let projectlessKey = "__projectless__"

    func testPinnedChatsAreSeparatedFromProjectsAndProjectlessChats() {
        let workspace = WorkspaceRef(name: "App", path: "/repo/app")
        let pinned = conversation("Pinned", workspace: "/repo/app", pinned: true, updatedAt: 30, threadId: "pinned")
        let project = conversation("Project", workspace: "/repo/app", updatedAt: 20, threadId: "project")
        let loose = conversation("Loose", workspace: "/repo/app", pinned: false, updatedAt: 10, threadId: "loose")

        let content = SidebarModel.build(
            conversations: [project],
            codexStubs: [
                workspace.path: [pinned],
                projectlessKey: [loose],
            ],
            workspaceRefs: [workspace],
            primaryPath: workspace.path,
            projectlessKey: projectlessKey,
            archivedCodexIds: []
        )

        XCTAssertEqual(content.pinnedConversations.map(\.title), ["Pinned"])
        XCTAssertEqual(content.projectlessConversations.map(\.title), ["Loose"])
        XCTAssertEqual(content.workspaces.first?.conversations.map(\.title), ["Project"])
    }

    func testArchivedCodexThreadsAreExcluded() {
        let workspace = WorkspaceRef(name: "App", path: "/repo/app")
        let archived = conversation("Archived", workspace: "/repo/app", updatedAt: 20, threadId: "dead")

        let content = SidebarModel.build(
            conversations: [],
            codexStubs: [workspace.path: [archived], projectlessKey: [archived]],
            workspaceRefs: [workspace],
            primaryPath: workspace.path,
            projectlessKey: projectlessKey,
            archivedCodexIds: ["dead"]
        )

        XCTAssertTrue(content.pinnedConversations.isEmpty)
        XCTAssertTrue(content.projectlessConversations.isEmpty)
        XCTAssertTrue(content.workspaces.first?.conversations.isEmpty ?? false)
    }

    func testLocalCodexConversationOverridesMatchingStub() {
        let workspace = WorkspaceRef(name: "App", path: "/repo/app")
        let local = conversation("Local", workspace: "/repo/app", updatedAt: 40, threadId: "same")
        let stub = conversation("Stub", workspace: "/repo/app", updatedAt: 50, threadId: "same")

        let content = SidebarModel.build(
            conversations: [local],
            codexStubs: [workspace.path: [stub]],
            workspaceRefs: [workspace],
            primaryPath: workspace.path,
            projectlessKey: projectlessKey,
            archivedCodexIds: []
        )

        XCTAssertEqual(content.workspaces.first?.conversations.map(\.title), ["Local"])
    }

    func testAddsWorkspaceRefsForLocalConversations() {
        let local = conversation("Local", workspace: "/repo/new", updatedAt: 10)

        let content = SidebarModel.build(
            conversations: [local],
            codexStubs: [:],
            workspaceRefs: [],
            primaryPath: "/repo/default",
            projectlessKey: projectlessKey,
            archivedCodexIds: []
        )

        XCTAssertEqual(content.workspaceRefs, [WorkspaceRef(name: "new", path: "/repo/new")])
        XCTAssertEqual(content.workspaces.first?.conversations.map(\.title), ["Local"])
    }

    private func conversation(_ title: String,
                              workspace: String,
                              pinned: Bool = false,
                              updatedAt: Double,
                              threadId: String? = nil) -> Conversation {
        let conversation = Conversation(model: "gpt-5.5", workspace: workspace, harness: .codex)
        conversation.title = title
        conversation.pinned = pinned
        conversation.updatedAt = updatedAt
        conversation.codexThreadId = threadId
        return conversation
    }
}
