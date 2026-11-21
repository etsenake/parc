import AppKit
import ParcCore

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

enum PortraitCaptureError: LocalizedError {
    case resources, encoding, desktopUnavailable
    var errorDescription: String? {
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
    static func palette(bundle: Bundle = .main) -> [NSColor] {
        guard let url = bundle.url(forResource: "presets", withExtension: "json", subdirectory: "ThemeEditor"),
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
    static func outputSize(source: CGSize) -> CGSize {
        guard source.width.isFinite, source.height.isFinite, source.width > 0, source.height > 0 else { return .zero }
        let ratio = min(1, 2160 / max(source.width, source.height))
        return CGSize(width: ceil(source.width * ratio) + 384, height: ceil(source.height * ratio) + 384)
    }
    static func render(source: CGImage, options: PortraitCaptureOptions, palette: [NSColor],
                       pageColor: NSColor?, desktop: NSImage?, backingScale: CGFloat = 1, preview: Bool = false,
                       previewSide: CGFloat = 440) throws -> CGImage {
        guard backingScale.isFinite, backingScale >= 1, backingScale <= 4 else { throw PortraitCaptureError.encoding }
        guard options.background != .desktop || desktop != nil else { throw PortraitCaptureError.desktopUnavailable }
        guard let selected = blendedColor(options.fraction, palette: palette),
              let fallback = blendedColor(0.95, palette: palette) else { throw PortraitCaptureError.resources }
        let color = options.background == .page ? (pageColor?.usingColorSpace(.sRGB) ?? fallback) : selected
        let size = outputSize(source: CGSize(width: CGFloat(source.width) / backingScale, height: CGFloat(source.height) / backingScale))
        let scale = preview ? min(backingScale, previewSide / max(size.width, size.height)) : backingScale
        let width = max(1, Int(ceil(size.width * scale))), height = max(1, Int(ceil(size.height * scale)))
        let space = source.colorSpace?.model == .rgb ? source.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PortraitCaptureError.encoding }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        let canvas = CGRect(origin: .zero, size: size)
        let content = canvas.insetBy(dx: 192, dy: 192)
        let frame = content.insetBy(dx: -8, dy: -8)
        let priorContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = priorContext }
        if options.background == .desktop, let desktop {
            desktop.draw(in: canvas, from: .zero, operation: .copy, fraction: 1)
        } else {
            context.setFillColor(color.cgColor); context.fill(canvas)
            drawBackground(context, color: color, size: size)
        }
        context.setBlendMode(.normal)
        let rounded = CGPath(roundedRect: frame, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(rounded); context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6))
        context.setLineWidth(1); context.strokePath()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.addPath(rounded); context.strokePath()
        context.restoreGState()
        context.addPath(rounded); context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5)); context.fillPath()
        context.saveGState()
        context.addPath(CGPath(roundedRect: content, cornerWidth: 6, cornerHeight: 6, transform: nil)); context.clip()
        context.draw(source, in: content)
        context.restoreGState()
        if options.watermark {
            let center = CGPoint(x: size.width / 2, y: 96)
            let backdrop = options.background == .desktop ? sampledBackdrop(context, rect: watermarkRect(center: center), scale: scale) : nil
            drawWatermark(in: context, center: center, color: backdrop ?? color)
        }
        guard let result = context.makeImage() else { throw PortraitCaptureError.encoding }
        return result
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
    private static func watermarkRect(center: CGPoint) -> CGRect {
        let width = ("Parc" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold)]).width + 36
        return CGRect(x: center.x - width / 2, y: center.y - 18, width: width, height: 36)
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
    private static func drawWatermark(in context: CGContext, center: CGPoint, color: NSColor) {
        let ink = watermarkInk(on: color)
        let word = NSAttributedString(string: "Parc", attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: ink])
        let mark = ParcBrandMark.image(.monochrome)
        let leading = mark == nil ? 0.0 : 36.0
        let total = word.size().width + leading
        if let mark {
            ParcBrandMark.drawMonochrome(mark,
                in: CGRect(x: center.x - total / 2, y: center.y - 18, width: 26, height: 36),
                color: ink, context: context)
        }
        word.draw(at: CGPoint(x: center.x - total / 2 + leading, y: center.y - word.size().height / 2))
    }
}

@MainActor
struct PortraitCaptureComposition {
    var options: PortraitCaptureOptions
    let palette: [NSColor]
    let pageColor: NSColor?
    let desktop: NSImage?
    var backingScale: CGFloat = 1

    func render(_ source: CGImage) throws -> CGImage {
        try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
                                           pageColor: pageColor, desktop: desktop, backingScale: backingScale)
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
    static let watermarkHeight: CGFloat = 26
    static let buttonHeight: CGFloat = 38
    static let buttonGap: CGFloat = 8
    static let previewSide: CGFloat = 1600
    static var width: CGFloat { CapturePresentation.paletteWidth }
    static var contentWidth: CGFloat { width - padding * 2 }
    static var tileWidth: CGFloat { floor((contentWidth - tileGap * 2) / 3) }
    static var height: CGFloat {
        headerHeight + tileHeight + spacing + sliderHeight + spacing + watermarkHeight + spacing * 1.5 + buttonHeight + padding
    }
}

@MainActor
final class PortraitCaptureView: NSView {
    var onCapture: (() -> Void)?
    var onCancel: (() -> Void)?
    var onPreview: ((CGImage?) -> Void)?
    var onResize: (() -> Void)?
    let captureButton = ParcDialogButton(title: "Apply", primary: true)
    let cancelButton = ParcDialogButton(title: "Cancel", primary: false)
    private let back = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let titleLabel = NSTextField(labelWithString: "Portrait Frame")
    private let colorTile = PortraitBackgroundTile(title: "Color", label: "Use a Color")
    private let websiteTile = PortraitBackgroundTile(title: "Website", label: "Use Website Color")
    private let wallpaperTile = PortraitBackgroundTile(title: "Wallpaper", label: "Use Desktop Wallpaper")
    private let slider = NSSlider(value: 0.95, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let watermark = ParcSelectionCheckbox(title: "Parc watermark", tint: NoteTheme.accent,
                                                  labelAttributes: [.font: NoteTheme.menuTitleFont(), .foregroundColor: NoteTheme.menuInk])
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
    private(set) var previewImage: CGImage?
    private(set) var applyState = CaptureFrameApply.pending
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(source: CGImage, pageColor: NSColor?, backingScale: CGFloat = 1,
         composition: PortraitCaptureComposition? = nil, defaults: UserDefaults = .standard) {
        self.source = source; self.pageColor = composition?.pageColor ?? pageColor
        self.palette = composition?.palette ?? PortraitCaptureRenderer.palette()
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
        watermark.target = self; watermark.action = #selector(changeWatermark)
        watermark.setAccessibilityLabel("Parc watermark")
        watermark.setAccessibilityIdentifier("Portrait Capture Watermark Toggle")
        status.font = NoteTheme.menuSubtitleFont(); status.textColor = NoteTheme.menuSecondaryInk
        status.isHidden = true
        for view in [back, titleLabel, colorTile, websiteTile, wallpaperTile, slider, watermark, status, cancelButton, captureButton] as [NSView] {
            addSubview(view)
        }
        nextKeyView = colorTile
        colorTile.nextKeyView = websiteTile; websiteTile.nextKeyView = wallpaperTile; wallpaperTile.nextKeyView = slider
        slider.nextKeyView = watermark; watermark.nextKeyView = cancelButton; cancelButton.nextKeyView = captureButton
        captureButton.nextKeyView = back; back.nextKeyView = colorTile
        if options.background == .desktop && desktop == nil {
            wantsSavedDesktop = true; options.background = .color; desktopError = "Loading desktop wallpaper…"
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { desktopTask?.cancel(); desktopTask = nil; previewTask?.cancel(); previewTask = nil; desktopGeneration += 1 }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refresh() }
    override var fittingSize: NSSize { NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height + statusHeight) }
    override var intrinsicContentSize: NSSize { fittingSize }

    private var statusHeight: CGFloat {
        guard !status.isHidden else { return 0 }
        let size = status.sizeThatFits(NSSize(width: PortraitCaptureLayout.contentWidth, height: .greatestFiniteMagnitude))
        return ceil(size.height) + PortraitCaptureLayout.spacing
    }

    override func layout() {
        super.layout()
        let L = PortraitCaptureLayout.self
        back.frame = NSRect(x: 8, y: (L.headerHeight - 28) / 2, width: 28, height: 28)
        titleLabel.frame = NSRect(x: back.frame.maxX + 4, y: (L.headerHeight - 20) / 2, width: bounds.width - back.frame.maxX - 4 - L.padding, height: 20)
        var y = L.headerHeight
        for (index, tile) in [colorTile, websiteTile, wallpaperTile].enumerated() {
            tile.frame = NSRect(x: L.padding + CGFloat(index) * (L.tileWidth + L.tileGap), y: y, width: L.tileWidth, height: L.tileHeight)
        }
        y += L.tileHeight + L.spacing
        slider.frame = NSRect(x: L.padding, y: y, width: L.contentWidth, height: L.sliderHeight)
        y += L.sliderHeight + L.spacing
        let mark = watermark.fittedSize(maxWidth: L.contentWidth)
        watermark.frame = NSRect(x: L.padding, y: y + (L.watermarkHeight - mark.height) / 2, width: mark.width, height: mark.height)
        y += L.watermarkHeight + L.spacing
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

    var composition: PortraitCaptureComposition {
        PortraitCaptureComposition(options: options, palette: palette, pageColor: pageColor, desktop: desktop, backingScale: backingScale)
    }

    @discardableResult
    func loadDesktop(screen: NSScreen?,
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

    func showError(_ message: String) {
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

    override func keyDown(with event: NSEvent) {
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
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func insertNewline(_ sender: Any?) { applyOrReturn() }

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
        guard previewTask == nil else { return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let self else { return }
            self.previewTask = nil; self.refresh()
        }
    }
    @objc private func changeWatermark() {
        options.watermark = watermark.state == .on; options.saveWatermark(to: defaults); refresh()
    }

    private func updateTiles() {
        colorTile.isChecked = options.background == .color
        websiteTile.isChecked = options.background == .page
        wallpaperTile.isChecked = options.background == .desktop
        colorTile.swatch = PortraitCaptureRenderer.blendedColor(options.fraction, palette: palette)
        watermark.state = options.watermark ? .on : .off
    }

    private func updateApply() {
        applyState = CaptureFrameApply.state(committed: committed, draft: options.settings, renderable: renderable)
        captureButton.isEnabled = applyState.isPrimary
    }

    private func refresh() {
        previewTask?.cancel(); previewTask = nil
        updateTiles()
        do {
            let image = try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
                pageColor: pageColor, desktop: desktop, backingScale: backingScale, preview: true,
                previewSide: PortraitCaptureLayout.previewSide)
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
