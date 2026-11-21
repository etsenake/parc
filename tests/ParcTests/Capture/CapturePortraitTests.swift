import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc

@MainActor
private final class PortraitFixture {
    let suite = "ParcPortraitTests-" + UUID().uuidString
    let defaults: UserDefaults
    var options: PortraitCaptureOptions
    let source: CGImage
    let original: Data
    let palette = PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor")
    let wallpaper = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { rect in
        NSColor.cyan.setFill()
        rect.fill()
        return true
    }

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        options = PortraitCaptureOptions(defaults: defaults)
        let context = Self.context(width: 320, height: 160)
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 160, y: 0, width: 160, height: 160))
        source = context.makeImage()!
        original = try Self.png(source)
    }

    deinit { defaults.removePersistentDomain(forName: suite) }

    static func context(width: Int, height: Int, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let pixel = context(width: 1, height: 1)
        pixel.interpolationQuality = .none
        pixel.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: pixel.data!.assumingMemoryBound(to: UInt8.self), count: 4))
    }

    static func png(_ image: CGImage) throws -> Data {
        let bytes = NSMutableData()
        let sink = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sink, image, nil)
        #expect(CGImageDestinationFinalize(sink))
        return bytes as Data
    }

    func render(_ options: PortraitCaptureOptions? = nil, color: NSColor? = .green, desktop: NSImage? = nil,
                backingScale: CGFloat = 1, source override: CGImage? = nil) throws -> CGImage {
        try PortraitCaptureRenderer.render(source: override ?? source, options: options ?? self.options, palette: palette,
                                           pageColor: color, desktop: desktop, backingScale: backingScale)
    }

    func composition(_ options: PortraitCaptureOptions? = nil, backingScale: CGFloat = 1, hasDesktop: Bool = true) -> PortraitCaptureComposition {
        var composition = PortraitCaptureComposition(options: options ?? self.options, palette: palette, pageColor: .green,
                                                     desktop: hasDesktop ? wallpaper : nil)
        composition.backingScale = backingScale
        return composition
    }

    func framed(_ background: PortraitCaptureOptions.Background = .page, backingScale: CGFloat = 1) throws -> (CapturedImage, PortraitCaptureComposition) {
        var options = self.options
        options.background = background
        let style = composition(options, backingScale: backingScale)
        let capture = try CapturedImage(pngData: original, backingScale: backingScale)
        try capture.applyFrame(style)
        return (capture, style)
    }
}

struct PortraitCaptureOptionsTests {
    private func suite() -> (UserDefaults, String) {
        let name = "ParcPortraitOptions-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func freshDefaultsUseTheColorBackgroundWithAWatermark() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let options = PortraitCaptureOptions(defaults: defaults)
        #expect(options.fraction == 0.95 && options.watermark && options.background == .color)
    }

    @Test func savedOptionsReloadFromTheSameDefaults() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        var options = PortraitCaptureOptions(defaults: defaults)
        options.fraction = 0.25
        options.background = .page
        options.watermark = false
        options.save(to: defaults)
        let saved = PortraitCaptureOptions(defaults: defaults)
        #expect(saved.fraction == 0.25 && saved.background == .page && !saved.watermark)
    }

    @Test func aNonFiniteSavedColorFallsBackToTheDefault() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Double.infinity, forKey: "parc.capture.portrait.color")
        #expect(PortraitCaptureOptions(defaults: defaults).fraction == 0.95)
    }
}

struct PortraitCaptureRendererTests {
    @MainActor @Test(arguments: [
        (CGSize(width: 4000, height: 2000), CGSize(width: 2544, height: 1464)),
        (CGSize(width: 320, height: 160), CGSize(width: 704, height: 544)),
    ])
    func outputSizeFitsTheSourceInsideTheFrame(_ source: CGSize, _ expected: CGSize) {
        #expect(PortraitCaptureRenderer.outputSize(source: source) == expected)
    }

    @MainActor @Test func theBundledPaletteHasNineColors() {
        #expect(PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor").count == 9)
    }

    @MainActor @Test func aNonNumberBlendsToNoColor() {
        let palette = PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor")
        #expect(PortraitCaptureRenderer.blendedColor(.nan, palette: palette) == nil)
    }

    @MainActor @Test(arguments: [0, 1, 2])
    func theFirstEndpointBlendsToTheFirstPaletteColor(_ channel: Int) throws {
        let palette = PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor")
        let endpoint = try #require(PortraitCaptureRenderer.blendedColor(0, palette: palette)?.usingColorSpace(.sRGB))
        let first = try #require(palette[0].usingColorSpace(.sRGB))
        let components = [(endpoint.redComponent, first.redComponent), (endpoint.greenComponent, first.greenComponent),
                          (endpoint.blueComponent, first.blueComponent)]
        #expect(abs(components[channel].0 - components[channel].1) < 0.00001)
    }

    @MainActor @Test func aPageBackgroundFramesTheSourceAtTheOutputSize() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .page
        let page = try fixture.render()
        #expect(page.width == 704 && page.height == 544)
    }

    @MainActor @Test func theLeftHalfOfTheSourceStaysRed() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .page
        let left = PortraitFixture.sample(try fixture.render(), x: 240, y: 240)
        #expect(left[0] > 245 && left[2] < 10)
    }

    @MainActor @Test func theRightHalfOfTheSourceStaysBlue() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .page
        let right = PortraitFixture.sample(try fixture.render(), x: 440, y: 240)
        #expect(right[2] > 245 && right[0] < 10)
    }

    @MainActor @Test func aColorBackgroundKeepsTheSamePixelsInsideTheFrame() throws {
        let fixture = try PortraitFixture()
        var page = fixture.options
        page.background = .page
        var color = fixture.options
        color.background = .color
        #expect(PortraitFixture.sample(try fixture.render(color), x: 240, y: 240) == PortraitFixture.sample(try fixture.render(page), x: 240, y: 240))
    }

    @MainActor @Test func aColorBackgroundPaintsTheMarginDifferentlyFromTheWebsiteColor() throws {
        let fixture = try PortraitFixture()
        var page = fixture.options
        page.background = .page
        var color = fixture.options
        color.background = .color
        #expect(PortraitFixture.sample(try fixture.render(color), x: 20, y: 20) != PortraitFixture.sample(try fixture.render(page), x: 20, y: 20))
    }

    @MainActor @Test func aDesktopBackgroundDrawsTheWallpaper() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        let desktop = try fixture.render(desktop: fixture.wallpaper)
        #expect(PortraitFixture.sample(desktop, x: 20, y: 20)[0] < 10)
    }

    @MainActor @Test func aMissingDesktopNeverSilentlyBecomesAColorBackground() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        #expect(throws: PortraitCaptureError.desktopUnavailable) { try fixture.render(desktop: nil) }
    }

    @MainActor @Test func theWatermarkChangesTheRenderedPixels() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        fixture.options.watermark = false
        let plain = try fixture.render(desktop: fixture.wallpaper)
        fixture.options.watermark = true
        let marked = try fixture.render(desktop: fixture.wallpaper)
        #expect((marked.dataProvider!.data! as Data) != (plain.dataProvider!.data! as Data))
    }

    @MainActor @Test func desktopContrastSamplesTheBottomWatermarkFootprint() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        let split = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 100, height: 50).fill()
            return true
        }
        fixture.options.watermark = true
        let marked = try fixture.render(desktop: split)
        fixture.options.watermark = false
        let plain = try fixture.render(desktop: split)
        var darker = 0
        for y in 80..<112 {
            for x in 300..<404 where PortraitFixture.sample(marked, x: x, y: y)[0] < PortraitFixture.sample(plain, x: x, y: y)[0] {
                darker += 1
            }
        }
        #expect(darker > 0)
    }

    @MainActor @Test func aPreviewRendersWithinThePreviewSide() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        let preview = try PortraitCaptureRenderer.render(source: fixture.source, options: fixture.options, palette: fixture.palette,
                                                         pageColor: .green, desktop: fixture.wallpaper, preview: true)
        #expect(max(preview.width, preview.height) <= 440)
    }

    @MainActor @Test func aRetinaRenderDoublesTheOutputPixels() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        let retina = try fixture.render(desktop: fixture.wallpaper, backingScale: 2)
        #expect(retina.width == 1088 && retina.height == 928)
    }

    @MainActor @Test func aRetinaRenderKeepsTheSourcePixels() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        let retina = try fixture.render(desktop: fixture.wallpaper, backingScale: 2)
        #expect(PortraitFixture.sample(retina, x: 420, y: 420)[0] > 245)
    }

    @MainActor @Test func aWideGamutSourceKeepsItsColorSpaceAndColors() throws {
        let fixture = try PortraitFixture()
        fixture.options.background = .desktop
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = PortraitFixture.context(width: 320, height: 160, space: p3)
        context.setFillColor(CGColor(colorSpace: p3, components: [0.8, 0.2, 0.4, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
        let wide = context.makeImage()!
        let result = try fixture.render(desktop: fixture.wallpaper, source: wide)
        #expect(result.colorSpace?.name == CGColorSpace.displayP3)
        let expected = PortraitFixture.sample(wide, x: 100, y: 100)
        let actual = PortraitFixture.sample(result, x: 250, y: 250)
        #expect(zip(expected, actual).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }

    @MainActor @Test(arguments: [
        (CGFloat(0.75), CGFloat(0), CGFloat(0.45)),
        (CGFloat(0.74), CGFloat(1), CGFloat(0.75)),
    ])
    func watermarkInkContrastsWithTheBackdrop(_ gray: CGFloat, _ red: CGFloat, _ alpha: CGFloat) {
        let ink = PortraitCaptureRenderer.watermarkInk(on: NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        #expect(ink.usingColorSpace(.sRGB)!.redComponent == red && ink.alphaComponent == alpha)
    }
}

struct CapturedImagePortraitTests {
    @MainActor @Test func applyingAFrameKeepsTheOriginalAndTheUnframedBytes() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        #expect(capture.originalPNG == fixture.original && capture.unframedPNG == fixture.original)
    }

    @MainActor @Test func applyingAFrameGrowsTheImageToTheFramedSize() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        #expect(capture.pixels.width == 704 && capture.pixels.height == 544)
    }

    @MainActor @Test func editingAFrameNeverFramesItsPreviousOutput() throws {
        let fixture = try PortraitFixture()
        let (capture, style) = try fixture.framed()
        var edited = style
        edited.options.background = .color
        try capture.applyFrame(edited)
        #expect(capture.pixels.width == 704 && capture.pixels.height == 544)
    }

    @MainActor @Test func removingTheFrameRestoresTheOriginalBytes() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        capture.removeFrame()
        #expect(capture.frame == nil && capture.pngData == fixture.original)
    }

    @MainActor @Test func croppingAFramedCaptureKeepsTheOriginalAndFramesTheCrop() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        #expect(capture.originalPNG == fixture.original && capture.unframedPixels.width == 160)
        #expect(capture.pixels.width == 544 && capture.pixels.height == 544)
    }

    @MainActor @Test func theFramedCropShowsTheCroppedColor() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        #expect(PortraitFixture.sample(capture.pixels, x: 240, y: 240)[2] > 245)
    }

    @MainActor @Test func removingTheFrameFromACropLeavesTheCroppedBytes() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        let cropped = capture.unframedPNG
        capture.removeFrame()
        #expect(capture.pngData == cropped && capture.pixels.width == 160)
    }

    @MainActor @Test func aFrameThatCannotRenderLeavesTheCommittedCapture() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        let committed = capture.pngData
        #expect(throws: (any Error).self) {
            try capture.applyFrame(PortraitCaptureComposition(options: fixture.options, palette: [], pageColor: nil, desktop: nil))
        }
        #expect(capture.pngData == committed && capture.frame != nil)
    }

    @MainActor @Test func anOutOfImageCropFailsAndLeavesTheCommittedCapture() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        let committed = capture.pngData, cropped = capture.unframedPNG
        #expect(throws: (any Error).self) { try capture.crop(to: CGRect(x: 900, y: 900, width: 1, height: 1)) }
        #expect(capture.pngData == committed && capture.unframedPNG == cropped)
    }

    @MainActor @Test func recroppingToTheFullSourceRestoresTheOriginalBytes() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed()
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        try capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
        capture.removeFrame()
        #expect(capture.pngData == fixture.original)
    }

    @MainActor @Test func aTallSourceIsFramedAtTheCappedHeightAndRestoredOnRemoval() throws {
        let fixture = try PortraitFixture()
        let tall = PortraitFixture.context(width: 300, height: 4000)
        tall.setFillColor(NSColor.red.cgColor)
        tall.fill(CGRect(x: 0, y: 0, width: 300, height: 4000))
        let tallPNG = try PortraitFixture.png(tall.makeImage()!)
        let capture = try CapturedImage(pngData: tallPNG)
        try capture.applyFrame(fixture.composition())
        #expect(capture.pixels.height == 2544 && capture.unframedPixels.height == 4000)
        capture.removeFrame()
        #expect(capture.pngData == tallPNG && capture.pixels.height == 4000)
    }

    @MainActor @Test func invalidImageDataFails() {
        #expect(throws: (any Error).self) { try CapturedImage(pngData: Data([0, 1, 2])) }
    }

    @MainActor @Test func aRetinaFrameIsEncodedAtDoubleDensity() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed(.page, backingScale: 2)
        let encoded = try #require(CGImageSourceCreateWithData(capture.pngData as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)) as NSDictionary
        #expect(abs((properties[kCGImagePropertyDPIWidth] as! Double) - 144) < 0.1)
    }

    @MainActor @Test func removingARetinaFrameRestoresTheOriginalBytes() throws {
        let fixture = try PortraitFixture()
        let (capture, _) = try fixture.framed(.page, backingScale: 2)
        capture.removeFrame()
        #expect(capture.pngData == fixture.original)
    }
}

@MainActor
private struct EditedPortraitFixture {
    let fixture: PortraitFixture
    let capture: CapturedImage
    let editedSource: CGImage

    init() throws {
        fixture = try PortraitFixture()
        capture = try CapturedImage(pngData: fixture.original, backingScale: 2)
        try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
        try capture.applyFrame(fixture.composition(backingScale: 2))
        let context = PortraitFixture.context(width: 320, height: 160)
        context.draw(fixture.source, in: CGRect(x: 0, y: 0, width: 320, height: 160))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 180, y: 20, width: 20, height: 20))
        editedSource = context.makeImage()!
    }
}

struct EditedPortraitCaptureTests {
    @MainActor @Test func anAcceptedEditReplacesTheSourceButNotTheOriginal() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        #expect(edited.capture.originalPNG == edited.fixture.original && edited.capture.sourcePNG != edited.fixture.original)
    }

    @MainActor @Test func anAcceptedEditKeepsTheCropAndTheFrame() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        #expect(edited.capture.unframedPixels.width == 160 && edited.capture.frame != nil)
    }

    @MainActor @Test func anAcceptedEditReappliesTheOriginalCrop() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        #expect(PortraitFixture.sample(edited.capture.unframedPixels, x: 30, y: 30)[1] > 245)
    }

    @MainActor @Test func anEditWithMismatchedDimensionsIsRefused() throws {
        let edited = try EditedPortraitFixture()
        let small = try #require(edited.fixture.source.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(throws: (any Error).self) { try edited.capture.applyEditedOriginal(small) }
    }

    @MainActor @Test func aRefusedEditLeavesTheAcceptedCapture() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        let accepted = edited.capture.pngData, acceptedSource = edited.capture.sourcePNG
        let small = try #require(edited.fixture.source.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 10)))
        _ = try? edited.capture.applyEditedOriginal(small)
        #expect(edited.capture.pngData == accepted && edited.capture.sourcePNG == acceptedSource)
    }

    @MainActor @Test func removingTheFrameAfterAnEditLeavesTheUnframedCapture() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        edited.capture.removeFrame()
        #expect(edited.capture.pngData == edited.capture.unframedPNG)
    }

    @MainActor @Test func recroppingAnEditedCaptureRetainsTheEditedPixels() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        let acceptedSource = edited.capture.sourcePNG
        edited.capture.removeFrame()
        try edited.capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
        #expect(edited.capture.pngData == acceptedSource)
    }

    @MainActor @Test func recroppingAnEditedCaptureKeepsTheOriginalAndBackingScale() throws {
        let edited = try EditedPortraitFixture()
        try edited.capture.applyEditedOriginal(edited.editedSource)
        try edited.capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
        #expect(edited.capture.originalPNG == edited.fixture.original && edited.capture.backingScale == 2)
    }
}

struct PortraitDesktopWallpaperTests {
    private static let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)

    private static func candidate(bundle: String, title: String, layer: Int) -> PortraitDesktopSnapshot.Candidate {
        PortraitDesktopSnapshot.Candidate(id: 1, processID: 1, bounds: display, bundle: bundle, title: title, layer: layer)
    }

    @MainActor @Test func theWindowManagerWallpaperWindowIsTheDesktop() {
        #expect(Self.candidate(bundle: "com.apple.WindowManager", title: "Wallpaper", layer: -2147483624).isWallpaper(for: Self.display))
    }

    @MainActor @Test func aWallpaperOnAnotherDisplayIsNotTheDesktop() {
        let wallpaper = Self.candidate(bundle: "com.apple.WindowManager", title: "Wallpaper", layer: -2147483624)
        #expect(!wallpaper.isWallpaper(for: CGRect(x: 0, y: 0, width: 1440, height: 900)))
    }

    @MainActor @Test(arguments: [
        ("com.apple.dock", "Mission Control", -1),
        ("com.apple.finder", "Wallpaper", -1),
        ("com.apple.dock", "Dock", 20),
    ])
    func otherSystemWindowsAreNotTheDesktop(_ bundle: String, _ title: String, _ layer: Int) {
        #expect(!Self.candidate(bundle: bundle, title: title, layer: layer).isWallpaper(for: Self.display))
    }
}

@MainActor
private struct PortraitViewFixture {
    let fixture: PortraitFixture
    let view: PortraitCaptureView

    init(background: PortraitCaptureOptions.Background = .color, fraction: Double = 0.5, desktop: Bool = true) throws {
        _ = NSApplication.shared
        fixture = try PortraitFixture()
        fixture.options.background = background
        fixture.options.fraction = fraction
        view = PortraitCaptureView(source: fixture.source, pageColor: .green,
                                   composition: fixture.composition(hasDesktop: desktop), defaults: fixture.defaults)
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
    }

    func button(_ label: String) -> NSButton? {
        view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == label }
    }
}

struct PortraitCaptureViewTests {
    @MainActor @Test func theFramePageFillsThePaletteCardWidth() throws {
        let page = try PortraitViewFixture()
        #expect(page.view.bounds.size == NSSize(width: PortraitCaptureLayout.width, height: PortraitCaptureLayout.height))
    }

    @MainActor @Test func reopeningAnAppliedFrameLeavesApplyQuiet() throws {
        let page = try PortraitViewFixture()
        #expect(page.view.applyState == .unchanged && !page.view.captureButton.isEnabled)
    }

    @MainActor @Test func theLivePreviewRendersAtTheFullPageSizedImage() throws {
        let page = try PortraitViewFixture()
        let preview = try #require(page.view.previewImage)
        #expect(preview.width == 704 && preview.height == 544)
    }

    @MainActor @Test(arguments: [
        ("Use Website Color", PortraitCaptureOptions.Background.page),
        ("Use Desktop Wallpaper", .desktop),
        ("Use a Color", .color),
    ])
    func eachTileChoosesItsBackground(_ label: String, _ background: PortraitCaptureOptions.Background) throws {
        let page = try PortraitViewFixture(background: label == "Use a Color" ? .page : .color)
        try #require(page.button(label)).sendClick()
        #expect(page.view.composition.options.background == background)
    }

    @MainActor @Test func movingTheColorSliderChoosesTheColorBackgroundAtThatPosition() throws {
        let page = try PortraitViewFixture(background: .page)
        let slider = try #require(page.view.subviews.compactMap { $0 as? NSSlider }.first)
        slider.doubleValue = 0.7
        slider.sendAction(slider.action!, to: slider.target)
        #expect(page.view.composition.options.background == .color && page.view.composition.options.fraction == 0.7)
    }

    @MainActor @Test func aChangedFrameMakesApplyThePrimaryButton() throws {
        let page = try PortraitViewFixture()
        let slider = try #require(page.view.subviews.compactMap { $0 as? NSSlider }.first)
        slider.doubleValue = 0.7
        slider.sendAction(slider.action!, to: slider.target)
        #expect(page.view.applyState == .pending && page.view.captureButton.isEnabled)
    }

    @MainActor @Test func applyingReportsTheChosenFrame() throws {
        let page = try PortraitViewFixture()
        let slider = try #require(page.view.subviews.compactMap { $0 as? NSSlider }.first)
        slider.doubleValue = 0.7
        slider.sendAction(slider.action!, to: slider.target)
        var applied = false
        page.view.onCapture = { applied = true }
        page.view.captureButton.sendClick()
        #expect(applied && page.view.composition.options.fraction == 0.7)
    }

    @MainActor @Test func escapeLeavesThePage() throws {
        let page = try PortraitViewFixture()
        var canceled = false
        page.view.onCancel = { canceled = true }
        page.view.cancelOperation(nil)
        #expect(canceled)
    }

    @MainActor @Test func aLongErrorKeepsEverySubviewInsideTheCard() throws {
        let page = try PortraitViewFixture()
        page.view.showError(String(repeating: "A desktop error. ", count: 16))
        page.view.setFrameSize(page.view.fittingSize)
        page.view.layoutSubtreeIfNeeded()
        #expect(page.view.subviews.allSatisfy { page.view.bounds.contains($0.frame) })
    }

    @MainActor @Test func aSavedDesktopBackgroundWithoutAWallpaperKeepsApplyDisabled() throws {
        let page = try PortraitViewFixture(background: .desktop, desktop: false)
        #expect(!page.view.captureButton.isEnabled)
    }

    @MainActor @Test func aDeniedWallpaperExplainsScreenRecordingAndKeepsApplyDisabled() async throws {
        let page = try PortraitViewFixture(background: .desktop, desktop: false)
        let load = try #require(page.view.loadDesktop(screen: nil, provider: { _ in throw PortraitDesktopSnapshot.Failure.permission }))
        await load.value
        let messages = page.view.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
        #expect(!page.view.captureButton.isEnabled && messages.contains { $0.contains("Screen Recording") })
    }

    @MainActor @Test func theWatermarkToggleAndBackingChangesDoNotEnableApplyWithoutAWallpaper() throws {
        let page = try PortraitViewFixture(background: .desktop, desktop: false)
        try #require(page.button("Parc watermark")).sendClick()
        page.view.viewDidChangeBackingProperties()
        #expect(!page.view.captureButton.isEnabled)
    }

    @MainActor @Test func choosingTheWebsiteColorReplacesAnUnavailableWallpaper() throws {
        let page = try PortraitViewFixture(background: .desktop, desktop: false)
        try #require(page.button("Use Website Color")).sendClick()
        #expect(page.view.captureButton.isEnabled && page.view.composition.options.background == .page)
    }
}
