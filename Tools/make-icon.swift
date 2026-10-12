// Builds Resources/AppIcon.icns from the mark (same geometry as
// Assets/kandela-mark.svg; the menu bar has its own small version, kandelaMark()).
// Usage: swift Tools/make-icon.swift   (from the project root)
import AppKit

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func drawIcon(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let k = CGFloat(px) / 1024   // everything is drawn on a 1024 canvas

    // Background: 824 rounded square, the standard macOS icon grid.
    let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let grad = NSGradient(colors: [rgb(0x2a3350), rgb(0x0d1020)], atLocations: [0, 0.7],
                          colorSpace: .sRGB)!
    // gradient center at (30%, 20%) from the top
    grad.draw(in: tile, relativeCenterPosition: NSPoint(x: -0.4, y: 0.6))
    NSGraphicsContext.restoreGraphicsState()

    // Mark: 100×100 grid at 98.43% of the square (the K, from 16 to 84 on the grid,
    // sits 1/6 of the tile from the top and bottom edges), centered.
    let side = 824 * 0.9843 * k
    let ox = tile.midX - side / 2, oy = tile.midY - side / 2
    let s = side / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + (100 - y) * s) }

    let r = 3 * s
    let arms = NSBezierPath()
    arms.move(to: p(31.23, 50))
    arms.appendArc(from: p(55.57, 16), to: p(77.57, 16), radius: r)
    arms.appendArc(from: p(77.57, 16), to: p(53.23, 50), radius: r)
    arms.line(to: p(53.23, 50))
    arms.appendArc(from: p(77.57, 84), to: p(55.57, 84), radius: r)
    arms.appendArc(from: p(55.57, 84), to: p(31.23, 50), radius: r)
    arms.close()
    arms.lineJoinStyle = .round

    // Dimmed background window (55%) in its own layer, so that cutting out the
    // arms (2.5 gap) and the three dots does not erase the tile underneath.
    let cg = ctx.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    rgb(0x7f8db8).withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: ox + 14 * s, y: oy + 30 * s, width: 72 * s, height: 40 * s),
                 xRadius: 4 * s, yRadius: 4 * s).fill()
    ctx.compositingOperation = .destinationOut
    arms.lineWidth = 5 * s
    arms.fill()
    arms.stroke()
    for cx: CGFloat in [18.5, 24.5, 30.5] {
        let c = p(cx, 36)
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.4 * s, y: c.y - 2.4 * s,
                                    width: 4.8 * s, height: 4.8 * s)).fill()
    }
    ctx.compositingOperation = .sourceOver
    cg.endTransparencyLayer()

    rgb(0xfff3dc).setFill()
    arms.fill()

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try drawIcon(px: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try drawIcon(px: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("OK: Resources/AppIcon.icns")
