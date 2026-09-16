import AppKit

// km-dimmer — dimmer local (estilo HazeOver): escurece tudo que não é a janela em foco.
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

    // MARK: menu na barra

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "circle.lefthalf.filled",
                             accessibilityDescription: "km-dimmer") {
            item.button?.image = img
        } else {
            item.button?.title = "◐"
        }
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
        let quit = NSMenuItem(title: "Sair do km-dimmer",
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
