import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct TodayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()

    init() {
        Theme.registerFonts()
        // debug: TODAY_AGENT_TEST=claudeCode|anthropic|openai|compatible makes one real call, prints it and quits
        if let p = DevTools.env["TODAY_AGENT_TEST"], let provider = Provider(rawValue: p) {
            Task { @MainActor in
                var cfg = Config.shared.agent
                cfg.provider = provider
                if let m = DevTools.env["TODAY_AGENT_MODEL"] { cfg.model = m } else { cfg.model = provider.defaultModel }
                let now = Date().timeIntervalSince1970
                let task = Item(id: "t", kind: "task", text: "Write a two-line thank-you note to a client after a good call",
                                day: Day.today, created: now, updated: now)
                let c = Comment(id: 1, author: "me", kind: "user", text: "@agent draft it", created: now)
                do {
                    let r = try await AgentRunner.reply(task: task, thread: [c], config: cfg)
                    let (text, state) = AgentRunner.state(from: r)
                    print("STATE:", state); print(text)
                    exit(0)
                } catch { print("ERROR:", error.localizedDescription); exit(1) }
            }
        }
    }

    var body: some Scene {
        WindowGroup("Today", id: "main") {
            Group {
                if DevTools.env["TODAY_SETTINGS_PREVIEW"] != nil {
                    SettingsView()
                } else if DevTools.env["TODAY_MENU_PREVIEW"] != nil {
                    // debug: render the top of the context menu, NSMenu itself does not show up in window snapshots
                    VStack(spacing: 0) {
                        MenuIconRow(label: "Date", icons: ["sun.max", "sunrise", "calendar.badge.plus", "calendar", "xmark.square"].map {
                            MenuIconRow.Icon(symbol: $0, help: "", tint: Theme.ink) {} })
                        MenuIconRow(label: "Area", icons: Area.all.map { MenuIconRow.Icon(symbol: $0.icon, help: "", tint: Area.color($0.id)) {} })
                    }
                    .padding(8).background(Color.white)
                } else {
                    RootView()
                }
            }
                .environment(store)
                .task {
                    store.start()
                    if !DevTools.isDemo { QuickCapture.install(store) }
                    if DevTools.env["TODAY_CAPTURE"] != nil { QuickCapture.toggle(store) }
                    DevTools.scheduleSnapshot()
                }
                .frame(minWidth: 680, minHeight: 440)
                .font(.g(13.5))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.tab = .today; store.focusNewTask += 1 }.keyboardShortcut("n")
            }
            CommandGroup(before: .toolbar) {
                Button("Hide or Show Sidebar") { NotificationCenter.default.post(name: .toggleSidebar, object: nil) }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("Quick Capture") { QuickCapture.toggle(store) }
                Divider()
                Button("Today") { store.tab = .today; store.who = nil }.keyboardShortcut("1")
                Button("Team") { store.tab = .team; store.who = nil }.keyboardShortcut("2")
                Button("Thoughts") { store.tab = .thoughts }.keyboardShortcut("3")
                Divider()
            }
        }
        Settings { SettingsView() }
    }
}
