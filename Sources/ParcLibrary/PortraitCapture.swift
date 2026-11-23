import AppKit
import ParcCore
import ParcEasels
import ParcKit
import ParcNotes

struct PortraitCaptureOptions {
    enum Background: Int, CaseIterable { case color, page, desktop }
    var background: Background
    var fraction: Double
    var watermark: Bool
    init(defaults: UserDefaults = .standard) {
        background = Background(rawValue: defaults.integer(forKey: "parc.capture.portrait.background")) ?? .color
        let saved = defaults.object(forKey: "parc.capture.portrait.color") as? Double ?? 0.95
        fraction = saved.isFinite ? min(1, max(0, saved)) : 0.95
        watermark = !defaults.bool(forKey: "parc.capture.portrait.hideWatermark")
    }
    func save(to defaults: UserDefaults = .standard) {
        saveBackground(to: defaults); saveColor(to: defaults); saveWatermark(to: defaults)
    }
    func saveBackground(to defaults: UserDefaults = .standard) {
        defaults.set(background.rawValue, forKey: "parc.capture.portrait.background")
    }
    func saveColor(to defaults: UserDefaults = .standard) {
        defaults.set(fraction, forKey: "parc.capture.portrait.color")
    }
    func saveWatermark(to defaults: UserDefaults = .standard) {
        defaults.set(!watermark, forKey: "parc.capture.portrait.hideWatermark")
    }
    var settings: CaptureFrameSettings {
        CaptureFrameSettings(background: CaptureFrameSettings.Background(rawValue: background.rawValue) ?? .color,
                             fraction: fraction, watermark: watermark)
    }
}

package enum PortraitCaptureError: LocalizedError {
    case resources, encoding, desktopUnavailable
    package var errorDescription: String? {
        switch self {
        case .desktopUnavailable: return "The desktop wallpaper is unavailable. Choose another background."
        case .resources: return "Portrait’s bundled colors could not be loaded."
        case .encoding: return "The portrait image could not be created. Try again."
        }
    }
}

@MainActor
enum PortraitCaptureRenderer {
    private struct Preset: Decodable {
        let red: CGFloat, green: CGFloat, blue: CGFloat, colorSpace: String, page: Int, index: Int
        var color: NSColor? {
            switch colorSpace {
            case "sRGB": return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            case "displayP3": return NSColor(displayP3Red: red, green: green, blue: blue, alpha: 1)
            case "linearSRGB":
                guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
                      let value = CGColor(colorSpace: space, components: [red, green, blue, 1]) else { return nil }
                return NSColor(cgColor: value)
            default: return nil
            }
        }
    }
    static func palette(bundle: Bundle = .main, subdirectory: String = "ThemeEditor") -> [NSColor] {
        guard let url = bundle.url(forResource: "presets", withExtension: "json", subdirectory: subdirectory),
              let data = try? Data(contentsOf: url), let records = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        let first = records.filter { $0.page == 0 }.sorted { $0.index < $1.index }
        guard first.map(\.index) == Array(0..<9) else { return [] }
        return first.compactMap { $0.color }
    }
    static func blendedColor(_ fraction: Double, palette: [NSColor]) -> NSColor? {
        guard palette.count == 9, fraction.isFinite else { return nil }
        let position = min(1, max(0, fraction)) * 8, lower = Int(position)
        return palette[lower].blended(withFraction: position - Double(lower), of: palette[min(8, lower + 1)])
    }
    static func margin(content: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0 else { return 0 }
        return min(160, max(40, (sqrt(content.width * content.height) * 0.08).rounded()))
    }
    static func geometry(pixels: CGSize, backingScale: CGFloat, fitting box: CGSize? = nil) -> PortraitCaptureGeometry? {
        guard pixels.width.isFinite, pixels.height.isFinite, pixels.width >= 1, pixels.height >= 1,
              backingScale.isFinite, backingScale > 0 else { return nil }
        let width = pixels.width.rounded(), height = pixels.height.rounded()
        let side = CGFloat(EaselImagePlacement.maximumSide), area = CGFloat(EaselImagePlacement.maximumPixels)
        let wanted = (margin(content: CGSize(width: width / backingScale, height: height / backingScale)) * backingScale).rounded()
        let smallest = (40 * backingScale).rounded()
        let sideRoom = floor((side - max(width, height)) / 2)
        let areaRoom = floor((sqrt((width - height) * (width - height) + 4 * area) - width - height) / 4)
        let inset = min(wanted, sideRoom, areaRoom)
        var result: PortraitCaptureGeometry
        if inset >= smallest {
            result = PortraitCaptureGeometry(canvas: CGSize(width: width + inset * 2, height: height + inset * 2),
                content: CGRect(x: inset, y: inset, width: width, height: height), density: backingScale)
        } else {
            let full = PortraitCaptureGeometry(canvas: CGSize(width: width + smallest * 2, height: height + smallest * 2),
                content: CGRect(x: smallest, y: smallest, width: width, height: height), density: backingScale)
            var factor = min(side / full.canvas.width, side / full.canvas.height,
                             sqrt(area / (full.canvas.width * full.canvas.height)))
            result = full.scaled(by: factor)
            while !result.fitsOutputLimits { factor *= 0.999; result = full.scaled(by: factor) }
        }
        if let box, box.width >= 1, box.height >= 1 {
            result = result.scaled(by: min(box.width / result.canvas.width, box.height / result.canvas.height))
        }
        return result
    }
    static func render(source: CGImage, options: PortraitCaptureOptions, palette: [NSColor],
                       pageColor: NSColor?, desktop: NSImage?, backingScale: CGFloat = 1,
                       fitting box: CGSize? = nil) throws -> CGImage {
        guard backingScale.isFinite, backingScale >= 1, backingScale <= 4,
              let geometry = geometry(pixels: CGSize(width: source.width, height: source.height),
                                      backingScale: backingScale, fitting: box) else { throw PortraitCaptureError.encoding }
        return try render(source: source, options: options, palette: palette, pageColor: pageColor, desktop: desktop, geometry: geometry)
    }
    static func render(source: CGImage, options: PortraitCaptureOptions, palette: [NSColor],
                       pageColor: NSColor?, desktop: NSImage?, geometry: PortraitCaptureGeometry) throws -> CGImage {
        guard options.background != .desktop || desktop != nil else { throw PortraitCaptureError.desktopUnavailable }
        guard let selected = blendedColor(options.fraction, palette: palette),
              let fallback = blendedColor(0.95, palette: palette) else { throw PortraitCaptureError.resources }
        let color = options.background == .page ? (pageColor?.usingColorSpace(.sRGB) ?? fallback) : selected
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = source.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? sRGB
        guard let context = CGContext(data: nil, width: Int(geometry.canvas.width), height: Int(geometry.canvas.height),
                                      bitsPerComponent: source.bitsPerComponent > 8 ? 16 : 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PortraitCaptureError.encoding }
        let scale = geometry.density
        let size = CGSize(width: geometry.canvas.width / scale, height: geometry.canvas.height / scale)
        let canvas = CGRect(origin: .zero, size: size)
        let content = CGRect(x: geometry.content.minX / scale, y: geometry.content.minY / scale,
                             width: geometry.content.width / scale, height: geometry.content.height / scale)
        let frame = content.insetBy(dx: -8, dy: -8)
        let priorContext = NSGraphicsContext.current
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        graphics.imageInterpolation = .high
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.current = priorContext }
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        if options.background == .desktop, let desktop {
            desktop.draw(in: canvas, from: coverRect(desktop.size, filling: size), operation: .copy, fraction: 1)
        } else {
            context.setFillColor(color.cgColor); context.fill(canvas)
            drawBackground(context, color: color, size: size)
        }
        context.setBlendMode(.normal)
        let rounded = roundedPath(frame, radius: 10)
        context.addPath(rounded); context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6))
        context.setLineWidth(1); context.strokePath()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4 * scale), blur: 16 * scale,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.addPath(rounded); context.strokePath()
        context.restoreGState()
        context.addPath(rounded); context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5)); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(roundedPath(geometry.content, radius: 6 * scale)); context.clip()
        let exact = geometry.content.size == CGSize(width: source.width, height: source.height)
        context.interpolationQuality = exact ? .none : .high
        context.draw(source, in: geometry.content)
        context.restoreGState()
        if options.watermark {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            let mark = Watermark(center: CGPoint(x: size.width / 2, y: content.minY / 2), margin: content.minY)
            let backdrop = options.background == .desktop ? sampledBackdrop(context, rect: mark.bounds, scale: scale) : nil
            mark.draw(in: context, ink: watermarkInk(on: backdrop ?? color))
            context.restoreGState()
        }
        guard let result = context.makeImage() else { throw PortraitCaptureError.encoding }
        return result
    }
    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let corner = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }
    private static func coverRect(_ image: CGSize, filling size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale = max(size.width / image.width, size.height / image.height)
        let visible = CGSize(width: size.width / scale, height: size.height / scale)
        return CGRect(x: (image.width - visible.width) / 2, y: (image.height - visible.height) / 2,
                      width: visible.width, height: visible.height)
    }
    private static func drawBackground(_ context: CGContext, color: NSColor, size: CGSize) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let pale = min(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) >= 0.8
        func gradient(_ color: NSColor, alpha: CGFloat, from: CGPoint, to: CGPoint, blend: CGBlendMode) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]) else { return }
            context.setBlendMode(blend); context.drawLinearGradient(gradient, start: from, end: to, options: [])
        }
        func shifted(_ delta: CGFloat) -> NSColor {
            let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
            let high = max(r, g, b), low = min(r, g, b), difference = high - low
            let lightness = (high + low) / 2
            guard difference > 0 else { return rgb }
            let saturation = difference / (lightness > 0.5 ? 2 - high - low : high + low)
            var hue: CGFloat
            if high == r { hue = (g - b) / difference + (g < b ? 6 : 0) }
            else if high == g { hue = (b - r) / difference + 2 }
            else { hue = (r - g) / difference + 4 }
            hue = (hue / 6 + delta + 1).truncatingRemainder(dividingBy: 1)
            let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
            let p = 2 * lightness - q
            func channel(_ offset: CGFloat) -> CGFloat {
                let t = (hue + offset + 1).truncatingRemainder(dividingBy: 1)
                if t < 1 / 6 { return p + (q - p) * 6 * t }
                if t < 0.5 { return q }
                if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
                return p
            }
            return NSColor(srgbRed: channel(1 / 3), green: channel(0), blue: channel(-1 / 3), alpha: 1)
        }
        gradient(pale ? .black : shifted(-1 / 12), alpha: pale ? 0.07 : 0.95,
                 from: .zero, to: CGPoint(x: size.width, y: size.height), blend: .hardLight)
        gradient(pale ? .black : shifted(1 / 12), alpha: pale ? 0.07 : 0.95,
                 from: CGPoint(x: size.width, y: size.height), to: .zero, blend: .softLight)
        gradient(pale ? .black : .white, alpha: pale ? 0.07 : 0.95,
                 from: CGPoint(x: 0, y: size.height), to: .zero, blend: pale ? .normal : .softLight)
    }
    private static func sampledBackdrop(_ context: CGContext, rect: CGRect, scale: CGFloat) -> NSColor? {
        guard let image = context.makeImage() else { return nil }
        let pixels = CGRect(x: rect.minX * scale, y: CGFloat(image.height) - rect.maxY * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        guard let crop = image.cropping(to: pixels),
              let sample = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        sample.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        guard let bytes = sample.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var red = 0.0, green = 0.0, blue = 0.0
        for y in 0..<crop.height { for x in 0..<crop.width {
            let index = y * sample.bytesPerRow + x * 4
            red += Double(bytes[index]); green += Double(bytes[index + 1]); blue += Double(bytes[index + 2])
        } }
        let total = Double(crop.width * crop.height) * 255
        return NSColor(srgbRed: red / total, green: green / total, blue: blue / total, alpha: 1)
    }
    static func watermarkInk(on color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        let light = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return light >= 0.75 ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45) : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.75)
    }
    @MainActor struct Watermark {
        static let caption = "Captured in"
        let font: NSFont
        let textWidth: CGFloat
        let markSize: CGSize
        let gap: CGFloat
        let origin: CGPoint

        init(center: CGPoint, margin: CGFloat) {
            font = NSFont.systemFont(ofSize: min(28, max(10, margin * 0.3)), weight: .semibold)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: Self.caption, attributes: [.font: font]))
            textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let outline = ParcBrandMark.monochromeBounds
            let height = font.capHeight * 1.3
            markSize = CGSize(width: height * outline.width / outline.height, height: height)
            gap = font.pointSize * 0.3
            let width = textWidth + gap + markSize.width
            origin = CGPoint(x: center.x - width / 2, y: center.y - font.capHeight / 2)
        }

        var markRect: CGRect {
            CGRect(x: origin.x + textWidth + gap, y: origin.y, width: markSize.width, height: markSize.height)
        }

        var bounds: CGRect {
            CGRect(x: origin.x, y: origin.y + font.descender, width: markRect.maxX - origin.x,
                   height: max(markSize.height, font.ascender) - font.descender).insetBy(dx: -4, dy: -2)
        }

        func draw(in context: CGContext, ink: NSColor) {
            context.saveGState()
            context.setFillColor(ink.cgColor)
            context.textMatrix = .identity
            context.textPosition = origin
            let colored = NSAttributedString(string: Self.caption, attributes: [.font: font, .foregroundColor: ink])
            CTLineDraw(CTLineCreateWithAttributedString(colored), context)
            let outline = ParcBrandMark.monochromeBounds
            let rect = markRect
            let scale = rect.height / outline.height
            var transform = CGAffineTransform(translationX: rect.minX, y: rect.maxY)
                .scaledBy(x: scale, y: -scale)
                .translatedBy(x: -outline.minX, y: -outline.minY)
            if let path = ParcBrandMark.monochromePath.copy(using: &transform) {
                context.addPath(path); context.fillPath()
            }
            context.restoreGState()
        }
    }
}

struct PortraitCaptureGeometry: Equatable {
    let canvas: CGSize
    let content: CGRect
    let density: CGFloat

    var fitsOutputLimits: Bool {
        canvas.width <= CGFloat(EaselImagePlacement.maximumSide) && canvas.height <= CGFloat(EaselImagePlacement.maximumSide)
            && canvas.width * canvas.height <= CGFloat(EaselImagePlacement.maximumPixels)
    }

    func scaled(by factor: CGFloat) -> PortraitCaptureGeometry {
        guard factor.isFinite, factor > 0, factor < 1 else { return self }
        let width = max(1, floor(canvas.width * factor + 0.001)), height = max(1, floor(canvas.height * factor + 0.001))
        let inset = max(0, min((content.minX * factor).rounded(), floor((min(width, height) - 1) / 2)))
        return PortraitCaptureGeometry(canvas: CGSize(width: width, height: height),
            content: CGRect(x: inset, y: inset, width: width - inset * 2, height: height - inset * 2),
            density: density * factor)
    }
}

@MainActor
package struct PortraitCaptureComposition {
    var options: PortraitCaptureOptions
    let palette: [NSColor]
    let pageColor: NSColor?
    let desktop: NSImage?
    var backingScale: CGFloat = 1

    func render(_ source: CGImage, reduction: CGFloat = 1) throws -> (image: CGImage, density: CGFloat) {
        guard backingScale.isFinite, backingScale >= 1, backingScale <= 4,
              let geometry = PortraitCaptureRenderer.geometry(pixels: CGSize(width: source.width, height: source.height),
                                                              backingScale: backingScale)?.scaled(by: reduction) else {
            throw PortraitCaptureError.encoding
        }
        let image = try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
                                                       pageColor: pageColor, desktop: desktop, geometry: geometry)
        return (image, geometry.density)
    }
}

enum PortraitCaptureLayout {
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 10
    static let headerHeight: CGFloat = 44
    static let tileGap: CGFloat = 8
    static let swatchHeight: CGFloat = 50
    static let tileHeight: CGFloat = 70
    static let swatchCorner: CGFloat = 7
    static let sliderHeight: CGFloat = 24
    static let buttonHeight: CGFloat = 38
    static let buttonGap: CGFloat = 8
    static var width: CGFloat { CapturePresentation.paletteWidth }
    static var contentWidth: CGFloat { width - padding * 2 }
    static var tileWidth: CGFloat { floor((contentWidth - tileGap * 2) / 3) }
    static var height: CGFloat {
        headerHeight + tileHeight + spacing + sliderHeight + spacing * 2.5 + buttonHeight + padding
    }
}

@MainActor
package final class PortraitCaptureView: NSView {
    package var onCapture: (() -> Void)?
    package var onCancel: (() -> Void)?
    package var onPreview: ((CGImage?) -> Void)?
    package var onResize: (() -> Void)?
    let captureButton = ParcDialogButton(title: "Apply", primary: true)
    let cancelButton = ParcDialogButton(title: "Cancel", primary: false)
    private let back = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let titleLabel = NSTextField(labelWithString: "Portrait Frame")
    private let colorTile = PortraitBackgroundTile(title: "Color", label: "Use a Color")
    private let websiteTile = PortraitBackgroundTile(title: "Website", label: "Use Website Color")
    private let wallpaperTile = PortraitBackgroundTile(title: "Wallpaper", label: "Use Desktop Wallpaper")
    private let slider = NSSlider(value: 0.95, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let watermark = PortraitWatermarkToggle()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var options: PortraitCaptureOptions
    private let committed: CaptureFrameSettings?
    private let source: CGImage
    private let pageColor: NSColor?
    private var desktop: NSImage?
    private let palette: [NSColor]
    private let backingScale: CGFloat
    private let defaults: UserDefaults
    private var desktopTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var desktopGeneration = 0
    private var wantsSavedDesktop = false
    private var desktopError: String?
    private var renderable = true
    package private(set) var previewImage: CGImage?
    package var previewPixels: CGSize {
        didSet {
            guard previewPixels.width >= 1, previewPixels.height >= 1,
                  abs(previewPixels.width - renderedPixels.width) > 1 || abs(previewPixels.height - renderedPixels.height) > 1 else { return }
            schedulePreview(after: 0)
        }
    }
    private var renderedPixels = CGSize.zero
    private(set) var applyState = CaptureFrameApply.pending
    package override var isFlipped: Bool { true }
    package override var acceptsFirstResponder: Bool { true }

    package init(source: CGImage, pageColor: NSColor?, backingScale: CGFloat = 1,
         composition: PortraitCaptureComposition? = nil, previewPixels: CGSize = CGSize(width: 4096, height: 4096),
         defaults: UserDefaults = .standard, colors: [NSColor]? = nil) {
        self.source = source; self.pageColor = composition?.pageColor ?? pageColor
        self.previewPixels = previewPixels
        self.palette = composition?.palette ?? colors ?? PortraitCaptureRenderer.palette()
        self.options = composition?.options ?? PortraitCaptureOptions(defaults: defaults)
        self.committed = composition?.options.settings
        self.desktop = composition?.desktop
        self.backingScale = composition?.backingScale ?? backingScale
        self.defaults = defaults
        super.init(frame: NSRect(x: 0, y: 0, width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height))
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Portrait Frame")
        titleLabel.font = NoteTheme.nunitoExtraBold(14.5); titleLabel.textColor = NoteTheme.menuInk
        titleLabel.lineBreakMode = .byTruncatingTail
        back.acceptsKeyboardFocus = true; back.focusRingType = .exterior
        back.onPress = { [weak self] in self?.onCancel?() }
        captureButton.target = self; captureButton.action = #selector(capture)
        cancelButton.target = self; cancelButton.action = #selector(cancel)
        colorTile.onPress = { [weak self] in self?.choose(.color) }
        websiteTile.onPress = { [weak self] in self?.choose(.page) }
        wallpaperTile.onPress = { [weak self] in self?.choose(.desktop) }
        colorTile.gradient = palette
        websiteTile.swatch = self.pageColor ?? PortraitCaptureRenderer.blendedColor(0.95, palette: palette)
        websiteTile.setAccessibilityIdentifier("Portrait Capture Website Tint Button")
        wallpaperTile.placeholderSymbol = "desktopcomputer"
        wallpaperTile.thumbnail = desktop; wallpaperTile.isEnabled = desktop != nil
        wallpaperTile.setAccessibilityIdentifier("Portrait Capture Desktop Wallpaper Button")
        wallpaperTile.setToolTip(desktop == nil ? "Wallpaper isn't ready yet." : "Use Desktop Wallpaper")
        let sliderCell = PortraitColorSliderCell(); sliderCell.palette = palette
        slider.cell = sliderCell; slider.minValue = 0; slider.maxValue = 1
        slider.target = self; slider.action = #selector(changeColor); slider.doubleValue = options.fraction; slider.isContinuous = true
        slider.setAccessibilityLabel("Portrait background color")
        watermark.onPress = { [weak self] in self?.toggleWatermark() }
        watermark.setAccessibilityIdentifier("Portrait Capture Watermark Toggle")
        status.font = NoteTheme.menuSubtitleFont(); status.textColor = NoteTheme.menuSecondaryInk
        status.isHidden = true
        for view in [back, titleLabel, colorTile, websiteTile, wallpaperTile, slider, watermark, status, cancelButton, captureButton] as [NSView] {
            addSubview(view)
        }
        nextKeyView = colorTile
        colorTile.nextKeyView = websiteTile; websiteTile.nextKeyView = wallpaperTile; wallpaperTile.nextKeyView = slider
        slider.nextKeyView = cancelButton; cancelButton.nextKeyView = captureButton
        captureButton.nextKeyView = back; back.nextKeyView = watermark; watermark.nextKeyView = colorTile
        if options.background == .desktop && desktop == nil {
            wantsSavedDesktop = true; options.background = .color; desktopError = "Loading desktop wallpaper…"
        }
        refresh()
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    package override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { desktopTask?.cancel(); desktopTask = nil; previewTask?.cancel(); previewTask = nil; desktopGeneration += 1 }
        super.viewWillMove(toWindow: newWindow)
    }
    package override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refresh() }
    package override var fittingSize: NSSize { NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height + statusHeight) }
    package override var intrinsicContentSize: NSSize { fittingSize }

    private var statusHeight: CGFloat {
        guard !status.isHidden else { return 0 }
        let size = status.sizeThatFits(NSSize(width: PortraitCaptureLayout.contentWidth, height: .greatestFiniteMagnitude))
        return ceil(size.height) + PortraitCaptureLayout.spacing
    }

    package override func layout() {
        super.layout()
        let L = PortraitCaptureLayout.self
        back.frame = NSRect(x: 8, y: (L.headerHeight - 28) / 2, width: 28, height: 28)
        watermark.frame = NSRect(x: bounds.width - 8 - 28, y: (L.headerHeight - 28) / 2, width: 28, height: 28)
        titleLabel.frame = NSRect(x: back.frame.maxX + 4, y: (L.headerHeight - 20) / 2, width: watermark.frame.minX - back.frame.maxX - 8, height: 20)
        var y = L.headerHeight
        for (index, tile) in [colorTile, websiteTile, wallpaperTile].enumerated() {
            tile.frame = NSRect(x: L.padding + CGFloat(index) * (L.tileWidth + L.tileGap), y: y, width: L.tileWidth, height: L.tileHeight)
        }
        y += L.tileHeight + L.spacing
        slider.frame = NSRect(x: L.padding, y: y, width: L.contentWidth, height: L.sliderHeight)
        y += L.sliderHeight + L.spacing
        if !status.isHidden {
            let height = statusHeight - L.spacing
            status.frame = NSRect(x: L.padding, y: y, width: L.contentWidth, height: height)
            y += height + L.spacing
        }
        y += L.spacing / 2
        let applyWidth = ceil(captureButton.bodyWidth) + 1, cancelWidth = ceil(cancelButton.bodyWidth) + 1
        captureButton.frame = NSRect(x: bounds.width - L.padding - applyWidth, y: y, width: applyWidth, height: L.buttonHeight)
        cancelButton.frame = NSRect(x: captureButton.frame.minX - L.buttonGap - cancelWidth, y: y, width: cancelWidth, height: L.buttonHeight)
    }

    package var composition: PortraitCaptureComposition {
        PortraitCaptureComposition(options: options, palette: palette, pageColor: pageColor, desktop: desktop, backingScale: backingScale)
    }

    @discardableResult
    package func loadDesktop(screen: NSScreen?,
                     provider: @escaping @MainActor (NSScreen?) async throws -> NSImage = PortraitDesktopSnapshot.capture) -> Task<Void, Never>? {
        guard desktop == nil, desktopTask == nil else { return nil }
        desktopGeneration += 1
        let generation = desktopGeneration
        wallpaperTile.setToolTip("Loading desktop wallpaper…")
        desktopTask = Task { [weak self] in
            do {
                let result = try await provider(screen)
                guard !Task.isCancelled, let self, self.desktopGeneration == generation else { return }
                self.desktop = result; self.wallpaperTile.thumbnail = result; self.wallpaperTile.isEnabled = true
                self.wallpaperTile.setToolTip("Use Desktop Wallpaper")
                if self.wantsSavedDesktop { self.options.background = .desktop; self.wantsSavedDesktop = false }
                self.desktopError = nil; self.desktopTask = nil; self.refresh()
            } catch {
                guard !Task.isCancelled, let self, self.desktopGeneration == generation else { return }
                self.wallpaperTile.setToolTip(error.localizedDescription)
                self.desktopTask = nil
                if self.wantsSavedDesktop {
                    self.desktopError = error.localizedDescription
                    self.renderable = false; self.updateApply(); self.showError(error.localizedDescription)
                }
            }
        }
        return desktopTask
    }

    package func showError(_ message: String) {
        guard status.stringValue != message || status.isHidden else { return }
        status.stringValue = message; status.isHidden = message.isEmpty
        invalidateIntrinsicContentSize(); needsLayout = true; onResize?()
        NSAccessibility.post(element: status, notification: .valueChanged)
        if !message.isEmpty { CaptureMotion.announce(message, from: self) }
    }

    private func clearError() {
        guard !status.isHidden else { return }
        status.stringValue = ""; status.isHidden = true
        invalidateIntrinsicContentSize(); needsLayout = true; onResize?()
    }

    package override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { super.keyDown(with: event); return }
        let key: CapturePaletteKey?
        switch event.keyCode {
        case 36, 76: key = .enter
        case 53: key = .escape
        case 123 where window?.firstResponder === self: key = .left
        default: key = nil
        }
        guard let key else { super.keyDown(with: event); return }
        switch CapturePaletteKeys.command(key, focus: .frame, highlighted: nil) {
        case .activate: applyOrReturn()
        case .back: onCancel?()
        default: super.keyDown(with: event)
        }
    }
    package override func cancelOperation(_ sender: Any?) { onCancel?() }
    package override func insertNewline(_ sender: Any?) { applyOrReturn() }

    private func applyOrReturn() {
        switch applyState {
        case .pending: capture()
        case .unchanged: onCancel?()
        case .unavailable: NSSound.beep()
        }
    }

    @objc private func capture() {
        previewTask?.cancel(); previewTask = nil
        if applyState.isPrimary { onCapture?() }
    }
    @objc private func cancel() { onCancel?() }

    private func choose(_ background: PortraitCaptureOptions.Background) {
        guard background != .desktop || desktop != nil else { return }
        wantsSavedDesktop = false; desktopError = nil
        options.background = background
        options.saveBackground(to: defaults); refresh()
    }
    @objc private func changeColor() {
        wantsSavedDesktop = false; desktopError = nil
        options.background = .color; options.fraction = slider.doubleValue
        options.saveColor(to: defaults); options.saveBackground(to: defaults)
        updateTiles(); updateApply()
        schedulePreview(after: 50_000_000)
    }
    private func schedulePreview(after delay: UInt64) {
        guard previewTask == nil else { return }
        previewTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self else { return }
            self.previewTask = nil; self.refresh()
        }
    }
    private func toggleWatermark() {
        options.watermark.toggle(); options.saveWatermark(to: defaults); refresh()
    }

    private func updateTiles() {
        colorTile.isChecked = options.background == .color
        websiteTile.isChecked = options.background == .page
        wallpaperTile.isChecked = options.background == .desktop
        colorTile.swatch = PortraitCaptureRenderer.blendedColor(options.fraction, palette: palette)
        watermark.isChecked = options.watermark
    }

    private func updateApply() {
        applyState = CaptureFrameApply.state(committed: committed, draft: options.settings, renderable: renderable)
        captureButton.isEnabled = applyState.isPrimary
    }

    private func refresh() {
        previewTask?.cancel(); previewTask = nil
        updateTiles()
        do {
            renderedPixels = previewPixels
            let image = try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
                pageColor: pageColor, desktop: desktop, backingScale: backingScale, fitting: previewPixels)
            renderable = !wantsSavedDesktop
            previewImage = wantsSavedDesktop ? nil : image
            if wantsSavedDesktop, let desktopError { showError(desktopError) } else { clearError() }
        } catch {
            renderable = false; previewImage = nil
            showError(error.localizedDescription)
        }
        updateApply()
        onPreview?(previewImage)
    }
}

@MainActor
final class PortraitWatermarkToggle: NoteControlButton {
    override var isChecked: Bool { didSet { describe() } }

    init() {
        super.init(frame: NSRect(origin: .zero, size: NoteTheme.toolbarButtonSize))
        acceptsKeyboardFocus = true; focusRingType = .exterior
        setAccessibilityRole(.checkBox); setAccessibilityLabel("Parc watermark")
        describe()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func describe() {
        setAccessibilityValue(isChecked ? 1 : 0)
        toolTip = isChecked ? "Hide “Captured in Parc”" : "Show “Captured in Parc”"
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outline = ParcBrandMark.monochromeBounds
        guard outline.height > 0 else { return }
        let height: CGFloat = 16, scale = height / outline.height
        let width = outline.width * scale
        var transform = CGAffineTransform(translationX: (bounds.midX - width / 2).rounded(), y: (bounds.midY - height / 2).rounded())
            .scaledBy(x: scale, y: scale).translatedBy(x: -outline.minX, y: -outline.minY)
        guard let path = ParcBrandMark.monochromePath.copy(using: &transform) else { return }
        context.saveGState()
        context.addPath(path); context.setFillColor(ink.cgColor); context.fillPath()
        if !isChecked {
            context.setStrokeColor(ink.cgColor); context.setLineWidth(1.5); context.setLineCap(.round)
            context.move(to: CGPoint(x: bounds.midX - 8, y: bounds.midY + 8))
            context.addLine(to: CGPoint(x: bounds.midX + 8, y: bounds.midY - 8))
            context.strokePath()
        }
        context.restoreGState()
    }
}

@MainActor
private final class PortraitBackgroundTile: NoteControlButton {
    var swatch: NSColor? { didSet { needsDisplay = true } }
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    var gradient: [NSColor] = [] { didSet { needsDisplay = true } }
    var placeholderSymbol: String? { didSet { needsDisplay = true } }
    override var isChecked: Bool { didSet { setAccessibilityValue(isChecked ? 1 : 0) } }
    private let tileTitle: String

    init(title: String, label: String) {
        tileTitle = title
        super.init(frame: NSRect(x: 0, y: 0, width: 77, height: PortraitCaptureLayout.tileHeight))
        acceptsKeyboardFocus = true; focusRingType = .exterior
        setAccessibilityRole(.radioButton); setAccessibilityLabel(label); setAccessibilityValue(0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var swatchRect: NSRect {
        NSRect(x: 1.5, y: 1.5, width: bounds.width - 3, height: PortraitCaptureLayout.swatchHeight - 3)
    }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? { nil }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let rect = swatchRect, corner = PortraitCaptureLayout.swatchCorner
        let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
            let scale = max(rect.width / thumbnail.size.width, rect.height / thumbnail.size.height)
            let size = NSSize(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale)
            thumbnail.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else if let swatch {
            swatch.setFill(); path.fill()
            if gradient.count > 1, let strip = NSGradient(colors: gradient) {
                strip.draw(in: NSRect(x: rect.minX, y: rect.maxY - 9, width: rect.width, height: 9), angle: 0)
            }
        } else {
            NoteTheme.fieldFill.setFill(); path.fill()
            if let placeholderSymbol, let symbol = NoteIconRenderer.symbol(placeholderSymbol, pointSize: 16, weight: .semibold) {
                NoteIconRenderer.drawTemplate(symbol, centeredIn: rect, tint: NoteTheme.menuTertiaryInk)
            }
        }
        if isHovered || isPressed { NoteTheme.menuInk.withAlphaComponent(isPressed ? 0.16 : 0.08).setFill(); path.fill() }
        NSGraphicsContext.restoreGraphicsState()
        if isChecked {
            NoteTheme.accent.setStroke()
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -0.25, dy: -0.25), xRadius: corner, yRadius: corner)
            ring.lineWidth = 2.5; ring.stroke()
        } else {
            NoteTheme.menuHairline.setStroke()
            path.lineWidth = 1 / (window?.backingScaleFactor ?? 2); path.stroke()
        }
        let font = NoteTheme.chromeFont(12)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: tileTitle, attributes: [
            .font: font, .foregroundColor: isChecked ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk, .paragraphStyle: paragraph])
        let height = ceil(font.ascender - font.descender)
        label.draw(with: NSRect(x: 0, y: PortraitCaptureLayout.swatchHeight + 3, width: bounds.width, height: height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: swatchRect, xRadius: PortraitCaptureLayout.swatchCorner, yRadius: PortraitCaptureLayout.swatchCorner).fill()
    }
    override var focusRingMaskBounds: NSRect { swatchRect }
}

@MainActor
private final class PortraitColorSliderCell: NSSliderCell {
    var palette: [NSColor] = []
    override var knobThickness: CGFloat { 24 }
    override func barRect(flipped: Bool) -> NSRect {
        let rect = super.barRect(flipped: flipped)
        return NSRect(x: rect.minX, y: (controlView?.bounds.midY ?? rect.midY) - 6, width: rect.width, height: 12)
    }
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard palette.count == 9, let gradient = NSGradient(colors: palette) else {
            super.drawBar(inside: rect, flipped: flipped); return
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
        gradient.draw(in: rect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func drawKnob(_ knobRect: NSRect) {
        let rect = NSRect(x: knobRect.midX - 12, y: knobRect.midY - 12, width: 24, height: 24).insetBy(dx: 1, dy: 1)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
        shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        NSColor.white.setFill(); NSBezierPath(ovalIn: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
        (PortraitCaptureRenderer.blendedColor(doubleValue, palette: palette) ?? .controlAccentColor).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
    }
}

extension PortraitCaptureView {
    func harnessFraction(_ value: Double) {
        slider.doubleValue = value
        options.background = .color; options.fraction = value
        refresh()
    }
    var harnessSlider: NSSlider { slider }
}
