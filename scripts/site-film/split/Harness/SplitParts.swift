import AppKit
import SwiftUI

func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
    let x = min(1, max(0, t))
    func sample(_ a: Double, _ b: Double, _ u: Double) -> Double {
        3 * a * u * (1 - u) * (1 - u) + 3 * b * u * u * (1 - u) + u * u * u
    }
    var lo = 0.0, hi = 1.0, u = x
    for _ in 0..<40 {
        let value = sample(x1, x2, u)
        if abs(value - x) < 1e-7 { break }
        if value < x { lo = u } else { hi = u }
        u = (lo + hi) / 2
    }
    return sample(y1, y2, u)
}

func easeInOut(_ t: Double) -> Double { bezier(0.42, 0, 0.58, 1, t) }
func easeOut(_ t: Double) -> Double { bezier(0, 0, 0.58, 1, t) }
func caDefault(_ t: Double) -> Double { bezier(0.25, 0.1, 0.25, 1, t) }
func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

func spring(_ t: Double) -> Double {
    guard t > 0 else { return 0 }
    let omega = 2 * Double.pi / 0.4, zeta = 0.7
    let damped = omega * sqrt(1 - zeta * zeta)
    return 1 - exp(-zeta * omega * t) * (cos(damped * t) + (zeta * omega / damped) * sin(damped * t))
}

@MainActor final class PageArt {
    let image: NSImage
    let width: CGFloat
    let fullHeight: CGFloat
    let height: CGFloat
    let band: (CGFloat, CGFloat)
    let fills: Bool
    let maxScale: CGFloat
    let top: NSColor
    let base: NSColor
    var mirrored: NSImage?

    init(path: String, band: (CGFloat, CGFloat), fills: Bool = false, maxScale: CGFloat, height cropped: CGFloat? = nil,
         baseSample: (Int, Int)? = nil, mirrors: Bool = false) {
        let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path)))!
        width = CGFloat(rep.pixelsWide); fullHeight = CGFloat(rep.pixelsHigh)
        height = cropped ?? fullHeight
        rep.size = NSSize(width: width, height: fullHeight)
        image = NSImage(size: rep.size); image.addRepresentation(rep)
        self.band = band; self.fills = fills; self.maxScale = maxScale
        top = rep.colorAt(x: 4, y: 4)!.usingColorSpace(.sRGB)!
        let sample = baseSample ?? (4, Int(height) - 4)
        base = rep.colorAt(x: sample.0, y: sample.1)!.usingColorSpace(.sRGB)!
        if mirrors {
            let source = image
            mirrored = NSImage(size: rep.size, flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.translateBy(x: 0, y: rect.height); context.scaleBy(x: 1, y: -1)
                source.draw(in: rect)
                return true
            }
        }
    }

    func placement(in size: NSSize) -> (scale: CGFloat, x: CGFloat) {
        let scale = fills ? max(size.width / width, size.height / height) : min(maxScale, size.width / (band.1 - band.0))
        var x = size.width / 2 - (band.0 + band.1) / 2 * scale
        if width * scale >= size.width { x = min(0, max(size.width - width * scale, x)) } else { x = (size.width - width * scale) / 2 }
        return (scale, x)
    }

    func point(_ px: CGFloat, _ py: CGFloat, in size: NSSize) -> NSPoint {
        let place = placement(in: size)
        return NSPoint(x: place.x + px * place.scale, y: py * place.scale)
    }

    func draw(in rect: NSRect) {
        base.setFill(); rect.fill()
        let place = placement(in: rect.size)
        let destination = NSRect(x: rect.minX + place.x, y: rect.minY, width: width * place.scale, height: height * place.scale)
        image.draw(in: destination, from: NSRect(x: 0, y: fullHeight - height, width: width, height: height),
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        if let mirrored, destination.maxY < rect.maxY {
            mirrored.draw(in: destination.offsetBy(dx: 0, dy: destination.height), from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }
}

@MainActor final class PageView: NSView {
    let art: PageArt
    var painted = true { didSet { needsDisplay = true } }
    init(art: PageArt) { self.art = art; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        if painted { art.draw(in: bounds) }
    }
}

@MainActor final class PaneStandIn: NSView {
    let page: PageView
    let toolbar = BrowserToolbarView(frame: .zero)
    let highlight = SplitPaneHighlight()
    var showsBar = false { didSet { needsLayout = true } }
    init(art: PageArt) {
        page = PageView(art: art)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(page)
        toolbar.isHidden = true
        addSubview(toolbar)
        highlight.attach(to: self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let bar: CGFloat = showsBar ? BrowserToolbarView.height : 0
        toolbar.isHidden = !showsBar
        toolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bar)
        page.frame = NSRect(x: 0, y: bar, width: bounds.width, height: bounds.height - bar)
        page.needsDisplay = true
        highlight.layout(bounds: bounds, cornerRadius: layer?.cornerRadius ?? 0)
        if let layer, highlight.layer.superlayer === layer, layer.sublayers?.last !== highlight.layer {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            highlight.layer.removeFromSuperlayer(); layer.addSublayer(highlight.layer)
            CATransaction.commit()
        }
    }
    var revealViews: [NSView] = []
    func findRevealViews() {
        toolbar.setControlsRevealed(true, duration: nil)
        let shown = Set(toolbar.subviews.filter { $0.alphaValue > 0.99 }.map(ObjectIdentifier.init))
        toolbar.setControlsRevealed(false, duration: nil)
        revealViews = toolbar.subviews.filter { shown.contains(ObjectIdentifier($0)) && $0.alphaValue < 0.01 }
    }
    var splitButton: NSView? {
        toolbar.subviews.compactMap { $0 as? SplitPaneControl }.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }.first
    }
}

struct MenuRow {
    let title: String
    let image: NSImage?
    let enabled: Bool
    let separator: Bool
}

@MainActor enum MenuMetrics {
    static let inset: CGFloat = 5
    static let row: CGFloat = 24
    static let separator: CGFloat = 11
    static let font = NSFont.menuFont(ofSize: 13)
    static func size(_ rows: [MenuRow]) -> NSSize {
        let text = rows.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let height = rows.reduce(2 * inset) { $0 + ($1.separator ? separator : row) }
        return NSSize(width: ceil(inset + 10 + 18 + 8 + text + 34 + inset), height: height)
    }
    static func rowRects(_ rows: [MenuRow], origin: NSPoint) -> [NSRect] {
        let width = size(rows).width
        var y = origin.y + inset
        return rows.map { row in
            let height = row.separator ? separator : self.row
            defer { y += height }
            return NSRect(x: origin.x + inset, y: y, width: width - 2 * inset, height: height)
        }
    }
}

@MainActor final class Overlay: NSView {
    struct Pill { var content: NSRect; var url: String; var alpha: CGFloat }
    struct Menu { var origin: NSPoint; var rows: [MenuRow]; var highlighted: Int?; var alpha: CGFloat }
    struct Toast { var image: NSImage; var frame: NSRect; var anchor: NSPoint; var scale: CGFloat; var alpha: CGFloat }
    struct Ring { var frame: NSRect; var radius: CGFloat; var path: CGPath; var width: CGFloat; var color: CGColor; var opacity: CGFloat }
    var rings: [Ring] = [] { didSet { needsDisplay = true } }
    var pill: Pill? { didSet { needsDisplay = true } }
    var panel: Menu? { didSet { needsDisplay = true } }
    var toast: Toast? { didSet { needsDisplay = true } }
    var pillBackground = NSColor.white
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func pillText(_ url: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let sentence: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.7)]
        let link: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.3)]
        let text = NSMutableAttributedString(string: "Open ", attributes: sentence)
        text.append(NSAttributedString(string: url, attributes: link))
        text.append(NSAttributedString(string: " in Split View", attributes: sentence))
        return text
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for ring in rings where ring.opacity > 0 {
            context.saveGState()
            context.addPath(CGPath(roundedRect: ring.frame, cornerWidth: ring.radius, cornerHeight: ring.radius, transform: nil))
            context.clip()
            context.translateBy(x: ring.frame.minX, y: ring.frame.minY)
            context.setAlpha(ring.opacity)
            context.addPath(ring.path)
            context.setLineWidth(ring.width)
            context.setLineJoin(.round); context.setLineCap(.round)
            context.setStrokeColor(ring.color)
            context.strokePath()
            context.restoreGState()
        }
        if let pill, pill.alpha > 0 { drawPill(pill, context) }
        if let panel, panel.alpha > 0 { drawMenu(panel, context) }
        if let toast, toast.alpha > 0 {
            context.saveGState()
            context.setAlpha(toast.alpha)
            context.translateBy(x: toast.anchor.x, y: toast.anchor.y)
            context.scaleBy(x: max(0.0001, toast.scale), y: max(0.0001, toast.scale))
            context.translateBy(x: -toast.anchor.x, y: -toast.anchor.y)
            toast.image.draw(in: toast.frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                             hints: [.interpolation: NSImageInterpolation.high.rawValue])
            context.restoreGState()
        }
    }

    private func drawPill(_ pill: Pill, _ context: CGContext) {
        let text = Self.pillText(pill.url)
        let size = text.size()
        let rect = NSRect(x: pill.content.minX + 10, y: pill.content.maxY - 10 - 24, width: ceil(size.width) + 18, height: 24)
        context.saveGState()
        context.setAlpha(pill.alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 5, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        pillBackground.setFill(); shape.fill()
        context.restoreGState()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 11.75, yRadius: 11.75)
        border.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.1).setStroke(); border.stroke()
        text.draw(at: NSPoint(x: rect.minX + 9, y: rect.midY - size.height / 2))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawMenu(_ menu: Menu, _ context: CGContext) {
        let size = MenuMetrics.size(menu.rows)
        let panel = NSRect(origin: menu.origin, size: size)
        context.saveGState()
        context.setAlpha(menu.alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let shape = NSBezierPath(roundedRect: panel, xRadius: 11, yRadius: 11)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        NSColor(white: 0.975, alpha: 1).setFill(); shape.fill()
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        NSColor(white: 0.975, alpha: 1).setFill(); shape.fill()
        context.restoreGState()
        let border = NSBezierPath(roundedRect: panel.insetBy(dx: 0.25, dy: 0.25), xRadius: 10.75, yRadius: 10.75)
        border.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.14).setStroke(); border.stroke()
        let rects = MenuMetrics.rowRects(menu.rows, origin: menu.origin)
        for (index, row) in menu.rows.enumerated() {
            let rect = rects[index]
            if row.separator {
                NSColor.black.withAlphaComponent(0.1).setFill()
                NSRect(x: rect.minX + 10, y: rect.midY - 0.25, width: rect.width - 20, height: 0.5).fill()
                continue
            }
            let lit = menu.highlighted == index && row.enabled
            if lit {
                NSColor.controlAccentColor.usingColorSpace(.sRGB)!.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            if let image = row.image {
                let side = image.size
                image.draw(in: NSRect(x: rect.minX + 10, y: rect.midY - side.height / 2, width: side.width, height: side.height),
                           from: .zero, operation: .sourceOver, fraction: row.enabled ? 1 : 0.35, respectFlipped: true, hints: nil)
            }
            let color: NSColor = lit ? .white : row.enabled ? NSColor.black.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.26)
            let attributed = NSAttributedString(string: row.title, attributes: [.font: MenuMetrics.font, .foregroundColor: color])
            let textSize = attributed.size()
            attributed.draw(at: NSPoint(x: rect.minX + 10 + 18 + 8, y: rect.midY - textSize.height / 2))
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

@MainActor enum ToastArt {
    static func render(urls: [URL], theme: SpaceTheme, size: NSSize) -> (image: NSImage, card: NSRect)? {
        let state = ParcToastState(content: .copiedLinks(urls), theme: theme)
        state.showing = true
        state.reduceMotion = true
        let actions = ParcToastActions(tap: nil, accessory: nil, dismiss: {}, share: { _ in }, frames: { _ in }, retry: nil)
        let view = ParcToastCard(state: state, actions: actions)
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let cg = renderer.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let card = NSRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2, width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
        return (NSImage(cgImage: cg, size: size), card)
    }
}
