import SwiftUI

/// Right column: everything about the selected task and the thread with your agent.
struct DetailColumn: View {
    @Environment(Store.self) private var store

    var body: some View {
        Group {
            if let it = store.item(store.selected) {
                TaskDetail(item: it).id(it.id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.cursor").font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Theme.ghost)
                    Text("Select a task").font(.g(13)).foregroundStyle(Theme.faint)
                    Text("Details and the thread with your agent open here").font(.g(12)).foregroundStyle(Theme.ghost)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.white)
    }
}

struct TaskDetail: View {
    @Environment(Store.self) private var store
    let item: Item
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CheckBox(on: item.done) { store.toggle(item.id) }
                Rectangle().fill(Theme.line).frame(width: 1, height: 16)
                DueMenu(item: item)
                Spacer()
                AreaTag(id: item.id, category: item.category)
                AssigneePicker(item: item)
                Menu {
                    Button("Move to Thoughts") { store.makeThought(item.id) }
                    Divider()
                    Button("Delete", role: .destructive) { store.delete(item.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 24, height: 24)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 18).frame(height: 46)
            Rectangle().fill(Theme.lineSoft).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Task", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.g(17, .semibold)).kerning(-0.2)
                    .foregroundStyle(item.done ? Theme.faint : Theme.ink)
                    .focused($editing)
                    .onChange(of: text) { store.setText(item.id, text) }
                HStack(spacing: 8) {
                    if let s = Day.since(item.day), !item.done { Text(s) }
                    Text(Day.updated(item.movedAt))
                }
                .font(.g(11.5)).foregroundStyle(item.isStale ? Theme.red : Theme.faint)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)

            Thread(id: item.id, busy: store.isBusy(item), agentWorking: store.isBusy(item), state: item.agent_state)
        }
        .onAppear { text = item.text }
        .onChange(of: item.text) { if !editing { text = item.text } }
    }
}

/// Due date: quick options and a date picker.
struct DueMenu: View {
    @Environment(Store.self) private var store
    let item: Item
    @State private var picking = false
    @State private var date = Date()

    var body: some View {
        Button { picking.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11))
                if let d = item.due {
                    let (l, tone) = Day.dueLabel(d)
                    Text(l).foregroundStyle(tone == 0 ? Theme.red : Theme.blue)
                } else {
                    Text("Set date").foregroundStyle(Theme.faint)
                }
            }
            .font(.g(12.5, .medium)).foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    quick("Today", Day.today)
                    quick("Tomorrow", Day.plus(1))
                    quick("Next week", Day.plus(7))
                    quick("None", nil)
                }
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                    .onChange(of: date) { store.setDue(item.id, Day.string(date)); picking = false }
            }
            .padding(12)
            .onAppear { date = item.due.flatMap { Day.date($0) } ?? Date() }
        }
        .onAppear { if store.pickDateFor == item.id { picking = true; store.pickDateFor = nil } }
        .onChange(of: store.pickDateFor) { if store.pickDateFor == item.id { picking = true; store.pickDateFor = nil } }
    }

    private func quick(_ title: String, _ due: String?) -> some View {
        Button(title) { store.setDue(item.id, due); picking = false }.buttonStyle(.dash(.normal, small: true))
    }
}

/// Thread with the agent on a task. Plain text is a note; with @agent the agent does what you wrote.
struct Thread: View {
    @Environment(Store.self) private var store
    let id: String
    let busy: Bool
    let agentWorking: Bool
    let state: String?
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var comments: [Comment] { (store.threads[id] ?? []).filter { $0.kind != "system" } }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.lineSoft).frame(height: 1)
            // the input sits right under the task, not at the bottom of the window
            composer
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(comments) { CommentView(c: $0).id($0.id) }
                        status.id("status")
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                }
                .onAppear { proxy.scrollTo("status", anchor: .bottom) }
                .onChange(of: comments.count) { withAnimation { proxy.scrollTo("status", anchor: .bottom) } }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }   // a click anywhere in the block focuses the input
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Write here. Plain text is a note, tag @agent and it does what you wrote.", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.g(13.5)).lineLimit(3...12)
                .focused($focused)
                .onSubmit(send)
            HStack(spacing: 8) {
                Text("↩ send · ⌥↩ new line").font(.g(11)).foregroundStyle(Theme.ghost)
                Spacer()
                Button { draft = draft.hasPrefix("@agent") ? draft : "@agent " + draft; focused = true } label: {
                    Text("@agent").font(.g(11.5, .semibold)).foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 7).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accentBg))
                }
                .buttonStyle(.plain).help("Hand it to the agent: it reads the task and does what you wrote")
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(store.mentionsAgent(draft) ? Theme.accent : Theme.ink))
                }
                .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(focused ? Theme.white : Theme.page))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(focused ? Theme.borderHover : Theme.lineSoft))
    }

    @ViewBuilder private var status: some View {
        if busy {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(agentWorking ? "Working on it" : "Starting").font(.g(12, .medium)).foregroundStyle(Theme.sec)
                Spacer()
                Button("Stop") { store.stop(id) }.buttonStyle(.dash(.ghost, small: true))
            }
        } else if let state {
            switch state {
            case "done": badge("checkmark", "Done by the agent", Theme.green, Theme.greenBg)
            case "doing": badge("arrow.triangle.2.circlepath", "In progress", Theme.sec, Theme.chip)
            case "stuck": badge("exclamationmark.circle", "Stuck", Theme.red, Theme.accentBg)
            case "needs_you": badge("hand.raised", "Needs your decision", Theme.amber, Theme.amberBg)
            case "error": badge("exclamationmark.triangle", "The agent could not finish", Theme.red, Theme.accentBg)
            default: EmptyView()
            }
        }
    }

    private func badge(_ icon: String, _ text: String, _ fg: Color, _ bg: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.g(11.5, .medium))
        }
        .foregroundStyle(fg).padding(.horizontal, 8).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(bg))
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.send(id, t)
        draft = ""
    }
}
