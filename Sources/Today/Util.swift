import AppKit
import CoreText
import SwiftUI

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func file(_ name: String) -> URL { support.appendingPathComponent(name) }
}

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard !DevTools.isDemo else { return }   // demo mode never touches your real tasks
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension Data {
    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }

    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum JWT {
    static func claims(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1, let data = Data(base64URL: String(parts[1])),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    static func expiry(_ jwt: String) -> Date? {
        (claims(jwt)["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
    }
}

enum Day {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var today: String { fmt.string(from: Date()) }
    static func plus(_ days: Int) -> String { fmt.string(from: Date().addingTimeInterval(Double(days) * 86400)) }
    static func string(_ d: Date) -> String { fmt.string(from: d) }

    private static let gbDay: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"; return f }()
    private static let gbWeekday: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE"; return f }()
    private static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    /// Due label for a row: text and tone (overdue, soon, later).
    static func dueLabel(_ due: String) -> (String, Int) {
        guard let d = date(due), let t = date(today) else { return (due, 2) }
        let days = Calendar.current.dateComponents([.day], from: t, to: d).day ?? 0
        if days < 0 { return (gbDay.string(from: d), 0) }
        if days == 0 { return ("Today", 1) }
        if days == 1 { return ("Tomorrow", 1) }
        if days < 7 { return (gbWeekday.string(from: d), 1) }
        return (gbDay.string(from: d), 2)
    }

    static func dayHeader(_ due: String) -> String {
        guard let d = date(due) else { return due }
        let (l, _) = dueLabel(due)
        return l == "Today" || l == "Tomorrow" ? l : gbWeekday.string(from: d) + ", " + gbDay.string(from: d)
    }
    static func date(_ s: String) -> Date? { fmt.date(from: s) }

    /// "Thursday, 30 October" for the header.
    static var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }

    /// How long a task has been open: "since Tue", "since 21 Oct".
    static func since(_ s: String) -> String? {
        guard let d = date(s), s < today else { return nil }
        let days = Calendar.current.dateComponents([.day], from: d, to: date(today) ?? Date()).day ?? 0
        if days == 1 { return "since yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = days < 7 ? "EEE" : "d MMM"
        return "since " + f.string(from: d)
    }

    /// "updated 14:20", "updated yesterday", "updated 28 Aug".
    static func updated(_ t: Double) -> String {
        let d = Date(timeIntervalSince1970: t)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "updated " + hm.string(from: d) }
        if cal.isDateInYesterday(d) { return "updated yesterday" }
        return "updated " + gbDay.string(from: d)
    }

    /// Days since t.
    static func daysSince(_ t: Double) -> Int { Int((Date().timeIntervalSince1970 - t) / 86400) }

    static func stamp(_ t: Double) -> String {
        let d = Date(timeIntervalSince1970: t)
        return Calendar.current.isDateInToday(d) ? hm.string(from: d) : gbDay.string(from: d) + ", " + hm.string(from: d)
    }
}

/// Design tokens.
enum Theme {
    static let ink = Color(hex: 0x14282B)
    static let ink2 = Color(hex: 0x3B4A4C)
    static let sec = Color(hex: 0x4A5759)
    static let muted = Color(hex: 0x7C8686)
    static let faint = Color(hex: 0x8A9393)
    static let ghost = Color(hex: 0xB4BABA)
    static let line = Color(hex: 0xE9EAE7)
    static let lineSoft = Color(hex: 0xF1F1EF)
    static let border = Color(hex: 0xE5E6E2)
    static let borderHover = Color(hex: 0xCFD2CD)
    static let page = Color(hex: 0xFAFAF8)
    static let side = Color(hex: 0xF4F4F1)
    static let chip = Color(hex: 0xF0F0ED)
    static let hover = Color(hex: 0xF3F3F0)
    static let navHover = Color(hex: 0xECECE8)
    static let navOn = Color(hex: 0xE9E9E5)
    static let navIcon = Color(hex: 0x6B7676)
    static let avatar = Color(hex: 0xDCDFDB)
    static let primaryHover = Color(hex: 0x1F3A3E)
    static let accent = Color(hex: 0xEE5B32)
    static let accentText = Color(hex: 0xC2471F)
    static let accentBg = Color(hex: 0xFDEEE8)
    static let green = Color(hex: 0x2E7A55)
    static let greenBg = Color(hex: 0xE8F2EC)
    static let amber = Color(hex: 0x9A6200)
    static let amberBg = Color(hex: 0xFBF1DC)
    static let red = Color(hex: 0xB33A2B)
    static let white = Color.white
    static let blue = Color(hex: 0x3A6FD8)

    static func registerFonts() {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Fonts")) }
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Fonts").standardized)
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
            if !files.isEmpty { return }
        }
    }
}

extension Font {
    /// Geist font.
    static func g(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Geist-Medium"
        case .semibold: name = "Geist-SemiBold"
        case .bold, .heavy, .black: name = "Geist-Bold"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size)
    }
}

extension NSFont {
    static func g(_ size: CGFloat) -> NSFont { NSFont(name: "Geist-Regular", size: size) ?? .systemFont(ofSize: size) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}


/// Buttons: normal (white with border), primary (ink), ghost.
struct DashButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, ghost }
    var kind: Kind = .normal
    var small = false
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color = kind == .primary ? .white : (kind == .ghost ? Theme.sec : Theme.ink)
        let bg: Color = kind == .primary ? (hover ? Theme.primaryHover : Theme.ink) : (kind == .ghost ? (hover ? Theme.chip : .clear) : Theme.white)
        let stroke: Color = kind == .primary ? Theme.ink : (kind == .ghost ? .clear : (hover ? Theme.borderHover : Theme.border))
        return configuration.label
            .fixedSize()
            .font(.g(small ? 12.5 : 13, .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? 28 : 32)
            .background(RoundedRectangle(cornerRadius: small ? 7 : 8).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: small ? 7 : 8).stroke(stroke, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

extension ButtonStyle where Self == DashButtonStyle {
    static func dash(_ kind: DashButtonStyle.Kind = .normal, small: Bool = false) -> DashButtonStyle { DashButtonStyle(kind: kind, small: small) }
}

/// Debugging without screen recording:
/// TODAY_DEMO=1 shows sample tasks, TODAY_SNAPSHOT=/path.png saves a window snapshot and quits, TODAY_TAB=thoughts.
enum DevTools {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var isDemo: Bool { env["TODAY_DEMO"] != nil }

    @MainActor
    static func scheduleSnapshot() {
        guard let path = env["TODAY_SNAPSHOT"] else { return }
        let delay = Double(env["TODAY_SNAPSHOT_DELAY"] ?? "2.5") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let panel = env["TODAY_CAPTURE"] != nil ? NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) : nil
            guard let window = panel ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView else { exit(2) }
            if panel == nil, let size = env["TODAY_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                window.setContentSize(NSSize(width: size[0], height: size[1]))
                view.layoutSubtreeIfNeeded()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let scale = window.backingScaleFactor
                let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
                guard let layer = view.layer,
                      let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { exit(3) }
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.scaleBy(x: scale, y: scale)
                layer.render(in: ctx)
                if let img = ctx.makeImage() {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                exit(0)
            }
        }
    }
}


/// Due date from the task text, English and Russian: "tomorrow", "fri", "13.11", "next week", "завтра", "пт".
/// The date words are removed from the text.
enum DueParser {
    private static let weekdays: [(String, Int)] = [
        ("понедельник|пн|monday|mon", 2), ("вторник|вт|tuesday|tue", 3), ("среду|среда|ср|wednesday|wed", 4),
        ("четверг|чт|thursday|thu", 5), ("пятницу|пятница|пт|friday|fri", 6), ("субботу|суббота|сб|saturday|sat", 7),
        ("воскресенье|вс|sunday|sun", 1),
    ]

    static func extract(_ text: String, now: Date = Date()) -> (String, String?) {
        let cal = Calendar.current
        func cut(_ pattern: String) -> Range<String.Index>? {
            text.range(of: "(?<![\\p{L}\\d])(?:" + pattern + ")(?![\\p{L}\\d])", options: [.regularExpression, .caseInsensitive])
        }
        func out(_ r: Range<String.Index>, _ d: Date) -> (String, String?) {
            // a preposition before the date goes too: "on fri", "до пт"
            var lo = r.lowerBound
            if let p = text[..<lo].range(of: "(?:^|\\s)(до|в|во|на|к|by|on|until)\\s+$", options: [.regularExpression, .caseInsensitive]) {
                lo = p.lowerBound
            }
            var t = text
            t.removeSubrange(lo..<r.upperBound)
            t = t.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
            return (t, Day.string(d))
        }
        if let r = cut("послезавтра") { return out(r, now.addingTimeInterval(2 * 86400)) }
        if let r = cut("сегодня|today") { return out(r, now) }
        if let r = cut("завтра|tomorrow|tmrw?") { return out(r, now.addingTimeInterval(86400)) }
        if let r = cut("next week|на следующей неделе|след(?:ующая|\\.)? неделя") {
            let wd = cal.component(.weekday, from: now)
            return out(r, now.addingTimeInterval(Double((9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7) * 86400))
        }
        if let r = text.range(of: "(?<![\\d.])(\\d{1,2})\\.(\\d{1,2})(?:\\.(\\d{2,4}))?(?![\\d.])", options: .regularExpression) {
            let parts = text[r].split(separator: ".").compactMap { Int($0) }
            // month with two digits or with a year: "13.11", "5.11", "05.01.27"; "1.2" is a version, not a date
            let monthText = text[r].split(separator: ".")[1]
            if parts.count >= 2, (1...31).contains(parts[0]), (1...12).contains(parts[1]), monthText.count == 2 || parts.count == 3 {
                var y = cal.component(.year, from: now)
                if parts.count == 3 { y = parts[2] < 100 ? 2000 + parts[2] : parts[2] }
                if var d = cal.date(from: DateComponents(year: y, month: parts[1], day: parts[0])) {
                    if parts.count == 2, d < cal.startOfDay(for: now) { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
                    return out(r, d)
                }
            }
        }
        for (pattern, weekday) in weekdays {
            if let r = cut(pattern) {
                let cur = cal.component(.weekday, from: now)
                var add = (weekday - cur + 7) % 7
                if add == 0 { add = 7 }
                return out(r, now.addingTimeInterval(Double(add) * 86400))
            }
        }
        return (text, nil)
    }
}
