import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsBacking {
    @MainActor private final class Rig {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let split: ParcSplitView
        let opaque = NSView(), translucent = NSView()

        init() {
            _ = NSApplication.shared
            host.wantsLayer = true
            host.layer?.cornerRadius = 7
            split = ParcSplitView(frame: host.bounds)
            host.addSubview(split)
            opaque.wantsLayer = true
            opaque.layer?.backgroundColor = NSColor.white.cgColor
            translucent.wantsLayer = true
            translucent.layer?.backgroundColor = NSColor.clear.cgColor
            split.addArrangedSubview(opaque)
            split.addArrangedSubview(translucent)
            split.configure(orientation: .horizontal, factors: [1, 1])
            split.configureBacking(in: host, hasTranslucentPane: true)
        }
    }

    @Test func theContainerExposesTheParentBackingInsteadOfAFixedSeparatorSurface() {
        let rig = Rig()
        #expect(!rig.split.isOpaque)
        #expect(rig.split.dividerColor.alphaComponent == 0)
        #expect(rig.split.layer?.backgroundColor == nil)
        #expect(rig.split.layer?.masksToBounds == false)
    }

    @Test func theHostRevealsItsOriginalSurroundingWindowSurface() {
        let rig = Rig()
        #expect(rig.host.layer?.backgroundColor?.alpha == 0)
        #expect(rig.host.layer?.masksToBounds == false)
    }

    @Test func eachPaneOwnsContinuousRoundedClipping() {
        let rig = Rig()
        #expect(rig.split.arrangedSubviews.allSatisfy {
            $0.layer?.cornerRadius == 6 && $0.layer?.cornerCurve == .continuous && $0.layer?.masksToBounds == true
        })
    }

    @Test func perPaneBackingsRemainUnchanged() {
        let rig = Rig()
        #expect(rig.opaque.layer?.backgroundColor?.alpha == 1)
        #expect(rig.translucent.layer?.backgroundColor?.alpha == 0)
    }

    @Test func backingUpdatesPreservePaneIdentityParentAndGeometry() {
        let rig = Rig()
        let frames = rig.split.arrangedSubviews.map(\.frame)
        rig.split.configureBacking(in: rig.host, hasTranslucentPane: true)
        #expect(rig.split.arrangedSubviews[0] === rig.opaque && rig.split.arrangedSubviews[1] === rig.translucent)
        #expect(rig.split.arrangedSubviews.map(\.frame) == frames)
    }

    @Test func drawingTheDividerLeavesTheExistingParentPixelsIntact() throws {
        let rig = Rig()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 12, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.magenta.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        rig.split.drawDivider(in: NSRect(x: 0, y: 0, width: 12, height: 12))
        NSGraphicsContext.restoreGraphicsState()
        let pixel = try #require(bitmap.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB))
        #expect(pixel.redComponent > 0.99 && pixel.greenComponent < 0.01 && pixel.blueComponent > 0.99 && pixel.alphaComponent > 0.99)
    }

    @Test func returningToASingleNoteRestoresItsTransparentHostPolicy() {
        let rig = Rig()
        rig.opaque.removeFromSuperview()
        rig.split.configureBacking(in: rig.host, hasTranslucentPane: true)
        #expect(rig.host.layer?.backgroundColor?.alpha == 0)
        #expect(rig.host.layer?.masksToBounds == true)
        #expect(rig.translucent.layer?.cornerRadius == 0)
        #expect(rig.translucent.layer?.masksToBounds == false)
    }

    @Test func returningToOneOrdinaryPageRestoresItsOpaqueRoundedHost() {
        let rig = Rig()
        rig.opaque.removeFromSuperview()
        rig.split.configureBacking(in: rig.host, hasTranslucentPane: false)
        #expect(rig.host.layer?.backgroundColor == NSColor.white.cgColor)
        #expect(rig.host.layer?.cornerRadius == 7)
    }
}
