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
    /// Whether a wash holds most of the page: text over it turns white.
    private(set) var isShown = false {
        didSet { if isShown != oldValue { onShownChange?(isShown) } }
    }
    var onShownChange: ((Bool) -> Void)?
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

    /// One wash per browser in order, and the chosen browser's index; true
    /// when that changes what the backdrop shows.
    @discardableResult
    func show(_ next: [BrowserImportWash], selected: Int?) -> Bool {
        guard next != pages || selected != page else { return false }
        // Already leaving: the kept pages are fading out.
        if next.isEmpty && selected == nil && page == nil { return false }
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
        guard animate else { settle(); return true }
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
        return true
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
        guard !pages.isEmpty else { back.alphaValue = 0; front.alphaValue = 0; isShown = false; return }
        let clamped = min(CGFloat(pages.count - 1), max(0, value))
        let lower = Int(clamped.rounded(.down)), upper = Int(clamped.rounded(.up))
        // The next page lies over the last by the strip's progress, so the mix
        // never dips to the page fill between two washes.
        back.wash = pages[lower]; front.wash = pages[upper]
        back.alphaValue = shown; front.alphaValue = lower == upper ? 0 : shown * (clamped - CGFloat(lower))
        isShown = shown >= 0.5
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { settle() }
    }

    /// Whether white text at `alpha` reads over the chosen wash where `rect`
    /// of `view` lies, on a page filled with `fill`: 3:1, WCAG's floor for
    /// large text, averaged along the text's middle line so a heading that
    /// starts on the deep colour isn't judged by its lightest end alone.
    func whiteInkHolds(over rect: NSRect, of view: NSView, fill: NSColor, alpha: CGFloat = 1) -> Bool {
        guard isShown, let page, pages.indices.contains(page), bounds.width > 0, bounds.height > 0 else { return false }
        var base: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { base = fill.usingColorSpace(.sRGB) }
        guard let base else { return false }
        let area = convert(rect, from: view), wash = pages[page]
        let paper = [base.redComponent, base.greenComponent, base.blueComponent]
        let cover = BrowserImportWashView.coverage(at: area.midY / bounds.height)
        let ratios = [area.minX, area.midX, area.maxX].map { x -> CGFloat in
            let behind = zip(paper, wash.color(at: x / bounds.width)).map { $0 + cover * ($1 - $0) }
            let ink = behind.map { $0 + alpha * (1 - $0) }
            return (Self.luminance(ink) + 0.05) / (Self.luminance(behind) + 0.05)
        }
        return ratios.reduce(0, +) / 3 >= 3
    }

    private static func luminance(_ rgb: [CGFloat]) -> CGFloat {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// White ink where it reads over the wash and the page's ink elsewhere, for
    /// every label and plain button under `container`; without a wash they
    /// return to their own. `BrowserImportInkOpaque` views keep theirs.
    func applyInk(under container: NSView, fill: NSColor) {
        guard !container.isHidden else { return }
        for view in container.subviews where !view.isHidden {
            switch view {
            case is BrowserImportInkOpaque: continue
            case let field as NSTextField where !field.isEditable:
                let text = field.cell?.cellSize(forBounds: field.bounds) ?? field.bounds.size
                let size = NSSize(width: min(text.width, field.bounds.width), height: min(text.height, field.bounds.height))
                let origin = NSPoint(x: 0, y: field.isFlipped ? 0 : field.bounds.height - size.height)
                var alpha: CGFloat = 1
                let own = originalInk.object(forKey: field) as? NSColor ?? field.textColor
                NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
                    alpha = own?.usingColorSpace(.sRGB)?.alphaComponent ?? 1
                }
                setInk(field, NSRect(origin: origin, size: size), fill: fill, alpha: alpha)
            case let button as NSButton:
                setInk(button, button.bounds, fill: fill, alpha: 1)
            default:
                applyInk(under: view, fill: fill)
            }
        }
    }

    /// Returns every label and plain button under `container` to its own ink.
    func clearInk(under container: NSView) {
        for view in container.subviews {
            switch view {
            case is BrowserImportInkOpaque: continue
            case let field as NSTextField where field.isEditable: continue
            case is NSTextField, is NSButton: view.appearance = nil; restoreInk(view)
            default: clearInk(under: view)
            }
        }
    }

    private func setInk(_ view: NSView, _ rect: NSRect, fill: NSColor, alpha: CGFloat) {
        let white = isShown && whiteInkHolds(over: rect, of: view, fill: fill, alpha: alpha)
        let ink = isShown ? NSAppearance(named: white ? .darkAqua : .aqua) : nil
        if view.appearance?.name != ink?.name { view.appearance = ink }
        // The page's greys lose their contrast over the wash's lighter colours.
        guard isShown, !white, bounds.height > 0,
              BrowserImportWashView.coverage(at: convert(rect, from: view).midY / bounds.height) > 0.1 else {
            restoreInk(view); return
        }
        if let field = view as? NSTextField {
            guard field.textColor !== Self.washInk else { return }
            originalInk.removeObject(forKey: field)
            guard let color = field.textColor, Self.isGrey(color, in: ink) else { return }
            originalInk.setObject(color, forKey: field); field.textColor = Self.washInk
        } else if let button = view as? NSButton, button.attributedTitle.length > 0 {
            let title = button.attributedTitle
            guard title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor !== Self.washInk else { return }
            originalInk.removeObject(forKey: button)
            guard let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                  Self.isGrey(color, in: ink) else { return }
            originalInk.setObject(title, forKey: button)
            let dark = NSMutableAttributedString(attributedString: title)
            dark.addAttribute(.foregroundColor, value: Self.washInk, range: NSRange(location: 0, length: dark.length))
            button.attributedTitle = dark
        }
    }

    /// Puts back a grey this backdrop replaced, unless its owner has set a new colour since.
    private func restoreInk(_ view: NSView) {
        guard let original = originalInk.object(forKey: view) else { return }
        originalInk.removeObject(forKey: view)
        if let field = view as? NSTextField, field.textColor === Self.washInk {
            field.textColor = original as? NSColor
        } else if let button = view as? NSButton, let title = original as? NSAttributedString,
                  button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor === Self.washInk {
            button.attributedTitle = title
        }
    }

    private let originalInk = NSMapTable<NSView, AnyObject>.weakToStrongObjects()
    private static let washInk = NSColor.black.withAlphaComponent(0.75)
    /// A grey lighter than near-black; coloured text such as errors keeps its colour.
    private static func isGrey(_ color: NSColor, in appearance: NSAppearance?) -> Bool {
        var rgb: NSColor?
        (appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance { rgb = color.usingColorSpace(.sRGB) }
        guard let rgb else { return false }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        return (channels.max()! - channels.min()!) < 0.12 && luminance(channels) > 0.05
    }
}

/// Views whose ink is their own, such as filled buttons; SwiftUI picks it per element.
protocol BrowserImportInkOpaque {}
extension NSHostingView: BrowserImportInkOpaque {}

///
/// the first deep at the left, the second at the right, with the dialog's
/// lighter blends between them.
struct BrowserImportWash: Equatable {
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

    /// The gradient's sRGB colour at a fraction of its width.
    func color(at fraction: CGFloat) -> [CGFloat] {
        func channels(_ color: UInt32) -> [CGFloat] { [16, 8, 0].map { CGFloat(color >> $0 & 0xff) / 255 } }
        let x = min(1, max(0, fraction))
        guard let upper = locations.firstIndex(where: { $0 >= x }), upper > 0 else { return channels(colors[0]) }
        let t = (x - locations[upper - 1]) / max(0.0001, locations[upper] - locations[upper - 1])
        return zip(channels(colors[upper - 1]), channels(colors[upper])).map { $0 + t * ($1 - $0) }
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
    /// How much of the wash shows at a fraction of the page's height.
    static func coverage(at fraction: CGFloat) -> CGFloat {
        guard let upper = fadeLocations.firstIndex(where: { $0 >= fraction }) else { return 0 }
        guard upper > 0 else { return 1 }
        let t = (fraction - fadeLocations[upper - 1]) / (fadeLocations[upper] - fadeLocations[upper - 1])
        return fadeLevels[upper - 1] + t * (fadeLevels[upper] - fadeLevels[upper - 1])
    }
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
