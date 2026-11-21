import AppKit
@testable import Parc

enum Ease {
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        func curve(_ a: Double, _ b: Double, _ s: Double) -> Double { 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s }
        var low = 0.0, high = 1.0, s = t
        for _ in 0..<60 {
            s = (low + high) / 2
            if curve(x1, x2, s) < t { low = s } else { high = s }
        }
        return curve(y1, y2, s)
    }
    static func easeOut(_ t: Double) -> Double { bezier(0, 0, 0.58, 1, t) }
    static func easeInOut(_ t: Double) -> Double { bezier(0.42, 0, 0.58, 1, t) }
    static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
    static func hermite(_ s: Double, _ p0: Double, _ p1: Double, _ m0: Double, _ m1: Double) -> Double {
        let s2 = s * s, s3 = s2 * s
        return (2 * s3 - 3 * s2 + 1) * p0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * p1 + (s3 - s2) * m1
    }
}

func drawUpright(_ image: CGImage, in rect: CGRect, _ context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    context.restoreGState()
}

func loadCGImage(_ path: String) -> CGImage {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let rep = NSBitmapImageRep(data: data),
          let image = rep.cgImage else { fatalError("cannot read \(path)") }
    return image
}

@MainActor final class LinkedPageView: NSView {
    let image: CGImage
    var scroll: CGFloat = 0 { didSet { if scroll != oldValue { needsDisplay = true } } }
    static let header: CGFloat = 72
    static let headerPiece: CGFloat = 300

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        hex(0xFFFDF8).setFill(); bounds.fill()
        let width = bounds.width, source = CGFloat(image.width)
        let crop = ((source - width) / 2).rounded(.down)
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: -scroll)
        hex(0x1F4D36).setFill(); NSRect(x: 0, y: 0, width: width, height: Self.header).fill()
        let piece = Self.headerPiece
        if let left = image.cropping(to: CGRect(x: 0, y: 0, width: piece, height: Self.header)) {
            drawUpright(left, in: CGRect(x: 0, y: 0, width: piece, height: Self.header), context)
        }
        if let right = image.cropping(to: CGRect(x: source - piece, y: 0, width: piece, height: Self.header)) {
            drawUpright(right, in: CGRect(x: width - piece, y: 0, width: piece, height: Self.header), context)
        }
        let rest = CGFloat(image.height) - Self.header
        if let body = image.cropping(to: CGRect(x: crop, y: Self.header, width: width, height: rest)) {
            drawUpright(body, in: CGRect(x: 0, y: Self.header, width: width, height: rest), context)
        }
        context.restoreGState()
    }
}

struct PeekBeat { let name: String; let time: Double }

@MainActor final class PeekFilm {
    let scene: BrowserScene
    let host: PeekHostView
    let linked: LinkedPageView
    let article: CGImage
    let layout: PeekWindowLayout
    let fps = 60
    let duration = 10.0
    let articleScroll: CGFloat = 860
    let link = NSRect(x: 570, y: 564, width: 32, height: 24)
    let linkURL = "https://openair.example/guides/fly-a-kite"
    var motion: PeekDismissalMotion
    var phase = 0

    let start = NSPoint(x: 905, y: 372)
    let target = NSPoint(x: 589, y: 579)
    let rest = NSPoint(x: 1118, y: 330)
    let idle = NSPoint(x: 1113, y: 351)

    static let swipeA = (start: 4.80, peak: 5.30, back: 5.40, release: 5.65, top: 0.56, end: 0.38, velocity: -0.4)
    static let swipeB = (start: 6.60, release: 7.05, end: 0.62, velocity: 2.6)
    static let entry = 1.60
    static let scrollStart = 2.40
    static let scrollDistance: CGFloat = 160

    init(scene: BrowserScene, articlePath: String, linkedPath: String) {
        self.scene = scene
        article = loadCGImage(articlePath)
        let page = scene.surface.pageCard
        scene.surface.drawPage = { [article, articleScroll] card in
            NSColor.white.setFill(); card.fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let crop = ((CGFloat(article.width) - card.width) / 2).rounded(.down)
            if let piece = article.cropping(to: CGRect(x: crop, y: articleScroll, width: card.width, height: card.height)) {
                drawUpright(piece, in: card, context)
            }
        }
        let bounds = NSRect(origin: .zero, size: scene.windowRect.size)
        layout = PeekWindowLayout(bounds: bounds, page: page, stepsBack: true)
        host = PeekHostView(frame: bounds)
        host.appearance = NSAppearance(named: .aqua)
        host.palette = scene.themeSurface.palette
        host.pageFrame = page
        host.stepsBack = true
        host.canExpand = true
        host.canSplit = true
        host.subviews[0].isHidden = true
        host.layoutSubtreeIfNeeded()
        linked = LinkedPageView(frame: host.content.bounds, image: loadCGImage(linkedPath))
        linked.autoresizingMask = [.width, .height]
        host.content.addSubview(linked)
        host.layoutSubtreeIfNeeded()
        for button in BrowserScene.descendants(host).compactMap({ $0 as? PeekControlButton }) { button.viewDidMoveToWindow() }
        linked.frame = host.content.bounds
        motion = PeekDismissalMotion(geometry: PeekDismissalMotion.Geometry(paneWidth: bounds.width, cardMinX: layout.card.minX))
    }

    func report() -> [String] {
        let card = host.cardFrame
        return ["peek card \(card) content \(host.content.frame) linked \(linked.frame)",
                "step scale \(layout.scale) stepped \(layout.steppedPage())",
                "exit distance \(motion.geometry.exitDistance) pane \(motion.geometry.paneWidth)",
                "host subviews \(host.subviews.map { "\(type(of: $0)) hidden=\($0.isHidden)" })"]
    }

    static func fingerA(_ t: Double) -> Double {
        let a = swipeA
        if t <= a.start { return 0 }
        if t < a.peak { return Ease.hermite((t - a.start) / (a.peak - a.start), 0, a.top, 0, 0) }
        if t < a.back { return a.top }
        let span = a.release - a.back
        return Ease.hermite(Ease.unit((t - a.back) / span), a.top, a.end, 0, a.velocity * span)
    }

    static func fingerB(_ t: Double) -> Double {
        let b = swipeB, span = b.release - b.start
        return Ease.hermite(Ease.unit((t - b.start) / span), 0, b.end, 0, b.velocity * span)
    }

    static func scroll(_ t: Double) -> CGFloat {
        let u = t - scrollStart
        guard u > 0 else { return 0 }
        let drag = 0.35, tau = 0.33
        let total = drag / 2 + tau
        let speed = Double(scrollDistance) / total
        if u < drag { return CGFloat(speed * (u / 2 - drag / (2 * Double.pi) * sin(Double.pi * u / drag))) }
        let travelled = speed * drag / 2 + speed * tau * (1 - exp(-(u - drag) / tau))
        return CGFloat(travelled)
    }

    func swipeFrame(_ t: Double) -> PeekDismissalFrame {
        let a = Self.swipeA, b = Self.swipeB
        if t >= a.start && phase == 0 { motion.begin(reducesMotion: false); phase = 1 }
        if phase == 1 {
            if t < a.release { motion.follow(Self.fingerA(t)); return motion.frame(at: t) }
            motion.follow(Self.fingerA(a.release))
            motion.springBack(velocity: a.velocity, at: a.release)
            phase = 2
        }
        if t >= b.start && phase == 2 { motion.begin(reducesMotion: false); phase = 3 }
        if phase == 3 {
            if t < b.release { motion.follow(Self.fingerB(t)); return motion.frame(at: t) }
            motion.follow(Self.fingerB(b.release))
            motion.exit(.slide, velocity: b.velocity, reducesMotion: false, at: b.release)
            phase = 4
        }
        return motion.frame(at: t)
    }

    struct State {
        var pointer: NSPoint
        var cursor: NSCursor
        var capsule: CGFloat
        var opacity: CGFloat
        var swipe: PeekDismissalFrame
        var step: CGFloat
        var scroll: CGFloat
        var present: Bool
    }

    func pointer(_ t: Double) -> NSPoint {
        func lerp(_ a: NSPoint, _ b: NSPoint, _ control: NSPoint, _ s: Double) -> NSPoint {
            let s = CGFloat(s), r = 1 - s
            return NSPoint(x: r * r * a.x + 2 * r * s * control.x + s * s * b.x, y: r * r * a.y + 2 * r * s * control.y + s * s * b.y)
        }
        if t < 0.15 { return start }
        if t < 0.95 { return lerp(start, target, NSPoint(x: 700, y: 420), Ease.easeInOut((t - 0.15) / 0.8)) }
        if t < 1.90 { return target }
        if t < 2.40 { return lerp(target, rest, NSPoint(x: 940, y: 560), Ease.easeInOut((t - 1.90) / 0.5)) }
        if t < 8.40 { return rest }
        if t < 9.30 { return lerp(rest, idle, NSPoint(x: 1121, y: 342), Ease.easeInOut((t - 8.40) / 0.9)) }
        return idle
    }

    func state(_ t: Double) -> State {
        let point = pointer(t)
        let hand = t < Self.entry && link.insetBy(dx: -1, dy: -1).contains(point)
        var capsule: CGFloat = 0
        if t >= 1.0 && t < 1.5 { capsule = CGFloat(Ease.unit((t - 1.0) / 0.15)) }
        let opening = t >= Self.entry ? Ease.easeOut((t - Self.entry) / PeekStepBack.openDuration) : 0
        let swipe = swipeFrame(t)
        let closed = t >= Self.swipeB.release + PeekDismissalTiming.slide
        let present = t >= Self.entry && !closed
        let step = present ? CGFloat(opening * swipe.wash) : 0
        return State(pointer: point, cursor: hand ? .pointingHand : .arrow, capsule: capsule, opacity: CGFloat(opening),
                     swipe: swipe, step: step, scroll: Self.scroll(t), present: present)
    }

    var beats: [PeekBeat] {
        let a = Self.swipeA, b = Self.swipeB
        func crossing(_ finger: (Double) -> Double, from: Double, to: Double, value: Double) -> Double {
            var low = from, high = to
            for _ in 0..<50 { let mid = (low + high) / 2; if finger(mid) < value { low = mid } else { high = mid } }
            return (high * 1000).rounded() / 1000
        }
        let disarm: Double = {
            var low = a.back, high = a.release
            for _ in 0..<50 { let mid = (low + high) / 2; if Self.fingerA(mid) > 0.45 { low = mid } else { high = mid } }
            return (high * 1000).rounded() / 1000
        }()
        var probe = PeekDismissalMotion(geometry: motion.geometry)
        probe.begin(reducesMotion: false); probe.follow(Self.fingerA(a.release))
        probe.springBack(velocity: a.velocity, at: a.release)
        var settled = a.release
        while probe.isAnimating(at: settled) && settled < a.release + 2 { settled += 1.0 / 600 }
        return [
            PeekBeat(name: "pointer_glide_start", time: 0.15),
            PeekBeat(name: "pointer_on_kite_link", time: 0.95),
            PeekBeat(name: "shift_down_capsule_in", time: 1.0),
            PeekBeat(name: "shift_click", time: 1.5),
            PeekBeat(name: "peek_entry_start", time: Self.entry),
            PeekBeat(name: "peek_entry_end_stepped_back", time: Self.entry + PeekStepBack.openDuration),
            PeekBeat(name: "pointer_drift_into_card", time: 1.9),
            PeekBeat(name: "peek_scroll_start", time: Self.scrollStart),
            PeekBeat(name: "peek_scroll_settled", time: 3.9),
            PeekBeat(name: "swipe1_start", time: a.start),
            PeekBeat(name: "swipe1_point_of_no_return_armed", time: crossing(Self.fingerA, from: a.start, to: a.peak, value: 0.5)),
            PeekBeat(name: "swipe1_hesitate", time: a.peak),
            PeekBeat(name: "swipe1_disarmed", time: disarm),
            PeekBeat(name: "swipe1_release_chicken_out_spring", time: a.release),
            PeekBeat(name: "swipe1_spring_settled", time: (settled * 1000).rounded() / 1000),
            PeekBeat(name: "swipe2_start", time: b.start),
            PeekBeat(name: "swipe2_point_of_no_return_armed", time: crossing(Self.fingerB, from: b.start, to: b.release, value: 0.5)),
            PeekBeat(name: "swipe2_release_fling", time: b.release),
            PeekBeat(name: "peek_removed_page_full_scale", time: b.release + PeekDismissalTiming.slide),
            PeekBeat(name: "pointer_idle", time: 8.4),
            PeekBeat(name: "end", time: duration),
        ]
    }

    private var baseKey: (CGFloat, CGFloat)?
    private var baseImage: CGImage?
    private var peekKey: CGFloat?
    private var peekImage: CGImage?

    func base(scale: CGFloat, wash: CGFloat) -> CGImage {
        if let baseKey, let baseImage, baseKey == (scale, wash) { return baseImage }
        scene.surface.pageScale = scale
        scene.surface.washAlpha = wash
        scene.edge.isHidden = true
        scene.pointer.isHidden = true
        let size = scene.stage.bounds.size
        let image = scene.render(NSRect(origin: .zero, size: size), pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2)).cgImage!
        baseKey = (scale, wash); baseImage = image
        return image
    }

    func peek(scroll: CGFloat) -> CGImage {
        if let peekKey, let peekImage, peekKey == scroll { return peekImage }
        linked.scroll = scroll
        host.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = host.bounds.size
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        let image = bitmap.cgImage!
        peekKey = scroll; peekImage = image
        return image
    }

    func drawCapsule(_ alpha: CGFloat, in window: NSRect, step: CGFloat) {
        guard alpha > 0 else { return }
        let card = scene.surface.pageCard.offsetBy(dx: window.minX, dy: window.minY)
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let secondary = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.7), tertiary = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3)
        let sentence = "Open \(linkURL) in Peek"
        let text = NSMutableAttributedString(string: sentence, attributes: [.font: font, .foregroundColor: secondary])
        text.addAttribute(.foregroundColor, value: tertiary, range: (sentence as NSString).range(of: linkURL))
        let size = text.size()
        let width = min(400, ceil(9 + size.width + 9)), height: CGFloat = 24
        let pill = NSRect(x: card.minX + 10, y: card.maxY - height - 10, width: width, height: height)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let shape = NSBezierPath(roundedRect: pill, xRadius: height / 2, yRadius: height / 2)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 10, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        scene.themeSurface.palette.background.setFill(); shape.fill()
        context.restoreGState()
        scene.themeSurface.palette.background.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let border = NSBezierPath(roundedRect: pill, xRadius: height / 2, yRadius: height / 2)
        border.lineWidth = 2
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.1).setStroke(); border.stroke()
        NSGraphicsContext.restoreGraphicsState()
        text.draw(at: NSPoint(x: pill.minX + 9, y: pill.midY - size.height / 2))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    func drawPointer(_ location: NSPoint, cursor: NSCursor) {
        let image = cursor.image, hot = cursor.hotSpot
        image.draw(in: NSRect(x: location.x - hot.x, y: location.y - hot.y, width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    func compose(_ t: Double, into context: CGContext) -> State {
        let s = state(t)
        let window = scene.windowRect
        let stageSize = scene.stage.bounds.size
        let scale = layout.scale(progress: s.step)
        let wash = s.present ? PeekCardAppearance.backdropOpacity * CGFloat(s.swipe.wash) * s.opacity : 0
        let base = base(scale: scale, wash: wash)
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(context.height)); context.scaleBy(x: CGFloat(context.width) / stageSize.width, y: -CGFloat(context.height) / stageSize.height)
        drawCapsule(s.capsule, in: window, step: s.step)
        let alpha = s.opacity * CGFloat(s.swipe.card)
        if s.present && alpha > 0 {
            let image = peek(scroll: s.scroll)
            context.saveGState()
            context.addPath(CGPath(roundedRect: window, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius, transform: nil))
            context.clip()
            context.setAlpha(alpha)
            drawUpright(image, in: window.offsetBy(dx: s.swipe.offset, dy: 0), context)
            context.restoreGState()
        }
        context.saveGState()
        context.translateBy(x: window.minX, y: window.minY)
        scene.edge.draw(scene.edge.bounds)
        context.restoreGState()
        drawPointer(NSPoint(x: s.pointer.x + window.minX, y: s.pointer.y + window.minY), cursor: s.cursor)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        fadeMargins(context, window: window, stage: stageSize)
        return s
    }

    func fadeMargins(_ context: CGContext, window: NSRect, stage: NSSize) {
        let height = CGFloat(context.height), scale = height / stage.height
        let bottom = (stage.height - window.maxY) * scale, top = window.minY * scale
        var locations: [CGFloat] = [], alphas: [CGFloat] = []
        for index in 0...8 {
            let u = CGFloat(index) / 8, eased = u * u * (3 - 2 * u)
            locations.append(u * bottom / height); alphas.append(eased)
        }
        for index in 0...8 {
            let u = CGFloat(index) / 8, eased = 1 - u * u * (3 - 2 * u)
            locations.append((height - top + u * top) / height); alphas.append(eased)
        }
        let colors = alphas.map { CGColor(gray: 0, alpha: $0) } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: locations) else { return }
        context.saveGState()
        context.setBlendMode(.destinationIn)
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        context.restoreGState()
    }

    static func offscreenContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }

    static func onGrey(_ image: CGImage) -> CGImage {
        let context = offscreenContext(width: image.width, height: image.height)
        context.setFillColor(hex(0x8E939B).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()!
    }

    static func writePNG(_ image: CGImage, _ path: String) {
        Render.writePNG(NSBitmapImageRep(cgImage: image), path)
    }

    func still(_ t: Double, path: String) {
        resetMotion()
        var time = 0.0
        while time < t { _ = state(time); time += 1.0 / Double(fps) }
        let context = Self.offscreenContext(width: 2880, height: 1800)
        _ = compose(t, into: context)
        Self.writePNG(Self.onGrey(context.makeImage()!), path)
    }

    func resetMotion() {
        motion = PeekDismissalMotion(geometry: motion.geometry)
        phase = 0
    }

    var quality = 1.0

    func film(out: String, keyTimes: [(String, Double)], stripTimes: [Double]) {
        resetMotion()
        let writer = try! AlphaMovieWriter(path: out + "/peek.mov", width: 2880, height: 1800, fps: Int32(fps), quality: quality)
        let frames = Int(duration * Double(fps))
        let keyFrames = Dictionary(uniqueKeysWithValues: keyTimes.map { (Int(($0.1 * Double(fps)).rounded()), $0.0) })
        let stripFrames = Set(stripTimes.map { Int(($0 * Double(fps)).rounded()) })
        var strip: [(Double, CGImage)] = []
        var log: [String] = []
        let began = Date()
        for frame in 0..<frames {
            let t = Double(frame) / Double(fps)
            var captured: CGImage?
            var state: State?
            writer.append { context in
                state = compose(t, into: context)
                if keyFrames[frame] != nil || stripFrames.contains(frame) { captured = context.makeImage() }
            }
            if let state, frame % 6 == 0 || keyFrames[frame] != nil {
                log.append(String(format: "t=%.3f offset=%.1f card=%.3f wash=%.3f step=%.3f scale=%.5f opacity=%.3f scroll=%.1f present=%@",
                                  t, state.swipe.offset, state.swipe.card, state.swipe.wash, state.step, layout.scale(progress: state.step),
                                  state.opacity, state.scroll, state.present ? "yes" : "no"))
            }
            if let captured {
                if let name = keyFrames[frame] { Self.writePNG(Self.onGrey(captured), out + "/key-\(name).png") }
                if stripFrames.contains(frame) { strip.append((t, captured)) }
            }
            if frame % 60 == 0 { print("frame", frame, String(format: "%.1fs elapsed", Date().timeIntervalSince(began))) }
        }
        let result = writer.finish()
        print("wrote", out + "/peek.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        try? log.joined(separator: "\n").write(toFile: out + "/peek-motion.txt", atomically: true, encoding: .utf8)
        writeStrip(strip, path: out + "/peek-strip.png")
        writeBeats(out + "/peek-beats.json")
    }

    func writeStrip(_ frames: [(Double, CGImage)], path: String) {
        let columns = 6, thumbWidth = 480, thumbHeight = 300, label = 22, gap = 8
        let rows = (frames.count + columns - 1) / columns
        let width = columns * thumbWidth + (columns + 1) * gap, height = rows * (thumbHeight + label) + (rows + 1) * gap
        let context = Self.offscreenContext(width: width, height: height)
        context.setFillColor(hex(0x8E939B).cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        for (index, (time, image)) in frames.enumerated() {
            let x = gap + (index % columns) * (thumbWidth + gap), y = gap + (index / columns) * (thumbHeight + label + gap)
            drawUpright(image, in: CGRect(x: x, y: y + label, width: thumbWidth, height: thumbHeight), context)
            NSAttributedString(string: String(format: "%.2f s", time), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                                                                                    .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: x + 4, y: y + 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        Self.writePNG(context.makeImage()!, path)
    }

    func writeBeats(_ path: String) {
        let body = beats.map { "  \"\($0.name)\": \(String(format: "%.3f", $0.time))" }.joined(separator: ",\n")
        try? ("{\n" + body + "\n}\n").write(toFile: path, atomically: true, encoding: .utf8)
        print("wrote", path)
    }
}
