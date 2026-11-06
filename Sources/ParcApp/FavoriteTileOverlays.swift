import AppKit
import QuartzCore

// Favorite tile overlays (TAB16): recording dot, keyboard highlight ring,
// Peek badge and music particles, plus the window dim input. References are
//
//
//
//

///
/// `PCNativeMediaSessionStatus` mirrors.
enum FavoriteMediaSessionStatus: Int, Equatable {
    case active, ducking, suspended, inactive

    ///
    init(rawStatus: Int) { self = FavoriteMediaSessionStatus(rawValue: rawStatus) ?? .inactive }
}

/// Live-chrome skip for TAB16 Favorite overlays. The fingerprint covers every
/// input that feeds visible tile overlay state. Media session status belongs
/// in a tile token only for listed music hosts — callers must not read
/// `mediaSessionStatus` otherwise (its first read arms engine observers).
enum FavoriteOverlayPresentationSkip {
    static let gatedToken = "gated"

    /// True no-op: identical presentation fingerprint, including an identical
    /// empty/gated token. A changed recording/badge/developer/music bit must
    /// not skip.
    static func shouldSkip(previous: String?, next: String) -> Bool {
        previous == next
    }

    /// Matches `favoriteOverlayStates`: only a listed saved host with the
    /// MediaSession bridge may read status (and thereby arm observers).
    static func needsMediaSessionRead(savedURL: String, engineRespondsToStatus: Bool) -> Bool {
        FavoriteTileOverlayRules.isMusicHost(URL(string: savedURL)?.host) && engineRespondsToStatus
    }

    static func badgeToken(peekID: UUID, tiffData: Data?) -> String {
        guard let tiffData else { return "\(peekID.uuidString)|-" }
        return "\(peekID.uuidString)|\(tiffDataToken(tiffData))"
    }

    static func tiffDataToken(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        data.withUnsafeBytes { raw in
            for byte in raw {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return "\(data.count).\(String(hash, radix: 16))"
    }

    static func tileToken(id: UUID, pageIdentifier: String, recording: Bool,
                          badge: String?, developerTab: Bool, music: Bool) -> String {
        [
            id.uuidString,
            pageIdentifier,
            recording ? "r1" : "r0",
            badge.map { "b:\($0)" } ?? "b-",
            developerTab ? "d1" : "d0",
            music ? "m1" : "m0",
        ].joined(separator: "\u{1f}")
    }
}

///
enum FavoriteTileOverlayRules {
    ///
    static let musicHosts = ["bandcamp.com", "music.apple.com", "music.youtube.com", "nts.live",
                             "pandora.com", "soundcloud.com", "spotify.com", "tidal.com"]

    ///
    /// equality, a "." + domain suffix, or an equal dot-separated label (which
    /// can never match these dotted domains). A missing host never matches.
    static func isMusicHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return musicHosts.contains { domain in
            host == domain || host.hasSuffix("." + domain) || host.components(separatedBy: ".").contains(domain)
        }
    }

    ///
    ///
    /// status `.active` and whose saved URL (SidebarTab.savedURL, not the live
    /// URL) is on the list. Audible and muted state take no part (MP2-06).
    static func showsMusic(singlePage: Bool, status: FavoriteMediaSessionStatus?, savedURL: String) -> Bool {
        guard singlePage, status == .active else { return false }
        return isMusicHost(URL(string: savedURL)?.host)
    }

    ///
    /// own page's TabTrait `.tabCapturing` and `.mediaRecording`, never
    /// `.desktopCapturing`. TabTrait follows Chromium's TabAlert order
    /// (inference), whose producer derives kMediaRecording from camera or
    /// microphone use and kTabCapturing only from IsBeingMirrored. Capturing
    /// another tab, a window or a display, and Parc's display-media source flag
    /// (`shared`), feed no tested trait, so they never show the dot.
    static func isRecording(camera: Bool, microphone: Bool, tab: Bool, window: Bool,
                            display: Bool, mirrored: Bool, shared: Bool) -> Bool {
        camera || microphone || mirrored
    }

    ///
    /// && !WindowState.isMain, the descriptor fields at +0x21/+0x22.
    static func shouldDim(isKey: Bool, isMain: Bool) -> Bool { !isKey && !isMain }
}

///
/// isKey/isMain mirror AppKit's key and main window state is an inference
/// from their names; a tile outside a window is not dimmed.
@MainActor final class FavoriteWindowActivity: NSObject {
    private static let names = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification]
    private weak var window: NSWindow?
    private let changed: (Bool) -> Void

    init(changed: @escaping (Bool) -> Void) { self.changed = changed }

    func observe(_ window: NSWindow?) {
        if window !== self.window {
            NotificationCenter.default.removeObserver(self)
            self.window = window
            // Never a nil object: that would observe every window.
            if let window {
                for name in Self.names {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowActivityChanged(_:)),
                                                           name: name, object: window)
                }
            }
        }
        refresh()
    }

    @objc private func windowActivityChanged(_ notification: Notification) { refresh() }

    private func refresh() {
        changed(window.map { FavoriteTileOverlayRules.shouldDim(isKey: $0.isKeyWindow, isMain: $0.isMainWindow) } ?? false)
    }
}

///
///
/// the producer keeps an unchanged icon's image identity.
struct FavoriteTileBadge: Equatable {
    var favicon: NSImage?
}

struct FavoriteTileOverlayState: Equatable {
    var recording = false
    var badge: FavoriteTileBadge?
    var music = false
    ///
    var developerTab = false
    static let none = FavoriteTileOverlayState()
}

///
enum FavoriteTileOverlayGeometry {
    static let dotSide: CGFloat = 8
    static let dotStroke: CGFloat = 1
    static let dotInset: CGFloat = 6
    static let badgeSide: CGFloat = 20
    static let badgeCenterInset: CGFloat = 6
    static let badgeIconInset: CGFloat = 2
    static let badgeCornerRadius: CGFloat = 6
    static let particleOutset: CGFloat = 30
    static let particleRise: CGFloat = 8
    static let emitterSide: CGFloat = 6

    /// REC-02: the 8-point dot's bottom-right corner is inset 6 from the tile's.
    static func dot(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - dotInset - dotSide, y: bounds.maxY - dotInset - dotSide,
               width: dotSide, height: dotSide)
    }

    /// BADGE-01: centred on (W − 6, 6), overhanging the top-right corner by 4.
    static func badge(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - badgeCenterInset - badgeSide / 2, y: bounds.minY + badgeCenterInset - badgeSide / 2,
               width: badgeSide, height: badgeSide)
    }

    /// BADGE-02: a centred 16-point image.
    static func badgeIcon(in bounds: CGRect) -> CGRect {
        let side = badgeSide - 2 * badgeIconInset
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    /// MUS-03: tile bounds inset by −30, then offset 8 up.
    static func particles(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: -particleOutset, dy: -particleOutset).offsetBy(dx: 0, dy: -particleRise)
    }

    /// Converts a flipped tile rectangle for a host with the given geometry.
    static func place(_ rect: CGRect, in bounds: CGRect, flipped: Bool) -> CGRect {
        flipped ? rect : CGRect(x: rect.minX, y: bounds.minY + bounds.maxY - rect.maxY,
                                width: rect.width, height: rect.height)
    }

    /// ANIM-02: translate the badge centre onto the tile centre, then scale 0.1.
    static func collapsedBadgeTransform(tileBounds: CGRect, badgePosition: CGPoint) -> CATransform3D {
        let moved = CATransform3DTranslate(CATransform3DIdentity, tileBounds.midX - badgePosition.x,
                                           tileBounds.midY - badgePosition.y, 0)
        return CATransform3DScale(moved, 0.1, 0.1, 1)
    }
}

///
enum FavoriteTileSpring {
    static let ratio = 0.6
    static let response = 0.4

    static func make(keyPath: String, ratio: Double = ratio, response: Double = response) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = pow(2 * Double.pi / response, 2)
        spring.damping = 4 * Double.pi * ratio / response
        spring.duration = spring.settlingDuration
        return spring
    }
}

///
///
struct FavoriteParticleCellConfiguration: Equatable {
    var birthRate: Float
    var lifetime: Float = 2
    var lifetimeRange: Float = 0
    var scale: CGFloat = 0
    var scaleRange: CGFloat = 0.2
    var scaleSpeed: CGFloat = 1
    var alphaSpeed: Float = -0.5
    var alphaRange: Float = 0.15
    var emissionLatitude: CGFloat = 0
    var emissionLongitude: CGFloat = .pi / 2
    var emissionRange: CGFloat = .pi / 3
    var spin: CGFloat = 0
    var spinRange: CGFloat = 0
    var xAcceleration: CGFloat = 0
    var yAcceleration: CGFloat = 0
    var velocityRange: CGFloat = 5
    var velocity: CGFloat = 20

    /// [MusicSprite1 at 1.4, MusicSprite2 at 1.0] (MP2-22/MP2-24).
    static let cells = [FavoriteParticleCellConfiguration(birthRate: 1.4),
                        FavoriteParticleCellConfiguration(birthRate: 1.0)]

    /// MUS-02: white 0.8 in dark appearances, otherwise black 0.6.
    static func tint(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.8) : NSColor.black.withAlphaComponent(0.6)
    }

    func apply(to cell: CAEmitterCell, tint: NSColor, contents: CGImage?) {
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetimeRange
        cell.scale = scale
        cell.scaleRange = scaleRange
        cell.scaleSpeed = scaleSpeed
        cell.color = tint.cgColor
        cell.alphaSpeed = alphaSpeed
        cell.alphaRange = alphaRange
        cell.emissionLatitude = emissionLatitude
        cell.emissionLongitude = emissionLongitude
        cell.emissionRange = emissionRange
        cell.spin = spin
        cell.spinRange = spinRange
        cell.xAcceleration = xAcceleration
        cell.yAcceleration = yAcceleration
        cell.velocityRange = velocityRange
        cell.velocity = velocity
        cell.contents = contents
    }
}

///
/// and template mode only; its artwork is not used). Only the alpha matters:
/// the tint replaces the colour.
@MainActor enum FavoriteNoteSprites {
    static let size = NSSize(width: 6, height: 6)

    /// A single eighth note.
    static let single: NSImage = sprite { path in
        path.appendOval(in: NSRect(x: 0.4, y: 0.3, width: 2.9, height: 2.1))
        path.appendRect(NSRect(x: 2.6, y: 1.3, width: 0.7, height: 4.5))
        path.move(to: NSPoint(x: 3.3, y: 5.8))
        path.curve(to: NSPoint(x: 5.5, y: 3.4), controlPoint1: NSPoint(x: 4.6, y: 5.3),
                   controlPoint2: NSPoint(x: 5.6, y: 4.4))
        path.curve(to: NSPoint(x: 3.3, y: 4.6), controlPoint1: NSPoint(x: 5.0, y: 4.1),
                   controlPoint2: NSPoint(x: 4.2, y: 4.6))
        path.close()
    }

    /// Two beamed eighth notes.
    static let pair: NSImage = sprite { path in
        path.appendOval(in: NSRect(x: 0.1, y: 0.6, width: 2.4, height: 1.7))
        path.appendOval(in: NSRect(x: 3.1, y: 0.1, width: 2.4, height: 1.7))
        path.appendRect(NSRect(x: 1.9, y: 1.4, width: 0.6, height: 4.1))
        path.appendRect(NSRect(x: 4.9, y: 0.9, width: 0.6, height: 4.1))
        path.move(to: NSPoint(x: 1.9, y: 5.9))
        path.line(to: NSPoint(x: 5.5, y: 5.4))
        path.line(to: NSPoint(x: 5.5, y: 4.4))
        path.line(to: NSPoint(x: 1.9, y: 4.9))
        path.close()
    }

    /// MP2-25: the sprite is drawn, the tint set and the rect filled with
    /// `.sourceIn`; the cell receives that image's default CGImage, so AppKit
    ///
    static func contents(_ sprite: NSImage, tint: NSColor) -> CGImage? {
        NSImage(size: sprite.size, flipped: false) { rect in
            sprite.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceIn)
            return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func sprite(_ build: @escaping (NSBezierPath) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.windingRule = .nonZero
            build(path)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// True no-op gate for Favorite overlay layer layout. Identical outer/inner
/// frames and corner radii, or identical ring frames and paths, skip the
/// CATransaction rewrite; style/appearance and pulse remain ungated.
enum FavoriteOverlayLayerLayoutSkip {
    static func shouldSkipDot(
        outerFrame: CGRect, innerFrame: CGRect,
        outerRadius: CGFloat, innerRadius: CGFloat,
        bounds: CGRect, stroke: CGFloat = FavoriteTileOverlayGeometry.dotStroke
    ) -> Bool {
        let expectedOuter = bounds
        let expectedInner = bounds.insetBy(dx: stroke, dy: stroke)
        return outerFrame == expectedOuter
            && innerFrame == expectedInner
            && outerRadius == expectedOuter.height / 2
            && innerRadius == expectedInner.height / 2
    }

    static func shouldSkipRing(
        ringFrame: CGRect, foregroundFrame: CGRect,
        ringPath: CGPath?, foregroundPath: CGPath?,
        bounds: CGRect, path: CGPath
    ) -> Bool {
        ringFrame == bounds
            && foregroundFrame == bounds
            && ringPath == path
            && foregroundPath == path
    }
}

///
/// padding 0, no shadow): an 8-point white circle with a 6-point red core.
final class FavoriteRecordingDotView: NSView {
    private let outer = CALayer()
    private let inner = CALayer()
    var pulse: CAAnimation? { inner.animation(forKey: "pulse") }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        for sublayer in [outer, inner] {
            FavoriteTileOverlayLayers.disableActions(sublayer)
            layer?.addSublayer(sublayer)
        }
        // REC-03: NSColor.whiteColor ring, NSColor.redColor core.
        outer.backgroundColor = NSColor.white.cgColor
        inner.backgroundColor = NSColor.red.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let stroke = FavoriteTileOverlayGeometry.dotStroke
        let outerFrame = bounds
        let innerFrame = bounds.insetBy(dx: stroke, dy: stroke)
        let outerRadius = outerFrame.height / 2
        let innerRadius = innerFrame.height / 2
        // Sidebar chrome can mark the tile dirty without changing the 8-point
        // dot geometry. Skip the CATransaction when frames and radii already
        // match; opacity pulse is independent and keeps running.
        if FavoriteOverlayLayerLayoutSkip.shouldSkipDot(
            outerFrame: outer.frame, innerFrame: inner.frame,
            outerRadius: outer.cornerRadius, innerRadius: inner.cornerRadius,
            bounds: bounds, stroke: stroke
        ) {
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outer.frame = outerFrame
        inner.frame = innerFrame
        outer.cornerRadius = outerRadius
        inner.cornerRadius = innerRadius
        CATransaction.commit()
    }

    /// REC-04: the core pulses only while in a window and without Reduce
    /// Motion; it leaves a window with every animation removed.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { inner.removeAllAnimations(); return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        // Only fromValue is set, so the core runs 0.4 ↔ its model opacity 1 (REC-05).
        pulse.fromValue = 0.4
        pulse.duration = 0.75
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.repeatCount = .infinity
        pulse.autoreverses = true
        inner.add(pulse, forKey: "pulse")
    }
}

/// AppTrayItemHighlightRingView (S15–S17, G24): background and foreground
/// unfilled 2-point strokes on the tile bounds inset 1 with continuous radius
/// 11, their frame the tile bounds, changed with implicit actions disabled.
final class FavoriteHighlightRingView: NSView {
    /// DisplayStyle (S16): `.highlight(color)` strokes only the background;
    /// `.developerTab` strokes it black under a systemYellow [6, 6] dash.
    enum Style: Equatable { case highlight(NSColor), developerTab }

    let ring = CAShapeLayer()
    let foreground = CAShapeLayer()
    ///
    var style: Style = .highlight(.clear) { didSet { if style != oldValue { applyStyle() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        for shape in [ring, foreground] {
            FavoriteTileOverlayLayers.disableActions(shape)
            shape.fillColor = nil
            shape.lineWidth = FavoriteTileMetrics.highlightRingWidth
            layer?.addSublayer(shape)
        }
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let path = FavoriteTilePaths.highlightRing(bounds: bounds)
        // Keyboard-highlight / chrome passes can re-layout without changing the
        // tile bounds. Skip the CATransaction when frames and ring paths already
        // match; style/appearance still redraws through applyStyle.
        if FavoriteOverlayLayerLayoutSkip.shouldSkipRing(
            ringFrame: ring.frame, foregroundFrame: foreground.frame,
            ringPath: ring.path, foregroundPath: foreground.path,
            bounds: bounds, path: path
        ) {
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for shape in [ring, foreground] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    ///
    /// no effect without a foreground stroke.
    private func applyStyle() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .highlight(let color):
                ring.strokeColor = color.cgColor
                foreground.strokeColor = nil
            case .developerTab:
                ring.strokeColor = NSColor.black.cgColor
                foreground.strokeColor = NSColor.systemYellow.cgColor
                foreground.lineDashPattern = [6, 6]
            }
        }
        CATransaction.commit()
    }
}

/// AppTrayItemBadgeView: a flipped, non-clipping 20-point badge with a
/// centred 16-point image (BADGE-02/BADGE-03).
final class FavoriteTileBadgeView: NSView {
    let icon = CALayer()
    private var favicon: NSImage?
    var isDark = false { didSet { if isDark != oldValue { applyStyle(); refreshIcon() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = false
        setAccessibilityElement(false)
        FavoriteTileOverlayLayers.disableActions(icon)
        icon.contentsGravity = .resizeAspect
        layer?.addSublayer(icon)
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateLayer() { applyStyle() }
    /// AppKit clears the backing layer's shadow when the view enters a window;
    ///
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle(); needsDisplay = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        icon.frame = backingAlignedRect(FavoriteTileOverlayGeometry.badgeIcon(in: bounds), options: .alignAllEdgesNearest)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        icon.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    /// ANIM-03: a new image replaces the old one directly, without a transition.
    func setFavicon(_ image: NSImage?) {
        favicon = image
        refreshIcon()
    }

    private func refreshIcon() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        icon.contents = favicon ?? FavoriteTileOverlayLayers.emptyPage(dark: isDark)
        CATransaction.commit()
    }

    private func applyStyle() {
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.masksToBounds = false
        layer.cornerRadius = FavoriteTileOverlayGeometry.badgeCornerRadius
        layer.cornerCurve = .continuous
        // FullOpacityBackgroundPrimary (installed 1.170 BaseAssets): white in
        // light appearances, black in dark ones.
        layer.backgroundColor = (isDark ? NSColor.black : NSColor.white).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        CATransaction.commit()
    }
}

///
/// is a CAEmitterLayer centred in its bounds (MP2-20). Unflipped geometry makes
/// emission longitude π/2 travel up the screen.
final class FavoriteMusicParticlesView: NSView {
    let emitter = CAEmitterLayer()
    let isDark: Bool

    init(dark: Bool) {
        isDark = dark
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
        let tint = FavoriteParticleCellConfiguration.tint(dark: dark)
        let sprites = [FavoriteNoteSprites.single, FavoriteNoteSprites.pair]
        emitter.emitterCells = zip(FavoriteParticleCellConfiguration.cells, sprites).map { configuration, sprite in
            let cell = CAEmitterCell()
            configuration.apply(to: cell, tint: tint, contents: FavoriteNoteSprites.contents(sprite, tint: tint))
            return cell
        }
        // Only the cells, size, shape and position are set; renderMode,
        // emitterMode, seed and the layer multipliers keep their defaults (MP2-21).
        emitter.emitterSize = CGSize(width: FavoriteTileOverlayGeometry.emitterSide,
                                     height: FavoriteTileOverlayGeometry.emitterSide)
        emitter.emitterShape = .circle
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { emitter }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

@MainActor enum FavoriteTileOverlayLayers {
    private static var emptyPageImages: [Bool: NSImage] = [:]

    ///
    /// sidebar's own generic page glyph, drawn 14 points inside the 16-point slot.
    static func emptyPage(dark: Bool) -> NSImage {
        if let image = emptyPageImages[dark] { return image }
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let symbol = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let tint = dark ? NSColor.white.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.85)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            guard let symbol else { return true }
            let side: CGFloat = 14
            let fitted = symbol.size.width >= symbol.size.height
                ? NSSize(width: side, height: side * symbol.size.height / max(symbol.size.width, 1))
                : NSSize(width: side * symbol.size.width / max(symbol.size.height, 1), height: side)
            let frame = NSRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                               width: fitted.width, height: fitted.height)
            symbol.draw(in: frame)
            tint.set()
            frame.fill(using: .sourceAtop)
            return true
        }
        emptyPageImages[dark] = image
        return image
    }

    static func disableActions(_ layer: CALayer) {
        layer.actions = ["backgroundColor": NSNull(), "contents": NSNull(), "bounds": NSNull(),
                         "position": NSNull(), "frame": NSNull(), "opacity": NSNull(),
                         "cornerRadius": NSNull(), "hidden": NSNull(), "path": NSNull(),
                         "strokeColor": NSNull()]
    }
}

/// Owns one tile's overlay subviews. Every update compares with the previous
/// value, so redraws never restart a spring, pulse or emitter.
@MainActor final class FavoriteTileOverlays {
    private unowned let host: NSView
    private(set) var state = FavoriteTileOverlayState.none
    private(set) var dotView: FavoriteRecordingDotView?
    private(set) var ringView: FavoriteHighlightRingView?
    private(set) var badgeView: FavoriteTileBadgeView?
    private(set) var particlesView: FavoriteMusicParticlesView?
    /// AppItem.isHighlighted: the sidebar keyboard highlight is on this Favorite.
    private(set) var highlighted = false
    /// AppItem.isSelected, from the tile.
    private(set) var selected = false
    private var highlightColor: NSColor?
    /// The badge's current target; false while a hide is in flight.
    private(set) var badgeShown = false
    /// badgeAnimationID: a later show cancels a pending hide removal.
    private var badgeGeneration = 0
    private var paletteIsDark: Bool?

    init(host: NSView) { self.host = host }

    private var isDark: Bool {
        paletteIsDark ?? (host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    func update(_ next: FavoriteTileOverlayState) {
        let previous = state
        state = next
        if next.recording != previous.recording { setRecording(next.recording) }
        if next.developerTab != previous.developerTab { refreshRing() }
        if next.badge != previous.badge { setBadge(next.badge) }
        if next.music != previous.music { refreshParticles() }
    }

    /// The tile's palette appearance; a change restyles the badge and ring and
    /// rebuilds running particles whose tint no longer matches (MUS-02).
    func setPaletteDark(_ dark: Bool) {
        guard paletteIsDark != dark else { return }
        paletteIsDark = dark
        restyle(rebuildParticles: particlesView.map { $0.isDark != dark } ?? false)
    }

    ///
    /// rebuilds a running particle view on every effective-appearance change.
    func appearanceDidChange() { restyle(rebuildParticles: particlesView != nil) }

    private func restyle(rebuildParticles: Bool) {
        badgeView?.isDark = isDark
        refreshRing()
        guard rebuildParticles else { return }
        particlesView?.removeFromSuperview(); particlesView = nil
        makeParticles()
    }

    func layout() {
        let bounds = host.bounds
        let flipped = host.isFlipped
        func place(_ rect: CGRect) -> CGRect { FavoriteTileOverlayGeometry.place(rect, in: bounds, flipped: flipped) }
        if let dotView { dotView.frame = place(FavoriteTileOverlayGeometry.dot(in: bounds)) }
        if let ringView { ringView.frame = bounds }
        if let badgeView, let layer = badgeView.layer {
            let frame = place(FavoriteTileOverlayGeometry.badge(in: bounds))
            if badgeView.frame != frame { badgeView.frame = frame }
            // BADGE-01: centre anchor and position so the springs pivot in place.
            // AppKit can reset a new backing layer's anchor at its first display;
            //
            //
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
            CATransaction.commit()
        }
        if let particlesView { particlesView.frame = place(FavoriteTileOverlayGeometry.particles(in: bounds)) }
    }

    func windowDidChange() {
        //
        if host.window == nil, badgeView != nil, !badgeShown { removeBadge() }
    }

    // MARK: Recording dot

    /// REC-01: added or removed at once, with no transition.
    private func setRecording(_ recording: Bool) {
        if recording {
            guard dotView == nil else { return }
            let dot = FavoriteRecordingDotView(frame: .zero)
            dotView = dot
            insert(dot)
            layout()
        } else {
            dotView?.removeFromSuperview(); dotView = nil
        }
    }

    // MARK: Highlight ring

    func setHighlighted(_ value: Bool) {
        guard value != highlighted else { return }
        highlighted = value
        refreshRing()
    }

    func setSelected(_ value: Bool) {
        guard value != selected else { return }
        selected = value
        refreshRing()
    }

    /// The window palette's maxContrastColor (S18).
    func setHighlightColor(_ color: NSColor?) {
        highlightColor = color
        refreshRing()
    }

    /// Without a palette, Parc's untinted maxContrastColor: white in dark, black in light.
    private var ringColor: NSColor { highlightColor ?? (isDark ? .white : .black) }

    ///
    /// else `.developerTab` while selected with a developer-tab page, else
    /// hidden. The ring is created once, at z 4, and shown or hidden without
    /// animation.
    private func refreshRing() {
        let style: FavoriteHighlightRingView.Style? = highlighted ? .highlight(ringColor)
            : selected && state.developerTab ? .developerTab : nil
        guard let style else { ringView?.isHidden = true; return }
        if ringView == nil {
            let ring = FavoriteHighlightRingView(frame: .zero)
            ringView = ring
            insert(ring)
            layout()
        }
        ringView?.style = style
        ringView?.isHidden = false
    }

    // MARK: Peek badge

    private func setBadge(_ badge: FavoriteTileBadge?) {
        guard let badge else {
            if badgeView != nil, badgeShown { showBadge(false) }
            return
        }
        let view = badgeView ?? makeBadge()
        view.setFavicon(badge.favicon)
        view.needsLayout = true
        // ANIM-03: every new image re-runs show(), restarting both springs from
        // their presentation values; on a settled badge that is identity to
        // identity (ANIM-04, inferred invisible).
        showBadge(true)
    }

    /// BADGE-04: created with layer opacity 0, then sorted into place.
    private func makeBadge() -> FavoriteTileBadgeView {
        let badge = FavoriteTileBadgeView(frame: .zero)
        badge.isDark = isDark
        badge.layer?.opacity = 0
        badgeView = badge
        insert(badge)
        layout()
        return badge
    }

    ///
    /// values; hiding collapses to scale 0.1 at the tile centre, then removes.
    private func showBadge(_ show: Bool) {
        guard let badge = badgeView, let layer = badge.layer else { return }
        layout()
        badgeGeneration &+= 1
        let generation = badgeGeneration
        badgeShown = show
        let collapsed = FavoriteTileOverlayGeometry.collapsedBadgeTransform(tileBounds: host.bounds,
                                                                            badgePosition: layer.position)
        let target = show ? CATransform3DIdentity : collapsed
        let opacity: Float = show ? 1 : 0
        guard host.window != nil else {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "badge_transform"); layer.removeAnimation(forKey: "badge_opacity")
            layer.transform = target; layer.opacity = opacity
            CATransaction.commit()
            if !show { removeBadge() }
            return
        }
        let presentation = layer.presentation()
        let transform = FavoriteTileSpring.make(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: presentation?.transform ?? (show ? collapsed : CATransform3DIdentity))
        transform.toValue = NSValue(caTransform3D: target)
        let fade = FavoriteTileSpring.make(keyPath: "opacity")
        fade.fromValue = presentation?.opacity ?? (show ? 0 : 1)
        fade.toValue = opacity
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak badge] in
            MainActor.assumeIsolated {
                guard !show, let self, let badge, self.badgeView === badge,
                      self.badgeGeneration == generation else { return }
                self.removeBadge()
            }
        }
        layer.add(transform, forKey: "badge_transform")
        layer.add(fade, forKey: "badge_opacity")
        CATransaction.setDisableActions(true)
        layer.transform = target; layer.opacity = opacity
        CATransaction.commit()
    }

    private func removeBadge() {
        badgeView?.removeFromSuperview(); badgeView = nil
        badgeShown = false
    }

    // MARK: Music particles

    ///
    /// while eligible and without Reduce Motion, removed with no fade
    ///
    private func refreshParticles() {
        guard state.music, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            particlesView?.removeFromSuperview(); particlesView = nil
            return
        }
        if particlesView == nil { makeParticles() }
    }

    ///
    private func makeParticles() {
        let particles = FavoriteMusicParticlesView(dark: isDark)
        particlesView = particles
        insert(particles)
        layout()
    }

    // MARK: Ordering

    /// Recording 2 < highlight 4 < badge 5 < music 6, above the tile's own layers.
    private func insert(_ view: NSView) {
        let ordered: [NSView?] = [dotView, ringView, badgeView, particlesView]
        guard let index = ordered.firstIndex(where: { $0 === view }) else { return }
        let above = ordered[(index + 1)...].compactMap { $0 }.first { $0.superview === host }
        if let above { host.addSubview(view, positioned: .below, relativeTo: above) } else { host.addSubview(view) }
    }
}

extension FavoriteTile {
    func setOverlays(_ state: FavoriteTileOverlayState) { overlays.update(state) }
    /// TAB17 producer contract: the sidebar keyboard highlight is on this Favorite.
    func setKeyboardHighlighted(_ highlighted: Bool) { overlays.setHighlighted(highlighted) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowActivity.observe(window)
        overlays.windowDidChange()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        overlays.appearanceDidChange()
    }
}
