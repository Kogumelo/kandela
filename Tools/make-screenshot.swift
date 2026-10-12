// Renders the README screenshots: a mock desktop with Kandela at work (focused window
// lit, everything else dimmed at 35%) and its menu bar menu open.
// The overlay is left out of real screen captures (sharingType = .none), so the scene
// is drawn here instead. The mark and the menu titles mirror Sources/main.swift and
// Resources/<lang>.lproj/Localizable.strings.
// Usage: swift Tools/make-screenshot.swift   (from the project root)
import AppKit

let W: CGFloat = 1200, H: CGFloat = 750, scale: CGFloat = 2
let intensity: CGFloat = 0.35          // Kandela's default
let menuBarHeight: CGFloat = 24

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    .systemFont(ofSize: size, weight: weight)
}

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ f: NSFont, _ c: NSColor) {
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: f, .foregroundColor: c])
}

func textWidth(_ s: String, _ f: NSFont) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: f]).width
}

func fillRound(_ r: NSRect, _ radius: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
}

// MARK: - Pieces

struct Strings {
    let enabled, intensity, highlight, quit, document, folder, clock: String
    let menus: [String]
    let body: [String]
}

let strings: [String: Strings] = [
    "en": Strings(enabled: "Enabled", intensity: "Intensity",
                  highlight: "Highlight All App Windows", quit: "Quit Kandela",
                  document: "Draft.txt", folder: "Documents", clock: "Sun Oct 11  9:41",
                  menus: ["File", "Edit", "Format", "View", "Window", "Help"],
                  body: ["Only the window you are working in stays lit.",
                         "",
                         "Everything else — other windows, other apps, the",
                         "desktop — fades into the background, so your eyes",
                         "stay where the work is.",
                         "",
                         "Clicks still go through to the dimmed windows:",
                         "click one and it becomes the lit one."]),
    "pt-BR": Strings(enabled: "Ativado", intensity: "Intensidade",
                     highlight: "Destacar todas as janelas do app", quit: "Sair do Kandela",
                     document: "Rascunho.txt", folder: "Documentos", clock: "dom. 11 de out.  9:41",
                     menus: ["Arquivo", "Editar", "Formatar", "Visualizar", "Janela", "Ajuda"],
                     body: ["Só a janela em que você está trabalhando fica acesa.",
                            "",
                            "Todo o resto — outras janelas, outros apps, a mesa —",
                            "vai para o fundo, e o olho fica onde está o",
                            "trabalho.",
                            "",
                            "Os cliques continuam chegando às janelas escuras:",
                            "clique numa e ela passa a ser a acesa."]),
]

/// Window chrome: rounded body, title bar with traffic lights and a title.
func window(_ r: NSRect, title: String, shadow: Bool) {
    if shadow {
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = .black.withAlphaComponent(0.45)
        sh.shadowBlurRadius = 30
        sh.shadowOffset = NSSize(width: 0, height: -10)   // down, in the flipped context
        sh.set()
        fillRound(r, 10, .white)
        NSGraphicsContext.restoreGraphicsState()
    }
    fillRound(r, 10, .white)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
    rgb(0xececec).setFill()
    NSRect(x: r.minX, y: r.minY, width: r.width, height: 28).fill()
    rgb(0xd6d6d6).setFill()
    NSRect(x: r.minX, y: r.minY + 28, width: r.width, height: 1).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (i, c) in [rgb(0xff5f57), rgb(0xfebc2e), rgb(0x28c840)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 12 + CGFloat(i) * 20, y: r.minY + 8, width: 12, height: 12)).fill()
    }
    let f = font(13, .semibold)
    text(title, r.midX - textWidth(title, f) / 2, r.minY + 6, f, rgb(0x4d4d4d))
}

/// Grey placeholder lines standing in for content.
func lines(x: CGFloat, y: CGFloat, widths: [CGFloat], gap: CGFloat = 16, color: NSColor = rgb(0xdedede)) {
    for (i, w) in widths.enumerated() {
        fillRound(NSRect(x: x, y: y + CGFloat(i) * gap, width: w, height: 7), 3.5, color)
    }
}

/// Kandela's menu bar icon (same geometry as kandelaMark() in Sources/main.swift and
/// Assets/kandela-menubar.svg, on an 18 pt grid), in one color. The scene is flipped.
func mark(at origin: NSPoint, color: NSColor) {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x, y: origin.y + y) }
    let r: CGFloat = 0.75
    let arms = NSBezierPath()
    arms.move(to: p(7.5, 9))
    arms.appendArc(from: p(13.23, 1), to: p(16.73, 1), radius: r)
    arms.appendArc(from: p(16.73, 1), to: p(11, 9), radius: r)
    arms.line(to: p(11, 9))
    arms.appendArc(from: p(16.73, 17), to: p(13.23, 17), radius: r)
    arms.appendArc(from: p(13.23, 17), to: p(7.5, 9), radius: r)
    arms.close()
    arms.lineJoinStyle = .round

    let ctx = NSGraphicsContext.current!
    ctx.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: origin.x + 1, y: origin.y + 4.5, width: 16, height: 9),
                 xRadius: 1.5, yRadius: 1.5).fill()
    ctx.compositingOperation = .destinationOut
    arms.lineWidth = 2
    arms.fill()
    arms.stroke()
    for cx: CGFloat in [2.75, 4.75, 6.75] {
        NSBezierPath(ovalIn: NSRect(x: origin.x + cx - 0.75, y: origin.y + 6, width: 1.5, height: 1.5)).fill()
    }
    ctx.compositingOperation = .sourceOver
    arms.fill()
    ctx.cgContext.endTransparencyLayer()
}

// MARK: - Scene

func drawScene(_ t: Strings) {
    // Wallpaper.
    NSGradient(colors: [rgb(0x3b4f8f), rgb(0x8a5a9e), rgb(0xe08a6a)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 60)

    // Background window 1: a file browser.
    let fb = NSRect(x: 60, y: 70, width: 520, height: 360)
    window(fb, title: t.folder, shadow: true)
    rgb(0xf3f3f5).setFill()
    NSRect(x: fb.minX, y: fb.minY + 29, width: 140, height: fb.height - 39).fill()
    lines(x: fb.minX + 18, y: fb.minY + 50, widths: [80, 64, 90, 72, 58], gap: 26, color: rgb(0xcfcfd4))
    let tiles = [rgb(0x5aa0f2), rgb(0x5aa0f2), rgb(0xf2b75a), rgb(0x7ac77a), rgb(0x5aa0f2), rgb(0xe07a7a)]
    for (i, c) in tiles.enumerated() {
        let x = fb.minX + 170 + CGFloat(i % 3) * 115, y = fb.minY + 55 + CGFloat(i / 3) * 120
        fillRound(NSRect(x: x + 20, y: y, width: 56, height: 46), 6, c)
        fillRound(NSRect(x: x + 14, y: y + 58, width: 68, height: 7), 3.5, rgb(0xdedede))
    }

    // Background window 2: a web page.
    let wb = NSRect(x: 640, y: 120, width: 500, height: 420)
    window(wb, title: "", shadow: true)
    fillRound(NSRect(x: wb.minX + 110, y: wb.minY + 6, width: 280, height: 17), 5, rgb(0xdcdcdc))
    fillRound(NSRect(x: wb.minX + 24, y: wb.minY + 52, width: wb.width - 48, height: 150), 8, rgb(0xb9c9e6))
    lines(x: wb.minX + 24, y: wb.minY + 222, widths: [300, 440, 410, 450, 380, 250, 420, 390], gap: 20)

    // Kandela's overlay: right below the focused window, over everything else
    // (the menu bar sits on a higher level, so it stays bright).
    NSColor.black.withAlphaComponent(intensity).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Focused window: a text document.
    let ed = NSRect(x: 330, y: 250, width: 520, height: 330)
    window(ed, title: t.document, shadow: true)
    let body = font(15)
    for (i, line) in t.body.enumerated() {
        text(line, ed.minX + 28, ed.minY + 50 + CGFloat(i) * 24, body, rgb(0x222222))
    }
    rgb(0x222222).setFill()
    NSRect(x: ed.minX + 28 + textWidth(t.body.last!, body) + 2, y: ed.minY + 50 + CGFloat(t.body.count - 1) * 24 + 2,
           width: 1.5, height: 18).fill()

    // Menu bar.
    rgb(0xf6f6f6, 0.82).setFill()
    NSRect(x: 0, y: 0, width: W, height: menuBarHeight).fill()
    let mf = font(13.5), mb = font(13.5, .bold)
    var x: CGFloat = 20
    text("\u{F8FF}", x, 3, font(15), .black); x += 32
    text("TextEdit", x, 3, mb, .black); x += textWidth("TextEdit", mb) + 20
    for item in t.menus {
        text(item, x, 3, mf, .black); x += textWidth(item, mf) + 20
    }
    let clock = t.clock
    let clockX = W - 16 - textWidth(clock, mf)
    text(clock, clockX, 3, mf, .black)

    // Kandela's status item, highlighted because its menu is open.
    let kx = clockX - 46
    fillRound(NSRect(x: kx - 5, y: 2, width: 28, height: 20), 5, .black.withAlphaComponent(0.12))
    mark(at: NSPoint(x: kx, y: 3), color: .black)

    // Kandela's menu.
    let menuFont = font(13.5)
    let items: [(String, Bool, Bool)] = [   // (title, checked, enabled); "-" = separator
        (t.enabled, true, true), ("-", false, true), (t.intensity, false, false),
        ("20%", false, true), ("35%", true, true), ("50%", false, true), ("65%", false, true), ("80%", false, true),
        ("-", false, true), (t.highlight, false, true), ("-", false, true), (t.quit, false, true),
    ]
    let menuW = max(240, textWidth(t.highlight, menuFont) + 80)
    let menuH = items.reduce(CGFloat(10)) { $0 + ($1.0 == "-" ? 11 : 22) }
    let menu = NSRect(x: min(kx - 5, W - 8 - menuW), y: menuBarHeight + 3, width: menuW, height: menuH)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = .black.withAlphaComponent(0.35)
    sh.shadowBlurRadius = 18
    sh.shadowOffset = NSSize(width: 0, height: -6)
    sh.set()
    fillRound(menu, 9, rgb(0xf2f2f2, 0.97))
    NSGraphicsContext.restoreGraphicsState()
    rgb(0x000000, 0.12).setStroke()
    NSBezierPath(roundedRect: menu.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
    var y = menu.minY + 5
    for (title, checked, enabled) in items {
        if title == "-" {
            rgb(0x000000, 0.1).setFill()
            NSRect(x: menu.minX + 12, y: y + 5, width: menu.width - 24, height: 1).fill()
            y += 11
            continue
        }
        let color: NSColor = enabled ? rgb(0x1a1a1a) : rgb(0x8a8a8a)
        if checked { text("✓", menu.minX + 10, y + 2, font(13, .semibold), color) }
        text(title, menu.minX + 28, y + 2, menuFont, color)
        if title == t.quit {
            let k = "⌘Q"
            text(k, menu.maxX - 14 - textWidth(k, menuFont), y + 2, menuFont, rgb(0x8a8a8a))
        }
        y += 22
    }
}

func render(_ lang: String) throws {
    let t = strings[lang]!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: H)
    cg.scaleBy(x: 1, y: -1)                // top-left origin, like the screen
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    drawScene(t)
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let path = "Assets/screenshot-\(lang).png"
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("OK: \(path)")
}

try render("en")
try render("pt-BR")
