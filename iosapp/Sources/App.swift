import SwiftUI
import Foundation

// MARK: - Model

struct Msg: Identifiable {
    let id = UUID()
    let role: String   // user | assistant | tool
    var text: String
}

// MARK: - Store (talks to the desktop DynAgent server over Tailscale)

@MainActor
final class Store: ObservableObject {
    @Published var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @Published var models: [String] = []
    @Published var model = "auto"
    @Published var messages: [Msg] = []
    @Published var input = ""
    @Published var sending = false
    @Published var credits = ""
    @Published var workspace = ""

    private let conversationId = UUID().uuidString
    private var base: URL? { URL(string: serverURL) }

    struct Named: Decodable { let id: String }
    struct Cwd: Decodable { let name: String }
    struct Quota: Decodable { let sessionCredits: Double? }

    func saveURL() { UserDefaults.standard.set(serverURL, forKey: "serverURL") }

    func load() async {
        guard let base else { return }
        if let (d, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("models")),
           let arr = try? JSONDecoder().decode([Named].self, from: d) {
            models = arr.map(\.id)
            if model == "auto", let f = models.first(where: { $0 != "auto" }) { model = f }
        }
        if let (d, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("cwd")),
           let c = try? JSONDecoder().decode(Cwd.self, from: d) { workspace = c.name }
        await refreshCredits()
    }

    func refreshCredits() async {
        guard let base else { return }
        if let (d, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("quota")),
           let q = try? JSONDecoder().decode(Quota.self, from: d) {
            credits = String(format: "credits %.3f", q.sessionCredits ?? 0)
        }
    }

    func send() async {
        guard let base, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !sending else { return }
        let text = input
        input = ""
        messages.append(Msg(role: "user", text: text))
        let history = messages
            .filter { ($0.role == "user" || $0.role == "assistant") && !$0.text.isEmpty }
            .map { ["role": $0.role, "content": $0.text] }
        let assistant = Msg(role: "assistant", text: "")
        messages.append(assistant)
        let aid = assistant.id
        sending = true

        var req = URLRequest(url: base.appendingPathComponent("chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "conversationId": conversationId, "messages": history,
        ])
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines where line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let d = payload.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let type = o["type"] as? String else { continue }
                switch type {
                case "text": update(aid) { $0.text += o["text"] as? String ?? "" }
                case "tool": insertTool("▸ \(o["name"] as? String ?? "tool")", before: aid)
                case "error": update(aid) { $0.text += "\n⚠︎ " + (o["error"] as? String ?? "error") }
                default: break
                }
            }
        } catch {
            update(aid) { $0.text += "\n⚠︎ " + error.localizedDescription }
        }
        sending = false
        await refreshCredits()
    }

    private func update(_ id: UUID, _ f: (inout Msg) -> Void) {
        if let i = messages.firstIndex(where: { $0.id == id }) { f(&messages[i]) }
    }
    private func insertTool(_ text: String, before id: UUID) {
        let at = messages.firstIndex(where: { $0.id == id }) ?? messages.count
        messages.insert(Msg(role: "tool", text: text), at: at)
    }
}

// MARK: - Views

@main
struct DynAgentMobileApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.messages) { MessageRow(msg: $0) }
                        }
                        .padding()
                    }
                    .onChange(of: store.messages.last?.text) { _, _ in
                        if let id = store.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                composer
            }
            .navigationTitle(store.workspace.isEmpty ? "DynAgent" : store.workspace)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(store.credits).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        }
        .task { await store.load() }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.models, id: \.self) { id in Button(id) { store.model = id } }
            } label: {
                Label(store.model, systemImage: "cpu").font(.caption).lineLimit(1)
            }
            TextField("Message…", text: $store.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
            Button { Task { await store.send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(store.sending || store.input.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct MessageRow: View {
    let msg: Msg
    var body: some View {
        switch msg.role {
        case "user":
            HStack {
                Spacer(minLength: 50)
                Text(msg.text)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
            }
        case "tool":
            Text(msg.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.orange)
        default:
            Text(msg.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Server (Tailscale)") {
                    TextField("http://100.x.y.z:4319", text: $store.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.saveURL(); Task { await store.load() }; dismiss() }
                }
            }
        }
    }
}
