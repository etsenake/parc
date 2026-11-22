import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitPaneControlPresentationTestsLayout {
    private typealias TrackingEvent = SplitPaneControlPresentationTestsSupport.TrackingEvent
    private typealias ControlFixture = SplitPaneControlPresentationTestsSupport.ControlFixture

    private typealias Skip = SplitPaneControlLayoutSkip
    private static let bounds = NSRect(x: 0, y: 0, width: 32, height: 24)

    private final class GeometryWrites: NSObject {
        private let surface: CALayer
        private var surfaceFrameWrites = 0
        private var surfaceLayerWrites = 0
        private var glyphFrameWrites = 0

        init(surface: CALayer) { self.surface = surface }

        @MainActor static func during(_ fixture: ControlFixture, _ update: () -> Void)
            -> (surfaceFrame: Int, surfaceLayer: Int, glyphFrame: Int) {
            let keys = ["frame", "bounds", "position", "transform", "cornerRadius", "maskedCorners", "shadowPath"]
            let writes = GeometryWrites(surface: fixture.background)
            let writeSurfaceFrame = fixture.control.writeSurfaceFrame
            fixture.control.writeSurfaceFrame = { layer, frame in
                writes.surfaceFrameWrites += 1
                writeSurfaceFrame(layer, frame)
            }
            for key in keys { fixture.background.addObserver(writes, forKeyPath: key, options: [], context: nil) }
            fixture.glyph.addObserver(writes, forKeyPath: "frame", options: [], context: nil)
            defer {
                fixture.glyph.removeObserver(writes, forKeyPath: "frame")
                for key in keys { fixture.background.removeObserver(writes, forKeyPath: key) }
                fixture.control.writeSurfaceFrame = writeSurfaceFrame
            }
            update()
            return (writes.surfaceFrameWrites, writes.surfaceLayerWrites, writes.glyphFrameWrites)
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                                   context: UnsafeMutableRawPointer?) {
            if object as? CALayer === surface { surfaceLayerWrites += 1 }
            else { glyphFrameWrites += 1 }
        }
    }

    @Test func aMatchingCentredSurfaceFrameSkips() {
        let current = Skip.surfaceFrame(bounds: Self.bounds, surfaceSize: SplitPaneControl.surfaceSize)
        #expect(Skip.shouldSkipSurface(current: current, bounds: Self.bounds, surfaceSize: SplitPaneControl.surfaceSize))
    }

    @Test func aMismatchedSurfaceFrameDoesNotSkip() {
        #expect(!Skip.shouldSkipSurface(current: .zero, bounds: Self.bounds, surfaceSize: SplitPaneControl.surfaceSize))
    }

    @Test func aMatchingGlyphFrameSkips() {
        #expect(Skip.shouldSkipGlyph(current: Self.bounds, bounds: Self.bounds))
    }

    @Test func aMismatchedGlyphFrameDoesNotSkip() {
        #expect(!Skip.shouldSkipGlyph(current: .zero, bounds: Self.bounds))
    }

    @Test func theSurfaceStaysCentredInsideALargerControl() {
        let oversized = NSRect(x: 0, y: 0, width: 40, height: 30)
        #expect(Skip.surfaceFrame(bounds: oversized, surfaceSize: SplitPaneControl.surfaceSize) == NSRect(x: 4, y: 3, width: 32, height: 24))
    }

    @Test func theFirstLargerLayoutWritesTheSurfaceAndGlyphFrames() {
        let fixture = ControlFixture()
        fixture.control.setFrameSize(NSSize(width: 36, height: 28))
        let writes = GeometryWrites.during(fixture) { fixture.control.layoutSubtreeIfNeeded() }
        #expect(writes.surfaceFrame == 1)
        #expect(writes.surfaceLayer > 0)
        #expect(writes.glyphFrame == 1)
    }

    @Test func aBoundsChangeRelaysTheCentredSurfaceAndGlyph() {
        let fixture = ControlFixture()
        fixture.control.frame = NSRect(x: 20, y: 20, width: 36, height: 28)
        fixture.control.layoutSubtreeIfNeeded()
        fixture.control.setFrameSize(NSSize(width: 40, height: 30))
        let writes = GeometryWrites.during(fixture) { fixture.control.layout() }
        #expect(writes.surfaceFrame == 1)
        #expect(writes.surfaceLayer > 0)
        #expect(writes.glyphFrame == 1)
        #expect(fixture.background.frame == Skip.surfaceFrame(bounds: fixture.control.bounds, surfaceSize: fixture.control.surfaceSize))
        #expect(fixture.glyph.frame == fixture.control.bounds)
    }

    @Test(arguments: [NSSize(width: 36, height: 28), NSSize(width: 40, height: 30)])
    func aLayoutAtTheSameSizeWritesNeitherTheSurfaceNorTheGlyph(size: NSSize) {
        let fixture = ControlFixture()
        fixture.control.setFrameSize(size)
        fixture.control.layoutSubtreeIfNeeded()
        let surface = fixture.background.frame, glyph = fixture.glyph.frame
        let writes = GeometryWrites.during(fixture) { fixture.control.layout() }
        #expect(writes == (0, 0, 0))
        #expect(fixture.background.frame == surface)
        #expect(fixture.glyph.frame == glyph)
    }

    @Test func aHoverRefreshIsNotGatedByTheLayoutSkip() {
        let fixture = ControlFixture()
        fixture.control.frame = NSRect(x: 20, y: 20, width: 36, height: 28)
        fixture.control.layoutSubtreeIfNeeded()
        fixture.control.updateTrackingAreas()
        let event = TrackingEvent()
        event.area = fixture.control.trackingAreas.first { $0.owner === fixture.control && $0.options.contains(.inVisibleRect) && !$0.options.contains(.cursorUpdate) }
        let writes = GeometryWrites.during(fixture) { fixture.control.mouseEntered(with: event) }
        #expect(fixture.control.isHovered)
        #expect(abs(fixture.background.opacity - 0.05) < 0.00001)
        #expect(writes == (0, 0, 0))
    }
}
