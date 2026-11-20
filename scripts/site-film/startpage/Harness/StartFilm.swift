import AppKit

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct BarRow {
    let id: String
    let title: String
    var subtitle: String? = nil
    var detail: String = ""
    var accessory: String = ""
    var isTab = false
    var icon: NSImage?
    var isAction = false
    var folder: CommandBarFolderAction? = nil
}

@MainActor final class FlippedBox: NSView { override var isFlipped: Bool { true } }

@MainActor final class Caret: NSView {
    var opacity: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard opacity > 0 else { return }
        NSColor(srgbRed: 0, green: 0.533, blue: 1, alpha: opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1, yRadius: 1).fill()
    }
}

enum Curve {
    static func bezier(_ x: Double, _ p1: CGPoint, _ p2: CGPoint) -> Double {
        let x = min(1, max(0, x))
        func b(_ t: Double, _ a: Double, _ c: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * c + t * t * t }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 { let mid = (lo + hi) / 2; if b(mid, Double(p1.x), Double(p2.x)) < x { lo = mid } else { hi = mid } }
        return b((lo + hi) / 2, Double(p1.y), Double(p2.y))
    }
    static func easeOut(_ x: Double) -> Double { bezier(x, CGPoint(x: 0, y: 0), CGPoint(x: 0.58, y: 1)) }
    static func easeInOut(_ x: Double) -> Double { bezier(x, CGPoint(x: 0.42, y: 0), CGPoint(x: 0.58, y: 1)) }
    static func unit(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
}

@MainActor final class StartFilm {
    static let fps = 60.0
    static let closeAt = 0.60
    static let keys: [(Double, String)] = [(2.00, "p"), (2.15, "pi"), (2.28, "pic"), (2.47, "picn"), (2.60, "picni"), (2.74, "picnic")]
    static let escapeAt = 4.00
    static let pointerIn = 4.45
    static let pointerArrive = 5.35
    static let pressAt = 5.50
    static let releaseAt = 6.95
    static let pointerLeave = 7.40
    static let pointerGone = 8.35
    static let frames = 676

    let scene: BrowserScene
    let scenario: Scenario
    let root: NSView
    let page: StartPageView
    let kite: PageImage?
    let barHost = NSView()
    let container = PopoverBackgroundView(blending: .withinWindow)
    let inputIcon = NSImageView()
    let input = NSTextField()
    let divider = CommandBarHairline(frame: .zero)
    let list = FlippedBox()
    let caret = Caret()
    let palette: CommandBarPalette
    var rowViews: [String: CommandResultRowView] = [:]
    var current: [BarRow] = []
    var folder: CommandBarFolderAction?
    let colors: [CGColor]
    var body: CALayer
    var recognizer = StartPageMarkGestureRecognizer()
    var session = StartPageMarkSession()
    var effects: CALayer?
    var pieces: [(StartPageMarkConfettiPiece, CALayer)] = []
    var buzz: [CGFloat] = []
    var log: [[String: Any]] = []

    init(pagePath: String) {
        scenario = StartScenario.make()
        scene = BrowserScene(size: NSSize(width: 1440, height: 900), windowRect: NSRect(x: 80, y: 18, width: 1280, height: 840),
                             scale: 2, pagePath: "", scenario: scenario)
        kite = PageImage(path: pagePath)
        let card = scene.surface.pageCard
        root = NSView(frame: NSRect(origin: .zero, size: card.size))
        root.wantsLayer = true
        root.appearance = NSAppearance(named: .aqua)
        page = StartPageView(frame: root.bounds)
        page.appearance = NSAppearance(named: .aqua)
        page.theme = scenario.work.theme
        page.barRestHeight = CommandBarResidentLayout.restHeight
        root.addSubview(page)
        page.layoutSubtreeIfNeeded()
        palette = CommandBarPalette(theme: scenario.work.theme)
        colors = scenario.work.theme.colors.map { NSColor(displayP3Red: $0.red, green: $0.green, blue: $0.blue, alpha: 1).cgColor }
        body = page.mark.subviews.first!.layer!
        buildBar()
        folder = Self.picnicFolder(scenario)
        var random = SplitMix(state: 0x5EED_0F_C0FFEE)
        let frame = StartPageMarkFrame(layer: body)
        let amplitude = StartPageMarkCharge.buzz * frame.scale
        buzz = (0..<StartPageMarkCharge.buzzFrames).map { _ in CGFloat.random(in: -amplitude...amplitude, using: &random) }
        print("page flipped chain: paper", page.paper.layer?.contentsAreFlipped() ?? false, "effects", page.markEffects.layer?.contentsAreFlipped() ?? false,
              "mark frame", frame, "folder", folder.map { "\($0.title) \($0.name) \($0.detail)" } ?? "none")
    }

    static func picnicFolder(_ scenario: Scenario) -> CommandBarFolderAction? {
        var state = scenario.state
        let home = scenario.spaces[1]
        state.folders.append(BrowserFolder(id: UUID(), spaceID: home.id, name: "Picnic plans", parentID: nil))
        return CommandBarFolderAction.snapshot(state: state, profileID: home.profileID).first { $0.name == "Picnic plans" }
    }

    func buildBar() {
        let slot = page.commandBarSlot
        barHost.frame = slot.bounds
        barHost.autoresizingMask = [.width, .height]
        slot.addSubview(barHost)
        container.flatFill = true
        container.cornerRadius = 12
        container.appearance = NSAppearance(named: .aqua)
        barHost.addSubview(container)
        inputIcon.imageScaling = .scaleProportionallyDown
        inputIcon.wantsLayer = true
        inputIcon.contentTintColor = palette.inputIcon
        container.addSubview(inputIcon)
        input.isBordered = false; input.drawsBackground = false; input.wantsLayer = true
        input.font = CommandBarTypography.field
        input.placeholderString = "Search or Enter URL…"
        input.usesSingleLineMode = true; input.cell?.wraps = false
        input.cell?.isScrollable = true; input.lineBreakMode = .byClipping
        input.focusRingType = .none
        input.textColor = palette.inputText
        container.addSubview(input)
        container.addSubview(divider)
        container.addSubview(list)
        container.addSubview(caret)
        layoutBar(rows: 0)
    }

    func layoutBar(rows: Int) {
        let expanded = rows > 0
        let height = CommandBarResidentLayout.height(expanded: expanded, rows: rows)
        container.frame = CommandBarResidentLayout.surfaceFrame(in: barHost.bounds, height: height)
        let width = container.bounds.width
        inputIcon.frame = NSRect(x: 22, y: 22, width: 18, height: 18)
        input.frame = NSRect(x: 49, y: 21, width: max(0, width - 71), height: 31)
        divider.frame = NSRect(x: 12, y: 64, width: max(0, width - 24), height: 0.5)
        list.frame = NSRect(x: 8, y: 68, width: max(0, width - 16), height: max(0, container.bounds.height - 76))
        divider.isHidden = !expanded
        list.isHidden = !expanded
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.updateLayer()
        divider.updateLayer()
    }

    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? SidebarPlusMenuArtwork.image(name)
    }

    func rows(for query: String) -> [BarRow] {
        func search(_ text: String) -> BarRow { BarRow(id: "search:" + text, title: text, icon: Self.symbol("magnifyingglass")) }
        let picnicTab = BarRow(id: "tab:picnic", title: Canon.picnic.title, accessory: CommandBarResultText.tabCaption(
            isFavorite: false, isInActiveSpace: false, spaceName: "Home", isInSplit: false).text, isTab: true,
            icon: Favicons.specs[Canon.picnic.url].map(Favicons.image))
        let note = BarRow(id: "note:picnic", title: "Picnic packing list", detail: "Note",
                          icon: Self.symbol(InternalPage.note(URL(fileURLWithPath: "/Picnic packing list.md")).sidebarFallbackSymbol))
        let pottery = BarRow(id: "tab:pottery", title: "Pottery wheel notes", accessory: CommandBarResultText.TabCaption.switchToTab.text,
                             isTab: true, icon: Favicons.specs["https://notes.example.com/pottery-wheel"].map(Favicons.image))
        let command: BarRow = folder.map {
            BarRow(id: $0.id, title: $0.title, detail: $0.detail, icon: Self.symbol("folder"), isAction: true, folder: $0)
        } ?? search("picnic spots near me")
        switch query {
        case "": return []
        case "p": return [search("p"), pottery, search("parks near me"), search("pasta recipes"), picnicTab]
        case "pi": return [search("pi"), search("pizza dough"), picnicTab, search("pilates classes"), note]
        case "pic": return [search("pic"), picnicTab, note, search("pictures"), search("pickled onions")]
        case "picn", "picni": return [search(query), note, picnicTab, search("picnic ideas"), command]
        default: return [search("picnic"), note, picnicTab, search("picnic ideas for summer"), command]
        }
    }

    func publish(_ rows: [BarRow]) {
        layoutBar(rows: rows.count)
        let ids = Set(rows.map(\.id))
        for (id, view) in rowViews where !ids.contains(id) { view.removeFromSuperview(); rowViews[id] = nil }
        for (index, row) in rows.enumerated() {
            let view: CommandResultRowView
            if let existing = rowViews[row.id] { view = existing } else {
                view = CommandResultRowView(frame: NSRect(x: 0, y: 0, width: list.bounds.width, height: 50))
                view.selectedColor = palette.selected
                view.selectionHighlightStyle = .none
                let cell = CommandResultCell(title: row.title, subtitle: row.subtitle, detail: row.detail, accessory: row.accessory,
                                             isTab: row.isTab, icon: row.icon, enabled: true, folderAction: row.folder, isAction: row.isAction)
                cell.selectedColor = palette.selected
                cell.frame = view.bounds
                cell.autoresizingMask = [.width, .height]
                view.addSubview(cell)
                list.addSubview(view)
                rowViews[row.id] = view
            }
            view.frame = NSRect(x: 0, y: CGFloat(index) * 50, width: list.bounds.width, height: 50)
            view.isSelected = index == 0
            view.selectedColor = palette.selected
            view.subviews.compactMap { $0 as? CommandResultCell }.forEach { $0.setSelected(index == 0) }
            view.needsLayout = true
        }
        current = rows
        list.layoutSubtreeIfNeeded()
        inputIcon.image = input.stringValue.isEmpty || rows.isEmpty ? Self.symbol("magnifyingglass") : rows[0].icon
    }

    func placeCaret(opacity: CGFloat) {
        let text = NSAttributedString(string: input.stringValue, attributes: [.font: CommandBarTypography.field])
        let width = input.stringValue.isEmpty ? 0 : ceil(text.size().width)
        caret.frame = NSRect(x: input.frame.minX + 2 + width, y: 21.5, width: 2, height: 22)
        caret.opacity = opacity
    }

    static func caretOpacity(idle: Double) -> CGFloat {
        guard idle > 0.5 else { return 1 }
        let phase = (idle - 0.5).truncatingRemainder(dividingBy: 1.0), fade = 0.12
        if phase < 0.5 { return phase < fade ? CGFloat(1 - phase / fade) : 0 }
        return phase - 0.5 < fade ? CGFloat((phase - 0.5) / fade) : 1
    }

    var markFrame: StartPageMarkFrame { StartPageMarkFrame(layer: body) }
    var pressPoint: CGPoint { CGPoint(x: 30, y: 58) }

    func setBody(transform: CATransform3D, glow: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        body.transform = transform
        let values = StartPageMarkCharge.glow(glow, scale: markFrame.scale)
        body.shadowOffset = .zero
        body.shadowColor = colors.first
        body.shadowRadius = values.radius
        body.shadowOpacity = values.opacity
        CATransaction.commit()
    }

    func landingPose(at time: Double) -> StartPageMarkPose {
        let poses = StartPageMarkLanding.poses(), times = StartPageMarkLanding.spring.times()
        guard time > 0 else { return poses[0] }
        guard let next = times.firstIndex(where: { $0 >= time }) else { return .identity }
        let previous = max(0, next - 1)
        let span = times[next] - times[previous]
        let u = span > 0 ? CGFloat((time - times[previous]) / span) : 1
        let a = poses[previous], b = poses[next]
        return StartPageMarkPose(scale: CGSize(width: a.scale.width + (b.scale.width - a.scale.width) * u,
                                               height: a.scale.height + (b.scale.height - a.scale.height) * u),
                                 origin: StartPageMarkPose.bottom)
    }

    func startConfetti() {
        guard let host = page.markEffects.layer else { return }
        var random = SplitMix(state: 0xC0_FE77_1D)
        let made = StartPageMarkConfetti.pieces(colors: colors.count, using: &random)
        let container = CALayer()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        container.frame = host.bounds
        container.isGeometryFlipped = false
        container.contentsScale = 2
        host.addSublayer(container)
        let home = page.markEffects.convert(NSPoint(x: page.mark.bounds.midX, y: page.mark.bounds.midY), from: page.mark)
        pieces = made.map { piece in
            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: piece.size)
            layer.position = home
            layer.backgroundColor = colors[piece.color]
            layer.opacity = 0
            container.addSublayer(layer)
            return (piece, layer)
        }
        CATransaction.commit()
        effects = container
        confettiHome = home
        log.append(["event": "confetti", "pieces": made.count, "home": [home.x, home.y],
                    "lifeMax": made.map(\.life).max() ?? 0, "colors": colors.count])
    }
    var confettiHome = CGPoint.zero

    func updateConfetti(_ time: Double) {
        guard let effects else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        var alive = false
        for (piece, layer) in pieces {
            guard time <= piece.life else { layer.opacity = 0; continue }
            alive = true
            let offset = piece.offset(at: time)
            layer.position = CGPoint(x: confettiHome.x + offset.dx, y: confettiHome.y + offset.dy)
            let turn = CATransform3DMakeRotation(piece.angle(at: time), 0, 0, 1)
            layer.transform = CATransform3DConcat(CATransform3DMakeScale(1, piece.flutter(at: time), 1), turn)
            layer.opacity = Float(piece.opacity(at: time))
        }
        if !alive { effects.removeFromSuperlayer(); self.effects = nil; pieces = [] }
        CATransaction.commit()
    }

    func pointer(at t: Double) -> CGPoint? {
        let mark = page.mark.frame
        let press = CGPoint(x: mark.minX + pressPoint.x, y: mark.minY + pressPoint.y)
        let start = CGPoint(x: 820, y: 690)
        let exit = CGPoint(x: page.bounds.width + 90, y: page.bounds.height + 60)
        guard t >= Self.pointerIn, t < Self.pointerGone else { return nil }
        if t < Self.pointerArrive {
            let u = CGFloat(Curve.easeInOut(Curve.unit(t, Self.pointerIn, Self.pointerArrive)))
            let bow = sin(u * .pi) * 26
            return CGPoint(x: start.x + (press.x - start.x) * u + bow * 0.4, y: start.y + (press.y - start.y) * u + bow)
        }
        if t < Self.pointerLeave { return press }
        let u = CGFloat(pow(Curve.unit(t, Self.pointerLeave, Self.pointerGone), 1.6))
        return CGPoint(x: press.x + (exit.x - press.x) * u, y: press.y + (exit.y - press.y) * u + sin(u * .pi) * 30)
    }

    func windowFlips() {
        root.layoutSubtreeIfNeeded()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in (page.paper.layer?.sublayers ?? []).prefix(2) where layer.isGeometryFlipped { layer.isGeometryFlipped = false }
        CATransaction.commit()
    }

    func snapshot() -> NSImage {
        windowFlips()
        let rep = StartProbe.snapshot(root)
        let image = NSImage(size: root.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func run(out: String, keysOnly: Bool) {
        let card = scene.surface.pageCard
        let land = Self.closeAt + PeekDismissalTiming.fade + 1 / Self.fps
        var kiteAlpha: CGFloat = 1, startAlpha: CGFloat = 0
        var startImage: NSImage?
        scene.surface.drawPage = { [unowned self] rect in
            if kiteAlpha > 0, let kite = self.kite, let context = NSGraphicsContext.current?.cgContext {
                context.saveGState(); context.setAlpha(kiteAlpha); context.beginTransparencyLayer(auxiliaryInfo: nil)
                kite.draw(in: rect)
                context.endTransparencyLayer(); context.restoreGState()
            }
            if startAlpha > 0, let startImage {
                startImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: startAlpha, respectFlipped: true,
                                hints: [.interpolation: NSImageInterpolation.high.rawValue])
            }
        }
        var motion = PeekDismissalMotion()
        var closed = false, landed = false, lastQuery: String? = nil
        var lastKeyEvent = land
        var chargeSince: Double?, released = false, loopStart: Double?, landingStart: Double?
        var level: CGFloat = 0
        var settledAt: Double?
        var pressDelivered = false, holdDelivered = false
        let sheetTimes: [Double] = [0.30, 0.70, 0.90, 1.60, 2.30, 3.40, 4.30, 5.20, 6.20, 6.75, 7.40, 8.10]
        let keyTimes: [(String, Double)] = [("fade-mid", 0.70), ("results", 3.40), ("charge-peak", 6.80), ("loop-mid", 7.42),
                                            ("confetti", 7.80), ("confetti-late", 8.60), ("settled", 9.40)]
        var sheet: [(Double, CGImage)] = []
        var trace: [[String: Any]] = []
        let writer = keysOnly ? nil : try! AlphaVideoWriter(path: out + "/startpage.mov", width: 2880, height: 1800)
        let wanted = keysOnly ? Set((sheetTimes + keyTimes.map(\.1) + [Double(Self.frames - 1) / Self.fps]).map { Int(($0 * Self.fps).rounded()) }) : nil
        var started = Date()
        for frame in 0..<Self.frames {
            let t = Double(frame) / Self.fps
            if t >= Self.closeAt, t < land {
                if frame == Int((Self.closeAt * Self.fps).rounded()) { motion.exit(.fade, velocity: 0, reducesMotion: false, at: Self.closeAt) }
                let value = motion.frame(at: t).card
                kiteAlpha = CGFloat(value); startAlpha = CGFloat(1 - value)
            } else if t >= land {
                kiteAlpha = 0; startAlpha = 1
            }
            if t >= Self.closeAt + PeekDismissalTiming.fade, !closed {
                closed = true
                scene.sidebar.render(state: StartScenario.closed(scenario), focusedTabID: nil, loading: [], canBack: false, canForward: false)
                let end = Date().addingTimeInterval(0.6)
                while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                scene.sidebar.needsLayout = true; scene.sidebar.layoutSubtreeIfNeeded()
                log.append(["event": "sidebar row leaves; tab closed", "t": t])
            }
            let slotAlpha: CGFloat = t < land ? 0 : CGFloat(Curve.easeOut(Curve.unit(t, land, land + 0.15)))
            if !landed, t >= land { landed = true; log.append(["event": "close lands; resident bar fades in 0.15 s easeOut, field focused", "t": t]) }
            page.commandBarSlot.alphaValue = slotAlpha
            page.commandBarSlot.isHidden = t < land
            let typed = t >= Self.escapeAt ? "" : (Self.keys.last { $0.0 <= t }?.1 ?? "")
            if let key = Self.keys.last(where: { $0.0 <= t }), t < Self.escapeAt { lastKeyEvent = max(lastKeyEvent, key.0) }
            if t >= Self.escapeAt { lastKeyEvent = max(lastKeyEvent, Self.escapeAt) }
            let arrivedQuery: String
            if t >= Self.escapeAt { arrivedQuery = "" } else if let index = Self.keys.lastIndex(where: { $0.0 + (($0.1 == "p") ? 0.05 : 0.034) <= t }) {
                arrivedQuery = Self.keys[index].1
            } else { arrivedQuery = "" }
            if input.stringValue != typed { input.stringValue = typed }
            if arrivedQuery != lastQuery || (typed.isEmpty && !current.isEmpty) {
                publish(rows(for: arrivedQuery))
                lastQuery = arrivedQuery
            }
            if current.isEmpty { inputIcon.image = Self.symbol("magnifyingglass") }
            placeCaret(opacity: t >= land ? Self.caretOpacity(idle: t - lastKeyEvent) : 0)
            container.updateLayer(); divider.updateLayer()

            let markTime = ProcessInfo.processInfo.systemUptime
            _ = markTime
            if t >= Self.pressAt, !pressDelivered {
                pressDelivered = true
                let cues = recognizer.pointerDown(at: pressPoint, time: Self.pressAt, idle: session.isIdle)
                log.append(["event": "mouse down on mark", "t": t, "cues": "\(cues)", "holdDeadline": recognizer.holdDeadline ?? -1])
            }
            if pressDelivered, !holdDelivered, let deadline = recognizer.holdDeadline, t >= deadline {
                holdDelivered = true
                let cues = recognizer.holdElapsed(at: deadline)
                var effects: [StartPageMarkSession.Effect] = []
                for cue in cues { effects += session.handle(cue, canAnimate: true, reduceMotion: false) }
                if effects.contains(.charge(.motion)) { chargeSince = deadline }
                log.append(["event": "hold elapsed (0.35 s)", "t": deadline, "cues": "\(cues)", "effects": "\(effects)"])
            }
            if t >= Self.releaseAt, !released, chargeSince != nil {
                released = true
                let cues = recognizer.pointerUp(at: pressPoint, time: Self.releaseAt)
                var effects: [StartPageMarkSession.Effect] = []
                for cue in cues { effects += session.handle(cue, canAnimate: true, reduceMotion: false) }
                if case .discharge(let value)? = cues.first { level = value }
                if effects.contains(.play(.loop)) { loopStart = Self.releaseAt; startConfetti() }
                log.append(["event": "mouse up", "t": Self.releaseAt, "level": Double(level), "cues": "\(cues)", "effects": "\(effects)"])
            }
            let frameGeometry = markFrame
            if let since = chargeSince, !released {
                let held = t - since
                let charge = StartPageMarkCharge.level(held: held)
                var transform = StartPageMarkCharge.holdPose(level: charge).transform(in: frameGeometry)
                if held >= StartPageMarkCharge.ramp {
                    let index = Int(((held - StartPageMarkCharge.ramp) * StartPageMarkCharge.frameRate).rounded(.down)) % StartPageMarkCharge.buzzFrames
                    transform.m41 += buzz[index]
                }
                setBody(transform: transform, glow: StartPageMarkEasing.outCubic(charge))
            } else if let start = loopStart, t - start < StartPageMarkCharge.loopDuration {
                let time = t - start
                setBody(transform: StartPageMarkCharge.loopPose(at: time, radius: StartPageMarkCharge.loopRadius * frameGeometry.scale)
                            .transform(in: frameGeometry), glow: StartPageMarkCharge.loopGlow(at: time))
            } else if let start = loopStart {
                if landingStart == nil {
                    landingStart = start + StartPageMarkCharge.loopDuration
                    let effects = session.land(generation: session.generation)
                    log.append(["event": "loop lands; landing squash + wobble", "t": landingStart!, "effects": "\(effects)",
                                "landingDuration": StartPageMarkLanding.duration])
                }
                let time = t - landingStart!
                setBody(transform: landingPose(at: time).transform(in: frameGeometry), glow: 0)
                if time >= StartPageMarkLanding.duration, settledAt == nil { settledAt = landingStart! + StartPageMarkLanding.duration }
            } else {
                setBody(transform: CATransform3DIdentity, glow: 0)
            }
            if let start = loopStart { updateConfetti(t - start) }
            if effects == nil, loopStart != nil, log.last?["event"] as? String != "confetti cleared",
               !log.contains(where: { $0["event"] as? String == "confetti cleared" }) {
                log.append(["event": "confetti cleared", "t": t])
                session.finish(generation: session.generation)
            }
            scene.pointer.location = pointer(at: t).map { CGPoint(x: $0.x + card.minX, y: $0.y + card.minY) }

            if let wanted, !wanted.contains(frame) { continue }
            autoreleasepool {
                startImage = startAlpha > 0 ? snapshot() : nil
                scene.surface.needsDisplay = true
                let bitmap = scene.render(NSRect(origin: .zero, size: scene.stage.bounds.size), pixelsWide: 2880, pixelsHigh: 1800)
                guard let image = bitmap.cgImage else { fatalError("no frame image") }
                writer?.append(image)
                if sheetTimes.contains(where: { abs($0 - t) < 0.5 / Self.fps }) { sheet.append((t, image)) }
                for (name, time) in keyTimes where abs(time - t) < 0.5 / Self.fps {
                    Render.writePNG(NSBitmapImageRep(cgImage: image), out + "/key-\(name).png")
                }
                if frame == Self.frames - 1 {
                    sheet.append((t, image))
                    Render.writePNG(NSBitmapImageRep(cgImage: image), out + "/rest.png")
                }
            }
            trace.append(["frame": frame, "t": t, "pageAlpha": Double(kiteAlpha), "startPageAlpha": Double(startAlpha), "barAlpha": Double(slotAlpha),
                          "query": typed, "rows": current.count, "caret": Double(caret.opacity), "pointer": scene.pointer.location.map { [$0.x, $0.y] } ?? NSNull(),
                          "confetti": pieces.filter { $0.1.opacity > 0 }.count, "markShadowOpacity": Double(body.shadowOpacity)])
            if frame % 60 == 0 { print(String(format: "frame %d t=%.2f (%.1fs)", frame, t, Date().timeIntervalSince(started))); started = Date() }
        }
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/startpage.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        Self.writeSheet(sheet, path: out + "/startpage-strip.png")
        writeBeats(out: out, trace: trace, land: land, settled: settledAt)
    }

    func writeBeats(out: String, trace: [[String: Any]], land: Double, settled: Double?) {
        func f(_ t: Double) -> Int { Int((t * Self.fps).rounded()) }
        let confettiEnd = (log.first { $0["event"] as? String == "confetti cleared" }?["t"] as? Double) ?? 0
        let end = Double(Self.frames) / Self.fps
        let beats: [[String: Any]] = [
            ["beat": "Kite page open in Side quest (single Today tab)", "start": 0.0, "end": Self.closeAt],
            ["beat": "Command-W: page fades out while the start page fades in beneath (0.2 s, eased out 1-(1-u)^2, opacities locked)", "start": Self.closeAt, "end": Self.closeAt + 0.2],
            ["beat": "Close lands: Today row leaves; resident bar fades in (0.15 s easeOut), field focused", "start": Self.closeAt + 0.2, "end": land + 0.15],
            ["beat": "Caret blinks in the empty resident bar", "start": land + 0.15, "end": Self.keys[0].0],
            ["beat": "Typing \"picnic\"; results grow downward from the fixed top edge (max 5 rows)", "start": Self.keys[0].0, "end": Self.keys.last!.0],
            ["beat": "Hold on results", "start": Self.keys.last!.0, "end": Self.escapeAt],
            ["beat": "Escape: query cleared, results collapse to the 64 pt field", "start": Self.escapeAt, "end": Self.pointerIn],
            ["beat": "Pointer drifts to the mark", "start": Self.pointerIn, "end": Self.pointerArrive],
            ["beat": "Press and hold on the mark (hold threshold 0.35 s)", "start": Self.pressAt, "end": Self.pressAt + 0.35],
            ["beat": "Charge-up: squish + glow fill over 0.65 s, buzz once full", "start": Self.pressAt + 0.35, "end": Self.releaseAt],
            ["beat": "Release at full charge: loop the loop (0.95 s) + 90 confetti pieces", "start": Self.releaseAt, "end": Self.releaseAt + StartPageMarkCharge.loopDuration],
            ["beat": "Landing squash + wobble settle", "start": Self.releaseAt + StartPageMarkCharge.loopDuration, "end": settled ?? 0.0],
            ["beat": "Confetti falls and fades out", "start": Self.releaseAt, "end": confettiEnd],
            ["beat": "Resting start page (pointer gone, no confetti, caret blinking; last frame caret fully on)", "start": max(confettiEnd, settled ?? 0, Self.pointerGone), "end": end],
        ].map { var row = $0; row["startFrame"] = f(row["start"] as! Double); row["endFrame"] = f(row["end"] as! Double); return row }
        let root: [String: Any] = [
            "file": "startpage.mov", "codec": "hevcWithAlpha", "width": 2880, "height": 1800, "pointSize": [1440, 900], "scale": 2,
            "fps": Self.fps, "frames": Self.frames, "duration": end,
            "window": ["x": 80, "y": 18, "width": 1280, "height": 840, "pixels": [160, 36, 2560, 1680], "origin": "top-left"],
            "pageCard": [scene.surface.pageCard.minX, scene.surface.pageCard.minY, scene.surface.pageCard.width, scene.surface.pageCard.height],
            "mark": [page.mark.frame.minX, page.mark.frame.minY, page.mark.frame.width, page.mark.frame.height],
            "commandBarSlot": [page.commandBarSlot.frame.minX, page.commandBarSlot.frame.minY, page.commandBarSlot.frame.width],
            "keys": Self.keys.map { ["t": $0.0, "frame": f($0.0), "text": $0.1] },
            "beats": beats, "events": log, "trace": trace]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: out + "/startpage-beats.json"))
        print("wrote", out + "/startpage-beats.json")
    }

    static func writeSheet(_ frames: [(Double, CGImage)], path: String) {
        let columns = 4, cell = CGSize(width: 720, height: 450), label: CGFloat = 28
        let rows = (frames.count + columns - 1) / columns
        let width = Int(cell.width) * columns, height = Int(cell.height + label) * rows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(hex(0xE6E6EA).cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        for (index, (time, image)) in frames.enumerated() {
            let column = index % columns, row = index / columns
            let x = CGFloat(column) * cell.width, top = CGFloat(height) - CGFloat(row) * (cell.height + label)
            context.draw(image, in: CGRect(x: x, y: top - label - cell.height, width: cell.width, height: cell.height))
            NSAttributedString(string: String(format: "t = %.2f s  ·  frame %d", time, Int((time * fps).rounded())),
                               attributes: [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black])
                .draw(at: NSPoint(x: x + 14, y: top - label + 6))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return }
        Render.writePNG(NSBitmapImageRep(cgImage: image), path)
    }
}
