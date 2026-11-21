import AppKit
import Metal
import SceneKit
@testable import Parc
import ParcCore

@MainActor final class SilentCrankOutput: WindowFrameCrankSoundOutput {
    func warm() {}
    func play(_ cue: WindowFrameCrankCue) {}
    func stop() {}
}

@MainActor final class CrankOverlay: NSView {
    var image: CGImage?
    var square = NSRect.zero
    var opacity: CGFloat = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let image, opacity > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius, transform: nil))
        context.clip()
        context.setAlpha(opacity)
        context.interpolationQuality = .high
        context.translateBy(x: square.minX, y: square.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: square.size))
        context.restoreGState()
    }
}

struct CrankPageArt {
    let image: NSImage
    let pixels: NSBitmapImageRep
    let scale: CGFloat
    let edge: NSImage

    init?(path: String, restingWidth: CGFloat) {
        guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data) else { return nil }
        pixels = rep
        let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        image = NSImage(size: size)
        image.addRepresentation(rep)
        scale = restingWidth / size.width
        edge = NSImage(size: NSSize(width: 1, height: size.height), flipped: false) { rect in
            rep.draw(in: NSRect(x: -size.width + 1, y: 0, width: size.width, height: size.height))
            return true
        }
    }

    func draw(in card: NSRect) {
        NSColor.white.setFill(); card.fill()
        let width = CGFloat(pixels.pixelsWide) * scale, height = CGFloat(pixels.pixelsHigh) * scale
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high.rawValue]
        image.draw(in: NSRect(x: card.minX, y: card.minY, width: width, height: height), from: .zero, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: hints)
        if card.width > width {
            edge.draw(in: NSRect(x: card.minX + width - 0.5, y: card.minY, width: card.width - width + 1, height: height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: hints)
        }
    }
}

struct HandGesture {
    let start: Double
    let duration: Double
    let from: Double
    let to: Double
    let release: Double

    static let notchDepth = 0.55

    func raw(at time: Double) -> Double {
        let p = min(1, max(0, (time - start) / duration))
        let eased = 0.5 - 0.5 * cos(Double.pi * p)
        let u = from + (to - from) * eased
        let range = Double(WindowFrameThickness.range.lowerBound)...Double(WindowFrameThickness.range.upperBound)
        guard range.contains(u) else { return u }
        return u - Self.notchDepth / (2 * .pi) * sin(2 * .pi * u)
    }
}

@MainActor final class CrankFilm {
    static let fps = 60.0
    static let presentAt = 0.45
    static let gestures = [
        HandGesture(start: 1.08, duration: 1.15, from: 10, to: 13.62, release: 2.58),
        HandGesture(start: 3.12, duration: 2.25, from: 13, to: 2.42, release: 5.72),
        HandGesture(start: 6.26, duration: 1.40, from: 3, to: 10.2, release: 7.78),
    ]
    static let dismissAt = 8.36
    static let duration = 9.0

    let scene: BrowserScene
    let crank: WindowFrameCrankView
    let renderer: SCNRenderer
    let overlay = CrankOverlay()
    let preferences = WindowFramePreferences(defaults: UserDefaults(suiteName: "film.crank.preview") ?? .standard)
    let page: CrankPageArt?
    let crankFrame: NSRect
    let local: NSRect
    let sidebarWidth: CGFloat
    var clock = 0.0
    var shudderStart: Double?
    var log: [[String: Any]] = []
    var released = Set<Int>()
    var presented = false
    var dismissed = false

    init(scene: BrowserScene, pagePath: String) {
        self.scene = scene
        local = NSRect(origin: .zero, size: scene.windowRect.size)
        sidebarWidth = CGFloat(scene.scenario.state.settings.sidebarWidth)
        let resting = SidebarChromeFrames(bounds: local, sidebarWidth: sidebarWidth, presentation: .locked, placement: .locked,
                                          thickness: CGFloat(WindowFrameThickness.standard))
        page = CrankPageArt(path: pagePath, restingWidth: resting.pageHost.width)
        let hub = WindowFrameCrankPlacement.hub(in: local, dockedSidebarEdge: resting.sidebar.maxX)
        let flippedY = local.maxY - (hub.y - local.minY)
        let side = WindowFrameCrankView.side
        func half(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        crankFrame = NSRect(x: half(hub.x - side / 2), y: half(flippedY - side / 2), width: side, height: side)
        let palette = Self.palette(theme: scene.scenario.work.theme, dark: scene.themeSurface.palette.isDark)
        let feedback = WindowFrameCrankFeedback(allowsSound: { false }, haptic: { _ in }, output: { SilentCrankOutput() }, now: { 0 })
        crank = WindowFrameCrankView(value: WindowFrameThickness.standard, palette: palette, feedback: feedback, reducesMotion: { false })
        renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = crank.model.scene
        renderer.pointOfView = crank.model.camera
        renderer.autoenablesDefaultLighting = false
        if let page { scene.surface.drawPage = { page.draw(in: $0) } }
        overlay.frame = local
        scene.surface.addSubview(overlay)
        crank.onPreview = { [unowned self] value in
            self.preferences.setPreview(value)
            self.applyThickness()
        }
        crank.onEvent = { [unowned self] event in
            switch event {
            case .notch(let point): self.note("notch", ["value": point])
            case .end(let end):
                self.shudderStart = self.clock
                self.note("end", ["end": end == .thick ? "thick" : "thin"])
            }
        }
        crank.onFinish = { [unowned self] commit, value in
            self.preferences.setPreview(nil)
            self.applyThickness()
            self.note("finish", ["commit": commit, "value": value])
        }
        applyThickness()
        print("crank frame", crankFrame, "hub", hub, "palette", palette)
    }

    static func palette(theme: SpaceTheme, dark: Bool) -> WindowFrameCrankPalette {
        guard let primary = theme.primaryColor, theme.isValid else {
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return WindowFrameCrankPalette(accent: accent, deep: accent.blended(withFraction: 0.35, of: .black) ?? accent,
                                           cap: NSColor(white: dark ? 0.32 : 0.78, alpha: 1), dark: dark)
        }
        let base: NSColor = primary.colorSpace == .displayP3
            ? NSColor(displayP3Red: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
            : NSColor(srgbRed: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
        let rgb = base.usingColorSpace(.sRGB) ?? base
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let accent = NSColor(hue: hue, saturation: max(0.55, saturation), brightness: dark ? 0.92 : 0.78, alpha: 1)
        let deep = NSColor(hue: hue, saturation: max(0.4, saturation * 0.9), brightness: dark ? 0.55 : 0.62, alpha: 1)
        let cap = NSColor(hue: hue, saturation: min(0.6, max(0.25, saturation)), brightness: dark ? 0.5 : max(0.7, brightness), alpha: 1)
        return WindowFrameCrankPalette(accent: accent, deep: deep, cap: cap, dark: dark)
    }

    func note(_ kind: String, _ extra: [String: Any] = [:]) {
        var entry: [String: Any] = ["t": (clock * 1000).rounded() / 1000, "frame": Int((clock * Self.fps).rounded()), "kind": kind]
        for (key, value) in extra { entry[key] = value }
        log.append(entry)
    }

    func applyThickness() {
        let thickness = preferences.thickness
        let frames = SidebarChromeFrames(bounds: local, sidebarWidth: sidebarWidth, presentation: .locked, placement: .locked,
                                         thickness: thickness)
        PageCard.follow(thickness: thickness)
        scene.surface.pageCard = frames.pageHost
        scene.surface.cardRadius = PageCard.cornerRadius
        scene.surface.needsDisplay = true
    }

    func shudderOffset() -> CGFloat {
        guard let start = shudderStart else { return 0 }
        let p = (clock - start) / OnboardingWindowFrameLayout.shudderDuration
        guard p >= 0, p < 1 else { return 0 }
        let keys = OnboardingWindowFrameLayout.shudderKeyTimes.map(\.doubleValue)
        let values = OnboardingWindowFrameLayout.shudderValues
        for index in 1..<keys.count where p <= keys[index] {
            let f = CGFloat((p - keys[index - 1]) / (keys[index] - keys[index - 1]))
            return values[index - 1] + (values[index] - values[index - 1]) * f
        }
        return 0
    }

    var crankVisible: Bool {
        switch crank.phase {
        case .presenting, .shown, .dismissing: return true
        case .idle, .finished: return false
        }
    }

    func step(frame: Int) {
        let dt = 1 / Self.fps
        clock = Double(frame) / Self.fps
        if presented, crank.phase != .finished { crank.advance(by: dt) }
        if !presented, clock >= Self.presentAt - 1e-9 {
            presented = true
            crank.present(takingFocus: false)
            note("present")
        }
        for (index, gesture) in Self.gestures.enumerated() where !released.contains(index) {
            guard clock >= gesture.start - 1e-9 else { continue }
            if clock >= gesture.release - 1e-9 {
                released.insert(index)
                crank.releaseTurn()
                note("release", ["value": crank.value, "shown": crank.shown])
                continue
            }
            let target = gesture.raw(at: clock)
            let delta = (target - crank.crank.raw) * WindowFrameCrank.degreesPerPoint
            if abs(delta) > 1e-9 { crank.turn(by: delta) }
        }
        if !dismissed, clock >= Self.dismissAt - 1e-9 {
            dismissed = true
            crank.dismiss(commit: true)
            note("dismiss", ["value": crank.value])
        }
        scene.surface.shudder = shudderOffset()
        scene.surface.needsDisplay = true
        updateOverlay()
    }

    func updateOverlay() {
        guard crankVisible, crank.alphaValue > 0 else {
            overlay.opacity = 0
            overlay.needsDisplay = true
            return
        }
        overlay.image = composite()
        let offset = crank.stageOffset
        overlay.square = crankFrame.offsetBy(dx: offset.x, dy: -offset.y)
        overlay.opacity = crank.alphaValue
        overlay.needsDisplay = true
    }

    func composite() -> CGImage? {
        let side = WindowFrameCrankView.side
        let pixels = Int(side * 2)
        let lightsRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        lightsRep.size = NSSize(width: side, height: side)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            crank.lights.cacheDisplay(in: crank.lights.bounds, to: lightsRep)
        }
        let sampled = CGFloat(pixels) * WindowFrameCrankSceneView.supersampling
        let shot = renderer.snapshot(atTime: clock, with: CGSize(width: sampled, height: sampled), antialiasingMode: .multisampling4X)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        context.interpolationQuality = .high
        if let lights = lightsRep.cgImage { context.draw(lights, in: rect) }
        if let model = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) { context.draw(model, in: rect) }
        return context.makeImage()
    }

    func frameState() -> [String: Any] {
        ["t": (clock * 1000).rounded() / 1000, "value": crank.value, "shown": (crank.shown * 1000).rounded() / 1000,
         "thickness": (Double(preferences.thickness) * 1000).rounded() / 1000, "radius": Double(PageCard.cornerRadius),
         "arm": (crank.model.armDegrees * 100).rounded() / 100, "lit": crank.lights.litCount, "readout": crank.lights.readout,
         "alpha": (Double(crank.alphaValue) * 1000).rounded() / 1000, "shudder": (Double(scene.surface.shudder) * 100).rounded() / 100,
         "tremble": (crank.tremble * 1000).rounded() / 1000, "flash": (crank.flash * 1000).rounded() / 1000,
         "phase": "\(crank.phase)", "sparkles": crank.lights.sparkles.count]
    }

    func run(out: String, video: Bool) {
        let frames = Int((Self.duration * Self.fps).rounded())
        let stills: [(String, Double)] = [("rest-start", 0), ("crank-sliding-in", 0.55), ("crank-in", 0.98), ("turning-11", 1.45),
                                          ("turning-12", 1.75), ("shudder-13", 119.0 / 60), ("at-13-give", 2.42), ("at-13-settled", 3.05),
                                          ("turning-down-8", 4.25), ("shudder-3", 305.0 / 60), ("at-3-give", 5.55), ("at-3-settled", 6.2),
                                          ("back-at-10", 8.2), ("sliding-out", 8.45), ("rest-end", Self.duration - 1 / Self.fps)]
        let stripTimes: [Double] = [0, 0.55, 0.98, 1.45, 1.75, 2.42, 3.05, 4.25, 5.55, 6.2, 8.2, Self.duration - 1 / Self.fps]
        let stillFrames = Dictionary(stills.map { (Int(($0.1 * Self.fps).rounded()), $0.0) }, uniquingKeysWith: { a, _ in a })
        let stripFrames = Set(stripTimes.map { Int(($0 * Self.fps).rounded()) })
        let writer = video ? try? AlphaVideoWriter(path: out + "/crank.mov", width: 2880, height: 1800) : nil
        var strip: [(Int, CGImage)] = []
        var zooms: [(Int, CGImage)] = []
        var states: [[String: Any]] = []
        let canvas = NSRect(origin: .zero, size: scene.stage.bounds.size)
        let started = Date()
        for frame in 0..<frames {
            step(frame: frame)
            let needed = video || stillFrames[frame] != nil || stripFrames.contains(frame)
            states.append(frameState())
            guard needed else { continue }
            let bitmap = scene.render(canvas, pixelsWide: 2880, pixelsHigh: 1800)
            guard let image = bitmap.cgImage else { continue }
            writer?.append(image)
            if let name = stillFrames[frame] {
                Render.writePNG(bitmap, out + "/key-\(name).png")
                if let zoom = crop(image) { Render.writePNG(NSBitmapImageRep(cgImage: zoom), out + "/zoom-\(name).png") }
            }
            if stripFrames.contains(frame) {
                strip.append((frame, image))
                if let zoom = crop(image) { zooms.append((frame, zoom)) }
            }
            if frame % 60 == 0 { print("frame", frame, "of", frames, String(format: "%.1fs", Date().timeIntervalSince(started))) }
        }
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/crank.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        writeStrip(strip, columns: 4, thumb: NSSize(width: 720, height: 450), path: out + "/crank-strip.png")
        writeStrip(zooms, columns: 6, thumb: NSSize(width: 360, height: 360), path: out + "/crank-zoom-strip.png")
        writeBeats(out + "/crank-beats.json", states: states)
    }

    func crop(_ image: CGImage) -> CGImage? {
        let half: CGFloat = 175
        let center = CGPoint(x: scene.windowRect.minX + crankFrame.midX,
                             y: min(scene.stage.bounds.height - half, scene.windowRect.minY + crankFrame.midY))
        let rect = CGRect(x: (center.x - half) * 2, y: (center.y - half) * 2, width: half * 4, height: half * 4)
        return image.cropping(to: rect)
    }

    func writeStrip(_ frames: [(Int, CGImage)], columns: Int, thumb: NSSize, path: String) {
        guard !frames.isEmpty else { return }
        let rows = (frames.count + columns - 1) / columns
        let size = NSSize(width: thumb.width * CGFloat(columns), height: thumb.height * CGFloat(rows))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor(white: 0.93, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
            for (index, entry) in frames.enumerated() {
                let rect = NSRect(x: CGFloat(index % columns) * thumb.width, y: CGFloat(index / columns) * thumb.height,
                                  width: thumb.width, height: thumb.height)
                NSImage(cgImage: entry.1, size: .zero).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                                                            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
                let label = String(format: "%.2fs  f%d", Double(entry.0) / Self.fps, entry.0)
                let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white])
                NSColor(white: 0, alpha: 0.6).setFill()
                NSRect(x: rect.minX + 4, y: rect.minY + 4, width: text.size().width + 10, height: text.size().height + 4).fill()
                text.draw(at: NSPoint(x: rect.minX + 9, y: rect.minY + 6))
            }
            return true
        }
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { Render.writePNG(rep, path) }
    }

    func writeBeats(_ path: String, states: [[String: Any]]) {
        let document: [String: Any] = [
            "scene": "window-frame-crank", "fps": Self.fps, "frames": states.count, "duration": Double(states.count) / Self.fps,
            "canvas": [2880, 1800], "window_px": [160, 36, 2560, 1680],
            "crank_square_pt_window_flipped": [crankFrame.minX, crankFrame.minY, crankFrame.width, crankFrame.height],
            "script": ["present": Self.presentAt, "dismiss": Self.dismissAt,
                       "gestures": Self.gestures.map { ["start": $0.start, "duration": $0.duration, "from": $0.from, "to": $0.to,
                                                        "release": $0.release] }],
            "events": log, "per_frame": states,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote", path)
        }
    }
}
