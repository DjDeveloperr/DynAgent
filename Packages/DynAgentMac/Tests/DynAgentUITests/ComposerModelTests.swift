@testable import DynAgentUI
import XCTest

final class ComposerModelTests: XCTestCase {
    func testFallbackModelsMatchHarnessDefaults() {
        XCTAssertEqual(ComposerModel.fallbackModel(for: .dynagent, preferred: nil), "auto")
        XCTAssertEqual(ComposerModel.fallbackModel(for: .codex, preferred: nil), "gpt-5.5")
        XCTAssertEqual(ComposerModel.fallbackModel(for: .pi, preferred: nil), "kiro::kiro/claude-opus-4.8")
        XCTAssertEqual(ComposerModel.fallbackModel(for: .codex, preferred: "gpt-5.5-codex"), "gpt-5.5-codex")
    }

    func testResolvesCodexModelAgainstAvailableList() {
        XCTAssertEqual(ComposerModel.resolvedCodexModel("gpt-5.5", available: []), "gpt-5.5")
        XCTAssertEqual(ComposerModel.resolvedCodexModel("missing", available: ["gpt-5.5-codex", "gpt-5.5"]), "gpt-5.5-codex")
        XCTAssertEqual(ComposerModel.resolvedCodexModel(nil, available: []), "gpt-5.5")
    }

    func testSelectedModelForListPrefersDesiredThenNonAuto() {
        XCTAssertEqual(
            ComposerModel.selectedModelForList(ids: ["auto", "claude-opus"], desiredModel: "claude-opus"),
            "claude-opus"
        )
        XCTAssertEqual(
            ComposerModel.selectedModelForList(ids: ["auto", "claude-opus"], desiredModel: "missing"),
            "claude-opus"
        )
        XCTAssertEqual(
            ComposerModel.selectedModelForList(ids: ["auto"], desiredModel: nil),
            "auto"
        )
        XCTAssertNil(ComposerModel.selectedModelForList(ids: [], desiredModel: nil))
    }

    func testCodexMenuModelPreservesCurrentModelAndMarksEntries() {
        let model = ComposerModel.codexMenuModel(
            ids: ["gpt-5.5-codex", "gpt-5.5-mini"],
            desiredModel: nil,
            currentModel: "gpt-5.5-mini",
            selectedEffort: "xhigh"
        )

        XCTAssertEqual(model.selectedModel, "gpt-5.5-mini")
        XCTAssertEqual(model.modelItems.map(\.title), ["5.5 Codex", "5.5 Mini"])
        XCTAssertEqual(model.modelItems.map(\.representedValue), ["gpt-5.5-codex", "gpt-5.5-mini"])
        XCTAssertEqual(model.modelItems.map(\.isSelected), [false, true])
        XCTAssertEqual(model.effortItems.map(\.title), ["Low", "Medium", "High", "Extra High"])
        XCTAssertEqual(model.effortItems.map(\.representedValue), ["low", "medium", "high", "xhigh"])
        XCTAssertEqual(model.effortItems.map(\.isSelected), [false, false, false, true])
    }

    func testCodexMenuModelDesiredAndFallbackSelection() {
        XCTAssertEqual(
            ComposerModel.codexMenuModel(
                ids: ["gpt-5.5-codex", "gpt-5.5-mini"],
                desiredModel: "gpt-5.5-codex",
                currentModel: "gpt-5.5-mini",
                selectedEffort: "high"
            ).selectedModel,
            "gpt-5.5-codex"
        )
        XCTAssertEqual(
            ComposerModel.codexMenuModel(
                ids: [],
                desiredModel: "missing",
                currentModel: "missing",
                selectedEffort: "high"
            ).selectedModel,
            "gpt-5.5"
        )
    }

    func testCodexLabels() {
        XCTAssertEqual(ComposerModel.shortCodexModelName("gpt-5.5-codex"), "5.5 Codex")
        XCTAssertEqual(ComposerModel.shortCodexModelName("gpt-5.5-codex-spark"), "5.5 Codex Spark")
        XCTAssertEqual(ComposerModel.shortCodexModelName("gpt-5.5-mini"), "5.5 Mini")
        XCTAssertEqual(ComposerModel.effortDisplayName("xhigh"), "Extra High")
        XCTAssertEqual(ComposerModel.effortDisplayName("unknown"), "High")
        XCTAssertEqual(ComposerModel.placeholder(agent: .codex), "Ask Codex")
    }

    func testMenuStateLocksAgentForExistingCodexThreads() {
        let thread = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        thread.codexThreadId = "thread-id"

        let state = ComposerModel.menuState(
            conversation: thread,
            selectedHarness: .codex,
            reasoningControlHidden: true
        )

        XCTAssertEqual(state.placeholder, "Ask Codex")
        XCTAssertFalse(state.showsHarnessMenu)
        XCTAssertFalse(state.showsReasoningMenu)

        let newChat = ComposerModel.menuState(conversation: nil, selectedHarness: .dynagent, reasoningControlHidden: false)
        XCTAssertEqual(newChat.placeholder, "Ask DynAgent")
        XCTAssertTrue(newChat.showsHarnessMenu)
        XCTAssertTrue(newChat.showsReasoningMenu)
    }

    func testContextState() {
        XCTAssertEqual(ComposerModel.contextState(percent: nil), ComposerContextState(fraction: 0, tooltip: "context 0%"))
        XCTAssertEqual(ComposerModel.contextState(percent: 42.8), ComposerContextState(fraction: 0.428, tooltip: "context 42%"))
    }

    func testDraftKeysUseThreadNewWorkspaceAndLocalConversation() {
        let codex = Conversation(model: "gpt", workspace: "/repo", harness: .codex)
        codex.codexThreadId = "thread-1"
        XCTAssertEqual(ComposerModel.draftKey(for: codex), "DynAgentComposerDraft.codex:thread-1")

        let draft = Conversation(model: "gpt", workspace: "/repo", harness: .codex)
        XCTAssertEqual(ComposerModel.draftKey(for: draft), "DynAgentComposerDraft.new:/repo")

        let projectless = Conversation(model: "gpt", workspace: "", harness: .codex)
        XCTAssertEqual(ComposerModel.draftKey(for: projectless), "DynAgentComposerDraft.new:projectless")

        let local = Conversation(model: "gpt", workspace: "/repo", harness: .codex)
        local.id = "local-id"
        local.messages.append(ChatMessage(role: .user, text: "hi"))
        XCTAssertEqual(ComposerModel.draftKey(for: local), "DynAgentComposerDraft.local:local-id")
    }

    func testMessageTextWithAttachments() {
        XCTAssertEqual(ComposerModel.messageText(typedText: "hello", attachmentPaths: []), "hello")
        XCTAssertEqual(
            ComposerModel.messageText(typedText: "", attachmentPaths: ["/tmp/a.png", "/tmp/b.swift"]),
            "Attached files:\n- /tmp/a.png\n- /tmp/b.swift"
        )
        XCTAssertEqual(
            ComposerModel.messageText(typedText: "please inspect", attachmentPaths: ["/tmp/a.png"]),
            "please inspect\n\nAttached files:\n- /tmp/a.png"
        )
    }

    func testAttachmentAdditionsNormalizeAndDeduplicatePaths() {
        let existing = [ComposerAttachment(url: URL(fileURLWithPath: "/tmp/a.png"))]
        let additions = ComposerModel.attachmentAdditions(
            existing: existing,
            incoming: [
                URL(fileURLWithPath: "/tmp/a.png"),
                URL(fileURLWithPath: "/tmp/b.swift"),
                URL(fileURLWithPath: "/tmp/b.swift"),
            ]
        )

        XCTAssertEqual(additions.map { $0.url.path }, ["/tmp/b.swift"])
    }

    func testDraftSnapshotRoundTripsAndRestoresExistingAttachmentsOnly() {
        let attachments = [
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/a.png")),
            ComposerAttachment(url: URL(fileURLWithPath: "/tmp/missing.swift")),
        ]
        let snapshot = ComposerModel.draftSnapshot(text: "hello", attachments: attachments)
        let decoded = ComposerModel.decodeDraftSnapshot(from: ComposerModel.encodeDraftSnapshot(snapshot))

        XCTAssertEqual(decoded, snapshot)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(
            ComposerModel.restoredAttachments(from: decoded) { $0.hasSuffix("a.png") }.map { $0.url.path },
            ["/tmp/a.png"]
        )
    }

    func testDraftSnapshotEmptyAndImageDetection() {
        XCTAssertTrue(ComposerDraftSnapshot(text: "", attachments: []).isEmpty)
        XCTAssertFalse(ComposerDraftSnapshot(text: "x", attachments: []).isEmpty)
        XCTAssertTrue(ComposerModel.isImageFile(URL(fileURLWithPath: "/tmp/screen.HEIC")))
        XCTAssertFalse(ComposerModel.isImageFile(URL(fileURLWithPath: "/tmp/main.swift")))
    }

    func testSendStateStopsOnlyWhenStreamingWithEmptyComposerAndNoAttachments() {
        XCTAssertEqual(ComposerModel.sendState(streaming: true, trimmedText: "", hasAttachments: false),
                       ComposerSendState(symbol: "stop.fill", accessibilityDescription: "Stop", isStop: true))
        XCTAssertEqual(ComposerModel.sendState(streaming: true, trimmedText: "steer", hasAttachments: false),
                       ComposerSendState(symbol: "arrow.up", accessibilityDescription: "Send", isStop: false))
        XCTAssertEqual(ComposerModel.sendState(streaming: true, trimmedText: "", hasAttachments: true).isStop, false)
    }
}
