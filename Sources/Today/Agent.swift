import Foundation
import Security

/// Which model answers when you tag the agent on a task.
enum Provider: String, Codable, CaseIterable, Identifiable {
    case anthropic, openai, compatible, claudeCode, codex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anthropic: return "Claude (Anthropic API)"
        case .openai: return "OpenAI API (separate billing)"
        case .compatible: return "OpenAI-compatible (Ollama, LM Studio, OpenRouter, Groq…)"
        case .claudeCode: return "Claude Code (your Claude account)"
        case .codex: return "Codex (your ChatGPT account)"
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: return ""
        case .openai: return ""
        case .compatible: return "llama3.1"
        case .claudeCode, .codex: return ""
        }
    }
    var needsKey: Bool { self == .anthropic || self == .openai }
}

struct AgentConfig: Codable, Equatable {
    var provider: Provider = .claudeCode
    var model: String = ""
    var baseURL: String = "http://localhost:11434/v1"
    var claudePath: String = ""
    var codexPath: String? = nil
    var workDir: String = ""
    var name: String = "Agent"
    var instructions: String = AgentConfig.defaultInstructions

    static let defaultInstructions = """
    You are the user's assistant inside a task app. Each request is about one task: its text is in <task>, \
    the conversation about it is in <thread>. Answer the last message addressed to you. Do the work in this reply \
    if you can (write the draft, the plan, the list, the answer) instead of promising to do it later. Be brief and \
    concrete: first line is what you did or found. If something needs the user's decision, say exactly what.
    """
}

/// Settings stored in UserDefaults; API keys go to the Keychain.
@MainActor
final class Config {
    static let shared = Config()
    static let changed = Notification.Name("today.config.changed")
    private let d = UserDefaults.standard
    private func changed() { NotificationCenter.default.post(name: Config.changed, object: nil) }

    var agent: AgentConfig {
        get { (d.data(forKey: "agent")).flatMap { try? JSONDecoder().decode(AgentConfig.self, from: $0) } ?? AgentConfig() }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "agent"); changed() }
    }
    var people: [String] {
        get { d.stringArray(forKey: "people") ?? [] }
        set { d.set(newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, forKey: "people"); changed() }
    }
    static let defaultAreas = ["Clients", "Pipeline", "Bugs", "Features", "Fundraising", "Team", "Ops"]
    var areas: [String] {
        get { d.stringArray(forKey: "areas") ?? Config.defaultAreas }
        set { d.set(newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, forKey: "areas"); changed() }
    }
}

enum KeyStore {
    private static let service = "app.today.apikey"

    static func get(_ p: Provider) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: p.rawValue, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
           let key = String(data: data, encoding: .utf8), !key.isEmpty { return key }
        // no key in the Keychain: fall back to the usual environment variables
        let env = ProcessInfo.processInfo.environment
        switch p {
        case .anthropic: return env["ANTHROPIC_API_KEY"]
        case .openai: return env["OPENAI_API_KEY"]
        default: return nil
        }
    }

    static func set(_ key: String, for p: Provider) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: p.rawValue]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum AgentError: LocalizedError {
    case noKey(String), http(Int, String), empty, refused(String), noClaude, failed(String)
    var errorDescription: String? {
        switch self {
        case .noKey(let p): return "Add your \(p) API key in Settings (⌘,)."
        case .http(let code, let msg): return "The model answered with an error \(code): \(msg)"
        case .empty: return "The model returned an empty answer."
        case .refused(let why): return "The model declined this request\(why.isEmpty ? "" : ": " + why)."
        case .noClaude: return "Claude Code was not found. Install it (claude.com/claude-code) or set its path in Settings."
        case .failed(let s): return s
        }
    }
}

enum AgentRunner {
    /// One reply from the configured model for a task and its thread.
    static func reply(task: Item, thread: [Comment], config: AgentConfig) async throws -> String {
        let prompt = buildPrompt(task: task, thread: thread)
        let system = config.instructions + "\n\n" + markers
        if config.provider.needsKey && config.model.trimmingCharacters(in: .whitespaces).isEmpty {
            throw AgentError.failed("Enter a model ID available in your API account in Settings.")
        }
        switch config.provider {
        case .anthropic: return try await anthropic(system: system, prompt: prompt, config: config)
        case .openai: return try await openAI(base: "https://api.openai.com/v1", key: KeyStore.get(.openai), needKey: true,
                                               system: system, prompt: prompt, model: config.model)
        case .compatible: return try await openAI(base: config.baseURL, key: KeyStore.get(.compatible), needKey: false,
                                                   system: system, prompt: prompt, model: config.model)
        case .claudeCode, .codex:
            return try await LocalAgentCLI.reply(backend: config.provider == .codex ? .codex : .claude,
                path: config.provider == .codex ? (config.codexPath ?? "") : config.claudePath,
                model: config.model, prompt: system + "\n\n" + prompt)
        }
    }

    static let markers = """
    End your reply with exactly one line: [[DONE]] if the request is fully done, [[NEEDS-YOU]] if it waits on the \
    user's decision, or nothing if you just answered.
    """

    /// The last line marker becomes the task's state and is removed from the text.
    static func state(from raw: String) -> (String, String) {
        var lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let last = lines.last?.trimmingCharacters(in: .whitespaces) ?? ""
        let map = ["[[DONE]]": "done", "[[NEEDS-YOU]]": "needs_you"]
        if let s = map[last] {
            lines.removeLast()
            return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), s)
        }
        return (raw.trimmingCharacters(in: .whitespacesAndNewlines), "answered")
    }

    static func buildPrompt(task: Item, thread: [Comment]) -> String {
        var s = "<task date=\"\(Day.today)\"\(task.due.map { " due=\"\($0)\"" } ?? "")>\n\(task.text)\n</task>\n\n<thread>\n"
        for c in thread.suffix(40) {
            s += "\(c.fromAgent ? "Assistant" : "User") (\(Day.stamp(c.created))): \(c.text)\n\n"
        }
        return s + "</thread>"
    }

    // MARK: providers

    /// Anthropic Messages API over HTTP (Swift has no official SDK).
    private static func anthropic(system: String, prompt: String, config: AgentConfig) async throws -> String {
        guard let key = KeyStore.get(.anthropic), !key.isEmpty else { throw AgentError.noKey("Anthropic") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "model": config.model.isEmpty ? Provider.anthropic.defaultModel : config.model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw AgentError.http(code, ((obj["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? "")
        }
        if obj["stop_reason"] as? String == "refusal" {
            throw AgentError.refused(((obj["stop_details"] as? [String: Any])?["explanation"] as? String) ?? "")
        }
        let text = (obj["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { throw AgentError.empty }
        return text
    }

    /// Chat Completions: OpenAI and every server that speaks the same API.
    private static func openAI(base: String, key: String?, needKey: Bool, system: String, prompt: String, model: String) async throws -> String {
        if needKey && (key ?? "").isEmpty { throw AgentError.noKey("OpenAI") }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmed + "/chat/completions") else { throw AgentError.failed("The base URL is not valid.") }
        var req = URLRequest(url: url, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key, !key.isEmpty { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw AgentError.http(code, ((obj["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? "")
        }
        let text = ((obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw AgentError.empty }
        return text
    }

}
