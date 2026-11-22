import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselStampArtworkTests {
    func render(_ face: EaselStampFace, stamp: NSRect, canvas: NSSize) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        EaselStampArtwork.draw(face, in: stamp, ink: .black)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    func paintedPixels(of design: EaselStampDesign) throws -> (inside: Int, outside: Int) {
        let stamp = NSRect(x: 60, y: 60, width: 80, height: 80)
        let visual = EaselStampArtwork.visualBounds(stamp)
        let bitmap = try #require(render(.design(design), stamp: stamp, canvas: NSSize(width: 200, height: 200)))
        var inside = 0, outside = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent, alpha > 0.01 else { continue }
                let point = NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(bitmap.pixelsHigh - y) - 0.5)
                if visual.insetBy(dx: -1, dy: -1).contains(point) { inside += 1 } else { outside += 1 }
            }
        }
        return (inside, outside)
    }

    @Test(arguments: EaselStampDesign.allCases)
    func aDesignDrawsSomething(design: EaselStampDesign) throws {
        #expect(try paintedPixels(of: design).inside > 0)
    }

    @Test(arguments: EaselStampDesign.allCases)
    func aDesignNeverPaintsPastItsRim(design: EaselStampDesign) throws {
        #expect(try paintedPixels(of: design).outside == 0)
    }

    @Test func emojiMeasurementsScaleFromOneCachedReading() {
        let small = EaselStampArtwork.emojiSize("🎉", side: 50), large = EaselStampArtwork.emojiSize("🎉", side: 100)
        #expect(small.width > 0)
        #expect(abs(large.width - small.width * 2) < 0.01)
    }

    @Test func tinyEmojiStampsDrawNothingWithoutFailing() {
        #expect(render(.emoji("🎉"), stamp: NSRect(x: 0, y: 0, width: 0.5, height: 0.5), canvas: NSSize(width: 8, height: 8)) != nil)
    }

    @Test func missingSymbolsFallBackToOneCachedPlaceholder() {
        let missing = "parc.not.a.real.symbol"
        let first = EaselStampArtwork.symbol(missing), second = EaselStampArtwork.symbol(missing)
        #expect(first != nil)
        #expect(first === second)
    }

    @Test func realSymbolsLoad() {
        #expect(EaselStampArtwork.symbol("cloud") != nil)
    }

    @Test func designLayersAreBuiltOnceAndReused() {
        let first = EaselStampArtwork.layers(.heart), second = EaselStampArtwork.layers(.heart)
        #expect(!first.isEmpty)
        #expect(first.count == second.count)
        #expect(zip(first, second).allSatisfy { $0.path === $1.path })
    }
}
