import AppKit

func springProgress(_ t: Double, response: Double, damping: Double) -> Double {
    guard t > 0 else { return 0 }
    let omega = 2 * Double.pi / response
    let decay = damping * omega
    let damped = omega * (1 - damping * damping).squareRoot()
    return 1 - exp(-decay * t) * (cos(damped * t) + decay / damped * sin(damped * t))
}

func easeInOut(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
}

func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    func curve(_ s: Double, _ a: Double, _ b: Double) -> Double { 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s }
    var low = 0.0, high = 1.0
    for _ in 0..<30 {
        let mid = (low + high) / 2
        if curve(mid, x1, x2) < x { low = mid } else { high = mid }
    }
    return curve((low + high) / 2, y1, y2)
}

func lerp(_ a: NSRect, _ b: NSRect, _ x: CGFloat) -> NSRect {
    NSRect(x: a.minX + (b.minX - a.minX) * x, y: a.minY + (b.minY - a.minY) * x,
           width: a.width + (b.width - a.width) * x, height: a.height + (b.height - a.height) * x)
}

struct PointerPath {
    var keys: [(Double, NSPoint)]
    func at(_ t: Double) -> NSPoint {
        guard let first = keys.first, let last = keys.last else { return .zero }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for index in 1..<keys.count where t <= keys[index].0 {
            let (t0, p0) = keys[index - 1], (t1, p1) = keys[index]
            let x = CGFloat(easeInOut((t - t0) / max(0.0001, t1 - t0)))
            let bow = CGFloat(sin(Double(x) * .pi)) * min(18, hypot(p1.x - p0.x, p1.y - p0.y) * 0.06)
            let length = max(0.001, hypot(p1.x - p0.x, p1.y - p0.y))
            let normal = NSPoint(x: -(p1.y - p0.y) / length, y: (p1.x - p0.x) / length)
            return NSPoint(x: p0.x + (p1.x - p0.x) * x + normal.x * bow, y: p0.y + (p1.y - p0.y) * x + normal.y * bow)
        }
        return last.1
    }
}

@MainActor final class StagePointer: NSView {
    var location: NSPoint? { didSet { needsDisplay = true } }
    var pointingHand = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let location else { return }
        let cursor = pointingHand ? NSCursor.pointingHand : NSCursor.arrow
        let image = cursor.image, hot = cursor.hotSpot
        image.draw(in: NSRect(x: location.x - hot.x, y: location.y - hot.y, width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor final class PiPStandIn: NSView {
    let panel: NSRect
    var video: CGImage?
    var showsChrome = false { didSet { slider.isHidden = !showsChrome; needsDisplay = true } }
    var progress: Double = 0.38 { didSet { slider.doubleValue = progress } }
    var favicon: NSImage?
    var title = ""
    let slider = NSSlider(value: 0.38, minValue: 0, maxValue: 1, target: nil, action: nil)
    override var isFlipped: Bool { true }

    init(frame: NSRect, panel: NSRect) {
        self.panel = panel
        super.init(frame: frame)
        slider.controlSize = .mini
        slider.isHidden = true
        addSubview(slider)
        let height = max(12, slider.fittingSize.height)
        let faviconLeft = panel.maxX - 12 - 18
        slider.frame = NSRect(x: panel.minX + 12, y: panel.maxY - 12 - height, width: faviconLeft - 8 - (panel.minX + 12), height: height)
    }
    required init?(coder: NSCoder) { fatalError() }

    var sliderRect: NSRect { slider.frame }

    func symbol(_ name: String, _ size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func button(_ rect: NSRect, _ name: String, glyph: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let disc = NSBezierPath(ovalIn: rect)
        NSColor.white.withAlphaComponent(0.16).setFill(); disc.fill()
        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 0.4, dy: 0.4)); rim.lineWidth = 0.75
        NSColor.white.withAlphaComponent(0.32).setStroke(); rim.stroke()
        if let image = symbol(name, glyph) {
            let size = image.size
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 0.925, respectFlipped: true, hints: nil)
        }
        context.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let body = CGPath(roundedRect: panel, cornerWidth: 16, cornerHeight: 16, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 18), blur: 46, color: NSColor.black.withAlphaComponent(0.34).cgColor)
        context.addPath(body); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        context.addPath(body); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(body); context.clip()
        NSColor.black.setFill(); panel.fill()
        if let video {
            let aspect = CGFloat(video.width) / CGFloat(video.height)
            var fit = panel
            if aspect > panel.width / panel.height { fit.size.height = panel.width / aspect; fit.origin.y = panel.midY - fit.height / 2 }
            else { fit.size.width = panel.height * aspect; fit.origin.x = panel.midX - fit.width / 2 }
            context.saveGState()
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: fit.maxY); context.scaleBy(x: 1, y: -1)
            context.draw(video, in: CGRect(x: fit.minX, y: 0, width: fit.width, height: fit.height))
            context.restoreGState()
        }
        context.restoreGState()
        guard showsChrome else { return }
        let side: CGFloat = 28
        let back = NSRect(x: panel.minX + 10, y: panel.minY + 10, width: side, height: side)
        let close = NSRect(x: panel.maxX - 10 - side, y: panel.minY + 10, width: side, height: side)
        let minimize = NSRect(x: close.minX - 6 - side, y: close.minY, width: side, height: side)
        let play = NSRect(x: panel.midX - 28, y: panel.midY - 28, width: 56, height: 56)
        let mute = NSRect(x: panel.maxX - 10 - side, y: sliderRect.minY - 8 - side, width: side, height: side)
        button(back, "arrow.up.left", glyph: side * 0.42)
        button(minimize, "minus", glyph: side * 0.42)
        button(close, "xmark", glyph: side * 0.42)
        button(play, "pause.fill", glyph: 22)
        button(mute, "speaker.wave.2.fill", glyph: side * 0.42)
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
                                                         .paragraphStyle: style]
        let natural = ceil((title as NSString).size(withAttributes: attributes).width)
        let limit = min(280, (minimize.minX - 8) - (back.maxX + 8))
        let width = min(natural, limit)
        let lineHeight = ceil(NSFont.systemFont(ofSize: 12, weight: .medium).boundingRectForFont.height)
        (title as NSString).draw(in: NSRect(x: panel.midX - width / 2, y: back.midY - lineHeight / 2 + 0.5, width: width, height: lineHeight),
                                 withAttributes: attributes)
        if let favicon {
            let icon = NSRect(x: panel.maxX - 12 - 18, y: sliderRect.midY - 9, width: 18, height: 18)
            context.saveGState()
            context.addPath(CGPath(roundedRect: icon, cornerWidth: 4, cornerHeight: 4, transform: nil)); context.clip()
            favicon.draw(in: icon, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            context.restoreGState()
        }
    }
}

@MainActor final class DeckMotion {
    var views: [NSView] = []
    var before: [ObjectIdentifier: NSRect] = [:]
    var after: [ObjectIdentifier: NSRect] = [:]
    var start = 0.0
    var active = false
    static let duration = 0.5

    static func collect(_ deck: NSView, companion: NSView?) -> [NSView] {
        BrowserScene.descendants(deck) + (companion.map { [$0] } ?? [])
    }
    func frames(_ views: [NSView]) -> [ObjectIdentifier: NSRect] {
        Dictionary(uniqueKeysWithValues: views.map { (ObjectIdentifier($0), $0.frame) })
    }
    func begin(deck: NSView, companion: NSView?, at time: Double, change: () -> Void) {
        let old = Self.collect(deck, companion: companion)
        let oldFrames = frames(old)
        change()
        views = Self.collect(deck, companion: companion)
        after = frames(views)
        before = oldFrames
        start = time
        active = true
    }
    func apply(at time: Double) -> Bool {
        guard active else { return false }
        let elapsed = time - start
        if elapsed >= Self.duration {
            for view in views { if let frame = after[ObjectIdentifier(view)] { view.frame = frame } }
            active = false
            return true
        }
        let x = CGFloat(springProgress(elapsed, response: 0.25, damping: 0.9))
        for view in views {
            let id = ObjectIdentifier(view)
            guard let end = after[id] else { continue }
            view.frame = lerp(before[id] ?? end, end, x)
        }
        for view in views { view.needsLayout = false }
        return true
    }
}

@MainActor final class MiniShot {
    let scene: BrowserScene
    let video: BrowserTab, kite: BrowserTab
    var state: BrowserState
    var selected: UUID
    var audio: [UUID: SidebarTabAudio] = [:]
    let videoPage: NSImage, kitePage: NSImage
    let page = PCNativePage()
    let media = PCNativeMediaState(identifier: "reel-golden-hour")
    var item: MiniPlayerItem!
    let deck: MiniPlayerDeck
    let pointer: StagePointer
    let pip: PiPStandIn
    let motion = DeckMotion()
    var pending: [(Double, @MainActor () -> Void)] = []
    var clock = 0.0
    var hoverInside = false
    var beats: [[String: Any]] = []
    let pipPanel: NSRect

    init(pages: String) {
        let size = NSSize(width: 1440, height: 900)
        let windowRect = NSRect(x: 80, y: 18, width: 1280, height: 840)
        let scenario = MiniScenario.make()
        scene = BrowserScene(size: size, windowRect: windowRect, scale: 2, pagePath: "", scenario: scenario)
        video = scenario.named["video"]!; kite = scenario.named["kite"]!
        state = scenario.state
        selected = video.id
        videoPage = NSImage(contentsOfFile: pages + "/video.png")!
        kitePage = NSImage(contentsOfFile: pages + "/kite.png")!
        deck = BrowserScene.descendants(scene.sidebar).compactMap { $0 as? MiniPlayerDeck }.first!
        scene.pointer.removeFromSuperview()
        let w: CGFloat = 512, h: CGFloat = 288
        let buffer = ((size.width - w) + (size.height - h)) / 2 * 0.02
        pipPanel = NSRect(x: windowRect.maxX - w - buffer, y: windowRect.maxY - h - buffer, width: w, height: h)
        pip = PiPStandIn(frame: NSRect(origin: .zero, size: size), panel: pipPanel)
        pip.appearance = NSAppearance(named: .aqua)
        pip.isHidden = true
        pip.title = media.title
        scene.stage.addSubview(pip)
        pointer = StagePointer(frame: NSRect(origin: .zero, size: size))
        scene.stage.addSubview(pointer)
        media.title = video.title
        media.sourceURL = video.url
        media.playing = true
        media.canPlayPause = true
        media.hasPreviousTrack = true
        media.hasNextTrack = true
        media.canSetVolume = true
        media.canEnterPictureInPicture = true
        media.castState = .available
        page.mediaState = media
        pip.title = media.title
        let icon = Favicons.image(for: video)
        pip.favicon = icon
        pip.video = Self.videoFrame(videoPage)
        item = MiniPlayerItem(page: page, state: media, icon: icon, host: MiniPlayerHostLease(nil), valid: { true }, reveal: {})
        deck.after = { [unowned self] delay, body in self.pending.append((self.clock + delay, body)) }
        showPage()
    }

    static func videoFrame(_ page: NSImage) -> CGImage? {
        guard let cg = page.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = CGFloat(cg.width) / page.size.width
        let crop = CGRect(x: 28 * scale, y: 74 * scale, width: 920 * scale, height: 517 * scale).integral
        guard let piece = cg.cropping(to: crop) else { return nil }
        let width = piece.width, height = piece.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return piece }
        context.draw(piece, in: CGRect(x: 0, y: 0, width: width, height: height))
        let barTop = (566 - 74) * scale, barBottom = (580 - 74) * scale
        context.setFillColor(NSColor(srgbRed: 0x24 / 255.0, green: 0x16 / 255.0, blue: 0x2C / 255.0, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: CGFloat(height) - barBottom, width: CGFloat(width), height: barBottom - barTop))
        return context.makeImage()
    }

    func pageBackground(_ image: NSImage) -> NSColor {
        guard let rep = image.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: image.tiffRepresentation!),
              let color = rep.colorAt(x: 4, y: rep.pixelsHigh - 4) else { return .white }
        return color
    }

    func showPage() {
        let image = selected == video.id ? videoPage : kitePage
        let fill = pageBackground(image)
        scene.surface.drawPage = { card in
            fill.setFill(); card.fill()
            let scale = card.width / image.size.width
            image.draw(in: NSRect(x: card.minX, y: card.minY, width: card.width, height: image.size.height * scale),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        scene.surface.needsDisplay = true
    }

    func rerender() {
        state.selectedTabIDs = [selected]
        scene.sidebar.render(state: state, focusedTabID: selected, loading: [], canBack: true, canForward: false, audio: audio)
        scene.sidebar.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        scene.sidebar.needsLayout = true
        scene.sidebar.layoutSubtreeIfNeeded()
        showPage()
    }

    func stageRect(_ view: NSView) -> NSRect { scene.stage.convert(view.bounds, from: view) }

    var deckButtons: [ActionButton] {
        BrowserScene.descendants(deck).compactMap { $0 as? ActionButton }.filter { !$0.isHiddenOrHasHiddenAncestor && $0.showsHoverFill }
    }

    func button(_ label: String) -> ActionButton? {
        BrowserScene.descendants(deck).compactMap { $0 as? ActionButton }.first { $0.accessibilityLabel() == label }
    }

    struct DeckComposite { let surface: NSRect; let fill: CGColor?; let leaves: [(NSRect, NSBitmapImageRep)] }

    func composedDeck() -> DeckComposite? {
        guard let row = BrowserScene.descendants(deck).first(where: { String(describing: type(of: $0)).contains("MiniPlayerRow") }),
              let surfaceView = row.subviews.first else { return nil }
        var leaves: [(NSRect, NSBitmapImageRep)] = []
        for leaf in surfaceView.subviews where !leaf.isHidden && leaf.alphaValue > 0.01 && leaf.bounds.width >= 1 && leaf.bounds.height >= 1 {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(leaf.bounds.width * 2)), pixelsHigh: Int(ceil(leaf.bounds.height * 2)),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = leaf.bounds.size
            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { leaf.cacheDisplay(in: leaf.bounds, to: rep) }
            leaves.append((stageRect(leaf), rep))
        }
        return DeckComposite(surface: stageRect(surfaceView), fill: surfaceView.layer?.backgroundColor, leaves: leaves)
    }

    func draw(_ composite: DeckComposite, into bitmap: NSBitmapImageRep) {
        guard let base = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        let cg = base.cgContext
        cg.saveGState()
        cg.translateBy(x: 0, y: bitmap.size.height); cg.scaleBy(x: 1, y: -1)
        let context = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let shape = CGPath(roundedRect: composite.surface, cornerWidth: 8, cornerHeight: 8, transform: nil)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 8, color: NSColor.black.withAlphaComponent(0.08).cgColor)
        cg.addPath(shape); cg.setFillColor(composite.fill ?? NSColor.white.cgColor); cg.fillPath()
        cg.restoreGState()
        cg.saveGState()
        cg.addPath(shape); cg.clip()
        for (rect, rep) in composite.leaves {
            rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        cg.restoreGState()
        if let location = pointer.location {
            let cursor = NSCursor.arrow, image = cursor.image, hot = cursor.hotSpot
            image.draw(in: NSRect(x: location.x - hot.x, y: location.y - hot.y, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        cg.restoreGState()
        cg.flush()
    }

    func beat(_ t: Double, _ text: String) {
        beats.append(["t": (t * 1000).rounded() / 1000, "frame": Int((t * 60).rounded()), "beat": text])
        print(String(format: "%.3f", t), text)
    }

    func run(out: String) {
        let fps = 60.0
        let duration = 5.6
        let frames = Int(duration * fps)
        let kiteRow = scene.row(titled: kite.title)!
        let kiteRect = stageRect(kiteRow)
        let restDeck = NSRect(x: scene.windowRect.minX + 8, y: scene.windowRect.minY + 840 - 50 - 33, width: 212, height: 33)
        let pipButton = NSPoint(x: restDeck.minX + 158 + 11.5, y: restDeck.maxY - 66 + 4 + 12)
        let enterPoint = NSPoint(x: restDeck.minX + 96, y: restDeck.midY + 3)
        let pipRest = NSPoint(x: pipPanel.minX + 150, y: pipPanel.minY + 206)
        let path = PointerPath(keys: [
            (0.00, NSPoint(x: 790, y: 380)), (0.30, NSPoint(x: 712, y: 318)),
            (0.55, NSPoint(x: 712, y: 318)), (1.12, NSPoint(x: kiteRect.minX + 70, y: kiteRect.midY + 2)),
            (1.32, NSPoint(x: kiteRect.minX + 70, y: kiteRect.midY + 2)), (1.86, enterPoint),
            (2.10, enterPoint), (2.58, pipButton),
            (3.02, pipButton), (3.78, pipRest), (duration, pipRest)])
        print("kite row", kiteRect, "rest deck", restDeck, "pip", pipPanel)
        let writer = try! VideoWriter(path: out + "/mini.mov", width: 2880, height: 1800, fps: 60, alpha: true, bitRate: 70_000_000)
        var keyframes: [(Double, NSBitmapImageRep)] = []
        let keyTimes: Set<Int> = [0, 30, 60, 90, 106, 109, 115, 156, 178, 210, 270, 314, 317, 335]
        var played = false, switched = false, pressed = false, released = false, entered = false
        var pressTarget: ActionButton?
        for frame in 0..<frames {
            let t = Double(frame) / fps
            clock = t
            if !played && t >= 0.35 {
                played = true
                audio = [video.id: SidebarTabAudio(lease: NSObject(), audible: true, muted: false)]
                rerender()
                scene.sidebar.updateMiniPlayers([item])
                scene.sidebar.layoutSubtreeIfNeeded()
                beat(t, "click on the video: playback starts, speaker glyph on the tab row, Mini Player deck pops in (instant, real)")
                print("deck after pop-in", stageRect(deck))
            }
            if !switched && t >= 1.20 {
                switched = true
                selected = kite.id
                rerender()
                beat(t, "click the kite tab: page swaps to kite.png, deck stays")
            }
            for (index, entry) in pending.enumerated().reversed() where t >= entry.0 {
                pending.remove(at: index)
                motion.begin(deck: deck, companion: deck.motionCompanion?(), at: t) {
                    entry.1()
                    scene.sidebar.layoutSubtreeIfNeeded()
                }
                beat(t, "hover-off delay (2.0 s) elapsed: deck collapses 66 to 33 on the 0.25/0.9 spring")
            }
            let point = path.at(t)
            pointer.location = point
            let deckRect = stageRect(deck)
            let inside = !deck.isHidden && deckRect.contains(point)
            if inside != hoverInside {
                hoverInside = inside
                if inside {
                    motion.begin(deck: deck, companion: deck.motionCompanion?(), at: t) {
                        deck.updateHover(true)
                        scene.sidebar.layoutSubtreeIfNeeded()
                    }
                    if !entered { entered = true; beat(t, "pointer enters the deck: updateHover(true), spring 33 to 66, title row appears") }
                    print("deck expanded", stageRect(deck), "pip button", button("Open Picture in Picture").map(stageRect) ?? .zero)
                } else {
                    deck.updateHover(false)
                    beat(t, "pointer leaves the deck: 2.0 s hover-off delay starts")
                }
            }
            let animating = motion.apply(at: t)
            scene.skipLayout = motion.active
            if !animating { scene.sidebar.layoutSubtreeIfNeeded() }
            let hovered = inside ? deckButtons.first { stageRect($0).contains(point) } : nil
            if !pressed && t >= 2.74, let target = button("Open Picture in Picture"), stageRect(target).contains(point) {
                pressed = true; pressTarget = target
                beat(t, "press Open Picture in Picture (pressed plate, 120 ms)")
            }
            let pressing = pressed && !released && t < 2.86
            if pressed && !released && t >= 2.86 {
                released = true
                pip.isHidden = false
                beat(t, "release: PiP panel appears bottom-right, instant (stand-in drawn from VideoPiPWindow.m numbers)")
            }
            for candidate in BrowserScene.descendants(deck).compactMap({ $0 as? ActionButton }) where candidate.showsHoverFill {
                let isTarget = candidate === hovered
                if pressing && candidate === pressTarget {
                    if candidate.showsSelectedFill { candidate.showsSelectedFill = false }
                    if !candidate.isHighlighted { candidate.highlight(true) }
                } else {
                    if candidate.isHighlighted { candidate.highlight(false) }
                    if candidate.showsSelectedFill != isTarget { candidate.showsSelectedFill = isTarget }
                }
            }
            let overPiP = !pip.isHidden && pipPanel.contains(point)
            if overPiP != pip.showsChrome {
                pip.showsChrome = overPiP
                if overPiP { beat(t, "pointer enters PiP: its chrome appears instantly") }
            }
            if released { pip.progress = 0.38 + (t - 2.86) * 0.0016 }
            let springing = motion.active
            let composite = springing ? composedDeck() : nil
            if springing { deck.isHidden = true; pointer.isHidden = true }
            let bitmap = scene.render(NSRect(origin: .zero, size: NSSize(width: 1440, height: 900)), pixelsWide: 2880, pixelsHigh: 1800)
            if springing {
                deck.isHidden = false; pointer.isHidden = false
                if let composite { draw(composite, into: bitmap) }
            }
            writer.append(bitmap.cgImage!, background: NSColor.clear.cgColor)
            if keyTimes.contains(frame) {
                keyframes.append((t, bitmap))
                Render.writePNG(bitmap, out + String(format: "/mini-frame-%03d.png", frame))
            }
            Render.requireNoWindows("during mini frame \(frame)")
        }
        let result = writer.finish()
        print("wrote mini.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        Strip.write(keyframes, thumb: NSSize(width: 480, height: 300), columns: 5, path: out + "/mini-strip.png")
        let info: [String: Any] = ["file": "mini.mov", "fps": 60, "frames": frames, "duration": duration, "size": [2880, 1800],
                                   "codec": "hevcWithAlpha", "beats": beats]
        let data = try! JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: out + "/mini-beats.json"))
    }
}

@MainActor enum Strip {
    static func write(_ frames: [(Double, NSBitmapImageRep)], thumb: NSSize, columns: Int, path: String) {
        let rows = (frames.count + columns - 1) / columns
        let label: CGFloat = 18
        let size = NSSize(width: thumb.width * CGFloat(columns), height: (thumb.height + label) * CGFloat(rows))
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor(white: 0.55, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
            for (index, entry) in frames.enumerated() {
                let x = CGFloat(index % columns) * thumb.width, y = CGFloat(index / columns) * (thumb.height + label)
                let cell = NSRect(x: x, y: y + label, width: thumb.width, height: thumb.height)
                for i in 0..<Int(thumb.width / 12) {
                    for j in 0..<Int(thumb.height / 12) where (i + j) % 2 == 0 {
                        NSColor(white: 0.62, alpha: 1).setFill()
                        NSRect(x: cell.minX + CGFloat(i) * 12, y: cell.minY + CGFloat(j) * 12, width: 12, height: 12).fill()
                    }
                }
                entry.1.draw(in: cell, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                (String(format: "%.2f s", entry.0) as NSString).draw(at: NSPoint(x: x + 6, y: y + 2), withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
            }
            return true
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        Render.writePNG(bitmap, path)
    }
}
