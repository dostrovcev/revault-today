import SwiftUI

// Shared UI pieces: assignee dot, checkbox, thread message, tags, thoughts.

/// Assignee dot: me, the agent (accent color), people.
struct AssigneeDot: View {
    let a: Assignee
    var size: CGFloat = 20

    var body: some View {
        Text(a.initial)
            .font(.g(size * 0.5, .semibold))
            .foregroundStyle(a.isAgent ? .white : Theme.ink2)
            .frame(width: size, height: size)
            .background(Circle().fill(a.isAgent ? Theme.accent : (a == .me ? Theme.avatar : Theme.chip)))
            .overlay(Circle().stroke(a.isPerson ? Theme.border : .clear))
    }
}

/// Who the task is on: a dot with a letter; click to hand it over.
struct AssigneePicker: View {
    @Environment(Store.self) private var store
    let item: Item

    var body: some View {
        let a = Assignee.of(item.assignee)
        Menu {
            ForEach(Assignee.all) { x in
                Button {
                    store.assign(item.id, x)
                } label: {
                    if x == a { Label(menuTitle(x), systemImage: "checkmark") } else { Text(menuTitle(x)) }
                }
            }
        } label: {
            AssigneeDot(a: a, size: 20)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(a == .me ? "Mine. Click to hand it to the agent or a person" : "Assigned to \(a.name)")
        .padding(.top, 0)
    }

    private func menuTitle(_ x: Assignee) -> String {
        switch x.id {
        case "": return "Me"
        case "agent": return "\(x.name) (does it now)"
        default: return x.name
        }
    }
}

struct CheckBox: View {
    var on: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.ink : (hover ? Theme.muted : Theme.ghost), lineWidth: 1.3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(on ? Theme.ink : .clear))
                if on || hover {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(on ? .white : Theme.muted)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let name: String
    let action: () -> Void
    @State private var hover = false
    init(_ name: String, action: @escaping () -> Void) { self.name = name; self.action = action }

    var body: some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(hover ? Theme.ink : Theme.faint)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.chip : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct CommentView: View {
    let c: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if c.fromAgent {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    Text(c.author_name ?? "Agent").font(.g(11, .semibold)).foregroundStyle(Theme.ink)
                } else {
                    Text("You").font(.g(11, .semibold)).foregroundStyle(Theme.sec)
                }
                Text(c.kind == "pending" ? "sending" : Day.stamp(c.created)).font(.g(10.5)).foregroundStyle(Theme.faint)
            }
            Text(rich)
                .font(.g(12.5))
                .foregroundStyle(c.error == true ? Theme.red : Theme.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, c.fromAgent ? 8 : 2).padding(.vertical, c.fromAgent ? 6 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(c.fromAgent ? Theme.page : .clear))
        .opacity(c.kind == "pending" ? 0.6 : 1)
    }

    private var rich: AttributedString {
        (try? AttributedString(markdown: c.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(c.text)
    }
}

/// Task state in one word for a card.
struct StateTag: View {
    let item: Item
    @Environment(Store.self) private var store

    var body: some View {
        let (t, fg, bg) = look
        Text(t).font(.g(11, .medium)).foregroundStyle(fg)
            .padding(.horizontal, 6).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }

    private var look: (String, Color, Color) {
        if item.done { return ("Done", Theme.green, Theme.greenBg) }
        if store.isBusy(item) { return ("Agent working", Theme.accentText, Theme.accentBg) }
        switch item.agent_state {
        case "done": return ("Done, tick it", Theme.green, Theme.greenBg)
        case "doing": return ("In progress", Theme.sec, Theme.chip)
        case "stuck": return ("Stuck", Theme.red, Theme.accentBg)
        case "needs_you": return ("Needs you", Theme.amber, Theme.amberBg)
        case "error": return ("Failed", Theme.red, Theme.accentBg)
        default: return item.isStale ? ("No movement", Theme.red, Theme.accentBg) : ("To do", Theme.muted, Theme.chip)
        }
    }
}

/// Area tag on a task: click to change.
struct AreaTag: View {
    @Environment(Store.self) private var store
    let id: String
    let category: String?

    var body: some View {
        let a = Area.of(category)
        Menu {
            ForEach(Area.all) { x in
                Button { store.setCategory(id, x.id) } label: {
                    if x.id == category { Label(x.name, systemImage: "checkmark") } else { Text(x.name) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: a.icon).font(.system(size: 9))
                Text(a.name).font(.g(10.5, .medium))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 5).frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.chip))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Area. Click to change")
    }
}

struct ThoughtsView: View {
    @Environment(Store.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Thoughts").font(.g(22, .semibold)).kerning(-0.5)
                    Text("Move one to Today when it is ready").font(.g(12.5)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 14)

                VStack(alignment: .trailing, spacing: 6) {
                    TextField("What's on your mind?", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.g(13.5))
                        .lineLimit(2...10)
                        .focused($focused)
                    HStack {
                        Text("⌘↩ to save").font(.g(11)).foregroundStyle(Theme.faint)
                        Spacer()
                        Button("Save") { save() }
                            .buttonStyle(.dash(.primary, small: true))
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.white))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.borderHover : Theme.line))
                .padding(.bottom, 4)

                if store.thoughts.isEmpty {
                    Text("No thoughts yet.")
                        .font(.g(13)).foregroundStyle(Theme.faint)
                        .padding(.vertical, 32).frame(maxWidth: .infinity)
                }
                ForEach(store.thoughts) { ThoughtRow(item: $0) }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 48)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .onAppear { focused = true }
    }

    private func save() {
        store.addThought(draft)
        draft = ""
        focused = true
    }
}

struct ThoughtRow: View {
    @Environment(Store.self) private var store
    let item: Item
    @State private var text = ""
    @State private var hover = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.g(13.5)).foregroundStyle(Theme.ink)
                    .focused($editing)
                    .onChange(of: text) { store.setText(item.id, text) }
                    .onChange(of: editing) {
                        if !editing, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.delete(item.id) }
                    }
                Text(Day.stamp(item.created)).font(.g(11)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                Button("To today") { store.makeTask(item.id) }.buttonStyle(.dash(.normal, small: true))
                IconButton("trash") { store.delete(item.id) }.help("Delete")
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .onHover { hover = $0 }
        .onAppear { text = item.text }
        .onChange(of: item.text) { if !editing { text = item.text } }
        .contextMenu {
            Button("Move to Today") { store.makeTask(item.id) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(item.id) }
        }
    }
}


/// Bottom of the sidebar: opens Settings (⌘,) where you pick the model and add your key.
struct SettingsRow: View {
    var collapsed: Bool
    @State private var hover = false

    var body: some View {
        SettingsLink {
            HStack(spacing: 9) {
                Image(systemName: "gearshape").font(.system(size: 13.5, weight: .light)).foregroundStyle(Theme.navIcon)
                    .frame(width: 20)
                if !collapsed {
                    Text("Settings").font(.g(13)).foregroundStyle(Theme.ink2)
                    Spacer()
                    Text(Config.shared.agent.provider == .claudeCode ? "Claude Code" : Config.shared.agent.model)
                        .font(.g(11)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            .padding(.horizontal, collapsed ? 0 : 8)
            .frame(width: collapsed ? 36 : nil, height: 30)
            .frame(maxWidth: collapsed ? nil : .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.navHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// App name in the sidebar.
struct AppTitle: View {
    var size: CGFloat = 15
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.square.fill").font(.system(size: size)).foregroundStyle(Theme.accent)
            Text("Today").font(.g(size, .semibold)).kerning(-0.3).foregroundStyle(Theme.ink)
        }
    }
}
