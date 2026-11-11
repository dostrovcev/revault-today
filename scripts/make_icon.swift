// Draws the app icon into AppIcon.iconset. Run: swift scripts/make_icon.swift <out_dir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconset = "\(out)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func draw(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    NSColor(red: 0.078, green: 0.082, blue: 0.094, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2).fill()

    // checkmark
    let check = NSBezierPath()
    check.move(to: NSPoint(x: s * 0.30, y: s * 0.50))
    check.line(to: NSPoint(x: s * 0.44, y: s * 0.36))
    check.line(to: NSPoint(x: s * 0.70, y: s * 0.64))
    check.lineWidth = s * 0.07
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()

    // two accent dots
    NSColor(red: 1.0, green: 0.31, blue: 0.10, alpha: 1).setFill()
    for y in [0.70, 0.58] {
        NSBezierPath(ovalIn: NSRect(x: s * 0.73, y: s * y, width: s * 0.075, height: s * 0.075)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}
print(iconset)
