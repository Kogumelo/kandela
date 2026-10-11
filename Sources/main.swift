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

// O K do Kandela, na grade 100×100 de Assets/kandela-mark.svg: haste apagada
// atrás, braços cheios por cima. Imagem-modelo (template), então o macOS pinta
// de preto ou branco conforme a barra; a haste usa só a transparência.
func kandelaMark(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        let s = rect.width / 100
        let stem = NSBezierPath(roundedRect: NSRect(x: 23.59 * s, y: 16 * s,
                                                    width: 22 * s, height: 68 * s),
                                xRadius: 3 * s, yRadius: 3 * s)
        NSColor.black.withAlphaComponent(0.42).setFill()
        stem.fill()

        let arms = NSBezierPath()
        let pts: [(CGFloat, CGFloat)] = [(32.39, 50), (56.73, 16), (76.41, 16),
                                         (52.07, 50), (76.41, 84), (56.73, 84)]
        arms.move(to: NSPoint(x: pts[0].0 * s, y: pts[0].1 * s))
        for p in pts.dropFirst() { arms.line(to: NSPoint(x: p.0 * s, y: p.1 * s)) }
        arms.close()
        NSColor.black.setFill()
        arms.fill()
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
