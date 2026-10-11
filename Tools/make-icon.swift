// Gera Resources/AppIcon.icns a partir da marca (mesma geometria de
// Assets/kandela-mark.svg e de kandelaMark() em Sources/main.swift).
// Uso: swift Tools/make-icon.swift   (na raiz do projeto)
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
    let k = CGFloat(px) / 1024   // tudo desenhado numa tela de 1024

    // Fundo: quadrado de cantos arredondados de 824, grade padrão do macOS.
    let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let grad = NSGradient(colors: [rgb(0x2a3350), rgb(0x0d1020)], atLocations: [0, 0.7],
                          colorSpace: .sRGB)!
    // centro do degradê em (30%, 20%) a partir do topo
    grad.draw(in: tile, relativeCenterPosition: NSPoint(x: -0.4, y: 0.6))
    NSGraphicsContext.restoreGraphicsState()

    // Marca: grade 100×100 ocupando 66% do quadrado, centralizada.
    let side = 824 * 0.66 * k
    let ox = tile.midX - side / 2, oy = tile.midY - side / 2
    let s = side / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + (100 - y) * s) }

    let stem = NSBezierPath(roundedRect: NSRect(x: ox + 23.59 * s, y: oy + 16 * s,
                                                width: 22 * s, height: 68 * s),
                            xRadius: 3 * s, yRadius: 3 * s)
    rgb(0x7f8db8).setFill()
    stem.fill()

    let arms = NSBezierPath()
    arms.move(to: p(32.39, 50))
    for (x, y) in [(56.73, 16.0), (76.41, 16), (52.07, 50), (76.41, 84), (56.73, 84)] {
        arms.line(to: p(CGFloat(x), CGFloat(y)))
    }
    arms.close()
    let glow = NSShadow()
    glow.shadowColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.63, alpha: 0.3)
    glow.shadowBlurRadius = 28 * k
    glow.shadowOffset = .zero
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    rgb(0xfff3dc).setFill()
    arms.fill()
    NSGraphicsContext.restoreGraphicsState()

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
guard task.terminationStatus == 0 else { fatalError("iconutil falhou") }
print("OK: Resources/AppIcon.icns")
