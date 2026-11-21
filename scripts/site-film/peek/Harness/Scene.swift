import AppKit
@testable import Parc
import ParcCore

let windowCornerRadius = WindowFrameThickness.windowCornerRadius
let frameThickness = CGFloat(WindowFrameThickness.standard)

@MainActor final class Stage: NSView {
    var windowRect = NSRect.zero
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: windowRect, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -22), blur: 60, color: NSColor.black.withAlphaComponent(0.30).cgColor)
        context.addPath(path); context.setFillColor(NSColor.white.cgColor); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        context.addPath(path); context.setFillColor(NSColor.white.cgColor); context.fillPath()
        context.restoreGState()
    }
}

@MainActor final class WindowSurface: NSView {
    var theme: CGImage?
    var material = NSColor(white: CGFloat(ThemeRenderMath.lightMaterial.x), alpha: 1)
    var pageCard = NSRect.zero
    var cardRadius = PageCard.cornerRadius
    var drawPage: (NSRect) -> Void = { _ in }
    var pageScale: CGFloat = 1 { didSet { if pageScale != oldValue { needsDisplay = true } } }
    var washAlpha: CGFloat = 0 { didSet { if washAlpha != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let shape = CGPath(roundedRect: bounds, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius, transform: nil)
        context.saveGState()
        context.addPath(shape); context.clip()
        drawBackground(context)
        context.saveGState()
        if pageScale != 1 {
            context.translateBy(x: pageCard.midX, y: pageCard.midY)
            context.scaleBy(x: pageScale, y: pageScale)
            context.translateBy(x: -pageCard.midX, y: -pageCard.midY)
        }
        drawCardShadow(context)
        let card = CGPath(roundedRect: pageCard, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
        context.saveGState()
        context.addPath(card); context.clip()
        context.interpolationQuality = .high
        drawPage(pageCard)
        context.restoreGState()
        context.restoreGState()
        if washAlpha > 0 {
            context.saveGState()
            context.clip(to: pageCard)
            context.setAlpha(washAlpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawBackground(context)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawBackground(_ context: CGContext) {
        material.setFill(); bounds.fill()
        if let theme {
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(theme, in: bounds)
            context.restoreGState()
        }
    }

    private func drawCardShadow(_ context: CGContext) {
        let scale: CGFloat = 2
        guard let image = ContentShadowImage.image(scale: scale, radius: cardRadius) else { return }
        let frame = ContentShadowImage.frame(around: pageCard)
        let edge = ContentShadowImage.outset + cardRadius + ContentShadowImage.straight
        let side = ContentShadowImage.size(radius: cardRadius)
        let px = { (v: CGFloat) in Int((v * scale).rounded()) }
        let xs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, edge, frame.minX, edge), (edge, 1, frame.minX + edge, frame.width - 2 * edge),
                                                           (side - edge, edge, frame.maxX - edge, edge)]
        let ys: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, edge, frame.minY, edge), (edge, 1, frame.minY + edge, frame.height - 2 * edge),
                                                           (side - edge, edge, frame.maxY - edge, edge)]
        for (sy, sh, dy, dh) in ys {
            for (sx, sw, dx, dw) in xs {
                let source = CGRect(x: px(sx), y: px(sy), width: max(1, px(sx + sw) - px(sx)), height: max(1, px(sy + sh) - px(sy)))
                guard let piece = image.cropping(to: source), dw > 0, dh > 0 else { continue }
                context.saveGState()
                context.translateBy(x: dx, y: dy + dh); context.scaleBy(x: 1, y: -1)
                context.draw(piece, in: CGRect(x: 0, y: 0, width: dw, height: dh))
                context.restoreGState()
            }
        }
    }
}

@MainActor final class TrafficLights: NSView {
    var lit = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let fills: [(UInt32, UInt32)] = [(0xFF5F57, 0xE0443E), (0xFEBC2E, 0xDEA123), (0x28C840, 0x1AAB29)]
        let dimension = WindowStandardButtons.buttonDimension, space = WindowStandardButtons.buttonSpace
        for (index, colors) in fills.enumerated() {
            let slot = NSRect(x: CGFloat(index) * (dimension + space), y: (bounds.height - dimension) / 2, width: dimension, height: dimension)
            if lit {
                hex(colors.0).setFill(); NSBezierPath(ovalIn: slot).fill()
                hex(colors.1, 0.9).setStroke()
                let ring = NSBezierPath(ovalIn: slot.insetBy(dx: 0.25, dy: 0.25)); ring.lineWidth = 0.5; ring.stroke()
            } else {
                NSColor.black.withAlphaComponent(0.1).setFill()
                NSBezierPath(ovalIn: slot.insetBy(dx: 1, dy: 1)).fill()
            }
        }
    }
}

@MainActor final class WindowEdge: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: windowCornerRadius, yRadius: windowCornerRadius)
        outer.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.22).setStroke(); outer.stroke()
        let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: windowCornerRadius - 0.75, yRadius: windowCornerRadius - 0.75)
        inner.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.45).setStroke(); inner.stroke()
    }
}

@MainActor final class Pointer: NSView {
    var location: NSPoint? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let location else { return }
        let cursor = NSCursor.arrow
        let image = cursor.image, hot = cursor.hotSpot
        image.draw(in: NSRect(x: location.x - hot.x, y: location.y - hot.y, width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor final class BrowserScene {
    let stage: Stage
    let surface: WindowSurface
    let sidebar: SidebarView
    let lights = TrafficLights()
    let edge: WindowEdge
    let pointer: Pointer
    let scenario: Scenario
    let windowRect: NSRect
    let themeSurface: ThemeRendererView

    init(size: NSSize, windowRect: NSRect, scale: CGFloat, pagePath: String) {
        let aqua = NSAppearance(named: .aqua)!
        scenario = ScenarioBuilder.make()
        self.windowRect = windowRect
        stage = Stage(frame: NSRect(origin: .zero, size: size))
        stage.appearance = aqua
        stage.windowRect = windowRect
        let local = NSRect(origin: .zero, size: windowRect.size)
        themeSurface = ThemeRendererView(frame: local)
        themeSurface.appearance = aqua
        themeSurface.theme = scenario.work.theme
        surface = WindowSurface(frame: windowRect)
        surface.theme = ThemeReadback.image(of: themeSurface, scale: scale)
        let width = CGFloat(scenario.state.settings.sidebarWidth)
        let frames = SidebarChromeFrames(bounds: local, sidebarWidth: width, presentation: .locked, placement: .locked,
                                         thickness: frameThickness)
        surface.pageCard = frames.pageHost
        if let page = NSImage(contentsOfFile: pagePath) {
            surface.drawPage = { card in
                NSColor.white.setFill(); card.fill()
                let scale = card.width / page.size.width
                page.draw(in: NSRect(x: card.minX, y: card.minY, width: card.width, height: page.size.height * scale),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            }
        } else {
            surface.drawPage = { ArticlePage.draw(in: $0) }
        }
        stage.addSubview(surface)
        sidebar = SidebarView(frame: frames.sidebar)
        sidebar.appearance = aqua
        sidebar.requestTabFavicon = { tab, completion in completion(Favicons.image(for: tab)) }
        sidebar.requestSavedFavicon = { tab, completion in completion(Favicons.image(for: tab)) }
        sidebar.canSelectSpace = { _, _ in true }
        sidebar.onNewSpace = {}
        sidebar.onClearToday = {}
        sidebar.onNewTab = {}
        sidebar.palette = themeSurface.palette
        surface.addSubview(sidebar)
        sidebar.render(state: scenario.state, focusedTabID: scenario.selected.id, loading: [], canBack: true, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let end = Date().addingTimeInterval(0.6)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        sidebar.needsLayout = true
        sidebar.layoutSubtreeIfNeeded()
        edge = WindowEdge(frame: local)
        surface.addSubview(edge)
        if let buttons = Self.descendants(sidebar).first(where: { $0 is WindowStandardButtons }), !buttons.isHidden {
            lights.frame = surface.convert(buttons.bounds, from: buttons)
            surface.addSubview(lights)
        }
        pointer = Pointer(frame: local)
        surface.addSubview(pointer)
        surface.needsDisplay = true
    }

    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    var tabRows: [SidebarTabRow] { Self.descendants(sidebar).compactMap { $0 as? SidebarTabRow } }

    func row(titled title: String) -> SidebarTabRow? {
        tabRows.first { row in Self.descendants(row).contains { ($0 as? NSTextField)?.stringValue == title } }
    }

    func setHover(_ hovered: SidebarTabRow?) {
        for row in tabRows {
            guard let background = row.subviews.compactMap({ $0 as? SidebarRowBackgroundView }).first else { continue }
            var state = background.appearanceState
            state.hovered = row === hovered
            background.appearanceState = state
            let close = row.subviews.compactMap { $0 as? SidebarRowActionButton }
            if close.count == 1, close[0].isHidden != (row !== hovered) {
                close[0].isHidden = row !== hovered
                row.needsLayout = true
            }
        }
    }

    func render(_ rect: NSRect, pixelsWide: Int, pixelsHigh: Int) -> NSBitmapImageRep {
        stage.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = rect.size
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { stage.cacheDisplay(in: rect, to: bitmap) }
        return bitmap
    }

    func renderLayers(scale: CGFloat, flip: Bool) -> CGImage? {
        stage.wantsLayer = true
        stage.layoutSubtreeIfNeeded()
        for view in Self.descendants(stage) {
            guard let layer = view.layer else { continue }
            layer.setNeedsDisplay(); layer.displayIfNeeded()
        }
        let width = Int(stage.bounds.width * scale), height = Int(stage.bounds.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let layer = stage.layer else { return nil }
        if flip { context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1) }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return context.makeImage()
    }

    func report() -> [String] {
        var lines: [String] = []
        lines.append("window \(windowRect) sidebar \(sidebar.frame) page card \(surface.pageCard)")
        lines.append("theme image \(surface.theme.map { "\($0.width)x\($0.height)" } ?? "none") palette dark=\(themeSurface.palette.isDark)")
        lines.append("hosting views: " + Self.descendants(sidebar).filter { String(describing: type(of: $0)).contains("Hosting") }
            .map { "\(type(of: $0)) \(surface.convert($0.bounds, from: $0)) hidden=\($0.isHiddenOrHasHiddenAncestor)" }.joined(separator: "; "))
        lines.append("traffic lights \(lights.superview == nil ? "absent" : "\(lights.frame)")")
        for row in tabRows {
            let title = Self.descendants(row).compactMap { $0 as? NSTextField }.first?.stringValue ?? "?"
            lines.append("row \(title) \(surface.convert(row.bounds, from: row)) hidden=\(row.isHiddenOrHasHiddenAncestor)")
        }
        return lines
    }
}
