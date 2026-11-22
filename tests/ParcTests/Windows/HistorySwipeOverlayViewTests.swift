import AppKit
@testable import ParcCore
import Testing
@testable import Parc
@testable import ParcKit

struct HistorySwipeOverlayViewTests {
    @Test @MainActor
    func theOverlayClipsToItsPane() {
        #expect(makeView().layer?.masksToBounds == true)
    }

    @Test(arguments: [false, true]) @MainActor
    func theOverlayLetsClicksThrough(indicatorVisible: Bool) {
        let view = indicatorVisible ? tracking(.back) : makeView()
        let point = indicatorVisible ? NSPoint(x: 50, y: 200) : NSPoint(x: 300, y: 200)
        #expect(view.hitTest(point) == nil)
    }

    @Test @MainActor
    func theOverlayStaysOutOfTheAccessibilityTree() {
        let view = makeView()
        #expect(!view.isAccessibilityElement())
        #expect(view.accessibilityChildren()?.isEmpty == true)
    }

    @Test @MainActor
    func theShadowAndIndicatorStartHidden() throws {
        let parts = try layers(in: makeView())
        #expect(parts.shadow.isHidden)
        #expect(parts.indicator.isHidden)
    }

    @Test @MainActor
    func theIndicatorClipsToItsContinuousCornerRing() throws {
        let layer = try #require(layers(in: makeView()).indicator.layer)
        #expect(layer.masksToBounds)
        #expect(layer.cornerCurve == .continuous)
        #expect(layer.borderWidth == 1)
    }

    @Test @MainActor
    func theIndicatorUsesActivePopoverMaterial() throws {
        let indicator = try layers(in: makeView()).indicator
        let material = try #require(indicator.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        #expect(material.material == .popover)
        #expect(material.blendingMode == .withinWindow)
        #expect(material.state == .active)
    }

    @Test @MainActor
    func theShadowIsSoftAndDropsBelowTheIndicator() throws {
        let shadow = try layers(in: makeView()).shadow
        let shade = try #require(shadow.layer?.sublayers?.first)
        #expect(shadow.layer?.masksToBounds == false)
        #expect(shade.shadowRadius == 8)
        #expect(shade.shadowOffset == CGSize(width: 0, height: -2))
    }

    @Test(arguments: [(true, 1.0, 0.15, 0.25), (false, 0.0, 0.125, 0.2)]) @MainActor
    func changingPaletteUpdatesTheRingAndShadow(dark: Bool, white: Double, alpha: Double, shadowAlpha: Double) throws {
        let view = makeView()
        view.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: !dark)
        view.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: dark)
        let parts = try layers(in: view)
        let shade = try #require(parts.shadow.layer?.sublayers?.first)
        let border = try #require(parts.indicator.layer?.borderColor)
        let ring = try #require(NSColor(cgColor: border)?.usingColorSpace(.genericGray))
        #expect(view.appearance?.name == (dark ? .darkAqua : .aqua))
        #expect(abs(ring.whiteComponent - white) < 1e-6)
        #expect(abs(ring.alphaComponent - alpha) < 0.002)
        #expect(abs(Double(shade.shadowOpacity) - shadowAlpha) < 1e-6)
    }

    @Test @MainActor
    func clearingThePaletteRestoresInheritedAppearance() {
        let view = makeView()
        view.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: true)
        view.palette = nil
        #expect(view.appearance == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func theCircleAndShadowRestInsideTheSwipeEdge(forward: Bool) throws {
        let view = tracking(forward ? .forward : .back)
        let parts = try layers(in: view)
        let left = forward ? view.bounds.width - 14 - 72 : 14
        let resting = NSRect(x: left, y: (view.bounds.height - 72) / 2, width: 72, height: 72)
        #expect(!parts.indicator.isHidden)
        #expect(parts.indicator.frame == resting)
        #expect(parts.shadow.frame == resting)
    }

    @Test @MainActor
    func theIndicatorAndShadowAreCircularAtRest() throws {
        let parts = try layers(in: tracking(.back))
        let shade = try #require(parts.shadow.layer?.sublayers?.first)
        let bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
        #expect(parts.indicator.layer?.cornerRadius == 36)
        #expect(shade.frame == bounds)
        #expect(shade.shadowPath?.boundingBox == bounds)
    }

    @Test @MainActor
    func theCircleCentersALabelColoredChevron() throws {
        let indicator = try layers(in: tracking(.back)).indicator
        let chevron = try #require(indicator.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(chevron.image != nil)
        #expect(chevron.frame == NSRect(x: 22, y: 22, width: 28, height: 28))
        #expect(chevron.contentTintColor == .labelColor)
    }

    @Test @MainActor
    func theListStaysHiddenUntilHold() throws {
        let indicator = try layers(in: tracking(.back)).indicator
        let list = try #require(indicator.subviews.first { !($0 is NSVisualEffectView) && !($0 is NSImageView) && !$0.subviews.isEmpty })
        #expect(list.isHidden)
    }

    @MainActor
    private func makeView() -> HistorySwipeOverlayView {
        HistorySwipeOverlayView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                reducesMotion: { false }, now: { 10 })
    }

    @MainActor
    private func tracking(_ direction: HistorySwipeDirection) -> HistorySwipeOverlayView {
        let view = makeView()
        view.handle(.begin(direction))
        view.handle(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        return view
    }

    @MainActor
    private func layers(in view: HistorySwipeOverlayView) throws -> (shadow: NSView, indicator: NSView) {
        try #require(view.subviews.count == 2)
        return (view.subviews[0], view.subviews[1])
    }
}
