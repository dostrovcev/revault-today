import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Global hotkey ⌃⌥Space: a capture window over any app. A Carbon hotkey needs no
/// Accessibility permission, unlike a keyboard monitor.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var current: HotKey?

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        HotKey.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x52565444), id: 1)   // 'RVTD'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

@MainActor
enum QuickCapture {
    private static var panel: CapturePanel?
    private static var hotKey: HotKey?
    private static var previous: NSRunningApplication?

    static func install(_ store: Store) {
        hotKey = HotKey { toggle(store) }
    }

    static func toggle(_ store: Store) {
        if let p = panel, p.isVisible { close(); return }
        previous = NSWorkspace.shared.frontmostApplication
        let p = panel ?? make(store)
        panel = p
        let host = NSHostingView(rootView: CaptureView(onDone: { close() }).environment(store))
        p.contentView = host
        p.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.minY + f.height * 0.68))
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    static func close() {
        panel?.orderOut(nil)
        // return focus to the app the user came from
        if let prev = previous, prev.bundleIdentifier != Bundle.main.bundleIdentifier { prev.activate() }
        previous = nil
    }

    private static func make(_ store: Store) -> CapturePanel {
        let p = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 96),
                             styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.hasShadow = true
        p.isOpaque = false
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        return p
    }
}

struct CaptureView: View {
    @Environment(Store.self) private var store
    var onDone: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 14, weight: .light)).foregroundStyle(Theme.muted)
                TextField("What needs doing? tomorrow · fri · 13.11", text: $text)
                    .textFieldStyle(.plain).font(.g(16))
                    .focused($focused)
                    .onSubmit {
                        if store.capture(text) { text = ""; onDone() }
                    }
            }
            HStack(spacing: 6) {
                hint("@agent", "does it")
                hint("#area", "files it")
                hint("?", "a thought")
                Spacer()
                Text("↩ save · esc close").font(.g(11)).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: 620)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .onAppear { focused = true }
    }

    private func hint(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.g(11, .medium)).foregroundStyle(Theme.accentText)
            Text(v).font(.g(11)).foregroundStyle(Theme.faint)
        }
        .padding(.trailing, 6)
    }
}
