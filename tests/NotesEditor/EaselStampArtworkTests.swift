import AppKit

@main
struct EaselStampArtworkTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    @MainActor static func main() {
        designsStayInsideTheirBounds()
        emojiMeasurementsScale()
        missingSymbolsFallBack()
        layersAreCached()
        print("EaselStampArtworkTests passed")
    }

    @MainActor static func render(_ face: EaselStampFace, stamp: NSRect, canvas: NSSize) -> NSBitmapImageRep? {
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

    @MainActor static func designsStayInsideTheirBounds() {
        let stamp = NSRect(x: 60, y: 60, width: 80, height: 80)
        let visual = EaselStampArtwork.visualBounds(stamp)
        for design in EaselStampDesign.allCases {
            guard let bitmap = render(.design(design), stamp: stamp, canvas: NSSize(width: 200, height: 200)) else {
                failTest("Could not render \(design)")
            }
            var inside = 0, outside = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent, alpha > 0.01 else { continue }
                    let point = NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(bitmap.pixelsHigh - y) - 0.5)
                    if visual.insetBy(dx: -1, dy: -1).contains(point) { inside += 1 } else { outside += 1 }
                }
            }
            expect(inside > 400, "\(design) draws something")
            expect(outside == 0, "\(design) never paints past its rim")
        }
    }

    @MainActor static func emojiMeasurementsScale() {
        let small = EaselStampArtwork.emojiSize("🎉", side: 50), large = EaselStampArtwork.emojiSize("🎉", side: 100)
        expect(small.width > 0 && abs(large.width - small.width * 2) < 0.01, "Emoji measurements scale from one cached reading")
        expect(render(.emoji("🎉"), stamp: NSRect(x: 0, y: 0, width: 0.5, height: 0.5), canvas: NSSize(width: 8, height: 8)) != nil,
               "Tiny emoji stamps draw nothing without failing")
    }

    @MainActor static func missingSymbolsFallBack() {
        let missing = "parc.not.a.real.symbol"
        let first = EaselStampArtwork.symbol(missing), second = EaselStampArtwork.symbol(missing)
        expect(first != nil && first === second, "Missing symbols fall back to one cached placeholder")
        expect(EaselStampArtwork.symbol("cloud") != nil, "Real symbols load")
    }

    @MainActor static func layersAreCached() {
        let first = EaselStampArtwork.layers(.heart), second = EaselStampArtwork.layers(.heart)
        expect(!first.isEmpty && first.count == second.count && zip(first, second).allSatisfy { $0.path === $1.path },
               "Design layers are built once and reused")
    }
}
