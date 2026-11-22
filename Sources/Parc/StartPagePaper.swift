import AppKit
import ParcCore
import ParcKit

struct StartPagePaperStyle: Equatable {
    struct Glow: Equatable {
        var color: SIMD3<Double>
        var anchor: CGPoint
    }

    static let anchors = [CGPoint(x: 0.05, y: 0), CGPoint(x: 1, y: 0.25), CGPoint(x: 0.35, y: 1.05)]
    static let radius: CGFloat = 0.62
    static let falloff = 1.6
    static let lightTint = 0.84
    static let darkTint = 0.82
    static let darkBase = SIMD3<Double>(0.05, 0.05, 0.07)
    static let colorlessLight = SIMD3<Double>(251, 251, 252) / 255
    static let colorlessDark = SIMD3<Double>(22, 22, 24) / 255

    var base: SIMD3<Double>
    var glows: [Glow]
    var glowStrength: Double
    var grain: Double
    var noise: Double
    var dark: Bool

    init(theme: SpaceTheme, dark: Bool) {
        self.dark = dark
        grain = dark ? 0.12 : 0.16
        noise = dark ? 0.08 : 0.1
        glowStrength = dark ? 0.42 : 0.55
        let colors = theme.colors.map { color -> SIMD3<Double> in
            let value = ThemeRenderMath.srgb(color)
            return SIMD3(Double(value.x), Double(value.y), Double(value.z))
        }
        guard !colors.isEmpty else {
            base = dark ? Self.colorlessDark : Self.colorlessLight
            glows = []
            return
        }
        let average = colors.reduce(SIMD3<Double>(repeating: 0), +) / Double(colors.count)
        base = dark ? Self.mix(average, Self.darkBase, Self.darkTint) : Self.mix(average, SIMD3(repeating: 1), Self.lightTint)
        glows = zip(colors, Self.anchors).map { Glow(color: $0, anchor: $1) }
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        a + (b - a) * min(1, max(0, amount))
    }

    static func glowAlpha(at distance: Double, strength: Double) -> Double {
        strength * pow(1 - min(1, max(0, distance)), falloff)
    }

    static func glowFrame(_ anchor: CGPoint, in size: CGSize) -> CGRect {
        let radius = Self.radius * max(size.width, size.height)
        return CGRect(x: anchor.x * size.width - radius, y: anchor.y * size.height - radius, width: radius * 2, height: radius * 2)
    }
}

@MainActor
final class StartPagePaperView: NSView {
    static let glowStops: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1]

    var theme = SpaceTheme() { didSet { if theme != oldValue { refresh() } } }
    var incognito = false { didSet { if incognito != oldValue { refresh() } } }
    var pagingTransition: ThemePagingTransition? {
        didSet {
            guard pagingTransition != oldValue else { return }
            if let old = oldValue, let new = pagingTransition, old.from == new.from, old.theme == new.theme, !incognito {
                applyProgress()
            } else {
                refresh()
            }
        }
    }
    private(set) var style = StartPagePaperStyle(theme: SpaceTheme(), dark: false)
    private(set) var incomingStyle: StartPagePaperStyle?
    private let current = CALayer()
    private let incoming = CALayer()
    private let grain = CALayer()
    private let noise = CALayer()
    private static let grainTile: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ThemeTextures/grain.png"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.size = NSSize(width: ThemeTexturePitch.points, height: ThemeTexturePitch.points)
        return image
    }()
    private static var noiseTiles: [Bool: NSImage] = [:]

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for sublayer in [current, incoming, grain, noise] {
            sublayer.actions = ["opacity": NSNull(), "bounds": NSNull(), "position": NSNull(), "contents": NSNull(),
                                "backgroundColor": NSNull(), "sublayers": NSNull()]
            layer?.addSublayer(sublayer)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    var effectiveTheme: SpaceTheme { incognito ? IncognitoWindowTheme.paletteTheme : theme }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in [current, incoming, grain, noise] where sublayer.frame != bounds { sublayer.frame = bounds }
        let flips = !(layer?.contentsAreFlipped() ?? false)
        for container in [current, incoming] where container.isGeometryFlipped != flips { container.isGeometryFlipped = flips }
        placeGlows(in: current, style: style)
        if let incomingStyle { placeGlows(in: incoming, style: incomingStyle) }
        CATransaction.commit()
    }

    override func updateLayer() { applyColors() }

    private func refresh() {
        let dark = isDark
        if let transition = pagingTransition, !incognito {
            style = StartPagePaperStyle(theme: transition.from, dark: dark)
            incomingStyle = StartPagePaperStyle(theme: transition.theme, dark: dark)
        } else {
            style = StartPagePaperStyle(theme: effectiveTheme, dark: dark)
            incomingStyle = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        buildGlows(in: current, style: style)
        if let incomingStyle { buildGlows(in: incoming, style: incomingStyle) } else { incoming.sublayers = nil }
        applyProgress()
        grain.backgroundColor = Self.grainTile.map { NSColor(patternImage: $0).cgColor }
        grain.opacity = Float(style.grain)
        noise.backgroundColor = NSColor(patternImage: Self.noiseTile(dark: dark)).cgColor
        noise.opacity = Float(style.noise)
        CATransaction.commit()
        needsLayout = true
        needsDisplay = true
    }

    private func applyProgress() {
        let progress = Float(min(1, max(0, pagingTransition?.progress ?? 0)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.opacity = incomingStyle == nil ? 1 : 1 - progress
        incoming.opacity = incomingStyle == nil ? 0 : progress
        CATransaction.commit()
        needsDisplay = true
    }

    private func applyColors() {
        var base = style.base
        if let incomingStyle {
            base = StartPagePaperStyle.mix(style.base, incomingStyle.base, Double(min(1, max(0, pagingTransition?.progress ?? 0))))
        }
        layer?.backgroundColor = CGColor(srgbRed: base.x, green: base.y, blue: base.z, alpha: 1)
    }

    private func buildGlows(in container: CALayer, style: StartPagePaperStyle) {
        container.sublayers = style.glows.map { glow in
            let gradient = CAGradientLayer()
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            gradient.locations = Self.glowStops.map { NSNumber(value: $0) }
            gradient.colors = Self.glowStops.map {
                CGColor(srgbRed: glow.color.x, green: glow.color.y, blue: glow.color.z,
                        alpha: StartPagePaperStyle.glowAlpha(at: $0, strength: style.glowStrength))
            }
            gradient.actions = ["bounds": NSNull(), "position": NSNull()]
            return gradient
        }
        placeGlows(in: container, style: style)
    }

    private func placeGlows(in container: CALayer, style: StartPagePaperStyle) {
        for (glow, sublayer) in zip(style.glows, container.sublayers ?? []) {
            let frame = StartPagePaperStyle.glowFrame(glow.anchor, in: bounds.size)
            if sublayer.frame != frame { sublayer.frame = frame }
        }
    }

    private static func noiseTile(dark: Bool) -> NSImage {
        if let cached = noiseTiles[dark] { return cached }
        let side = 256
        var state: UInt64 = 0x5DEECE66D
        func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let tone: UInt8 = dark ? 255 : 0
        for index in 0..<(side * side) {
            let gaussian = (-2 * log(max(uniform(), 1e-9))).squareRoot() * cos(2 * Double.pi * uniform())
            let alpha = UInt8(min(255, max(0, gaussian * 40)))
            let premultiplied = UInt8(Int(tone) * Int(alpha) / 255)
            pixels[index * 4] = premultiplied
            pixels[index * 4 + 1] = premultiplied
            pixels[index * 4 + 2] = premultiplied
            pixels[index * 4 + 3] = alpha
        }
        let image: NSImage
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let cgImage = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: side / 2, height: side / 2))
        } else {
            image = NSImage(size: NSSize(width: 1, height: 1))
        }
        noiseTiles[dark] = image
        return image
    }
}
