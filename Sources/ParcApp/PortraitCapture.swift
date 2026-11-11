import AppKit

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
                       pageColor: NSColor?, desktop: NSImage?, backingScale: CGFloat = 1, preview: Bool = false) throws -> CGImage {
        guard backingScale.isFinite, backingScale >= 1, backingScale <= 4 else { throw PortraitCaptureError.encoding }
        guard options.background != .desktop || desktop != nil else { throw PortraitCaptureError.desktopUnavailable }
        guard let selected = blendedColor(options.fraction, palette: palette),
              let fallback = blendedColor(0.95, palette: palette) else { throw PortraitCaptureError.resources }
        let color = options.background == .page ? (pageColor?.usingColorSpace(.sRGB) ?? fallback) : selected
        let size = outputSize(source: CGSize(width: CGFloat(source.width) / backingScale, height: CGFloat(source.height) / backingScale))
        let scale = preview ? min(backingScale, 440 / max(size.width, size.height)) : backingScale
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
    static let padding: CGFloat = 10
    static let spacing: CGFloat = 8
    static let captureHeight: CGFloat = 32
    static let preview = CGSize(width: 140, height: 96)
    static let previewInset: CGFloat = 2.5
    static let previewInnerCorner: CGFloat = 2.5
    static let previewOuterCorner: CGFloat = 5
    static let previewChromeAlpha: CGFloat = 0.4
    static let previewShadowAlpha: CGFloat = 0.15
    static let watermarkPad: CGFloat = 4
    static let watermarkSide: CGFloat = 24
    static let sliderTravel: CGFloat = 152
    static let optionSide: CGFloat = 24
    static let cardCorner: CGFloat = 10
    static var contentWidth: CGFloat { sliderTravel + spacing + optionSide + spacing + optionSide }
    static var width: CGFloat { padding * 2 + contentWidth }
    static var height: CGFloat {
        padding + captureHeight + spacing + preview.height + spacing + optionSide + padding
    }
}

@MainActor
final class PortraitCaptureView: NSView {
    var onCapture: (() -> Void)?
    var onCancel: (() -> Void)?
    var onResize: (() -> Void)?
    let captureButton = PortraitPrimaryButton(title: "Apply Frame")
    private let material = NSVisualEffectView()
    private let previewChrome = PortraitPreviewChrome()
    private let preview = NSImageView()
    private let slider = NSSlider(value: 0.95, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let watermark = PortraitOptionButton(label: "Parc watermark", symbol: "p.circle")
    private let website = PortraitOptionButton(label: "Use Website Color", symbol: "globe")
    private let wallpaper = PortraitOptionButton(label: "Use Desktop Wallpaper", symbol: "desktopcomputer")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var options: PortraitCaptureOptions
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
    private var motionObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }

    init(source: CGImage, pageColor: NSColor?, backingScale: CGFloat = 1,
         composition: PortraitCaptureComposition? = nil, defaults: UserDefaults = .standard) {
        self.source = source; self.pageColor = composition?.pageColor ?? pageColor
        self.palette = composition?.palette ?? PortraitCaptureRenderer.palette()
        self.options = composition?.options ?? PortraitCaptureOptions(defaults: defaults)
        self.desktop = composition?.desktop
        self.backingScale = composition?.backingScale ?? backingScale
        self.defaults = defaults
        super.init(frame: NSRect(x: 0, y: 0, width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height))
        wantsLayer = true; layer?.cornerRadius = PortraitCaptureLayout.cardCorner
        layer?.cornerCurve = .continuous
        layer?.shadowOpacity = 0.25; layer?.shadowRadius = 10
        material.material = .popover; material.blendingMode = .withinWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = PortraitCaptureLayout.cardCorner
        material.layer?.cornerCurve = .continuous; material.layer?.masksToBounds = true
        addSubview(material)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Frame in Portrait Mode")
        captureButton.target = self; captureButton.action = #selector(capture)
        captureButton.keyEquivalent = "\r"; captureButton.keyEquivalentModifierMask = []
        preview.imageScaling = .scaleProportionallyUpOrDown; preview.setAccessibilityLabel("Portrait image preview")
        preview.wantsLayer = true
        preview.layer?.cornerRadius = PortraitCaptureLayout.previewInnerCorner
        preview.layer?.masksToBounds = true
        website.target = self; website.action = #selector(changeWebsite)
        website.swatch = self.pageColor
        website.setAccessibilityIdentifier("Portrait Capture Website Tint Button")
        wallpaper.target = self; wallpaper.action = #selector(changeDesktop)
        wallpaper.isEnabled = desktop != nil; wallpaper.thumbnail = desktop
        wallpaper.setAccessibilityIdentifier("Portrait Capture Desktop Wallpaper Button")
        LiveShortcutToolTip.set(wallpaper, desktop == nil ? "Desktop wallpaper has not been loaded." : "Use Desktop Wallpaper")
        let sliderCell = PortraitColorSliderCell(); sliderCell.palette = palette
        slider.cell = sliderCell; slider.minValue = 0; slider.maxValue = 1
        slider.target = self; slider.action = #selector(changeColor); slider.doubleValue = options.fraction; slider.isContinuous = true
        slider.setAccessibilityLabel("Portrait background color")
        watermark.target = self; watermark.action = #selector(changeWatermark)
        watermark.image = ParcBrandMark.image(.monochrome)
        LiveShortcutToolTip.set(watermark, "Hide Watermark")
        watermark.setAccessibilityIdentifier("Portrait Capture Watermark Toggle")
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        for view in [captureButton, previewChrome, preview, watermark, slider, website, wallpaper, status] { addSubview(view) }
        captureButton.nextKeyView = watermark; watermark.nextKeyView = slider; slider.nextKeyView = website
        website.nextKeyView = wallpaper; wallpaper.nextKeyView = captureButton
        if options.background == .desktop && desktop == nil {
            wantsSavedDesktop = true; options.background = .color; desktopError = "Loading desktop wallpaper…"
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { CaptureMotion.settleImageBlend(preview); desktopTask?.cancel(); desktopTask = nil; previewTask?.cancel(); previewTask = nil; desktopGeneration += 1 }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }; motionObserver = nil
        if window != nil {
            motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                    guard let self, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    CaptureMotion.settleImageBlend(self.preview)
                } }
        }
    }
    deinit { if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refresh() }
    override func layout() {
        super.layout()
        let L = PortraitCaptureLayout.self
        material.frame = bounds
        var y = L.padding
        captureButton.frame = NSRect(x: L.padding, y: y, width: L.contentWidth, height: L.captureHeight)
        y += L.captureHeight + L.spacing
        let previewX = L.padding + (L.contentWidth - L.preview.width) / 2
        let previewRect = NSRect(x: previewX, y: y, width: L.preview.width, height: L.preview.height)
        previewChrome.frame = previewRect
        preview.frame = previewRect.insetBy(dx: L.previewInset, dy: L.previewInset)
        watermark.frame = NSRect(x: previewRect.minX + L.watermarkPad,
                                 y: previewRect.maxY - L.watermarkPad - L.watermarkSide,
                                 width: L.watermarkSide, height: L.watermarkSide)
        y += L.preview.height + L.spacing
        slider.frame = NSRect(x: L.padding, y: y, width: L.sliderTravel, height: L.optionSide)
        website.frame = NSRect(x: L.padding + L.sliderTravel + L.spacing, y: y, width: L.optionSide, height: L.optionSide)
        wallpaper.frame = NSRect(x: website.frame.maxX + L.spacing, y: y, width: L.optionSide, height: L.optionSide)
        y += L.optionSide + L.padding
        status.frame = NSRect(x: L.padding, y: y, width: L.contentWidth, height: max(0, bounds.height - y - L.padding))
    }
    var composition: PortraitCaptureComposition {
        PortraitCaptureComposition(options: options, palette: palette, pageColor: pageColor, desktop: desktop, backingScale: backingScale)
    }
    func loadDesktop(screen: NSScreen?,
                     provider: @escaping @MainActor (NSScreen?) async throws -> NSImage = PortraitDesktopSnapshot.capture) {
        guard desktop == nil, desktopTask == nil else { return }
        desktopGeneration += 1
        let generation = desktopGeneration
        LiveShortcutToolTip.set(wallpaper, "Loading desktop wallpaper…")
        desktopTask = Task { [weak self] in
            do {
                let result = try await provider(screen)
                guard !Task.isCancelled, let self, self.desktopGeneration == generation else { return }
                self.desktop = result; self.wallpaper.thumbnail = result; self.wallpaper.isEnabled = true
                LiveShortcutToolTip.set(self.wallpaper, "Use Desktop Wallpaper")
                if self.wantsSavedDesktop { self.options.background = .desktop; self.wantsSavedDesktop = false }
                self.desktopError = nil; self.desktopTask = nil; self.refresh()
            } catch {
                guard !Task.isCancelled, let self, self.desktopGeneration == generation else { return }
                LiveShortcutToolTip.set(self.wallpaper, error.localizedDescription)
                self.desktopTask = nil
                if self.wantsSavedDesktop {
                    self.desktopError = error.localizedDescription
                    self.captureButton.isEnabled = false; self.showError(error.localizedDescription)
                }
            }
        }
    }
    func showError(_ message: String) {
        status.stringValue = message
        let height = max(44, status.sizeThatFits(NSSize(width: PortraitCaptureLayout.contentWidth, height: CGFloat.greatestFiniteMagnitude)).height)
        setFrameSize(NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height + PortraitCaptureLayout.padding + height))
        needsLayout = true; onResize?()
        NSAccessibility.post(element: status, notification: .valueChanged)
    }
    @objc private func capture() {
        previewTask?.cancel(); previewTask = nil
        if captureButton.isEnabled { onCapture?() }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    @objc private func changeWebsite() {
        wantsSavedDesktop = false; desktopError = nil
        options.background = options.background == .page ? .color : .page
        options.saveBackground(to: defaults); refresh()
    }
    @objc private func changeDesktop() {
        guard desktop != nil else { return }
        wantsSavedDesktop = false; desktopError = nil
        options.background = options.background == .desktop ? .color : .desktop
        options.saveBackground(to: defaults); refresh()
    }
    @objc private func changeColor() {
        wantsSavedDesktop = false; desktopError = nil
        options.background = .color; options.fraction = slider.doubleValue
        options.saveColor(to: defaults); options.saveBackground(to: defaults)
        website.state = .off; wallpaper.state = .off
        guard previewTask == nil else { return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let self else { return }
            self.previewTask = nil; self.refresh()
        }
    }
    @objc private func changeWatermark() {
        options.watermark.toggle(); options.saveWatermark(to: defaults); refresh()
    }
    private func refresh() {
        previewTask?.cancel(); previewTask = nil
        watermark.state = options.watermark ? .on : .off
        watermark.setAccessibilityValue(options.watermark ? "On" : "Off")
        website.state = options.background == .page ? .on : .off
        wallpaper.state = options.background == .desktop ? .on : .off
        do {
            let image = try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
                pageColor: pageColor, desktop: desktop, backingScale: backingScale, preview: true)
            let previous = preview.image
            preview.image = wantsSavedDesktop ? nil : NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
            CaptureMotion.blendPortrait(preview, previous: previous)
            captureButton.isEnabled = !wantsSavedDesktop
            if wantsSavedDesktop, let desktopError { showError(desktopError) }
            else { status.stringValue = ""; setFrameSize(NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height)); needsLayout = true; onResize?() }
        } catch { captureButton.isEnabled = false; showError(error.localizedDescription) }
    }
}

@MainActor
final class PortraitPrimaryButton: PointingHandButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false; bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        focusRingType = .exterior
        font = .systemFont(ofSize: 13, weight: .semibold)
        setButtonType(.momentaryLight)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: PortraitCaptureLayout.captureHeight) }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let pressed = isHighlighted
        let gray1 = NSColor(srgbRed: 0.085, green: 0.085, blue: 0.085, alpha: 1)
        let face = dark ? (pressed ? gray1.withAlphaComponent(0.88) : gray1)
            : (pressed ? NSColor(white: 0.88, alpha: 1) : .white)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        face.setFill(); path.fill()
        if let context = NSGraphicsContext.current?.cgContext, let gradient = NSGradient(colors: [.white, NSColor.black.withAlphaComponent(0.22)]) {
            context.saveGState()
            context.setAlpha(dark ? 0.08 : 0.13)
            gradient.draw(from: NSPoint(x: 0, y: isFlipped ? 0 : bounds.maxY),
                          to: NSPoint(x: 0, y: isFlipped ? bounds.maxY : 0), options: [])
            context.restoreGState()
        }
        NSColor.white.withAlphaComponent(dark ? 0.22 : 0.08).setStroke()
        let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: -0.5, dy: -0.5).offsetBy(dx: 0, dy: isFlipped ? -1 : 1), xRadius: 6, yRadius: 6)
        highlight.lineWidth = 1; highlight.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if isEnabled {
            NSColor.black.withAlphaComponent(dark ? 0.87 : 0.5).setStroke()
            let hairline = NSBezierPath(roundedRect: bounds.insetBy(dx: -0.25, dy: -0.25), xRadius: 6, yRadius: 6)
            hairline.lineWidth = 0.25; hairline.stroke()
        }
        let color = (dark ? NSColor.white : NSColor.black).withAlphaComponent(isEnabled ? 0.8 : 0.3)
        let text = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

@MainActor
private final class PortraitPreviewChrome: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PortraitCaptureLayout.previewOuterCorner
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(PortraitCaptureLayout.previewChromeAlpha).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(PortraitCaptureLayout.previewShadowAlpha)
        layer?.shadowRadius = 4
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
private final class PortraitOptionButton: PointingHandButton {
    var swatch: NSColor? { didSet { needsDisplay = true } }
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(label: String, symbol: String) {
        super.init(frame: .zero)
        title = ""; image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        isBordered = false; imagePosition = .imageOnly; imageScaling = .scaleProportionallyDown
        focusRingType = .exterior; setButtonType(.momentaryChange)
        setAccessibilityLabel(label); LiveShortcutToolTip.set(self, label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let value = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = value; addTrackingArea(value); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        (swatch ?? NSColor.controlBackgroundColor).setFill(); path.fill()
        if let thumbnail {
            thumbnail.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4, respectFlipped: true, hints: nil)
        }
        if hovered || isHighlighted { NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.18 : 0.08).setFill(); path.fill() }
        NSGraphicsContext.restoreGraphicsState()
        (state == .on ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = state == .on ? 2 : 1; path.stroke()
        if swatch == nil && thumbnail == nil, let image {
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                if isFlipped { context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1) }
                ParcBrandMark.drawMonochrome(image, in: rect.insetBy(dx: 5, dy: 4),
                    color: NSColor.labelColor.withAlphaComponent(isEnabled ? 1 : 0.35), context: context)
                context.restoreGState()
            }
        }
    }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
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
