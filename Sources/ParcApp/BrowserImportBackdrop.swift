import AppKit
import SwiftUI

///
///
/// paging strip; a new choice springs the strip's position to that page and
/// the backdrop mixes the two pages either side of it (`transitioning(from:to:
///
/// the mix is. The first choice, and leaving the import, fade the backdrop on
/// the same spring over the page's own fill.
@MainActor
final class BrowserImportBackdrop: NSView {
    private let back = BrowserImportWashView(), front = BrowserImportWashView()
    ///
    private var position = SidebarSpring(response: SidebarSpacePagingModel.springResponse, damping: 1)
    private var visibility = SidebarSpring(response: SidebarSpacePagingModel.springResponse, damping: 1)
    private var pages: [BrowserImportWash] = []
    private var page: Int?
    private var timer: Timer?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [back, front] {
            view.autoresizingMask = [.width, .height]; view.frame = bounds; view.alphaValue = 0
            addSubview(view)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// One wash per browser in order, and the chosen browser's index.
    func show(_ next: [BrowserImportWash], selected: Int?) {
        guard next != pages || selected != page else { return }
        // Already leaving: the kept pages are fading out.
        if next.isEmpty && selected == nil && page == nil { return }
        let animate = window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let now = CACurrentMediaTime()
        let hidden = visibility.value(at: now) < 0.01
        // Leaving the import keeps the last pages so the backdrop fades out.
        if !next.isEmpty || selected != nil { pages = next }
        page = selected
        if let selected {
            if hidden || !animate { position.place(CGFloat(selected)) } else { position.retarget(CGFloat(selected), now: now) }
        }
        if animate { visibility.retarget(selected == nil ? 0 : 1, now: now) } else { visibility.place(selected == nil ? 0 : 1) }
        guard animate else { settle(); return }
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    self.tick()
                }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        tick()
    }

    /// Places the strip and fade directly, for a still frame of the motion.
    func showFrame(position value: CGFloat, visibility shown: CGFloat) {
        position.place(value); visibility.place(shown); apply(value, shown)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        guard !position.isSettled(at: now) || !visibility.isSettled(at: now) else { settle(); return }
        apply(position.value(at: now), visibility.value(at: now))
    }

    private func settle() {
        timer?.invalidate(); timer = nil
        if let page { position.place(CGFloat(page)) }
        visibility.place(page == nil ? 0 : 1)
        apply(position.value(at: CACurrentMediaTime()), page == nil ? 0 : 1)
    }

    private func apply(_ value: CGFloat, _ visible: CGFloat) {
        let shown = min(1, max(0, visible))
        guard !pages.isEmpty else { back.alphaValue = 0; front.alphaValue = 0; return }
        let clamped = min(CGFloat(pages.count - 1), max(0, value))
        let lower = Int(clamped.rounded(.down)), upper = Int(clamped.rounded(.up))
        // The next page lies over the last by the strip's progress, so the mix
        // never dips to the page fill between two washes.
        back.wash = toned(pages[lower]); front.wash = toned(pages[upper])
        back.alphaValue = shown; front.alphaValue = lower == upper ? 0 : shown * (clamped - CGFloat(lower))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { settle() }
    }

    /// The page's fill, its one text colour, and the fraction of the page's
    /// width its text spans: each wash darkens or lightens there just enough
    /// for that colour to read on it.
    func setPage(fill: NSColor, ink: NSColor, text: ClosedRange<CGFloat>) {
        guard fill != surface.fill || ink != surface.ink || text != surface.text else { return }
        surface = (fill, ink, text); retone()
    }
    private var surface: (fill: NSColor, ink: NSColor, text: ClosedRange<CGFloat>) =
        (.textBackgroundColor, .textColor, 0...1)
    private var tones: [BrowserImportWash: BrowserImportWash] = [:]

    private func toned(_ wash: BrowserImportWash) -> BrowserImportWash {
        if let cached = tones[wash] { return cached }
        var fill: NSColor?, ink: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = surface.fill.usingColorSpace(.sRGB); ink = surface.ink.usingColorSpace(.sRGB)
        }
        guard let fill, let ink else { return wash }
        let result = wash.toned(ink: [ink.redComponent, ink.greenComponent, ink.blueComponent],
                                fill: [fill.redComponent, fill.greenComponent, fill.blueComponent], across: surface.text)
        tones[wash] = result
        return result
    }

    private func retone() {
        tones = [:]
        apply(position.value(at: CACurrentMediaTime()), visibility.value(at: CACurrentMediaTime()))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        retone()
    }

    nonisolated static func contrast(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    nonisolated static func luminance(_ rgb: [CGFloat]) -> CGFloat {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}

///
/// the first deep at the left, the second at the right, with the dialog's
/// lighter blends between them.
struct BrowserImportWash: Hashable {
    let locations: [CGFloat]
    let colors: [UInt32]

    ///
    static let arc = BrowserImportWash(locations: [0, 0.11, 0.21, 0.31, 0.42, 0.52, 0.62, 0.72, 1],
        colors: [0x3320B4, 0x4B3EC8, 0x5954D8, 0x786FDF, 0x9F75D4, 0xC86BB5, 0xEA6D93, 0xF85F72, 0xFD5967])
    /// How much closer to white each of the dialog's stops is than a plain
    /// blend of its two end colours.
    private static let lift: [CGFloat] = [0, 0.153, 0.245, 0.34, 0.367, 0.345, 0.358, 0.307, 0]

    static func pair(_ first: UInt32, _ second: UInt32) -> BrowserImportWash {
        func channels(_ color: UInt32) -> [CGFloat] { [16, 8, 0].map { CGFloat(color >> $0 & 0xff) } }
        let a = channels(first), b = channels(second)
        let colors = zip(arc.locations, lift).map { location, lift -> UInt32 in
            let mixed = zip(a, b).map { $0 + location * ($1 - $0) }.map { $0 + lift * (255 - $0) }
            return mixed.reduce(0) { $0 << 8 | UInt32(min(255, max(0, $1.rounded()))) }
        }
        return BrowserImportWash(locations: arc.locations, colors: colors)
    }

    /// Each colour stop behind text (`span` of the width, with the stops either
    /// side so no blend between them crosses it) moves toward black under light
    /// ink, or toward white under dark ink, by the least amount that gives the
    /// ink 4.5:1 on it, WCAG's floor for body text; never more than the page's
    /// own fill gives. Hue stays. Past the text the change eases off over a
    /// third of the width, so no seam shows where it ends.
    func toned(ink: [CGFloat], fill: [CGFloat], across span: ClosedRange<CGFloat>) -> BrowserImportWash {
        let target = min(4.5, BrowserImportBackdrop.contrast(fill, ink))
        let toward: CGFloat = BrowserImportBackdrop.contrast(ink, [0, 0, 0]) > BrowserImportBackdrop.contrast(ink, [1, 1, 1]) ? 0 : 1
        let colors = colors.indices.map { index -> UInt32 in
            let before = locations[max(0, index - 1)], after = locations[min(locations.count - 1, index + 1)]
            let color = [16, 8, 0].map { CGFloat(colors[index] >> $0 & 0xff) / 255 }
            func mixed(_ t: CGFloat) -> [CGFloat] { color.map { $0 + t * (toward - $0) } }
            guard BrowserImportBackdrop.contrast(color, ink) < target else { return colors[index] }
            let behind = after >= span.lowerBound && before <= span.upperBound
            let distance = max(0, span.lowerBound - locations[index], locations[index] - span.upperBound)
            let weight = behind ? 1 : max(0, 1 - distance / 0.35)
            guard weight > 0 else { return colors[index] }
            var low: CGFloat = 0, high: CGFloat = 1
            for _ in 0..<16 {
                let t = (low + high) / 2
                if BrowserImportBackdrop.contrast(mixed(t), ink) < target { low = t } else { high = t }
            }
            // Rounding toward the target colour keeps the contrast just reached.
            return mixed(high * weight).reduce(0) { result, channel in
                let value = channel * 255
                return result << 8 | UInt32(min(255, max(0, toward == 0 ? value.rounded(.down) : value.rounded(.up))))
            }
        }
        return BrowserImportWash(locations: locations, colors: colors)
    }
}

/// One wash: solid across the top and fading into the page below, with the
///
@MainActor
final class BrowserImportWashView: NSView {
    /// The fraction of the page's height that stays solid, and where the
    /// colour is gone; the dialog's own header is shorter than these pages'.
    static let solid: CGFloat = 0.3, clear: CGFloat = 0.64
    private static let fadeLevels: [CGFloat] = [1, 1, 0.55, 0.15, 0]
    private static let fadeLocations: [CGFloat] = [0, solid, solid + (clear - solid) * 0.4, solid + (clear - solid) * 0.75, clear]
    private static let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
        colors: fadeLevels.map { CGColor(gray: $0, alpha: 1) } as CFArray, locations: fadeLocations)!
    var wash = BrowserImportWash.arc { didSet { if wash != oldValue { needsDisplay = true } } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let gradient = CGGradient(colorsSpace: space, colors: wash.colors.map { color in
            CGColor(srgbRed: CGFloat(color >> 16 & 0xff) / 255, green: CGFloat(color >> 8 & 0xff) / 255,
                    blue: CGFloat(color & 0xff) / 255, alpha: 1)
        } as CFArray, locations: wash.locations)!
        let rows = max(1, Int(bounds.height * 2))
        let mask = CGContext(data: nil, width: 1, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        // Bitmap rows run bottom-up; the solid end belongs at the view's top.
        mask.drawLinearGradient(Self.fade, start: CGPoint(x: 0, y: CGFloat(rows)), end: .zero, options: [])
        context.saveGState()
        context.clip(to: bounds, mask: mask.makeImage()!)
        context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: 0), end: CGPoint(x: bounds.maxX, y: 0), options: [])
        if let grain = OnboardingSetupCard.grainTile(.grain) {
            context.setBlendMode(.overlay); context.setAlpha(0.6)
            context.draw(grain, in: CGRect(origin: .zero, size: OnboardingSetupLayout.grainTileSize), byTiling: true)
        }
        context.restoreGState()
    }
}
