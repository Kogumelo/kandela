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
// Code and comments are in English. Menu titles are localized: the English text is the
// key, and Resources/<lang>.lproj/Localizable.strings holds the translations.

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

// Kandela's K redrawn for the menu bar, on an 18×18 pt grid (Assets/kandela-menubar.svg).
// Scaling Assets/kandela-mark.svg down to 18 pt turned it into a blur (hollow arms with
// sub-point lines, dots under one pixel), so this version keeps the idea with fewer,
// bigger parts: a background window drawn as a 1 pt outline (16×9 outside) with the
// three traffic-light dots, solid arms (the app icon's), and a 1 pt gap cut between
// arms and window. Every edge falls on half points, i.e. whole pixels on Retina. It is a template image, so
// macOS paints it black or white to match the menu bar.
func kandelaArms() -> NSBezierPath {
    // Vertex at (7.5, 9), arms 3.5 wide horizontally and running from y 1 to 17
    // (the slope of kandela-mark.svg); tip corners rounded with radius 0.75.
    let r: CGFloat = 0.75
    let arms = NSBezierPath()
    arms.move(to: NSPoint(x: 7.5, y: 9))
    arms.appendArc(from: NSPoint(x: 13.23, y: 1), to: NSPoint(x: 16.73, y: 1), radius: r)
    arms.appendArc(from: NSPoint(x: 16.73, y: 1), to: NSPoint(x: 11, y: 9), radius: r)
    arms.line(to: NSPoint(x: 11, y: 9))
    arms.appendArc(from: NSPoint(x: 16.73, y: 17), to: NSPoint(x: 13.23, y: 17), radius: r)
    arms.appendArc(from: NSPoint(x: 13.23, y: 17), to: NSPoint(x: 7.5, y: 9), radius: r)
    arms.close()
    arms.lineJoinStyle = .round
    return arms
}

let kandelaDots: [CGFloat] = [3.25, 5.25, 7.25]   // dot centers, at y = 6.75, diameter 1.5

func kandelaMark() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let ctx = NSGraphicsContext.current!
        let arms = kandelaArms()

        NSColor.black.set()
        let window = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5, width: 15, height: 8), xRadius: 1, yRadius: 1)
        window.lineWidth = 1
        window.stroke()
        for cx in kandelaDots {
            NSBezierPath(ovalIn: NSRect(x: cx - 0.75, y: 6, width: 1.5, height: 1.5)).fill()
        }

        // Cutout: the arms widened by the gap.
        ctx.compositingOperation = .destinationOut
        arms.lineWidth = 2
        arms.fill()
        arms.stroke()
        ctx.compositingOperation = .sourceOver

        arms.fill()
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
        item.button?.image = kandelaMark()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: NSLocalizedString("Enabled", comment: "Menu item: turns dimming on/off"),
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        let header = NSMenuItem(title: NSLocalizedString("Intensity", comment: "Menu header above the percentages"),
                                action: nil, keyEquivalent: "")
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
        let mode = NSMenuItem(title: NSLocalizedString("Highlight All App Windows",
                                                        comment: "Menu item: keep every window of the focused app lit"),
                              action: #selector(toggleAppMode), keyEquivalent: "")
        mode.target = self
        mode.state = appMode ? .on : .off
        menu.addItem(mode)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: NSLocalizedString("Quit Kandela", comment: "Menu item"),
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
