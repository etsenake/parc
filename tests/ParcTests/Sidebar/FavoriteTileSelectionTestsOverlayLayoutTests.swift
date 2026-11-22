import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct FavoriteTileSelectionTestsOverlayLayoutTests {
    private func layoutWrites(_ view: NSView) -> Int {
        SidebarLayerWrites.count(byLayersOf: view) { view.layout() }
    }

    @Test func theFirstRecordingDotLayoutWritesItsLayers() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        #expect(layoutWrites(dot) > 0)
    }

    @Test func aNoOpRecordingDotLayoutSkipsTheRewrite() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = layoutWrites(dot)
        #expect(layoutWrites(dot) == 0)
    }

    @Test func aRecordingDotBoundsChangeStillRewritesLayers() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = layoutWrites(dot)
        dot.setFrameSize(NSSize(width: 10, height: 10))
        #expect(layoutWrites(dot) > 0)
    }

    @Test func aFollowUpRecordingDotLayoutAtTheNewSizeIsANoOp() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = layoutWrites(dot)
        dot.setFrameSize(NSSize(width: 10, height: 10))
        _ = layoutWrites(dot)
        #expect(layoutWrites(dot) == 0)
    }

    @Test func reduceMotionArmsNoRecordingDotPulse() {
        let host = PulseHost(reduceMotion: true)
        host.window.contentView!.addSubview(host.dot)
        #expect(host.dot.pulse == nil)
    }

    @Test func theRecordingDotPulseStillArmsAfterLayoutSkips() {
        let host = PulseHost(reduceMotion: false)
        host.window.contentView!.addSubview(host.dot)
        #expect(host.dot.pulse != nil)
    }

    @Test func aLayoutSkipLeavesThePulseAnimationInstalled() {
        let host = PulseHost(reduceMotion: false)
        host.window.contentView!.addSubview(host.dot)
        _ = layoutWrites(host.dot)
        #expect(layoutWrites(host.dot) == 0)
        #expect(host.dot.pulse != nil)
    }

    @MainActor private final class PulseHost {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 40, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))

        init(reduceMotion: Bool) {
            dot.reducesMotion = { reduceMotion }
            window.isReleasedWhenClosed = false
        }

        deinit {
            MainActor.assumeIsolated { window.close() }
        }
    }

    private func isolatedRing() -> FavoriteHighlightRingView {
        let ring = FavoriteHighlightRingView(frame: CGRect(x: 0, y: 0, width: 60, height: 47))
        ring.style = .highlight(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        return ring
    }

    @Test func theFirstHighlightRingLayoutWritesItsLayers() {
        let ring = isolatedRing()
        #expect(layoutWrites(ring) > 0)
    }

    @Test func aNoOpHighlightRingLayoutSkipsTheRewriteAndLeavesTheStyle() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        let strokeBefore = ring.ring.strokeColor
        #expect(layoutWrites(ring) == 0)
        #expect(ring.ring.strokeColor === strokeBefore)
    }

    @Test func aHighlightRingBoundsChangeStillRewritesThePath() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        ring.setFrameSize(NSSize(width: 80, height: 47))
        #expect(layoutWrites(ring) > 0)
        #expect(ring.ring.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds))
    }

    @Test func aFollowUpHighlightRingLayoutAtTheNewSizeIsANoOp() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        ring.setFrameSize(NSSize(width: 80, height: 47))
        _ = layoutWrites(ring)
        #expect(layoutWrites(ring) == 0)
    }

    @Test func styleChangesStayUngatedByTheLayoutSkip() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        ring.style = .developerTab
        #expect(ring.ring.strokeColor == NSColor.black.cgColor)
        #expect(ring.foreground.lineDashPattern == [6, 6])
    }
}
