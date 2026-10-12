// Builds Resources/AppIcon.icns from the mark (same geometry as Assets/kandela-mark.svg
// and Assets/kandela.svg; the menu bar has its own small version, kandelaMark()).
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

    // Mark: the 100×100 grid of Assets/kandela-mark.svg at 0.73 of the 100 units of
    // Assets/kandela.svg (whose tile is 84 units = 824 px), centered: translate 13.5.
    let u = 824 / 84 * k
    let s = 0.73 * u
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: 100 * k + (13.5 + 0.73 * x - 8) * u, y: 924 * k - (13.5 + 0.73 * y - 8) * u)
    }
    func polygon(_ pts: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: p(pts[0].0, pts[0].1))
        for q in pts.dropFirst() { path.line(to: p(q.0, q.1)) }
        path.close()
        path.lineJoinStyle = .round
        return path
    }
    let cream = rgb(0xfff3dc)

    // Window (x 8 to 52, y 25 to 75, 5-wide outline) in its own layer, so that cutting
    // out its opening and the 3-wide gap around the block does not erase the tile.
    let cg = ctx.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    cream.setFill()
    NSBezierPath(roundedRect: NSRect(origin: p(8, 75), size: NSSize(width: 44 * s, height: 50 * s)),
                 xRadius: 7 * s, yRadius: 7 * s).fill()
    ctx.compositingOperation = .destinationOut
    NSBezierPath(roundedRect: NSRect(origin: p(13, 70), size: NSSize(width: 34 * s, height: 40 * s)),
                 xRadius: 4.5 * s, yRadius: 4.5 * s).fill()
    let gap = polygon([(36, 50), (55, 25), (92, 25), (92, 75), (55, 75)])
    gap.lineWidth = 6 * s
    gap.fill()
    gap.stroke()
    ctx.compositingOperation = .sourceOver
    cg.endTransparencyLayer()

    // The three dots, in amber.
    rgb(0xe3a548).setFill()
    for cx: CGFloat in [19.5, 25.5, 31.5] {
        let c = p(cx, 36)
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.2 * s, y: c.y - 2.2 * s, width: 4.4 * s, height: 4.4 * s)).fill()
    }

    // Block with the point (x 36 to 92), corners rounded with radius 4: the polygon
    // moved in by 4, filled and stroked 8 wide with round joins.
    let block = polygon([(41.02, 50), (56.98, 29), (88, 29), (88, 71), (56.98, 71)])
    cream.set()
    block.lineWidth = 8 * s
    block.fill()
    block.stroke()

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
