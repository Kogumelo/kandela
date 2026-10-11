import AppKit

// Kandela — dimmer local (estilo HazeOver): escurece tudo que não é a janela em foco.
//
// Técnica: uma janela preta translúcida por monitor, sempre ordenada logo ABAIXO
// da janela frontal. Números de janela são globais no macOS, então dá para
// posicionar nossa janela relativa a janelas de outros apps. Cliques atravessam
// o overlay (ignoresMouseEvents) e ele não aparece em capturas de tela
// (sharingType = .none). Nenhuma permissão especial é necessária.

// MARK: - Janela de escurecimento (overlay)

final class OverlayWindow: NSWindow {
    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        hasShadow = false
        backgroundColor = .black
        alphaValue = 0
        ignoresMouseEvents = true          // cliques passam direto
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none                // não aparece em capturas de tela
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        level = .normal                    // mesmo nível das janelas comuns:
    }                                      // quem manda é a ordem relativa

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Marca (ícone da barra de menus)

// O K do Kandela, na grade 100×100 de Assets/kandela-mark.svg: janela de fundo
// (bloco 72×40) com os três pontos do macOS vazados no alto à esquerda; a parte
// dela à esquerda do vértice é a haste. Os braços ficam vazados (contorno 5)
// dentro de um recorte de 10 no bloco. Imagem-modelo (template), então o macOS
// pinta de preto ou branco conforme a barra.
func kandelaArms(_ p: (CGFloat, CGFloat) -> NSPoint, radius r: CGFloat) -> NSBezierPath {
    // Braços: 22 de largura na horizontal, cantos das pontas com raio 3;
    // a ponta e o encaixe continuam vivos.
    let arms = NSBezierPath()
    arms.move(to: p(31.23, 50))
    arms.appendArc(from: p(55.57, 16), to: p(77.57, 16), radius: r)
    arms.appendArc(from: p(77.57, 16), to: p(53.23, 50), radius: r)
    arms.line(to: p(53.23, 50))
    arms.appendArc(from: p(77.57, 84), to: p(55.57, 84), radius: r)
    arms.appendArc(from: p(55.57, 84), to: p(31.23, 50), radius: r)
    arms.close()
    arms.lineJoinStyle = .round
    return arms
}

let kandelaDots: [CGFloat] = [18.5, 24.5, 30.5]   // centros dos pontos, em y = 36, raio 2,4

func kandelaMark(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        let s = rect.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let ctx = NSGraphicsContext.current!
        let arms = kandelaArms(p, radius: 3 * s)

        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14 * s, y: 30 * s, width: 72 * s, height: 40 * s),
                     xRadius: 4 * s, yRadius: 4 * s).fill()

        // Recorte: braços engrossados (vão) e os três pontos.
        ctx.compositingOperation = .destinationOut
        arms.lineWidth = 10 * s
        arms.fill()
        arms.stroke()
        for cx in kandelaDots {
            NSBezierPath(ovalIn: NSRect(x: (cx - 2.4) * s, y: (36 - 2.4) * s,
                                        width: 4.8 * s, height: 4.8 * s)).fill()
        }
        ctx.compositingOperation = .sourceOver

        NSColor.black.setStroke()
        arms.lineWidth = 5 * s
        arms.stroke()
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "Kandela"
    return img
}

// MARK: - Delegate principal

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var lastTarget: CGWindowID = 0

    private let defaults = UserDefaults.standard
    private var enabled: Bool {
        get { defaults.bool(forKey: "enabled") }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    private var intensity: Double {
        get { defaults.double(forKey: "intensity") }
        set { defaults.set(newValue, forKey: "intensity") }
    }
    private var appMode: Bool {            // true = todas as janelas do app em foco ficam claras
        get { defaults.bool(forKey: "appMode") }
        set { defaults.set(newValue, forKey: "appMode") }
    }

    // MARK: ciclo de vida

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePreferencesFromOldName()
        defaults.register(defaults: ["enabled": true, "intensity": 0.35, "appMode": false])

        buildOverlays()
        buildStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(focusChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // O timer cobre trocas de janela dentro do mesmo app (sem precisar de
        // permissão de Acessibilidade). Custo de CPU: desprezível.
        let t = Timer(timeInterval: 0.2, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t

        applyIntensity(animated: true)
        updateOrdering(force: true)
    }

    // MARK: overlays

    private func buildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screenFrame: $0.frame) }
        lastTarget = 0
    }

    private func applyIntensity(animated: Bool) {
        let target = enabled ? CGFloat(intensity) : 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.25 : 0
            overlays.forEach { $0.animator().alphaValue = target }
        }
    }

    @objc private func screensChanged() {
        buildOverlays()
        applyIntensity(animated: false)
        updateOrdering(force: true)
    }

    @objc private func focusChanged() { updateOrdering(force: true) }
    @objc private func tick() { updateOrdering(force: false) }

    /// Reposiciona os overlays logo abaixo da janela do app em primeiro plano.
    private func updateOrdering(force: Bool) {
        guard enabled else { return }
        guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return }

        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // A lista vem ordenada da frente para trás.
        var target: CGWindowID = 0
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != myPID,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
               alpha == 0 { continue }                       // janelas invisíveis
            if let b = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
               rect.width < 50 || rect.height < 50 { continue } // janelas auxiliares minúsculas
            if let frontPID, pid != frontPID { continue }    // só janelas do app em foco
            target = num          // sem appMode: a mais à frente e para;
            if !appMode { break } // com appMode: continua até a mais atrás do app
        }

        if target == 0 {          // nada em foco (ex.: desktop) → não escurece
            if lastTarget != 0 || force {
                overlays.forEach { $0.orderOut(nil) }
                lastTarget = 0
            }
            return
        }
        guard force || target != lastTarget else { return }
        lastTarget = target
        overlays.forEach { $0.order(.below, relativeTo: Int(target)) }
    }

    /// Até 11/10/2026 o app se chamava km-dimmer, com o bundle id `br.com.kogut.km-dimmer`.
    /// As preferências ficam guardadas pelo bundle id; na primeira abertura com o id novo,
    /// copia as do antigo. O domínio antigo fica como está.
    private func migratePreferencesFromOldName() {
        let mark = "migratedFromOldName"
        guard !defaults.bool(forKey: mark) else { return }
        defer { defaults.set(true, forKey: mark) }
        guard let old = defaults.persistentDomain(forName: "br.com.kogut.km-dimmer") else { return }
        for key in ["enabled", "intensity", "appMode"] where defaults.object(forKey: key) == nil {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
    }

    // MARK: menu na barra

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = kandelaMark(size: 18)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: "Ativado", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Intensidade", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for pct in [20, 35, 50, 65, 80] {
            let mi = NSMenuItem(title: "\(pct)%", action: #selector(setIntensity(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = pct
            mi.state = Int((intensity * 100).rounded()) == pct ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let mode = NSMenuItem(title: "Destacar todas as janelas do app",
                              action: #selector(toggleAppMode), keyEquivalent: "")
        mode.target = self
        mode.state = appMode ? .on : .off
        menu.addItem(mode)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair do Kandela",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    // MARK: ações

    @objc private func toggleEnabled() {
        enabled.toggle()
        applyIntensity(animated: true)
        if enabled {
            updateOrdering(force: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.enabled else { return }
                self.overlays.forEach { $0.orderOut(nil) }
                self.lastTarget = 0
            }
        }
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        intensity = Double(sender.tag) / 100.0
        applyIntensity(animated: true)
        updateOrdering(force: true)
    }

    @objc private func toggleAppMode() {
        appMode.toggle()
        updateOrdering(force: true)
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // sem ícone no Dock, só na barra de menus
app.run()
