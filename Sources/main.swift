import AppKit

// Kandela — escurecedor de distrações local (estilo HazeOver): escurece tudo que
// não é a janela em foco.
//
// Técnica: um véu, janela preta translúcida, por monitor, sempre ordenado logo
// ABAIXO da janela frontal. Números de janela são globais no macOS, então dá para
// posicionar o véu relativo a janelas de outros apps. Cliques atravessam o véu
// (ignoresMouseEvents) e ele não aparece em capturas de tela (sharingType = .none).
// Nenhuma permissão especial é necessária.
//
// Convenção: nomes e comentários em português, como no resto da família K (Konfig,
// Katraca). Ficam em inglês só a API da Apple e as chaves de preferência (`Chave`).

// MARK: - Véu (janela de escurecimento)

final class Veu: NSWindow {
    init(quadro: NSRect) {
        super.init(contentRect: quadro,
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
func bracosKandela(_ p: (CGFloat, CGFloat) -> NSPoint, raio r: CGFloat) -> NSBezierPath {
    // Braços: 22 de largura na horizontal, cantos das pontas com raio 3;
    // a ponta e o encaixe continuam vivos.
    let bracos = NSBezierPath()
    bracos.move(to: p(31.23, 50))
    bracos.appendArc(from: p(55.57, 16), to: p(77.57, 16), radius: r)
    bracos.appendArc(from: p(77.57, 16), to: p(53.23, 50), radius: r)
    bracos.line(to: p(53.23, 50))
    bracos.appendArc(from: p(77.57, 84), to: p(55.57, 84), radius: r)
    bracos.appendArc(from: p(55.57, 84), to: p(31.23, 50), radius: r)
    bracos.close()
    bracos.lineJoinStyle = .round
    return bracos
}

let pontosKandela: [CGFloat] = [18.5, 24.5, 30.5]   // centros dos pontos, em y = 36, raio 2,4

func marcaKandela(tamanho: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: tamanho, height: tamanho), flipped: true) { quadro in
        let s = quadro.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let ctx = NSGraphicsContext.current!
        let bracos = bracosKandela(p, raio: 3 * s)

        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14 * s, y: 30 * s, width: 72 * s, height: 40 * s),
                     xRadius: 4 * s, yRadius: 4 * s).fill()

        // Recorte: braços engrossados (vão) e os três pontos.
        ctx.compositingOperation = .destinationOut
        bracos.lineWidth = 10 * s
        bracos.fill()
        bracos.stroke()
        for cx in pontosKandela {
            NSBezierPath(ovalIn: NSRect(x: (cx - 2.4) * s, y: (36 - 2.4) * s,
                                        width: 4.8 * s, height: 4.8 * s)).fill()
        }
        ctx.compositingOperation = .sourceOver

        NSColor.black.setStroke()
        bracos.lineWidth = 5 * s
        bracos.stroke()
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "Kandela"
    return img
}

// MARK: - Preferências

/// Chaves no `defaults` (domínio `br.com.kogut.kandela`). Os valores vêm do km-dimmer e
/// ficam em inglês de propósito: mudá-los apagaria as preferências de quem já usa o app.
enum Chave {
    static let ativado = "enabled"
    static let intensidade = "intensity"
    static let modoApp = "appMode"
    static let migrouDoNomeAntigo = "migratedFromOldName"
}

// MARK: - Delegado

final class Delegado: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var itemBarra: NSStatusItem?
    private var veus: [Veu] = []
    private var relogio: Timer?
    private var ultimoAlvo: CGWindowID = 0

    private let padrao = UserDefaults.standard
    private var ativado: Bool {
        get { padrao.bool(forKey: Chave.ativado) }
        set { padrao.set(newValue, forKey: Chave.ativado) }
    }
    private var intensidade: Double {
        get { padrao.double(forKey: Chave.intensidade) }
        set { padrao.set(newValue, forKey: Chave.intensidade) }
    }
    private var modoApp: Bool {            // true = todas as janelas do app em foco ficam claras
        get { padrao.bool(forKey: Chave.modoApp) }
        set { padrao.set(newValue, forKey: Chave.modoApp) }
    }

    // MARK: ciclo de vida

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrarPreferenciasDoNomeAntigo()
        padrao.register(defaults: [Chave.ativado: true, Chave.intensidade: 0.35, Chave.modoApp: false])

        montarVeus()
        montarItemBarra()

        NotificationCenter.default.addObserver(
            self, selector: #selector(telasMudaram),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(focoMudou),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // O relógio cobre trocas de janela dentro do mesmo app (sem precisar de
        // permissão de Acessibilidade). Custo de CPU: desprezível.
        let r = Timer(timeInterval: 0.2, target: self,
                      selector: #selector(pulso), userInfo: nil, repeats: true)
        RunLoop.main.add(r, forMode: .common)
        relogio = r

        aplicarIntensidade(animado: true)
        reordenar(forcado: true)
    }

    // MARK: véus

    private func montarVeus() {
        veus.forEach { $0.orderOut(nil) }
        veus = NSScreen.screens.map { Veu(quadro: $0.frame) }
        ultimoAlvo = 0
    }

    private func aplicarIntensidade(animado: Bool) {
        let alvo = ativado ? CGFloat(intensidade) : 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animado ? 0.25 : 0
            veus.forEach { $0.animator().alphaValue = alvo }
        }
    }

    @objc private func telasMudaram() {
        montarVeus()
        aplicarIntensidade(animado: false)
        reordenar(forcado: true)
    }

    @objc private func focoMudou() { reordenar(forcado: true) }
    @objc private func pulso() { reordenar(forcado: false) }

    /// Reposiciona os véus logo abaixo da janela do app em primeiro plano.
    private func reordenar(forcado: Bool) {
        guard ativado else { return }
        guard let lista = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return }

        let meuPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let pidFrente = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // A lista vem ordenada da frente para trás.
        var alvo: CGWindowID = 0
        for info in lista {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != meuPID,
                  let numero = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            if let alfa = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
               alfa == 0 { continue }                        // janelas invisíveis
            if let b = info[kCGWindowBounds as String] as? [String: Any],
               let ret = CGRect(dictionaryRepresentation: b as CFDictionary),
               ret.width < 50 || ret.height < 50 { continue }  // janelas auxiliares minúsculas
            if let pidFrente, pid != pidFrente { continue }  // só janelas do app em foco
            alvo = numero         // sem modoApp: a mais à frente e para;
            if !modoApp { break } // com modoApp: continua até a mais atrás do app
        }

        if alvo == 0 {            // nada em foco (ex.: mesa) → não escurece
            if ultimoAlvo != 0 || forcado {
                veus.forEach { $0.orderOut(nil) }
                ultimoAlvo = 0
            }
            return
        }
        guard forcado || alvo != ultimoAlvo else { return }
        ultimoAlvo = alvo
        veus.forEach { $0.order(.below, relativeTo: Int(alvo)) }
    }

    /// Até 11/10/2026 o app se chamava km-dimmer, com o bundle id `br.com.kogut.km-dimmer`.
    /// As preferências ficam guardadas pelo bundle id; na primeira abertura com o id novo,
    /// copia as do antigo. O domínio antigo fica como está.
    private func migrarPreferenciasDoNomeAntigo() {
        guard !padrao.bool(forKey: Chave.migrouDoNomeAntigo) else { return }
        defer { padrao.set(true, forKey: Chave.migrouDoNomeAntigo) }
        guard let antigas = padrao.persistentDomain(forName: "br.com.kogut.km-dimmer") else { return }
        for chave in [Chave.ativado, Chave.intensidade, Chave.modoApp] where padrao.object(forKey: chave) == nil {
            if let valor = antigas[chave] { padrao.set(valor, forKey: chave) }
        }
    }

    // MARK: menu na barra

    private func montarItemBarra() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = marcaKandela(tamanho: 18)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        itemBarra = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let liga = NSMenuItem(title: "Ativado", action: #selector(alternarAtivado), keyEquivalent: "")
        liga.target = self
        liga.state = ativado ? .on : .off
        menu.addItem(liga)

        menu.addItem(.separator())
        let titulo = NSMenuItem(title: "Intensidade", action: nil, keyEquivalent: "")
        titulo.isEnabled = false
        menu.addItem(titulo)
        for pct in [20, 35, 50, 65, 80] {
            let i = NSMenuItem(title: "\(pct)%", action: #selector(escolherIntensidade(_:)), keyEquivalent: "")
            i.target = self
            i.tag = pct
            i.state = Int((intensidade * 100).rounded()) == pct ? .on : .off
            menu.addItem(i)
        }

        menu.addItem(.separator())
        let modo = NSMenuItem(title: "Destacar todas as janelas do app",
                              action: #selector(alternarModoApp), keyEquivalent: "")
        modo.target = self
        modo.state = modoApp ? .on : .off
        menu.addItem(modo)

        menu.addItem(.separator())
        let sair = NSMenuItem(title: "Sair do Kandela",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        sair.target = NSApp
        menu.addItem(sair)
    }

    // MARK: ações

    @objc private func alternarAtivado() {
        ativado.toggle()
        aplicarIntensidade(animado: true)
        if ativado {
            reordenar(forcado: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.ativado else { return }
                self.veus.forEach { $0.orderOut(nil) }
                self.ultimoAlvo = 0
            }
        }
    }

    @objc private func escolherIntensidade(_ item: NSMenuItem) {
        intensidade = Double(item.tag) / 100.0
        aplicarIntensidade(animado: true)
        reordenar(forcado: true)
    }

    @objc private func alternarModoApp() {
        modoApp.toggle()
        reordenar(forcado: true)
    }
}

// MARK: - Partida

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.setActivationPolicy(.accessory)   // sem ícone no Dock, só na barra de menus
app.run()
