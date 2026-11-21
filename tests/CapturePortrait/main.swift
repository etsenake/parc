import AppKit
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit

@main
struct PortraitChecks {
    @MainActor static func main() async { await exitOnFailure(runChecks) }
    @MainActor static func runChecks() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let suite = "ParcPortraitChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var options = PortraitCaptureOptions(defaults: defaults)
        precondition(options.fraction == 0.95 && options.watermark && options.background == .color)
        options.fraction = 0.25; options.background = .page; options.watermark = false; options.save(to: defaults)
        let saved = PortraitCaptureOptions(defaults: defaults)
        precondition(saved.fraction == 0.25 && saved.background == .page && !saved.watermark)
        defaults.set(Double.infinity, forKey: "parc.capture.portrait.color")
        precondition(PortraitCaptureOptions(defaults: defaults).fraction == 0.95)
        precondition(PortraitCaptureRenderer.outputSize(source: CGSize(width: 4000, height: 2000)) == CGSize(width: 2544, height: 1464))
        precondition(PortraitCaptureRenderer.outputSize(source: CGSize(width: 320, height: 160)) == CGSize(width: 704, height: 544))
        let context = CGContext(data: nil, width: 320, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 160, y: 0, width: 160, height: 160))
        let source = context.makeImage()!
        let palette = PortraitCaptureRenderer.palette()
        precondition(palette.count == 9)
        precondition(PortraitCaptureRenderer.blendedColor(.nan, palette: palette) == nil)
        let endpoint = PortraitCaptureRenderer.blendedColor(0, palette: palette)!.usingColorSpace(.sRGB)!
        precondition(abs(endpoint.redComponent - palette[0].usingColorSpace(.sRGB)!.redComponent) < 0.00001)
        precondition(abs(endpoint.greenComponent - palette[0].usingColorSpace(.sRGB)!.greenComponent) < 0.00001)
        precondition(abs(endpoint.blueComponent - palette[0].usingColorSpace(.sRGB)!.blueComponent) < 0.00001)
        func make(_ options: PortraitCaptureOptions, color: NSColor? = .green, desktop: NSImage? = nil) throws -> CGImage {
            try PortraitCaptureRenderer.render(source: source, options: options, palette: palette, pageColor: color, desktop: desktop)
        }
        func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
            let sample = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sample.interpolationQuality = .none
            sample.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: sample.data!.assumingMemoryBound(to: UInt8.self), count: 4))
        }
        let page = try make(options)
        precondition(page.width == 704 && page.height == 544)
        let left = sample(page, x: 240, y: 240), right = sample(page, x: 440, y: 240)
        precondition(left[0] > 245 && left[2] < 10 && right[2] > 245 && right[0] < 10)
        options.background = .color
        let color = try make(options)
        precondition(sample(color, x: 240, y: 240) == left)
        precondition(sample(color, x: 20, y: 20) != sample(page, x: 20, y: 20))
        options.background = .desktop
        let wallpaper = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { rect in
            NSColor.cyan.setFill(); rect.fill(); return true
        }
        let desktop = try make(options, desktop: wallpaper)
        precondition(sample(desktop, x: 20, y: 20)[0] < 10)
        do { _ = try make(options, desktop: nil); preconditionFailure("A missing desktop must not silently become a color background") }
        catch PortraitCaptureError.desktopUnavailable { }
        options.watermark = true
        let marked = try make(options, desktop: wallpaper)
        precondition(marked.dataProvider!.data! != desktop.dataProvider!.data!)
        let splitDesktop = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 100, height: 50).fill(); return true
        }
        let contrast = try make(options, desktop: splitDesktop)
        var unmarkedOptions = options; unmarkedOptions.watermark = false
        let unmarkedContrast = try make(unmarkedOptions, desktop: splitDesktop)
        var darkerMarkPixels = 0
        for y in 80..<112 { for x in 300..<404 {
            let changed = sample(contrast, x: x, y: y), plain = sample(unmarkedContrast, x: x, y: y)
            if changed[0] < plain[0] { darkerMarkPixels += 1 }
        } }
        precondition(darkerMarkPixels > 30, "Desktop contrast samples the bottom watermark footprint, not the opposite edge")
        let preview = try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
            pageColor: .green, desktop: wallpaper, preview: true)
        precondition(max(preview.width, preview.height) <= 440)
        func png(_ image: CGImage) -> Data {
            let bytes = NSMutableData()
            let sink = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(sink, image, nil); precondition(CGImageDestinationFinalize(sink))
            return bytes as Data
        }
        let original = png(source)
        let capture = try CapturedImage(pngData: original)
        var style = PortraitCaptureComposition(options: options, palette: palette, pageColor: .green, desktop: wallpaper)
        try capture.applyFrame(style)
        precondition(capture.originalPNG == original && capture.unframedPNG == original)
        precondition(capture.pixels.width == 704 && capture.pixels.height == 544)
        style.options.background = .page
        try capture.applyFrame(style)
        precondition(capture.pixels.width == 704 && capture.pixels.height == 544, "Editing a frame must not frame its previous output")
        capture.removeFrame()
        precondition(capture.frame == nil && capture.pngData == original)
        try capture.applyFrame(style)
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        precondition(capture.originalPNG == original && capture.unframedPixels.width == 160)
        precondition(capture.pixels.width == 544 && capture.pixels.height == 544)
        precondition(sample(capture.pixels, x: 240, y: 240)[2] > 245)
        let croppedPNG = capture.unframedPNG
        capture.removeFrame()
        precondition(capture.pngData == croppedPNG && capture.pixels.width == 160)
        try capture.applyFrame(style)
        let committed = capture.pngData
        do {
            try capture.applyFrame(PortraitCaptureComposition(options: options, palette: [], pageColor: nil, desktop: nil))
            preconditionFailure("Missing compositor resources must fail")
        } catch { precondition(capture.pngData == committed && capture.frame != nil) }
        do {
            try capture.crop(to: CGRect(x: 900, y: 900, width: 1, height: 1))
            preconditionFailure("Out-of-image crop must fail")
        } catch { precondition(capture.pngData == committed && capture.unframedPNG == croppedPNG) }
        try capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
        capture.removeFrame()
        precondition(capture.pngData == original, "Recrop to full source restores original bytes")
        let tallContext = CGContext(data: nil, width: 300, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        tallContext.setFillColor(NSColor.red.cgColor); tallContext.fill(CGRect(x: 0, y: 0, width: 300, height: 4000))
        let tallPNG = png(tallContext.makeImage()!)
        let editedCapture = try CapturedImage(pngData: original, backingScale: 2)
        try editedCapture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        var editedStyle = style; editedStyle.backingScale = 2
        try editedCapture.applyFrame(editedStyle)
        let editedContext = CGContext(data: nil, width: 320, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        editedContext.draw(source, in: CGRect(x: 0, y: 0, width: 320, height: 160))
        editedContext.setFillColor(NSColor.green.cgColor); editedContext.fill(CGRect(x: 180, y: 20, width: 20, height: 20))
        let editedSource = editedContext.makeImage()!
        try editedCapture.applyEditedOriginal(editedSource)
        precondition(editedCapture.originalPNG == original && editedCapture.sourcePNG != original)
        precondition(editedCapture.unframedPixels.width == 160 && editedCapture.frame != nil)
        precondition(sample(editedCapture.unframedPixels, x: 30, y: 30)[1] > 245, "Accepted edit reapplies original crop")
        let acceptedPNG = editedCapture.pngData, acceptedSource = editedCapture.sourcePNG
        do { try editedCapture.applyEditedOriginal(source.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 10))!); preconditionFailure("Mismatched edit dimensions accepted") }
        catch { precondition(editedCapture.pngData == acceptedPNG && editedCapture.sourcePNG == acceptedSource) }
        editedCapture.removeFrame()
        precondition(editedCapture.pngData == editedCapture.unframedPNG)
        try editedCapture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
        precondition(editedCapture.pngData == acceptedSource, "Recrop retains original edited pixels without another raster pass")
        precondition(editedCapture.originalPNG == original && editedCapture.backingScale == 2)
        let tallCapture = try CapturedImage(pngData: tallPNG)
        try tallCapture.applyFrame(style)
        precondition(tallCapture.pixels.height == 2544 && tallCapture.unframedPixels.height == 4000)
        tallCapture.removeFrame()
        precondition(tallCapture.pngData == tallPNG && tallCapture.pixels.height == 4000)
        do { _ = try CapturedImage(pngData: Data([0, 1, 2])); preconditionFailure("Invalid image must fail") }
        catch { }
        let retina = try PortraitCaptureRenderer.render(source: source, options: options, palette: palette,
            pageColor: .green, desktop: wallpaper, backingScale: 2)
        precondition(retina.width == 1088 && retina.height == 928)
        precondition(sample(retina, x: 420, y: 420)[0] > 245)
        let retinaCapture = try CapturedImage(pngData: original, backingScale: 2)
        var retinaStyle = style; retinaStyle.backingScale = 2
        try retinaCapture.applyFrame(retinaStyle)
        let encodedSource = CGImageSourceCreateWithData(retinaCapture.pngData as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(encodedSource, 0, nil)! as NSDictionary
        precondition(abs((properties[kCGImagePropertyDPIWidth] as! Double) - 144) < 0.1)
        retinaCapture.removeFrame(); precondition(retinaCapture.pngData == original)
        let p3 = CGContext(data: nil, width: 320, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        p3.setFillColor(CGColor(colorSpace: p3.colorSpace!, components: [0.8, 0.2, 0.4, 1])!)
        p3.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
        let p3Result = try PortraitCaptureRenderer.render(source: p3.makeImage()!, options: options, palette: palette,
            pageColor: .green, desktop: wallpaper)
        precondition(p3Result.colorSpace?.name == CGColorSpace.displayP3)
        let expected = sample(p3.makeImage()!, x: 100, y: 100)
        let actual = sample(p3Result, x: 250, y: 250)
        precondition(zip(expected, actual).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        let darkInk = PortraitCaptureRenderer.watermarkInk(on: NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1))
        precondition(darkInk.usingColorSpace(.sRGB)!.redComponent == 0 && darkInk.alphaComponent == 0.45)
        let lightInk = PortraitCaptureRenderer.watermarkInk(on: NSColor(srgbRed: 0.74, green: 0.74, blue: 0.74, alpha: 1))
        precondition(lightInk.usingColorSpace(.sRGB)!.redComponent == 1 && lightInk.alphaComponent == 0.75)
        let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let exactWallpaper = PortraitDesktopSnapshot.Candidate(id: 1, processID: 1, bounds: display,
            bundle: "com.apple.WindowManager", title: "Wallpaper", layer: -2147483624)
        precondition(exactWallpaper.isWallpaper(for: display))
        precondition(!PortraitDesktopSnapshot.Candidate(id: 4, processID: 4, bounds: display,
            bundle: "com.apple.dock", title: "Mission Control", layer: -1).isWallpaper(for: display))
        precondition(!exactWallpaper.isWallpaper(for: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        precondition(!PortraitDesktopSnapshot.Candidate(id: 2, processID: 2, bounds: display,
            bundle: "com.apple.finder", title: "Wallpaper", layer: -1).isWallpaper(for: display))
        precondition(!PortraitDesktopSnapshot.Candidate(id: 3, processID: 3, bounds: display,
            bundle: "com.apple.dock", title: "Dock", layer: 20).isWallpaper(for: display))
        let view = PortraitCaptureView(source: source, pageColor: .green, composition: style, defaults: defaults)
        view.setFrameSize(view.fittingSize); view.layoutSubtreeIfNeeded()
        precondition(view.bounds.size == NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height),
                     "The Frame page fills the palette card's width")
        precondition(view.applyState == .unchanged && !view.captureButton.isEnabled, "Reopening an applied frame leaves Apply quiet")
        precondition(view.previewImage.map { max($0.width, $0.height) > 440 && CGFloat(max($0.width, $0.height)) <= PortraitCaptureLayout.previewSide } == true,
                     "The live preview renders large for the page-sized image")
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        let websiteButton = buttons.first { $0.accessibilityLabel() == "Use Website Color" }!
        let desktopButton = buttons.first { $0.accessibilityLabel() == "Use Desktop Wallpaper" }!
        let colorButton = buttons.first { $0.accessibilityLabel() == "Use a color" }!
        websiteButton.performClick(nil)
        precondition(view.composition.options.background == .page)
        desktopButton.performClick(nil)
        precondition(view.composition.options.background == .desktop)
        colorButton.performClick(nil)
        precondition(view.composition.options.background == .color)
        let colorSlider = view.subviews.compactMap { $0 as? NSSlider }.first!
        colorSlider.doubleValue = 0.7
        colorSlider.sendAction(colorSlider.action!, to: colorSlider.target)
        precondition(view.composition.options.background == .color && view.composition.options.fraction == 0.7)
        precondition(view.applyState == .pending && view.captureButton.isEnabled, "A changed frame makes Apply the primary button")
        var applied = false; view.onCapture = { applied = true }; view.captureButton.performClick(nil)
        precondition(applied && view.composition.options.fraction == 0.7)
        var canceled = false; view.onCancel = { canceled = true }; view.cancelOperation(nil); precondition(canceled)
        view.showError(String(repeating: "A desktop error. ", count: 16)); view.setFrameSize(view.fittingSize); view.layoutSubtreeIfNeeded()
        precondition(view.subviews.allSatisfy { view.bounds.contains($0.frame) })
        defaults.set(PortraitCaptureOptions.Background.desktop.rawValue, forKey: "parc.capture.portrait.background")
        let unavailableView = PortraitCaptureView(source: source, pageColor: .green, defaults: defaults)
        precondition(!unavailableView.captureButton.isEnabled)
        unavailableView.loadDesktop(screen: nil, provider: { _ in throw PortraitDesktopSnapshot.Failure.permission })
        try await Task.sleep(nanoseconds: 10_000_000)
        precondition(!unavailableView.captureButton.isEnabled)
        let unavailableButtons = unavailableView.subviews.compactMap { $0 as? NSButton }
        unavailableButtons.first { $0.accessibilityLabel() == "Parc watermark" }!.performClick(nil)
        unavailableView.viewDidChangeBackingProperties()
        precondition(!unavailableView.captureButton.isEnabled)
        precondition(unavailableView.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Screen Recording") })
        unavailableButtons.first { $0.accessibilityLabel() == "Use Website Color" }!.performClick(nil)
        precondition(unavailableView.captureButton.isEnabled && unavailableView.composition.options.background == .page)
        if let directory = ProcessInfo.processInfo.environment["PARC_PORTRAIT_PREVIEW_DIR"] {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                let previewView = PortraitCaptureView(source: source, pageColor: .green, composition: retinaStyle, defaults: defaults)
                let window = NSWindow(contentRect: previewView.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance); window.contentView = previewView
                previewView.layoutSubtreeIfNeeded(); window.orderFront(nil); window.displayIfNeeded()
                try await Task.sleep(nanoseconds: 50_000_000)
                defer { window.orderOut(nil) }
                let rendered = previewView.previewImage!
                precondition(sample(rendered, x: 160, y: 175)[0] > 245, "Nested AppKit drawing must preserve source pixels")
                precondition(sample(rendered, x: 153, y: 175)[1] > 20, "Nested AppKit drawing must preserve the translucent frame")
                try png(rendered).write(to: URL(fileURLWithPath: directory).appendingPathComponent("render-\(name).png"))
                if #available(macOS 14.0, *), CGPreflightScreenCaptureAccess() {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    let actualWindow = content.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(window.frame.width * window.backingScaleFactor)
                    configuration.height = Int(window.frame.height * window.backingScaleFactor)
                    configuration.showsCursor = false; configuration.ignoreShadowsSingleWindow = true
                    let pixels = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: actualWindow), configuration: configuration)
                    try png(pixels).write(to: URL(fileURLWithPath: directory).appendingPathComponent("portrait-\(name).png"))
                }

            }
        }
        if ProcessInfo.processInfo.environment["PARC_PORTRAIT_DESKTOP_CHECK"] == "1" {
            let wallpaper = try await PortraitDesktopSnapshot.capture(screen: NSScreen.main)
            let actual = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            print("Desktop-only provider: logical=\(wallpaper.size), pixels=\(actual.width)x\(actual.height), profile=\(actual.colorSpace?.name as String? ?? "unknown")")
        }
        if let output = ProcessInfo.processInfo.environment["PARC_PORTRAIT_CHECK_IMAGE"] {
            let sink = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(sink, marked, nil); precondition(CGImageDestinationFinalize(sink))
        }
        print("Portrait compositor, reversible captured-image edits and isolated-preference checks passed.")
    }
}
