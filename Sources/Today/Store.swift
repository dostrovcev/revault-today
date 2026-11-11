import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// A task or a thought. Everything lives on this Mac in ~/Library/Application Support/Today.
struct Item: Codable, Identifiable, Equatable {
    var id: String
    var kind: String                // task | thought
    var text: String
    var done: Bool = false
    var day: String                 // the day the task was created, yyyy-MM-dd
    var done_day: String? = nil
    var position: Double = 0
    var created: Double
    var updated: Double
    var deleted: Bool? = nil
    var assignee: String? = nil     // nil = me; "agent"; or a person id
    var category: String? = nil     // area id
    var due: String? = nil          // yyyy-MM-dd
    var agent_state: String? = nil  // answered | done | needs_you | error
    var last_activity: Double? = nil

    var movedAt: Double { max(updated, last_activity ?? 0) }
    var isStale: Bool { !done && Date().timeIntervalSince1970 - movedAt > 2 * 86400 }
    var isTask: Bool { kind == "task" }
}

struct Comment: Codable, Identifiable, Equatable {
    var id: Int
    var author: String
    var author_name: String?
    var kind: String                // user | agent | pending
    var text: String
    var created: Double
    var error: Bool?

    var fromAgent: Bool { kind == "agent" }
}

/// What the middle column shows.
enum Tab: String { case today, upcoming, all, team, thoughts, completed }

/// An area a task belongs to. Names come from Settings; icons and colors follow the position.
struct Area: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String

    private static let icons = ["creditcard", "arrow.right.circle", "ladybug", "sparkles", "banknote", "person.2", "gearshape",
                                "book", "house", "heart", "briefcase", "star"]
    private static let palette: [UInt32] = [0x2E7A55, 0x3A6FD8, 0xC93A2E, 0x8B5CF6, 0xD99A1E, 0xE0679A, 0x7C8686,
                                            0x0E9AA7, 0x9A6B3F, 0xD64F8B, 0x4F5BD5, 0x6B8E23]

    @MainActor static var all: [Area] {
        Config.shared.areas.enumerated().map { i, n in
            Area(id: slug(n), name: n, icon: icons[i % icons.count])
        }
    }
    static let sorting = Area(id: "", name: "No area", icon: "tray")
    @MainActor static func of(_ id: String?) -> Area { all.first { $0.id == id } ?? sorting }
    @MainActor static func color(_ id: String) -> Color {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return Color(hex: 0xB4BABA) }
        return Color(hex: palette[i % palette.count])
    }
    static func slug(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }
}

/// Who a task is on: me, the agent, or a person from Settings.
struct Assignee: Identifiable, Hashable {
    let id: String                  // "" = me
    let name: String
    let aliases: [String]

    static let me = Assignee(id: "", name: "Me", aliases: ["me"])
    @MainActor static var agent: Assignee {
        let n = Config.shared.agent.name
        return Assignee(id: "agent", name: n, aliases: ["agent", "ai", Area.slug(n)])
    }
    @MainActor static var people: [Assignee] {
        Config.shared.people.map { Assignee(id: Area.slug($0), name: $0, aliases: [Area.slug($0)]) }
    }
    @MainActor static var all: [Assignee] { [me, agent] + people }
    @MainActor static func of(_ id: String?) -> Assignee { all.first { $0.id == (id ?? "") } ?? me }
    var isAgent: Bool { id == "agent" }
    var isPerson: Bool { !id.isEmpty && id != "agent" }
    var initial: String { id.isEmpty ? "Me".prefix(1).uppercased() : String(name.prefix(1)).uppercased() }
}

@Observable
@MainActor
final class Store {
    var items: [Item] = [] { didSet { rebuild(); schedulePersist() } }
    var threads: [String: [Comment]] = [:] { didSet { schedulePersist() } }
    /// Tasks the agent is working on right now.
    var running: Set<String> = []
    var selected: String?
    var pickDateFor: String?
    var error: String? { didSet { if error != nil { clearErrorLater() } } }
    var tab: Tab = Tab(rawValue: DevTools.env["TODAY_TAB"] ?? "") ?? .today
    var who: String? = DevTools.env["TODAY_WHO"]
    var area: String? = DevTools.env["TODAY_AREA"]
    var focusNewTask = 0

    private(set) var openTasks: [Item] = []
    private(set) var doneToday: [Item] = []
    private(set) var thoughts: [Item] = []
    private(set) var completed: [Item] = []

    private var tasks: [String: Task<Void, Never>] = [:]
    private var persistTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?

    private struct Local: Codable { var items: [Item]; var threads: [String: [Comment]] }
    private static let localURL = AppPaths.file("items.json")
    private static let diskQueue = DispatchQueue(label: "today.disk", qos: .utility)

    // MARK: derived lists, computed once per change instead of every frame

    private func rebuild() {
        let t = Day.today
        var open: [Item] = [], done: [Item] = [], th: [Item] = [], comp: [Item] = []
        for it in items where it.deleted != true {
            if it.kind == "thought" { th.append(it) }
            else if it.isTask {
                if !it.done { open.append(it) } else {
                    comp.append(it)
                    if it.done_day == t { done.append(it) }
                }
            }
        }
        openTasks = open.sorted { ($0.position, $0.created) < ($1.position, $1.created) }
        doneToday = done.sorted { $0.updated > $1.updated }
        thoughts = th.sorted { $0.created > $1.created }
        completed = comp.sorted { $0.updated > $1.updated }.prefix(300).map { $0 }
    }

    func item(_ id: String?) -> Item? { id.flatMap { i in items.first { $0.id == i } } }
    func inArea(_ cat: String?) -> Bool { area == nil || (cat ?? "") == area }
    func isBusy(_ it: Item) -> Bool { running.contains(it.id) }
    func comments(_ id: String) -> Int { threads[id]?.count ?? 0 }

    var visibleOpen: [Item] { (who == nil ? openTasks : openTasks.filter { ($0.assignee ?? "") == who }).filter { inArea($0.category) } }
    var visibleDone: [Item] { (who == nil ? doneToday : doneToday.filter { ($0.assignee ?? "") == who }).filter { inArea($0.category) } }
    func openCount(_ a: Assignee) -> Int { openTasks.reduce(0) { $0 + (($1.assignee ?? "") == a.id ? 1 : 0) } }
    func areaCount(_ a: String?) -> Int { openTasks.reduce(0) { $0 + ((a == nil || ($1.category ?? "") == a) ? 1 : 0) } }
    var todayCount: Int { let t = Day.today; return openTasks.filter { ($0.due ?? "") <= t }.count }
    var upcomingCount: Int { let t = Day.today, e = Day.plus(7); return openTasks.filter { ($0.due ?? "") > t && ($0.due ?? "") <= e }.count }

    var todayOpen: [Item] { let t = Day.today; return visibleOpen.filter { ($0.due ?? "") <= t } }
    var upcoming: [Item] {
        let t = Day.today, end = Day.plus(7)
        return visibleOpen.filter { if let d = $0.due { return d > t && d <= end } else { return false } }
            .sorted { ($0.due ?? "", $0.position) < ($1.due ?? "", $1.position) }
    }

    // MARK: start and disk

    func start() {
        if DevTools.isDemo { Demo.seed(self); return }
        if let l = JSONFile.load(Local.self, from: Self.localURL) {
            items = l.items; threads = l.threads
        }
        // notifications need a real app bundle; `swift run` has none
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Writes are batched and go to a background queue: typing never waits for the disk.
    private func schedulePersist() {
        guard !DevTools.isDemo else { return }
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            let live = Set(self.items.filter { $0.deleted != true }.map(\.id))
            let snap = Local(items: self.items.filter { $0.deleted != true },
                             threads: self.threads.filter { live.contains($0.key) })
            Self.diskQueue.async { JSONFile.save(snap, to: Self.localURL) }
        }
    }

    // MARK: edits

    private func touch(_ id: String, _ change: (inout Item) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        items[i].updated = Date().timeIntervalSince1970
    }

    private func newItem(_ kind: String, _ text: String, position: Double) -> Item {
        let now = Date().timeIntervalSince1970
        return Item(id: UUID().uuidString.lowercased(), kind: kind, text: text, day: Day.today, position: position,
                    created: now, updated: now)
    }

    @discardableResult
    func addTask(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var it = newItem("task", t, position: (openTasks.map(\.position).max() ?? 0) + 1)
        if let who, !who.isEmpty { it.assignee = who }
        if let area { it.category = area }
        items.append(it)
        return it.id
    }

    /// A line from your head: "?" first makes it a thought, "@agent" or "@name" hands it over,
    /// "#area" files it, and "tomorrow", "fri", "13.11" set the date.
    @discardableResult
    func capture(_ raw: String) -> Bool {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t.hasPrefix("?") { addThought(String(t.dropFirst())); return true }
        var who: Assignee? = nil
        for a in Assignee.all where !a.id.isEmpty {
            let pattern = "(?<![\\w.@])@(" + a.aliases.map(NSRegularExpression.escapedPattern).joined(separator: "|") + ")\\b"
            if let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                who = a; t.removeSubrange(r); break
            }
        }
        var cat: String? = nil
        for a in Area.all {
            if let r = t.range(of: "(?<![\\w])#" + NSRegularExpression.escapedPattern(for: a.id) + "\\b", options: [.regularExpression, .caseInsensitive]) {
                cat = a.id; t.removeSubrange(r); break
            }
        }
        let (rest, due) = DueParser.extract(t)
        t = rest.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",:")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let id = addTask(t) else { return false }
        if let i = items.firstIndex(where: { $0.id == id }) {
            if let due { items[i].due = due }
            if let cat { items[i].category = cat }
        }
        if let who { assign(id, who) }
        selected = id
        return true
    }

    /// Hand a task over. The agent starts working right away; a person just gets it on their column.
    func assign(_ id: String, _ a: Assignee) {
        let was = items.first { $0.id == id }?.assignee ?? ""
        touch(id) { $0.assignee = a.id.isEmpty ? nil : a.id }
        if a.isAgent && was != a.id { send(id, "@\(a.aliases[0]) do this task.") }
    }

    func addThought(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(newItem("thought", t, position: 0))
    }

    func setText(_ id: String, _ text: String) {
        guard items.first(where: { $0.id == id })?.text != text else { return }
        touch(id) { $0.text = text }
    }

    func toggle(_ id: String) {
        let bottom = (openTasks.map(\.position).max() ?? 0) + 1
        touch(id) {
            $0.done.toggle()
            $0.done_day = $0.done ? Day.today : nil
            if !$0.done { $0.position = bottom }
        }
    }

    func delete(_ id: String) {
        touch(id) { $0.deleted = true }
        threads[id] = nil
        if selected == id { selected = nil }
    }

    func setDue(_ id: String, _ due: String?) { touch(id) { $0.due = due } }
    func setCategory(_ id: String, _ cat: String) { touch(id) { $0.category = cat } }

    func duplicate(_ id: String) {
        guard let src = items.first(where: { $0.id == id }) else { return }
        var it = newItem(src.kind, src.text, position: src.position + 0.01)
        it.due = src.due; it.category = src.category
        items.append(it)
        selected = it.id
    }

    func makeTask(_ id: String) {
        let bottom = (openTasks.map(\.position).max() ?? 0) + 1
        touch(id) { $0.kind = "task"; $0.day = Day.today; $0.done = false; $0.done_day = nil; $0.position = bottom }
        tab = .today
        selected = id
    }

    func makeThought(_ id: String) { touch(id) { $0.kind = "thought"; $0.done = false; $0.done_day = nil } }

    // MARK: talking to the agent

    func mentionsAgent(_ text: String) -> Bool {
        let names = Assignee.agent.aliases.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        return text.range(of: "(?<![\\w.@])@(" + names + ")\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func nextCommentID(_ id: String) -> Int { (threads[id]?.map(\.id).max() ?? 0) + 1 }

    /// A line in the task's thread. Plain text is a note; with @agent the agent reads the task and does it.
    func send(_ id: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, item(id) != nil else { return }
        let now = Date().timeIntervalSince1970
        threads[id, default: []].append(Comment(id: nextCommentID(id), author: "me", author_name: "You", kind: "user",
                                                text: t, created: now))
        touch(id) { $0.last_activity = now }
        guard mentionsAgent(t) else { return }
        runAgent(id)
    }

    private func runAgent(_ id: String) {
        guard let task = item(id) else { return }
        tasks[id]?.cancel()
        running.insert(id)
        touch(id) { $0.agent_state = nil }
        let thread = threads[id] ?? []
        let cfg = Config.shared.agent
        tasks[id] = Task { [weak self] in
            let result: Result<String, Error>
            do { result = .success(try await AgentRunner.reply(task: task, thread: thread, config: cfg)) }
            catch { result = .failure(error) }
            guard let self, !Task.isCancelled else { return }
            self.running.remove(id)
            self.tasks[id] = nil
            let (text, state, failed): (String, String, Bool)
            switch result {
            case .success(let raw):
                let parsed = AgentRunner.state(from: raw)
                (text, state, failed) = (parsed.0, parsed.1, false)
            case .failure(let e):
                (text, state, failed) = (e.localizedDescription, "error", true)
            }
            let now = Date().timeIntervalSince1970
            self.threads[id, default: []].append(Comment(id: self.nextCommentID(id), author: "agent",
                                                         author_name: Config.shared.agent.name, kind: "agent",
                                                         text: text, created: now, error: failed))
            self.touch(id) { $0.agent_state = state; $0.last_activity = now }
            self.notify(task.text, state: state)
        }
    }

    func stop(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        running.remove(id)
    }

    // MARK: misc

    private func clearErrorLater() {
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.error = nil
        }
    }

    private func notify(_ task: String, state: String) {
        guard !NSApp.isActive, !DevTools.isDemo, Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = state == "needs_you" ? "\(Config.shared.agent.name) needs you" : "\(Config.shared.agent.name) answered"
        c.body = task
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Demo data seeds through here so the view code stays the same.
    func load(items: [Item], threads: [String: [Comment]]) { self.items = items; self.threads = threads }
}

/// Fictional sample data for screenshots: TODAY_DEMO=1.
enum Demo {
    @MainActor static func seed(_ s: Store) {
        let now = Date().timeIntervalSince1970
        func t(_ id: String, _ text: String, _ pos: Double, due: String? = nil, who: String? = nil, cat: String? = nil,
               state: String? = nil, done: Bool = false) -> Item {
            var it = Item(id: id, kind: "task", text: text, done: done, day: Day.today, done_day: done ? Day.today : nil,
                          position: pos, created: now - pos * 900, updated: now)
            it.due = due; it.assignee = who; it.category = cat; it.agent_state = state
            return it
        }
        let areas = Area.all.map(\.id)
        func a(_ i: Int) -> String? { areas.indices.contains(i) ? areas[i] : nil }
        s.load(items: [
            t("d1", "Reply to the investor about the term sheet", 1, due: Day.plus(-1), cat: a(4), state: "needs_you"),
            t("d2", "Send the onboarding docs to the new client", 2, due: Day.today, cat: a(0), state: "done"),
            t("d3", "Draft a launch post for the new feature", 3, due: Day.plus(2), who: "agent", cat: a(3)),
            t("d4", "Fix the signup form on Safari", 4, cat: a(2)),
            t("d5", "Prepare the call with Northwind: pricing, first list", 5, cat: a(1)),
            t("d6", "Book flights for the conference https://example.com/summit", 6, due: Day.plus(5), cat: a(6)),
            t("d7", "Approve the first campaign", 7, cat: a(0), done: true),
            Item(id: "h1", kind: "thought", text: "Weekly review should open with one number: meetings booked.", day: Day.today,
                 created: now - 3600, updated: now),
        ], threads: [
            "d1": [Comment(id: 1, author: "me", author_name: "You", kind: "user", text: "@agent draft my reply, short", created: now - 4000),
                   Comment(id: 2, author: "agent", author_name: "Agent", kind: "agent",
                           text: "Draft below. One open point: the size of the first tranche. Tell me the number and I finish it.\n\nHi Sam, thanks for sending the term sheet...",
                           created: now - 3900)],
            "d2": [Comment(id: 1, author: "me", author_name: "You", kind: "user", text: "@agent list what the docs must include", created: now - 2000),
                   Comment(id: 2, author: "agent", author_name: "Agent", kind: "agent", text: "Done: a 6-point checklist is below.", created: now - 1900)],
        ])
        s.selected = DevTools.env["TODAY_SELECT"]
    }
}
