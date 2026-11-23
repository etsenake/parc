import AppKit
import Testing
@testable import ParcLibrary

struct CapturePresentationTests {
    private static let bounds = NSRect(x: 0, y: 0, width: 1000, height: 700)
    private static let source = NSRect(x: 100, y: 120, width: 300, height: 200)
    private static let pixels = NSSize(width: 600, height: 400)

    private static func layout(source: NSRect?, in area: NSRect = bounds, pixels: NSSize = pixels, paletteHeight: CGFloat = 350,
                               editing: Bool = false, fullPalette: Bool = false) -> CapturePresentation.Layout {
        CapturePresentation.layout(bounds: area, pixels: pixels, source: source, paletteHeight: paletteHeight,
                                   editing: editing, fullPalette: fullPalette)
    }

    @Test func backingScalePixelsKeepTheOriginalLogicalRectangle() {
        #expect(Self.layout(source: Self.source).image == Self.source)
    }

    @Test func thePaletteSitsToTheRightWhenThereIsRoom() {
        #expect(Self.layout(source: Self.source).palette == NSRect(x: 414, y: 116, width: 273, height: 350))
    }

    @Test func aTrailingCaptureKeepsItsRectangle() {
        let trailing = NSRect(x: 600, y: 450, width: 300, height: 200)
        #expect(Self.layout(source: trailing).image == trailing)
    }

    @Test func aTrailingCapturePutsThePaletteOnItsLeft() {
        let trailing = NSRect(x: 600, y: 450, width: 300, height: 200)
        #expect(Self.layout(source: trailing).palette == NSRect(x: 313, y: 304, width: 273, height: 350))
    }

    @Test func aSelectionInsideTheImageMapsToPixels() {
        let crop = CapturePresentation.pixelCrop(NSRect(x: 175, y: 170, width: 150, height: 100), imageRect: Self.source,
                                                 pixels: NSSize(width: 1200, height: 800))
        #expect(crop == NSRect(x: 300, y: 200, width: 600, height: 400))
    }

    @Test func aSelectionOfTheWholeImageMapsToAllPixels() {
        let crop = CapturePresentation.pixelCrop(Self.source, imageRect: Self.source, pixels: NSSize(width: 1200, height: 800))
        #expect(crop == NSRect(x: 0, y: 0, width: 1200, height: 800))
    }

    @Test func aSelectionOutsideTheImageHasNoCrop() {
        let crop = CapturePresentation.pixelCrop(NSRect(x: -20, y: -20, width: 40, height: 40), imageRect: Self.source,
                                                 pixels: NSSize(width: 1200, height: 800))
        #expect(crop == nil)
    }

    @Test(arguments: LayoutSample.all)
    func theImageAndPaletteStayInsideThePane(_ sample: LayoutSample) {
        let (area, pixels) = (sample.area, sample.pixels)
        let result = Self.layout(source: area, in: area, pixels: pixels, paletteHeight: 450)
        #expect(area.contains(result.image) && area.contains(result.palette))
    }

    @Test(arguments: LayoutSample.all)
    func theImageKeepsItsAspectRatio(_ sample: LayoutSample) {
        let (area, pixels) = (sample.area, sample.pixels)
        let image = Self.layout(source: area, in: area, pixels: pixels, paletteHeight: 450).image
        #expect(image.width > 0 && image.height > 0 && abs(image.width / image.height - pixels.width / pixels.height) < 0.0001)
    }

    @Test(arguments: LayoutSample.all.filter { $0.area.width < 576 })
    func compactPanesKeepThePreviewClearOfThePalette(_ sample: LayoutSample) {
        let (area, pixels) = (sample.area, sample.pixels)
        let result = Self.layout(source: area, in: area, pixels: pixels, paletteHeight: 450)
        #expect(!result.image.intersects(result.palette))
    }

    @Test(arguments: LayoutSample.all)
    func editingKeepsTheImageInsideThePane(_ sample: LayoutSample) {
        let (area, pixels) = (sample.area, sample.pixels)
        #expect(area.contains(Self.layout(source: area, in: area, pixels: pixels, paletteHeight: 450, editing: true).image))
    }

    struct LayoutSample: Sendable {
        let area: NSRect
        let pixels: NSSize

        static let all = [160.0, 320, 480, 600, 1000].flatMap { width in
            [200.0, 400, 800].flatMap { height in
                [NSSize(width: 400, height: 200), NSSize(width: 300, height: 9000)].map { pixels in
                    LayoutSample(area: NSRect(x: 0, y: 0, width: width, height: height), pixels: pixels)
                }
            }
        }
    }

    private static let viewportPixels = NSSize(width: 2000, height: 1400)

    private static func visibleArea(pixels: NSSize = viewportPixels, in area: NSRect = bounds, paletteHeight: CGFloat = 350,
                                    editing: Bool = false, fullPalette: Bool = false) -> CapturePresentation.Layout {
        layout(source: area, in: area, pixels: pixels, paletteHeight: paletteHeight, editing: editing, fullPalette: fullPalette)
    }

    private static func card(_ result: CapturePresentation.Layout) -> NSRect {
        result.image.insetBy(dx: -CapturePresentation.imageBorder, dy: -CapturePresentation.imageBorder)
    }

    @Test func aSmallRegionStaysWhereItWasCaptured() {
        #expect(!Self.layout(source: Self.source).lifted)
    }

    @Test func aVisibleAreaCaptureBecomesACardClearlySmallerThanThePage() {
        let image = Self.visibleArea().image
        #expect(image.width < Self.bounds.width * 0.7 && image.height < Self.bounds.height * 0.8)
    }

    @Test func aVisibleAreaCardLeavesDimmedPageOnEverySide() {
        #expect(Self.bounds.insetBy(dx: 24, dy: 24).contains(Self.card(Self.visibleArea())))
    }

    @Test func aVisibleAreaCardHasThePaletteBesideItWithoutOverlap() {
        let result = Self.visibleArea()
        #expect(!result.palette.intersects(Self.card(result)) && result.palette.minX >= Self.card(result).maxX)
    }

    @Test func aVisibleAreaCardKeepsTheImageAndPaletteCentredTogether() {
        let result = Self.visibleArea()
        let left = Self.card(result).minX - Self.bounds.minX, right = Self.bounds.maxX - result.palette.maxX
        #expect(abs(left - right) < 1)
    }

    @Test func aVisibleAreaCardLiftsFromThePageSizedCapture() {
        let result = Self.visibleArea()
        #expect(result.lifted && result.captured.width > Self.bounds.width * 0.9 && result.captured.contains(result.image))
    }

    @Test func aFullPageCaptureIsATallCardBesideThePalette() {
        let result = Self.visibleArea(pixels: NSSize(width: 2000, height: 9000))
        #expect(Self.bounds.insetBy(dx: 24, dy: 24).contains(Self.card(result)) && !result.palette.intersects(Self.card(result)))
    }

    @Test func aFramedVisibleAreaCaptureKeepsItsNewShapeInTheCard() {
        let result = Self.visibleArea(pixels: NSSize(width: 1600, height: 1600))
        #expect(abs(result.image.width - result.image.height) < 0.001 && !result.palette.intersects(Self.card(result)))
    }

    @Test func theFramePageSitsBesideTheCardInsideThePage() {
        let result = Self.visibleArea(paletteHeight: 620, fullPalette: true)
        #expect(Self.bounds.contains(result.palette) && !result.palette.intersects(Self.card(result)))
    }

    @Test func aLargeRegionMovesAsideForThePaletteWithoutGrowing() {
        let region = NSRect(x: 200, y: 50, width: 600, height: 600)
        let result = Self.layout(source: region, pixels: NSSize(width: 1200, height: 1200))
        #expect(result.lifted && result.image.width <= 600 && !result.palette.intersects(Self.card(result)))
    }

    @Test func croppingAVisibleAreaCaptureUsesMoreOfThePageThanTheCard() {
        #expect(Self.visibleArea(editing: true).image.width > Self.visibleArea().image.width)
    }

    @Test(arguments: LayoutSample.all.filter { $0.area.width >= 576 })
    func widePanesKeepThePaletteClearOfAPageSizedCapture(_ sample: LayoutSample) {
        let result = Self.layout(source: sample.area, in: sample.area, pixels: sample.pixels, paletteHeight: 450)
        #expect(!result.palette.intersects(Self.card(result)))
    }

    private static let narrow = NSRect(x: 0, y: 0, width: 400, height: 500)

    @Test func aNarrowPaneCapsThePaletteHeight() {
        let capped = Self.layout(source: nil, in: Self.narrow, pixels: NSSize(width: 800, height: 600), paletteHeight: 400)
        #expect(capped.palette.height < 300)
    }

    @Test func aNarrowPaneCanShowTheWholeFramePage() {
        let page = Self.layout(source: nil, in: Self.narrow, pixels: NSSize(width: 800, height: 600), paletteHeight: 400, fullPalette: true)
        #expect(page.palette.height == 400 && Self.narrow.contains(page.palette))
    }

    @Test func theWholeFramePageKeepsTheImageAboveIt() {
        let page = Self.layout(source: nil, in: Self.narrow, pixels: NSSize(width: 800, height: 600), paletteHeight: 400, fullPalette: true)
        #expect(page.image.maxY <= page.palette.minY)
    }

    @MainActor @Test func theLightImageBackgroundIsWhite() throws {
        let light = try #require(CaptureAppearance.imageBackground(false).usingColorSpace(.sRGB))
        #expect(light.redComponent == 1)
    }

    @MainActor @Test func theDarkImageBackgroundLeansBlue() throws {
        let dark = try #require(CaptureAppearance.imageBackground(true).usingColorSpace(.sRGB))
        #expect(dark.blueComponent > dark.redComponent)
    }

    @MainActor @Test func theCursorArtworkLoadsAtItsNativeHeight() throws {
        let cursor = try #require(CaptureArtwork.image("camera-cross-cursor", in: Bundle.module.url(forResource: "CaptureArtwork", withExtension: nil, subdirectory: "CaptureFixtures")))
        #expect(cursor.size.height == 50)
    }

    @MainActor @Test func theCursorArtworkCarriesRetinaRenditions() throws {
        let cursor = try #require(CaptureArtwork.image("camera-cross-cursor", in: Bundle.module.url(forResource: "CaptureArtwork", withExtension: nil, subdirectory: "CaptureFixtures")))
        #expect(cursor.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsHigh }.sorted() == [50, 100] && !cursor.isTemplate)
    }
}
