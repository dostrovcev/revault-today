import AppKit
import SwiftUI

/// ⌘, : choose the model, add your key, name the agent, edit people and areas.
struct SettingsView: View {
    var body: some View {
        TabView {
            VStack(spacing: 12) {
                Text("Today").font(.title)
                Text("Free, open source tasks with your own AI.")
                Link("Built by Dmitry Ostrovtsev", destination: URL(string: "https://www.linkedin.com/in/dostrovcev/")!)
                Link("Re:Vault · AI for your business", destination: URL(string: "https://re-vault.io/?utm_source=revault-today&utm_medium=app&utm_campaign=open-source")!)
                Link("Source code · MIT", destination: URL(string: "https://github.com/dostrovcev/revault-today")!)
            }.tabItem { Label("About", systemImage: "info.circle") }
            AgentSettings().tabItem { Label("Agent", systemImage: "sparkles") }
            ListSettings(title: "People you hand tasks to", hint: "One name per line. Tag them as @name.",
                         get: { Config.shared.people }, set: { Config.shared.people = $0 })
                .tabItem { Label("People", systemImage: "person.2") }
            ListSettings(title: "Areas", hint: "One per line, in the order you want them. File a task with #area.",
                         get: { Config.shared.areas }, set: { Config.shared.areas = $0 })
                .tabItem { Label("Areas", systemImage: "square.grid.2x2") }
        }
        .frame(width: 560, height: 560)
    }
}

struct AgentSettings: View {
    @State private var cfg = Config.shared.agent
    @State private var key = ""
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                Picker("Model provider", selection: $cfg.provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: cfg.provider) { _, p in
                    cfg.model = p.defaultModel
                    key = KeyStore.get(p) ?? ""
                }
                TextField("Agent name", text: $cfg.name, prompt: Text("Agent"))
                TextField((cfg.provider == .claudeCode || cfg.provider == .codex) ? "Model (optional)" : "Model", text: $cfg.model,
                          prompt: Text(cfg.provider.defaultModel.isEmpty ? "default" : cfg.provider.defaultModel))
            } footer: {
                Text(tagHint).foregroundStyle(.secondary)
            }

            switch cfg.provider {
            case .anthropic, .openai:
                Section {
                    SecureField("API key", text: $key, prompt: Text(cfg.provider == .anthropic ? "sk-ant-…" : "sk-…"))
                } footer: {
                    Text("Stored in your Keychain on this Mac. Requests go straight from this Mac to \(cfg.provider == .anthropic ? "api.anthropic.com" : "api.openai.com").")
                        .foregroundStyle(.secondary)
                }
            case .compatible:
                Section {
                    TextField("Base URL", text: $cfg.baseURL, prompt: Text("http://localhost:11434/v1"))
                    SecureField("API key (if the server needs one)", text: $key)
                } footer: {
                    Text("Ollama: http://localhost:11434/v1 · LM Studio: http://localhost:1234/v1 · OpenRouter: https://openrouter.ai/api/v1")
                        .foregroundStyle(.secondary)
                }
            case .claudeCode, .codex:
                Section {
                    if cfg.provider == .claudeCode {
                        TextField("Claude Code path", text: $cfg.claudePath,
                                  prompt: Text(LocalAgentCLI.find(.claude) ?? "Auto-detect"))
                    } else {
                        TextField("Codex path", text: Binding(get: { cfg.codexPath ?? "" }, set: { cfg.codexPath = $0 }),
                                  prompt: Text(LocalAgentCLI.find(.codex) ?? "Auto-detect"))
                    }
                    Text("Sign in once in Terminal: claude, or codex login. Your account's usage limits apply. Replies are drafts and answers inside Today.")
                        .foregroundStyle(.secondary)
                }

            }

            Section("Instructions for the agent") {
                TextEditor(text: $cfg.instructions).font(.system(size: 12)).frame(minHeight: 110)
                Button("Reset to default") { cfg.instructions = AgentConfig.defaultInstructions }
            }

            Section {
                HStack {
                    Button(testing ? "Testing…" : "Test connection") { test() }.disabled(testing)
                    if let testResult { Text(testResult).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { key = KeyStore.get(cfg.provider) ?? "" }
        .onChange(of: cfg) { _, v in Config.shared.agent = v }
        .onChange(of: key) { _, k in KeyStore.set(k, for: cfg.provider) }
    }

    private var tagHint: String {
        let slug = Area.slug(cfg.name)
        let tags = slug.isEmpty || slug == "agent" ? "@agent" : "@\(slug) or @agent"
        return "Tag \(tags) in a task and it does what you wrote."
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { cfg.workDir = url.path }
    }

    private func test() {
        testing = true; testResult = nil
        let now = Date().timeIntervalSince1970
        let task = Item(id: "test", kind: "task", text: "Connection test", day: Day.today, created: now, updated: now)
        let c = Comment(id: 1, author: "me", kind: "user", text: "@agent reply with one word: ready", created: now)
        Task {
            do {
                let r = try await AgentRunner.reply(task: task, thread: [c], config: cfg)
                testResult = "Works: " + AgentRunner.state(from: r).0.prefix(60)
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}

struct ListSettings: View {
    let title: String
    let hint: String
    let get: () -> [String]
    let set: ([String]) -> Void
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text).font(.system(size: 13)).frame(minHeight: 260)
            } header: { Text(title) } footer: { Text(hint).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .onAppear { text = get().joined(separator: "\n") }
        .onChange(of: text) { _, v in set(v.components(separatedBy: "\n")) }
    }
}
