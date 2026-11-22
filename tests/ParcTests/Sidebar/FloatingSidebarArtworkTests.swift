import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

@MainActor
struct FloatingSidebarArtworkTests {
    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.002) -> Bool { abs(a - b) <= tolerance }

    static func shadowImage() throws -> NSImage {
        let directory = try #require(Bundle.module.url(forResource: "ChromeFixtures", withExtension: nil))
            .appendingPathComponent("FloatingSidebar", isDirectory: true)
        return try #require(FloatingSidebarSurface.shadowImage(in: directory))
    }

    @Test func theShadowIsBuiltOnce() throws {
        let directory = try #require(Bundle.module.url(forResource: "FloatingSidebar", withExtension: nil, subdirectory: "ChromeFixtures"))
        let artwork = FloatingSidebarSurface.ShadowArtwork(in: directory)
        let first = try #require(artwork.image)
        #expect(artwork.image === first)
    }

    @Test func theSurfaceRoundsItsCornersAtEightPoints() {
        #expect(FloatingSidebarSurface.cornerRadius == 8)
    }

    @Test func theSurfaceHasAOnePointEdge() {
        #expect(FloatingSidebarSurface.borderWidth == 1)
    }

    @Test func theEdgeIsSRGBWhiteAtThirtyPercent() throws {
        let border = try #require(NSColor(cgColor: FloatingSidebarSurface.borderColor)?.usingColorSpace(.sRGB))
        #expect(Self.near(border.redComponent, 1) && Self.near(border.greenComponent, 1) && Self.near(border.blueComponent, 1))
        #expect(Self.near(border.alphaComponent, 0.3))
    }

    @Test func theShadowShowsAtTwentyPercentTenPointsOut() {
        #expect(FloatingSidebarSurface.shadowAlpha == 0.2)
        #expect(FloatingSidebarSurface.shadowOutset == 10)
    }

    @Test func theShadowArtworkIsAFortyPointImage() throws {
        #expect(try Self.shadowImage().size == NSSize(width: 40, height: 40))
    }

    @Test func theShadowArtworkStretchesFromItsCapInsets() throws {
        let caps = try Self.shadowImage().capInsets
        #expect(caps.top == 19 && caps.left == 19 && caps.bottom == 20 && caps.right == 20)
    }

    @Test func theShadowArtworkHoldsBothRenditionsAtTheOneTimesPointSize() throws {
        let bitmaps = try Self.shadowImage().representations.compactMap { $0 as? NSBitmapImageRep }
        #expect(bitmaps.map(\.pixelsWide).sorted() == [40, 80])
        #expect(bitmaps.allSatisfy { $0.size == NSSize(width: 40, height: 40) })
    }

    @Test func theShadowArtworkIsARingClearOutsideAndInItsHole() throws {
        let base = try #require(try Self.shadowImage().representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == 40 })
        func alpha(_ x: Int, _ y: Int) -> CGFloat { base.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
        #expect(alpha(0, 20) < 0.01 && alpha(20, 20) < 0.01)
        #expect(alpha(9, 20) > 0.35 && alpha(9, 20) < 0.4)
    }

    @Test func missingArtworkLoadsNothing() {
        #expect(FloatingSidebarSurface.shadowImage(in: nil) == nil)
        #expect(FloatingSidebarSurface.shadowImage(in: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) == nil)
    }

    @Test func squareCornersNeedNoMask() {
        #expect(FloatingSidebarSurface.mask(radius: 0) == nil)
    }

    @Test func theMaskIsASquareStretchedFromItsCaps() throws {
        let mask = try #require(FloatingSidebarSurface.mask(radius: 8))
        #expect(mask.size == NSSize(width: 17, height: 17))
        #expect(mask.resizingMode == .stretch)
        #expect(mask.capInsets.top == 8 && mask.capInsets.left == 8 && mask.capInsets.bottom == 8 && mask.capInsets.right == 8)
    }

    @Test func theMaskHasRoundedCornersAndAnOpaqueMiddle() throws {
        let mask = try #require(FloatingSidebarSurface.mask(radius: 8))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 17, pixelsHigh: 17, bitsPerSample: 8, samplesPerPixel: 4,
                                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        mask.draw(in: NSRect(x: 0, y: 0, width: 17, height: 17))
        NSGraphicsContext.restoreGraphicsState()
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05)
        #expect((bitmap.colorAt(x: 8, y: 8)?.alphaComponent ?? 0) > 0.99)
    }

    @Test func theCrossfadeIsFullyShownAtNinetyPercentOfTheSwipe() {
        #expect(FloatingSidebarSurface.pagingOpaqueProgress == 0.9)
    }

    @Test(arguments: [CGFloat(0), -0.2])
    func atTheStartOnlyTheLeftPagesBlurShows(_ progress: CGFloat) {
        let blend = FloatingSidebarSurface.pagingBlend(progress: progress)
        #expect(blend.base == 1 && blend.incoming == 0)
    }

    @Test func halfwayToOpaqueTheCrossfadeIsAtHalf() {
        let blend = FloatingSidebarSurface.pagingBlend(progress: 0.45)
        #expect(Self.near(blend.base, 1) && Self.near(blend.incoming, 0.5))
    }

    @Test func atNinetyPercentBothBlursAreFullyShown() {
        let blend = FloatingSidebarSurface.pagingBlend(progress: 0.9)
        #expect(Self.near(blend.base, 1) && Self.near(blend.incoming, 1))
    }

    @Test func pastNinetyPercentTheBaseFadesBeneathTheOpaqueCrossfade() {
        let blend = FloatingSidebarSurface.pagingBlend(progress: 0.95)
        #expect(Self.near(blend.base, 0.5) && Self.near(blend.incoming, 1))
    }

    @Test(arguments: [CGFloat(1), 1.3])
    func atTheEndOnlyTheRightPagesBlurRemains(_ progress: CGFloat) {
        let blend = FloatingSidebarSurface.pagingBlend(progress: progress)
        #expect(blend.base == 0 && blend.incoming == 1)
    }

    @Test(arguments: 1...100)
    func theBlendMovesSteadily(_ step: Int) {
        let previous = FloatingSidebarSurface.pagingBlend(progress: CGFloat(step - 1) / 100)
        let next = FloatingSidebarSurface.pagingBlend(progress: CGFloat(step) / 100)
        #expect(next.base <= previous.base + 1e-9 && next.incoming >= previous.incoming - 1e-9)
        #expect(abs(next.base - previous.base) <= 0.11 && abs(next.incoming - previous.incoming) <= 0.012)
    }

    @Test(arguments: 0...100)
    func oneOfTheTwoBlursIsAlwaysFullyShown(_ step: Int) {
        let blend = FloatingSidebarSurface.pagingBlend(progress: CGFloat(step) / 100)
        #expect(blend.base >= 1 - 1e-9 || blend.incoming >= 1 - 1e-9)
    }
}
