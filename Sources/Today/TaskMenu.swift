import AppKit
import SwiftUI

/// Right click on a row: a native macOS menu with icon rows on top (date, area) and items below.
/// SwiftUI context menus cannot host icon rows, so the menu is built by hand.
extension View {
    func taskMenu(_ build: @escaping () -> NSMenu) -> some View {
        overlay(RightClickCatcher(build: build))
    }
}

private struct RightClickCatcher: NSViewRepresentable {
    let build: () -> NSMenu
    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.build = build; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.build = build }

    final class CatcherView: NSView {
        var build: (() -> NSMenu)?
        /// Normal clicks pass through to the row; right and ⌃-clicks are caught here.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let right = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { show(event) }
        override func mouseDown(with event: NSEvent) { show(event) }
        private func show(_ event: NSEvent) {
            guard let menu = build?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

/// Menu item backed by a closure.
final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

enum TaskMenu {
    static func item(_ title: String, _ symbol: String, tint: NSColor? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = MenuAction(run)
        let it = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        it.target = a
        it.representedObject = a
        if var img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            if let tint, let colored = img.withSymbolConfiguration(.init(paletteColors: [tint])) { img = colored }
            it.image = img
        }
        if let tint, title.hasPrefix("Delete") {
            it.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: tint])
        }
        return it
    }

    /// A labeled row of icons at the top of the menu.
    static func iconRow(_ label: String, _ icons: [(String, String, Color, () -> Void)], menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem()
        let view = MenuIconRow(label: label, icons: icons.map { i in
            MenuIconRow.Icon(symbol: i.0, help: i.1, tint: i.2) { i.3(); menu.cancelTracking() }
        })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 252, height: 62)
        it.view = host
        return it
    }

    @MainActor
    static func forTask(_ item: Item, store: Store) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        if !item.done {
            m.addItem(iconRow("Date", [
                ("sun.max", "Today", Color(Theme.ink), { store.setDue(item.id, Day.today) }),
                ("sunrise", "Tomorrow", Color(Theme.ink), { store.setDue(item.id, Day.plus(1)) }),
                ("calendar.badge.plus", "In a week", Color(Theme.ink), { store.setDue(item.id, Day.plus(7)) }),
                ("calendar", "Pick a date", Color(Theme.ink), { store.selected = item.id; store.pickDateFor = item.id }),
                ("xmark.square", "No date", Color(Theme.ink), { store.setDue(item.id, nil) }),
            ], menu: m))
        }
        m.addItem(areaRow(id: item.id, current: item.category, store: store, menu: m))
        m.addItem(.separator())
        let a = Assignee.of(item.assignee)
        if !a.isAgent {
            m.addItem(TaskMenu.item("Hand to \(Assignee.agent.name), it does it", "sparkles", tint: NSColor(Theme.accent)) { store.assign(item.id, Assignee.agent) })
        }
        for p in Assignee.people where p != a {
            m.addItem(TaskMenu.item("Hand to \(p.name)", "person.crop.circle.badge.plus") { store.assign(item.id, p) })
        }
        if a != .me {
            m.addItem(TaskMenu.item("Take it back", "arrow.uturn.backward") { store.assign(item.id, .me) })
        }
        m.addItem(.separator())
        m.addItem(TaskMenu.item(item.done ? "Mark as open" : "Mark as done", item.done ? "arrow.uturn.left.square" : "checkmark.square") {
            store.toggle(item.id)
        })
        m.addItem(TaskMenu.item("Open details", "sidebar.right") { store.selected = item.id })
        m.addItem(TaskMenu.item("Duplicate", "plus.square.on.square") { store.duplicate(item.id) })
        m.addItem(TaskMenu.item("Copy text", "doc.on.doc") { copy(item.text) })
        m.addItem(TaskMenu.item("Move to Thoughts", "lightbulb") { store.makeThought(item.id) })
        m.addItem(.separator())
        m.addItem(TaskMenu.item("Delete", "trash", tint: NSColor(Theme.red)) { store.delete(item.id) })
        return m
    }

    @MainActor
    private static func areaRow(id: String, current: String?, store: Store, menu: NSMenu) -> NSMenuItem {
        iconRow("Area", Area.all.map { a in
            (current == a.id ? "checkmark.circle.fill" : a.icon, a.name, Area.color(a.id), { store.setCategory(id, a.id) })
        }, menu: menu)
    }

    private static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Menu header: label and a row of icons with hover highlight.
struct MenuIconRow: View {
    struct Icon: Identifiable {
        let id = UUID()
        let symbol: String
        let help: String
        let tint: Color
        let action: () -> Void
    }
    let label: String
    let icons: [Icon]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.leading, 6)
            HStack(spacing: 2) {
                ForEach(icons) { i in IconCell(icon: i) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(width: 252, alignment: .leading)
    }

    private struct IconCell: View {
        let icon: Icon
        @State private var hover = false
        var body: some View {
            Button(action: icon.action) {
                Image(systemName: icon.symbol).font(.system(size: 15, weight: .light))
                    .foregroundStyle(icon.tint)
                    .frame(width: 30, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color(nsColor: .quaternaryLabelColor).opacity(0.5) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(icon.help)
            .onHover { hover = $0 }
        }
    }
}
