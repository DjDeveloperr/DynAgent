import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MobileChatStore {
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var models: [String] = []
    var conversation = Conversation(model: "auto", harness: .dynagent)
    var input = ""
    var sending = false
    var credits = ""
    var workspace = ""

    private var base: URL? { URL(string: serverURL) }

    private struct Named: Decodable { let id: String }
    private struct Cwd: Decodable { let name: String }
    private struct Quota: Decodable { let sessionCredits: Double? }

    func saveURL() {
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
    }

    func load() async {
        guard let base else { return }
        if let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("models")),
           let availableModels = try? JSONDecoder().decode([Named].self, from: data) {
            models = availableModels.map(\.id)
            if conversation.model == "auto", let first = models.first(where: { $0 != "auto" }) {
                conversation.model = first
            }
        }
        if let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("cwd")),
           let cwd = try? JSONDecoder().decode(Cwd.self, from: data) {
            workspace = cwd.name
        }
        await refreshCredits()
    }

    func refreshCredits() async {
        guard let base else { return }
        if let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("quota")),
           let quota = try? JSONDecoder().decode(Quota.self, from: data) {
            let amount = quota.sessionCredits ?? 0
            credits = "credits \(amount.formatted(.number.precision(.fractionLength(3))))"
        }
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base, !text.isEmpty, !sending else { return }

        input = ""
        let user = ChatMessage(role: .user, text: text)
        conversation.messages.append(user)

        let assistant = ChatMessage(role: .assistant, text: "")
        conversation.messages.append(assistant)
        sending = true

        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": conversation.model,
            "conversationId": conversation.id,
            "messages": conversation.history,
        ])

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in bytes.lines where line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = event["type"] as? String else { continue }

                switch type {
                case "text":
                    assistant.text += event["text"] as? String ?? ""
                case "tool":
                    insertTool(event, before: assistant)
                case "error":
                    assistant.text += "\n" + (event["error"] as? String ?? "error")
                default:
                    break
                }
            }
        } catch {
            assistant.text += "\n" + error.localizedDescription
        }

        assistant.timestamp = Date().timeIntervalSince1970
        assistant.isFinal = true
        sending = false
        await refreshCredits()
    }

    private func insertTool(_ event: [String: Any], before assistant: ChatMessage) {
        let name = event["name"] as? String ?? "tool"
        let detail = event["detail"] as? String ?? name
        let tool = ChatMessage(role: .tool, text: detail, toolName: "shell", toolDetail: detail)
        tool.toolDone = event["done"] as? Bool ?? true
        let index = conversation.messages.firstIndex { $0 === assistant } ?? conversation.messages.count
        conversation.messages.insert(tool, at: index)
    }
}

private enum MobileSheet: String, Identifiable {
    case settings
    var id: String { rawValue }
}

@main
struct DynAgentMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var store = MobileChatStore()
    @State private var activeSheet: MobileSheet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TranscriptList(messages: store.conversation.messages, sending: store.sending)
                ComposerBar(store: store)
            }
            .navigationTitle(store.workspace.isEmpty ? "DynAgent" : store.workspace)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(store.credits)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $activeSheet) { _ in
                SettingsView(store: store)
            }
        }
        .task {
            await store.load()
        }
    }
}

private struct TranscriptList: View {
    let messages: [ChatMessage]
    let sending: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages, id: \.stableID) { message in
                        MessageRow(message: message)
                            .id(message.stableID)
                    }
                    if sending {
                        Text(WorkDividerModel.durationText(seconds: 0, active: true))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("mobile-working")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.text) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if sending {
                proxy.scrollTo("mobile-working", anchor: .bottom)
            } else if let id = messages.last?.stableID {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
            }
        case .tool:
            ToolMessageRow(message: message)
        case .assistant:
            Text(assistantText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistantText: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }
}

private struct ToolMessageRow: View {
    let message: ChatMessage

    var body: some View {
        let summary = ShellToolModel.summary(from: message.toolDetail ?? message.text)
        let title = ShellToolModel.title(command: summary.command.nilIfEmpty ?? message.text, done: message.toolDone)
        VStack(alignment: .leading, spacing: 4) {
            Text(toolTitle(title))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if !summary.output.isEmpty {
                Text(summary.output)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolTitle(_ title: ShellToolTitle) -> String {
        if let detail = title.detail, !detail.isEmpty {
            return "\(title.action) \(detail)"
        }
        return title.action
    }
}

private struct ComposerBar: View {
    @Bindable var store: MobileChatStore

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.models, id: \.self) { id in
                    Button(id) {
                        store.conversation.model = id
                    }
                }
            } label: {
                Text(ComposerModel.shortCodexModelName(store.conversation.model))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            TextField(ComposerModel.placeholder(agent: store.conversation.harness), text: $store.input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
            Button {
                Task { await store.send() }
            } label: {
                Image(systemName: ComposerModel.sendState(
                    streaming: store.sending,
                    trimmedText: store.input.trimmingCharacters(in: .whitespacesAndNewlines),
                    hasAttachments: false
                ).symbol)
                .font(.title2)
            }
            .disabled(store.sending || store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct SettingsView: View {
    @Bindable var store: MobileChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://100.x.y.z:4319", text: $store.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.saveURL()
                        Task { await store.load() }
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension ChatMessage {
    var stableID: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
