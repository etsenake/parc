import AppKit
import QuartzCore
import SwiftUI

@MainActor enum NavigationControlArtwork {
    static let directory: URL? = resourcesDirectory(in: .main)
    private static var forceReloadImages: [URL: NSImage] = [:]

    static func resourcesDirectory(in bundle: Bundle) -> URL? {
        bundle.resourceURL?.appendingPathComponent("NavigationControls", isDirectory: true)
    }
    private static var symbols: [String: NSImage] = [:]

    static func symbol(_ name: String, pointSize: CGFloat) -> NSImage? {
        let key = "\(name) \(pointSize)"
        if let cached = symbols[key] { return cached }
        let glyph = Image(systemName: name).font(.system(size: pointSize, weight: .medium)).foregroundColor(.black)
        let bounds = ImageRenderer(content: glyph)
        bounds.scale = 2
        guard let measured = bounds.cgImage else { return nil }
        let size = NSSize(width: ceil(CGFloat(measured.width) / 2), height: ceil(CGFloat(measured.height) / 2))
        let image = NSImage(size: size)
        for scale in [1, 2] as [CGFloat] {
            let renderer = ImageRenderer(content: glyph.frame(width: size.width, height: size.height))
            renderer.scale = scale
            guard let raster = renderer.cgImage else { continue }
            let representation = NSBitmapImageRep(cgImage: raster)
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        symbols[key] = image
        return image
    }

    static var forceReload: NSImage? { forceReload(in: directory) }

    static func forceReload(in directory: URL?) -> NSImage? {
        guard let directory else { return nil }
        if let cached = forceReloadImages[directory] { return cached }
        let name = "icon-browser-navigation-force-reload"
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        base.size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        let image = NSImage(size: base.size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = NSSize(width: CGFloat(double.pixelsWide) / 2, height: CGFloat(double.pixelsHigh) / 2)
            image.addRepresentation(double)
        }
        if let vector = NSImage(contentsOf: directory.appendingPathComponent(name + ".pdf")) {
            for representation in vector.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        forceReloadImages[directory] = image
        return image
    }
}

@MainActor final class ReloadGlyph {
    static let toolbarPointSize: CGFloat = 13
    static let clipCornerRadius: CGFloat = 6
    static let response = 0.2, dampingFraction = 0.6
    static let actionResponse = 0.4, actionDamping = 0.6
    static let actionRotation: CGFloat = 2 * .pi
    static func delay(enteringLoading: Bool) -> CFTimeInterval { enteringLoading ? 0.2 : 0.1 }

    static let pressedRotation: CGFloat = .pi / 2
    static let pressedOffset: CGFloat = 1

    var pointSize: CGFloat {
        didSet {
            guard pointSize != oldValue else { return }
            loadImages(); tinted = nil
            view?.needsDisplay = true
        }
    }
    private let rasterized: Bool
    private var arrowImage: NSImage?
    private var stopImage: NSImage?
    private func loadImages() {
        func image(_ name: String) -> NSImage? {
            rasterized ? NavigationControlArtwork.symbol(name, pointSize: pointSize)
                : NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium, scale: .medium))
        }
        arrowImage = image("arrow.clockwise"); stopImage = image("xmark")
    }
    private weak var view: NSView?
    private(set) var loading = false
    private(set) var forceReload = false
    private(set) var progress: CGFloat = 0
    private(set) var rotation: CGFloat = 0
    private var from: CGFloat = 0, target: CGFloat = 0
    private var start: CFTimeInterval = 0, delay: CFTimeInterval = 0
    private var spinFrom: CGFloat = 0, spinTarget: CGFloat = 0
    private var spinStart: CFTimeInterval = 0
    private var spinning = false
    var frames: any DisplayFrameDriving = ViewDisplayFrameDriver()
    var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var artworkDirectory: URL? = NavigationControlArtwork.directory
    private var tinted: (color: NSColor, images: [ObjectIdentifier: NSImage])?
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }

    init(view: NSView, pointSize: CGFloat, rasterized: Bool) {
        self.view = view; self.pointSize = pointSize; self.rasterized = rasterized
        loadImages()
    }

    func update(loading: Bool, forceReload: Bool, animated: Bool) {
        if forceReload != self.forceReload {
            self.forceReload = forceReload
            tinted = nil
            view?.needsDisplay = true
        }
        guard loading != self.loading else { return }
        self.loading = loading
        let next: CGFloat = loading ? 1 : 0
        guard animated, !reduceMotion() else {
            progress = next; from = next; target = next
            if !spinning { stopFrames() }
            view?.needsDisplay = true
            return
        }
        from = progress; target = next
        start = now(); delay = Self.delay(enteringLoading: loading)
        startFrames()
    }

    func playActionSpin(animated: Bool) {
        let next = rotation + Self.actionRotation
        guard animated, !reduceMotion() else {
            rotation = next.truncatingRemainder(dividingBy: Self.actionRotation)
            spinFrom = rotation; spinTarget = rotation; spinning = false
            if progress == target { stopFrames() }
            view?.needsDisplay = true
            return
        }
        spinFrom = rotation; spinTarget = next
        spinStart = now(); spinning = true
        startFrames()
    }

    func stop() {
        stopFrames()
        progress = target; from = target
        rotation = spinTarget.truncatingRemainder(dividingBy: Self.actionRotation)
        spinFrom = rotation; spinning = false
    }

    private func startFrames() {
        guard let view else { return }
        frames.start(in: view) { [weak self] in self?.tick() ?? false }
    }
    private func stopFrames() { frames.stop() }

    private func tick() -> Bool {
        let time = now()
        var keep = false
        let loadElapsed = time - start - delay
        if progress != target {
            if loadElapsed >= 0 {
                if loadElapsed >= Self.settlingTime {
                    progress = target
                } else {
                    progress = from + (target - from) * Self.spring(loadElapsed)
                    keep = true
                }
            } else {
                keep = true
            }
        }
        if spinning {
            let elapsed = time - spinStart
            if elapsed >= Self.actionSettlingTime {
                rotation = spinTarget.truncatingRemainder(dividingBy: Self.actionRotation)
                spinFrom = rotation; spinTarget = rotation; spinning = false
            } else {
                rotation = spinFrom + (spinTarget - spinFrom) * Self.actionSpring(elapsed)
                keep = true
            }
        }
        view?.needsDisplay = true
        return keep
    }

    static func spring(_ t: Double) -> CGFloat { unitSpring(t, response: response, damping: dampingFraction) }
    static func actionSpring(_ t: Double) -> CGFloat { unitSpring(t, response: actionResponse, damping: actionDamping) }
    static func unitSpring(_ t: Double, response: Double, damping: Double) -> CGFloat {
        let omega = 2 * Double.pi / response, decay = damping * omega
        let damped = omega * (1 - damping * damping).squareRoot()
        return CGFloat(1 - exp(-decay * t) * (cos(damped * t) + decay / damped * sin(damped * t)))
    }
    static func settlingDuration(response: Double, damping: Double) -> CFTimeInterval {
        log(1000) / (damping * 2 * Double.pi / response)
    }
    static let settlingTime: CFTimeInterval = settlingDuration(response: response, damping: dampingFraction)
    static let actionSettlingTime: CFTimeInterval = settlingDuration(response: actionResponse, damping: actionDamping)

    var idleImage: NSImage? { forceReload ? NavigationControlArtwork.forceReload(in: artworkDirectory) ?? arrowImage : arrowImage }

    func draw(in bounds: NSRect, tint: NSColor, press: CGFloat = 0, in view: NSView) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: Self.clipCornerRadius, yRadius: Self.clipCornerRadius).addClip()
        if abs(rotation) > 0.001 { Self.rotate(by: rotation, about: bounds) }
        let p = progress
        let arrowPress = idleImage === arrowImage ? press : 0
        draw(idleImage, scale: 1 - 0.3 * p, alpha: 1 - p, press: arrowPress, bounds: bounds, tint: tint, view: view)
        draw(stopImage, scale: 0.7 + 0.3 * p, alpha: p, press: 0, bounds: bounds, tint: tint, view: view)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func rotate(by angle: CGFloat, about bounds: NSRect) {
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byRadians: angle)
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.concat()
    }

    private func draw(_ image: NSImage?, scale: CGFloat, alpha: CGFloat, press: CGFloat, bounds: NSRect, tint: NSColor, view: NSView) {
        guard let image, alpha > 0.001, scale > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        var rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        if abs(press) > 0.0001 {
            let down: CGFloat = view.isFlipped ? 1 : -1
            rect = rect.offsetBy(dx: Self.pressedOffset * press * scale, dy: Self.pressedOffset * press * scale * down)
            Self.rotate(by: Self.pressedRotation * press * (view.isFlipped ? 1 : -1),
                        about: NSRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2))
        } else if abs(scale - 1) < 0.001 {
            rect = view.backingAlignedRect(rect, options: .alignAllEdgesNearest)
        }
        tintedImage(image, tint).draw(in: rect, from: .zero, operation: .sourceOver, fraction: min(1, alpha) * tint.alphaComponent,
                                      respectFlipped: true, hints: nil)
    }

    private func tintedImage(_ image: NSImage, _ color: NSColor) -> NSImage {
        let opaque = color.withAlphaComponent(1)
        if tinted?.color != opaque { tinted = (opaque, [:]) }
        let key = ObjectIdentifier(image)
        if let cached = tinted?.images[key] { return cached }
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            opaque.set(); rect.fill(using: .sourceIn)
            return true
        }
        tinted?.images[key] = result
        return result
    }
}
