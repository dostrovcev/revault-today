import SwiftUI

/// Who is on what: a column per person, stale tasks on top. Click opens details.
struct TeamView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Assignee.all) { a in column(a) }
            }
            .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 40)
        }
    }

    private func column(_ a: Assignee) -> some View {
        let list = store.openTasks.filter { ($0.assignee ?? "") == a.id && store.inArea($0.category) }
            .sorted { ($0.isStale ? 0 : 1, $0.movedAt) < ($1.isStale ? 0 : 1, $1.movedAt) }
        let doneToday = store.doneToday.filter { ($0.assignee ?? "") == a.id }.count
        let engine: [Item] = []
        return LazyVStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                AssigneeDot(a: a, size: 20)
                Text(a.name).font(.g(13, .semibold))
                Text("\(list.count + engine.count)").font(.g(12)).foregroundStyle(Theme.faint)
                Spacer()
                if doneToday > 0 { Text("\(doneToday) done today").font(.g(11)).foregroundStyle(Theme.green) }
            }
            .padding(.horizontal, 2).padding(.bottom, 2)
            if list.isEmpty && engine.isEmpty {
                Text("Nothing open").font(.g(12)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            ForEach(list) { TeamCard(item: $0) }
        }
        .frame(minWidth: 240, maxWidth: .infinity, alignment: .top)
    }
}

struct TeamCard: View {
    @Environment(Store.self) private var store
    let item: Item
    @State private var hover = false

    var body: some View {
        let on = store.selected == item.id
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                CheckBox(on: item.done) { store.toggle(item.id) }.padding(.top, 1)
                LinkedText(text: item.text, size: 12.5).lineLimit(3)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                StateTag(item: item)
                Text(age).font(.g(10.5)).foregroundStyle(item.isStale ? Theme.red : Theme.faint).lineLimit(1)
            }
            .padding(.leading, 24)
            if let t = store.threads[item.id]?.last?.text, !t.isEmpty {
                Text(t).font(.g(11.5)).foregroundStyle(Theme.sec).lineLimit(2).padding(.leading, 24)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.navOn : Theme.white))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.isStale ? Theme.accent.opacity(0.45) : (hover ? Theme.borderHover : Theme.line)))
        .contentShape(Rectangle())
        .onTapGesture { store.selected = item.id }
        .onHover { hover = $0 }
        .taskMenu { TaskMenu.forTask(item, store: store) }
    }

    private var age: String {
        let moved = Date().timeIntervalSince1970 - item.movedAt
        return Day.updated(item.movedAt) + (moved >= 2 * 86400 ? " (\(Int(moved / 86400))d)" : "")
    }
}
