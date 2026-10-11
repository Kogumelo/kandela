import AppKit

// Kandela — a local, minimal macOS menu bar app (in the spirit of HazeOver) that
// dims everything except the focused window.
//
// How it works: one translucent black window per display, the overlay, is always
// ordered right BELOW the frontmost window. Window numbers are global on macOS, so
// the overlay can be ordered relative to windows of other apps. Clicks pass through
// it (ignoresMouseEvents) and it is left out of screenshots (sharingType = .none).
// No special permission is needed.
//
// Code and comments are in English; only the user-facing menu titles are in Portuguese.

// MARK: - Overlay window

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
        ignoresMouseEvents = true          // clicks go straight through
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none                // left out of screenshots
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        level = .normal                    // same level as regular windows:
    }                                      // what matters is the relative order

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Mark (menu bar icon)

// Kandela's K, on the 100×100 grid of Assets/kandela-mark.svg: a background window
// (72×40 block) with the three macOS traffic-light dots cut out at the top left; the
// part of it left of the vertex is the stem. The arms are hollow (5-wide outline)
// inside a 10-wide cutout in the block. It is a template image, so macOS paints it
// black or white to match the menu bar.
func kandelaArms(_ p: (CGFloat, CGFloat) -> NSPoint, radius r: CGFloat) -> NSBezierPath {
    // Arms: 22 wide horizontally, tip corners rounded with radius 3;
    // the point and the joint stay sharp.
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

let kandelaDots: [CGFloat] = [18.5, 24.5, 30.5]   // dot centers, at y = 36, radius 2.4

func kandelaMark(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        let s = rect.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let ctx = NSGraphicsContext.current!
        let arms = kandelaArms(p, radius: 3 * s)

        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14 * s, y: 30 * s, width: 72 * s, height: 40 * s),
                     xRadius: 4 * s, yRadius: 4 * s).fill()

        // Cutout: thickened arms (the gap) and the three dots.
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

// MARK: - Preferences

/// Keys in `defaults` (domain `br.com.kogut.kandela`). They come from km-dimmer and must
/// not change: renaming them would wipe the settings of existing users.
enum PrefKey {
    static let enabled = "enabled"
    static let intensity = "intensity"
    static let appMode = "appMode"
    static let migratedFromOldName = "migratedFromOldName"
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var lastTarget: CGWindowID = 0

    private let defaults = UserDefaults.standard
    private var enabled: Bool {
        get { defaults.bool(forKey: PrefKey.enabled) }
        set { defaults.set(newValue, forKey: PrefKey.enabled) }
    }
    private var intensity: Double {
        get { defaults.double(forKey: PrefKey.intensity) }
        set { defaults.set(newValue, forKey: PrefKey.intensity) }
    }
    private var appMode: Bool {            // true = every window of the focused app stays lit
        get { defaults.bool(forKey: PrefKey.appMode) }
        set { defaults.set(newValue, forKey: PrefKey.appMode) }
    }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePreferencesFromOldName()
        defaults.register(defaults: [PrefKey.enabled: true, PrefKey.intensity: 0.35, PrefKey.appMode: false])

        buildOverlays()
        buildStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(focusChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // The timer catches window switches within the same app (without needing the
        // Accessibility permission). CPU cost: negligible.
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

    /// Moves the overlays right below the window of the frontmost app.
    private func updateOrdering(force: Bool) {
        guard enabled else { return }
        guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return }

        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // The list is ordered front to back.
        var target: CGWindowID = 0
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != myPID,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
               alpha == 0 { continue }                       // invisible windows
            if let b = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
               rect.width < 50 || rect.height < 50 { continue } // tiny helper windows
            if let frontPID, pid != frontPID { continue }    // only the focused app's windows
            target = num          // without appMode: the frontmost one, then stop;
            if !appMode { break } // with appMode: keep going to the app's rearmost one
        }

        if target == 0 {          // nothing focused (e.g. the desktop) → don't dim
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

    /// Until 2026-10-11 the app was called km-dimmer, with bundle id `br.com.kogut.km-dimmer`.
    /// Preferences are stored per bundle id; on the first launch under the new id, copy the
    /// old ones over. The old domain is left untouched.
    private func migratePreferencesFromOldName() {
        guard !defaults.bool(forKey: PrefKey.migratedFromOldName) else { return }
        defer { defaults.set(true, forKey: PrefKey.migratedFromOldName) }
        guard let old = defaults.persistentDomain(forName: "br.com.kogut.km-dimmer") else { return }
        for key in [PrefKey.enabled, PrefKey.intensity, PrefKey.appMode] where defaults.object(forKey: key) == nil {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
    }

    // MARK: menu bar menu

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

    // MARK: actions

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
app.setActivationPolicy(.accessory)   // no Dock icon, menu bar only
app.run()
