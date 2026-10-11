// Gera Resources/AppIcon.icns a partir da marca (mesma geometria de
// Assets/kandela-mark.svg e de marcaKandela(tamanho:) em Sources/main.swift).
// Uso: swift Tools/make-icon.swift   (na raiz do projeto)
import AppKit

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func desenharIcone(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let k = CGFloat(px) / 1024   // tudo desenhado numa tela de 1024

    // Fundo: quadrado de cantos arredondados de 824, grade padrão do macOS.
    let placa = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let forma = NSBezierPath(roundedRect: placa, xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.saveGraphicsState()
    forma.addClip()
    let degrade = NSGradient(colors: [rgb(0x2a3350), rgb(0x0d1020)], atLocations: [0, 0.7],
                          colorSpace: .sRGB)!
    // centro do degradê em (30%, 20%) a partir do topo
    degrade.draw(in: placa, relativeCenterPosition: NSPoint(x: -0.4, y: 0.6))
    NSGraphicsContext.restoreGraphicsState()

    // Marca: grade 100×100 em 98,43% do quadrado (o K, de 16 a 84 na grade,
    // fica a 1/6 da placa de cada borda em cima e embaixo), centralizada.
    let lado = 824 * 0.9843 * k
    let ox = placa.midX - lado / 2, oy = placa.midY - lado / 2
    let s = lado / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + (100 - y) * s) }

    let r = 3 * s
    let bracos = NSBezierPath()
    bracos.move(to: p(31.23, 50))
    bracos.appendArc(from: p(55.57, 16), to: p(77.57, 16), radius: r)
    bracos.appendArc(from: p(77.57, 16), to: p(53.23, 50), radius: r)
    bracos.line(to: p(53.23, 50))
    bracos.appendArc(from: p(77.57, 84), to: p(55.57, 84), radius: r)
    bracos.appendArc(from: p(55.57, 84), to: p(31.23, 50), radius: r)
    bracos.close()
    bracos.lineJoinStyle = .round

    // Janela de fundo apagada (55%) numa camada própria, para o recorte dos
    // braços (vão de 2,5) e dos três pontos não apagar a placa por baixo.
    let cg = ctx.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    rgb(0x7f8db8).withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: ox + 14 * s, y: oy + 30 * s, width: 72 * s, height: 40 * s),
                 xRadius: 4 * s, yRadius: 4 * s).fill()
    ctx.compositingOperation = .destinationOut
    bracos.lineWidth = 5 * s
    bracos.fill()
    bracos.stroke()
    for cx: CGFloat in [18.5, 24.5, 30.5] {
        let c = p(cx, 36)
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.4 * s, y: c.y - 2.4 * s,
                                    width: 4.8 * s, height: 4.8 * s)).fill()
    }
    ctx.compositingOperation = .sourceOver
    cg.endTransparencyLayer()

    rgb(0xfff3dc).setFill()
    bracos.fill()

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let arquivos = FileManager.default
let conjunto = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? arquivos.removeItem(at: conjunto)
try arquivos.createDirectory(at: conjunto, withIntermediateDirectories: true)
for tam in [16, 32, 128, 256, 512] {
    try desenharIcone(px: tam).write(to: conjunto.appendingPathComponent("icon_\(tam)x\(tam).png"))
    try desenharIcone(px: tam * 2).write(to: conjunto.appendingPathComponent("icon_\(tam)x\(tam)@2x.png"))
}
try arquivos.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let processo = Process()
processo.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
processo.arguments = ["-c", "icns", conjunto.path, "-o", "Resources/AppIcon.icns"]
try processo.run()
processo.waitUntilExit()
try? arquivos.removeItem(at: conjunto)
guard processo.terminationStatus == 0 else { fatalError("iconutil falhou") }
print("OK: Resources/AppIcon.icns")
