import AppKit
import SwiftUI
@testable import Parc

@MainActor
enum SidebarHeaderGlyphTestsSupport {
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0005) -> Bool { abs(a - b) <= e }

    static func render(_ size: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func inkBounds(_ rep: NSBitmapImageRep, threshold: CGFloat = 0.2) -> (minX: Int, maxX: Int) {
        var minX = Int.max, maxX = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where rep.colorAt(x: x, y: y)!.alphaComponent > threshold { minX = min(minX, x); maxX = max(maxX, x) }
        }
        return (minX, maxX)
    }

    static let light = TranslucentButtonColors.standard(dark: false)

    @MainActor final class Face {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        let face: TranslucentButtonFace

        init() {
            view.appearance = NSAppearance(named: .aqua)
            face = TranslucentButtonFace(view: view)
        }

        func draw() -> (fill: CGFloat, edge: CGFloat, tint: NSColor?) {
            var tint: NSColor?
            let size = view.bounds.size
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            face.draw(in: view.bounds, enabled: true, view: view) { tint = $0 }
            NSGraphicsContext.restoreGraphicsState()
            return (rep.colorAt(x: 32, y: 32)!.alphaComponent, rep.colorAt(x: 0, y: 32)!.alphaComponent, tint)
        }
    }
}
