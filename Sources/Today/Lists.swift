import AppKit
import SwiftUI

/// Middle column: the input and the selected list. Rows are lazy: only what is on screen lives in memory.
struct ListColumn: View {
    @Environment(Store.self) private var store

    var body: some View {
        switch store.tab {
        case .team: TeamView()
        case .thoughts: ThoughtsView()
        default:
            VStack(spacing: 0) {
                if store.tab != .completed { AddField().padding(.horizontal, 14).padding(.bottom, 8) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { content }
                        .padding(.horizontal, 14).padding(.bottom, 40)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.tab {
        case .today: today
        case .upcoming: upcoming
        case .completed: completed
        default: all
        }
    }

    // Today: overdue, due today, no date
    @ViewBuilder private var today: some View {
        let list = store.todayOpen
        let t = Day.today
        let overdue = list.filter { ($0.due ?? "9") < t }
        let due = list.filter { $0.due == t }
        let rest = list.filter { $0.due == nil }
        ListSection(key: "overdue", title: "Overdue", count: overdue.count, tone: Theme.red) { ForEach(overdue) { TaskLine(item: $0) } }
        ListSection(key: "today", title: "Today", count: due.count) { ForEach(due) { TaskLine(item: $0) } }
        ListSection(key: "nodate", title: overdue.isEmpty && due.isEmpty ? "My list" : "No date", count: rest.count) {
            ForEach(rest) { TaskLine(item: $0) }
        }
        if list.isEmpty {
            Text("Nothing here. Type above, or press ⌃⌥Space from any app.")
                .font(.g(12.5)).foregroundStyle(Theme.faint).padding(.vertical, 18)
        }
        ListSection(key: "doneToday", title: "Done today", count: store.doneToday.count, startsClosed: true) {
            ForEach(store.doneToday) { TaskLine(item: $0) }
        }
    }

    @ViewBuilder private var upcoming: some View {
        let list = store.upcoming
        let days = Array(Set(list.compactMap(\.due))).sorted()
        if list.isEmpty {
            Text("Nothing due in the next 7 days. Add «tomorrow», «fri» or «13.11» to a task.")
                .font(.g(12.5)).foregroundStyle(Theme.faint).padding(.vertical, 18)
        }
        ForEach(days, id: \.self) { d in
            let rows = list.filter { $0.due == d }
            ListSection(key: "d" + d, title: Day.dayHeader(d), count: rows.count) { ForEach(rows) { TaskLine(item: $0) } }
        }
    }

    // All: grouped by area, in the order from Settings
    @ViewBuilder private var all: some View {
        let tasks = store.visibleOpen
        ForEach(Area.all + [Area.sorting]) { a in
            let ts = tasks.filter { ($0.category ?? "") == a.id }
            if !ts.isEmpty {
                ListSection(key: "a" + a.id, title: a.name, count: ts.count, dot: Area.color(a.id)) {
                    ForEach(ts) { TaskLine(item: $0) }
                }
            }
        }
        if tasks.isEmpty {
            Text("Nothing open here.").font(.g(12.5)).foregroundStyle(Theme.faint).padding(.vertical, 18)
        }
    }

    @ViewBuilder private var completed: some View {
        if store.completed.isEmpty {
            Text("Nothing completed yet.").font(.g(12.5)).foregroundStyle(Theme.faint).padding(.vertical, 18)
        }
        ForEach(store.completed) { TaskLine(item: $0) }
    }
}

/// Collapsible section with a title and a count.
struct ListSection<Content: View>: View {
    let key: String
    let title: String
    let count: Int
    var tone: Color = Theme.ink
    var dot: Color? = nil
    var startsClosed = false
    var hint: String? = nil
    @ViewBuilder var content: () -> Content
    @AppStorage("closedSections") private var closed = ""

    init(key: String, title: String, count: Int, tone: Color = Theme.ink, dot: Color? = nil, startsClosed: Bool = false,
         hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.key = key; self.title = title; self.count = count; self.tone = tone; self.dot = dot
        self.startsClosed = startsClosed; self.hint = hint; self.content = content
    }

    private var isOpen: Bool {
        let set = Set(closed.split(separator: ",").map(String.init))
        return startsClosed ? set.contains("+" + key) : !set.contains(key)
    }

    var body: some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Button { toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ghost)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .frame(width: 12)
                        if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                        Text(title).font(.g(13, .semibold)).foregroundStyle(tone)
                        Text("\(count)").font(.g(12)).foregroundStyle(Theme.faint)
                        if let hint { Text(hint).font(.g(12)).foregroundStyle(Theme.faint) }
                        Spacer()
                    }
                    .padding(.top, 14).padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isOpen { content() }
            }
        }
    }

    private func toggle() {
        var set = Set(closed.split(separator: ",").map(String.init))
        let k = startsClosed ? "+" + key : key
        if set.contains(k) { set.remove(k) } else { set.insert(k) }
        closed = set.sorted().joined(separator: ",")
    }
}

/// Input above the list. Date, assignee and area are read from the text.
struct AddField: View {
    @Environment(Store.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 12, weight: .light)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain).font(.g(13.5))
                .focused($focused)
                .onSubmit {
                    // inside an area list the new task lands in that area
                    if store.capture(draft), let id = store.selected, let a = store.area { store.setCategory(id, a) }
                    draft = ""; focused = true
                }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(focused ? Theme.white : Theme.page))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.borderHover : Theme.lineSoft))
        .onChange(of: store.focusNewTask) { focused = true }
    }

    private var placeholder: String {
        if let w = store.who, !w.isEmpty { return "Add a task for \(Assignee.of(w).name)" }
        return "Add task · tomorrow, fri, 13.11 · @agent @name · #area · ? for a thought"
    }
}

// MARK: rows

/// A task in one line: checkbox, text, badges, assignee, date on the right.
struct TaskLine: View {
    @Environment(Store.self) private var store
    let item: Item
    @State private var hover = false

    var body: some View {
        let on = store.selected == item.id
        HStack(spacing: 10) {
            CheckBox(on: item.done) { store.toggle(item.id) }
            LinkedText(text: item.text, done: item.done)
                .lineLimit(1)
            Spacer(minLength: 8)
            RowBadges(threadID: item.id, busy: store.isBusy(item), state: item.agent_state, comments: store.comments(item.id))
            if let a = item.assignee, !a.isEmpty { AssigneeDot(a: Assignee.of(a), size: 17) }
            if let d = item.due, !item.done {
                let (label, tone) = Day.dueLabel(d)
                Text(label).font(.g(11.5)).foregroundStyle(tone == 0 ? Theme.red : (tone == 1 ? Theme.blue : Theme.faint))
            } else if item.isStale {
                Text(Day.updated(item.movedAt).replacingOccurrences(of: "updated ", with: "")).font(.g(11.5)).foregroundStyle(Theme.red)
                    .help("No movement for 2 days")
            }
        }
        .padding(.leading, 6).padding(.trailing, 8)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.navOn : (hover ? Theme.hover : .clear)))
        .overlay(alignment: .bottom) { if !on && !hover { Rectangle().fill(Theme.lineSoft).frame(height: 1).padding(.leading, 32) } }
        .contentShape(Rectangle())
        .onTapGesture { store.selected = item.id }
        .onHover { hover = $0 }
        .taskMenu { TaskMenu.forTask(item, store: store) }
    }
}

/// Quiet badges on the right: agent working, its result, number of messages.
struct RowBadges: View {
    let threadID: String
    let busy: Bool
    let state: String?
    let comments: Int

    var body: some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().controlSize(.mini).help("The agent is working on it")
            } else if let state {
                switch state {
                case "done": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).help("Done by the agent")
                case "needs_you": Image(systemName: "hand.raised.fill").foregroundStyle(Theme.amber).help("Needs your decision")
                case "stuck": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.red).help("Stuck")
                case "doing": Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.muted).help("In progress")
                case "error": Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red).help("The agent could not finish")
                default: EmptyView()
                }
            }
            if comments > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                    Text("\(comments)")
                }
                .foregroundStyle(Theme.faint)
            }
        }
        .font(.system(size: 10.5))
    }
}

/// Task text with clickable links. Link detection is cached.
struct LinkedText: View {
    let text: String
    var done = false
    var size: CGFloat = 13.5

    private static let cache = NSCache<NSString, NSAttributedString>()
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    var body: some View {
        Text(attributed)
            .font(.g(size))
            .foregroundStyle(done ? Theme.faint : Theme.ink)
            .strikethrough(done, color: Theme.ghost)
    }

    private var attributed: AttributedString {
        let key = text as NSString
        if let hit = Self.cache.object(forKey: key) { return AttributedString(hit) }
        var s = AttributedString(text)
        if text.contains("http") || text.contains("www.") {
            let ns = text as NSString
            for m in Self.detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
                guard let url = m.url, let r = Range(m.range, in: text),
                      let lo = AttributedString.Index(r.lowerBound, within: s), let hi = AttributedString.Index(r.upperBound, within: s)
                else { continue }
                s[lo..<hi].link = url
                s[lo..<hi].foregroundColor = Theme.blue
            }
        }
        Self.cache.setObject(NSAttributedString(s), forKey: key)
        return s
    }
}
