import AppKit
import SwiftUI

extension Notification.Name {
    static let toggleSidebar = Notification.Name("rvt.toggleSidebar")
}

/// Three columns: lists, tasks, details. Drag the borders to resize.
struct RootView: View {
    @Environment(Store.self) private var store
    /// Sidebar: full, icons, hidden.
    @AppStorage("sidebarMode") private var mode = "full"
    @AppStorage("sidebarWidth") private var sidebarWidth = 210.0
    @AppStorage("detailWidth") private var detailWidth = 420.0
    @AppStorage("detailHidden") private var detailHidden = false
    /// Settings changed (areas, people, agent name): redraw the lists with the new names.
    @State private var configTick = 0

    var body: some View {
        Group {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if mode != "hidden" {
                            Sidebar(collapsed: mode == "icons")
                                .frame(width: mode == "icons" ? 60 : sidebarWidth)
                            if mode == "full" {
                                Splitter(width: $sidebarWidth, range: 170...340, grows: .right)
                            } else {
                                Rectangle().fill(Theme.line).frame(width: 1)
                            }
                        }
                        VStack(spacing: 0) {
                            TopBar(mode: $mode, detailHidden: $detailHidden)
                            ListColumn()
                        }
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.white)
                        if !detailHidden {
                            Splitter(width: $detailWidth, range: 300...max(320, geo.size.width * 0.6), grows: .left)
                            DetailColumn()
                                .frame(width: detailWidth)
                        }
                    }
                }
        }
        .id(configTick)
        .onReceive(NotificationCenter.default.publisher(for: Config.changed)) { _ in configTick += 1 }
        .background(Theme.page)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let e = store.error {
                Text(e)
                    .font(.g(12.5, .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.ink))
                    .padding(.bottom, 20)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in mode = mode == "hidden" ? "full" : "hidden" }
    }
}

/// Column border: a 1px line with a 7px drag area.
struct Splitter: View {
    enum Grows { case left, right }
    @Binding var width: Double
    let range: ClosedRange<Double>
    let grows: Grows
    @State private var start: Double?
    @State private var hover = false

    var body: some View {
        Rectangle().fill(hover || start != nil ? Theme.borderHover : Theme.line)
            .frame(width: 1)
            .overlay(
                Color.clear.frame(width: 7).contentShape(Rectangle())
                    .onHover { h in
                        hover = h
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            if start == nil { start = width }
                            let delta = grows == .right ? v.translation.width : -v.translation.width
                            width = min(max((start ?? width) + delta, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in start = nil })
            )
    }
}

// MARK: left column: smart lists, areas, people

struct Sidebar: View {
    @Environment(Store.self) private var store
    var collapsed: Bool

    var body: some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: 1) {
            Group {
                if collapsed {
                    Image(systemName: "checkmark.square.fill").font(.system(size: 17)).foregroundStyle(Theme.accent)
                } else {
                    AppTitle(size: 15)
                }
            }
            .padding(.leading, collapsed ? 0 : 8)
            .frame(height: 30)
            .padding(.top, 36).padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: collapsed ? .center : .leading, spacing: 1) {
                    nav(.today, "sun.max", "Today", store.todayCount)
                    nav(.upcoming, "calendar", "Next 7 Days", store.upcomingCount)
                    nav(.all, "tray.full", "All", store.openTasks.count)
                    nav(.team, "person.2", "Team", store.openTasks.filter(\.isStale).count, hot: true)
                    nav(.thoughts, "lightbulb", "Thoughts", store.thoughts.count)

                    label("Areas")
                    ForEach(Area.all) { a in
                        NavItem(icon: a.icon, tint: Area.color(a.id), title: a.name, count: store.areaCount(a.id),
                                on: store.tab == .all && store.area == a.id && store.who == nil, collapsed: collapsed) {
                            store.tab = .all; store.area = a.id; store.who = nil
                        }
                    }

                    label("People")
                    ForEach(Assignee.all) { a in
                        NavItem(avatar: a, title: a.name, count: store.openCount(a),
                                on: store.tab == .all && store.who == a.id && store.area == nil, collapsed: collapsed) {
                            store.tab = .all; store.who = a.id; store.area = nil
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
            nav(.completed, "checkmark.circle", "Completed", 0)
            SettingsRow(collapsed: collapsed)
        }
        .padding(.horizontal, collapsed ? 6 : 8).padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.side)
    }

    private func nav(_ t: Tab, _ icon: String, _ title: String, _ n: Int, hot: Bool = false) -> some View {
        NavItem(icon: icon, title: title, count: n, hot: hot,
                on: store.tab == t && store.area == nil && store.who == nil, collapsed: collapsed) {
            store.tab = t; store.area = nil; store.who = nil
        }
    }

    @ViewBuilder private func label(_ t: String) -> some View {
        if collapsed {
            Rectangle().fill(Theme.line).frame(width: 22, height: 1).padding(.vertical, 8)
        } else {
            Text(t).font(.g(11, .medium)).foregroundStyle(Theme.faint)
                .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 3)
        }
    }
}

struct NavItem: View {
    var icon: String? = nil
    var avatar: Assignee? = nil
    var tint: Color? = nil
    let title: String
    var count = 0
    var hot = false
    var on = false
    var collapsed = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if let avatar {
                        AssigneeDot(a: avatar, size: 17)
                    } else if let icon {
                        Image(systemName: icon).font(.system(size: 13.5, weight: .light))
                            .foregroundStyle(tint ?? (on ? Theme.ink : Theme.navIcon))
                    }
                }
                .frame(width: 20)
                if !collapsed {
                    Text(title).font(.g(13, on ? .medium : .regular)).foregroundStyle(on ? Theme.ink : Theme.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if count > 0 {
                        Text("\(count)").font(.g(11.5)).foregroundStyle(hot ? Theme.accentText : Theme.faint)
                    }
                }
            }
            .padding(.horizontal, collapsed ? 0 : 8)
            .frame(width: collapsed ? 36 : nil, height: 28)
            .frame(maxWidth: collapsed ? nil : .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.navOn : (hover ? Theme.navHover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? title : "")
        .onHover { hover = $0 }
    }
}

// MARK: top bar of the middle column

struct TopBar: View {
    @Environment(Store.self) private var store
    @Binding var mode: String
    @Binding var detailHidden: Bool

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Full sidebar") { mode = "full" }
                Button("Icons only") { mode = "icons" }
                Button("Hide sidebar") { mode = "hidden" }
            } label: {
                Image(systemName: "sidebar.left").font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.muted).frame(width: 26, height: 26)
            } primaryAction: {
                mode = mode == "full" ? "icons" : (mode == "icons" ? "hidden" : "full")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Click: full, icons, hidden. ⌘\\ hides it")
            .padding(.leading, mode == "hidden" ? 66 : 0)

            Text(title).font(.g(17, .semibold)).kerning(-0.3).lineLimit(1)
            if let sub = subtitle { Text(sub).font(.g(12)).foregroundStyle(Theme.faint).lineLimit(1) }
            Spacer(minLength: 6)
            Button { detailHidden.toggle() } label: {
                Image(systemName: "sidebar.right").font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.muted).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain).help("Hide or show the details")
        }
        .padding(.leading, 14).padding(.trailing, 12)
        .frame(height: 46)
    }

    private var title: String {
        if let w = store.who { return Assignee.of(w).name }
        if let a = store.area { return Area.of(a).name }
        switch store.tab {
        case .today: return "Today"
        case .upcoming: return "Next 7 Days"
        case .all: return "All"
        case .team: return "Team"
        case .thoughts: return "Thoughts"
        case .completed: return "Completed"
        }
    }

    private var subtitle: String? { store.tab == .today && store.area == nil && store.who == nil ? Day.title : nil }
}
