// Renders Resources/AppIcon.icns: a white aperture on a soft purple→blue squircle.
//   swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.first!).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1), NSColor(red: 0.24, green: 0.52, blue: 0.98, alpha: 1)])!
        .draw(in: shape, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(CGFloat(base)).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(CGFloat(base * 2)).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
