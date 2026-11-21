import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTests {
    private static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0001) -> Bool { abs(a - b) <= e }

    @MainActor @Test func theLoadingPillIsOneTwentyEightByFour() {
        #expect(PageLoadingIndicator.size == NSSize(width: 128, height: 4))
    }

    @MainActor @Test func thePillIsCentredInTheBand() {
        #expect(PageLoadingIndicator.frame(paneMinX: 0, paneWidth: 1000, bandHeight: 10) == NSRect(x: 436, y: 3, width: 128, height: 4))
    }

    @MainActor @Test func thePillIsCentredOverTheSecondPane() {
        #expect(PageLoadingIndicator.frame(paneMinX: 500, paneWidth: 500, bandHeight: 10).midX == 750)
    }

    @MainActor @Test func aNarrowPaneClipsThePill() {
        #expect(PageLoadingIndicator.frame(paneMinX: 0, paneWidth: 100, bandHeight: 10).width == 100)
    }

    @MainActor @Test func theHostSpansTheTopInset() {
        #expect(PageLoadingIndicatorHost.frame(pageHost: NSRect(x: 228, y: 10, width: 1232, height: 811)) == NSRect(x: 228, y: 0, width: 1232, height: 10))
    }

    @MainActor @Test func thereIsNoBandInPageFullScreen() {
        #expect(PageLoadingIndicatorHost.frame(pageHost: NSRect(x: 0, y: 0, width: 1470, height: 831)).height == 0)
    }

    @MainActor @Test func aStackedSplitShowsTheFirstPaneOnly() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(PageLoadingIndicatorHost.eligible([a, b, c], stacked: true) == [a])
    }

    @MainActor @Test func sideBySidePanesShowEveryPane() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(PageLoadingIndicatorHost.eligible([a, b, c], stacked: false) == [a, b, c])
    }

    @MainActor @Test func noPanesShowNothing() {
        #expect(PageLoadingIndicatorHost.eligible([], stacked: true).isEmpty)
    }

    @MainActor private static func host(_ panes: [PageLoadingIndicatorHost.Pane]) -> PageLoadingIndicatorHost {
        _ = NSApplication.shared
        let host = PageLoadingIndicatorHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 10))
        host.update(panes)
        return host
    }

    @MainActor @Test func theHostKeepsOneIndicatorPerEligiblePane() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        #expect(host.indicators.count == 2)
        #expect(!host.isHidden)
    }

    @MainActor @Test func eachIndicatorFollowsItsOwnPane() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        #expect(host.indicators[a]?.isLoading == true)
        #expect(host.indicators[b]?.isLoading == false)
    }

    @MainActor @Test func theSecondPanesPill() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        #expect(host.indicators[b]?.frame == NSRect(x: 686, y: 3, width: 128, height: 4))
    }

    @MainActor @Test func aRemovedPaneLosesItsIndicator() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        host.update([.init(id: b, minX: 0, width: 1000, loading: true)])
        #expect(host.indicators.count == 1)
        #expect(host.indicators[a] == nil)
        #expect(host.indicators[b]?.isLoading == true)
    }

    @MainActor @Test func aZeroBandHidesAndStops() {
        let b = UUID()
        let host = Self.host([.init(id: b, minX: 0, width: 1000, loading: true)])
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 0)
        host.update([.init(id: b, minX: 0, width: 1000, loading: true)])
        #expect(host.isHidden)
        #expect(host.indicators[b]?.isLoading == false)
    }

    @MainActor @Test func resetRemovesEveryIndicator() {
        let host = Self.host([.init(id: UUID(), minX: 0, width: 1000, loading: true)])
        host.reset()
        #expect(host.indicators.isEmpty)
    }

    @MainActor private static func stroke(_ t: Double) -> (CGFloat, CGFloat) {
        let s = PageLoadingIndicator.stroke(at: t)
        return (s.start, s.end)
    }

    @MainActor @Test func theCycleStartsEmpty() {
        #expect(Self.stroke(0) == (0, 0))
    }

    @MainActor @Test func theStrokeGrowsFromTheStart() {
        #expect(Self.near(Self.stroke(0.1875).1, 0.5))
        #expect(Self.stroke(0.1875).0 == 0)
    }

    @MainActor @Test func theStrokeShrinksFromTheStart() {
        #expect(Self.near(Self.stroke(0.5625).0, 0.5))
        #expect(Self.stroke(0.5625).1 == 1)
    }

    @MainActor @Test func theLastThirdIsEmpty() {
        #expect(Self.stroke(0.9) == (0, 0))
        #expect(PageLoadingIndicator.stroke(at: 0.9) == (0, 0))
    }

    @MainActor @Test func theCycleRepeatsEveryOnePointOneTwoFiveSeconds() {
        #expect(Self.near(Self.stroke(1.125 + 0.1875).1, 0.5))
    }

    @MainActor @Test func theSweepComesAfterThreePointTwoSeconds() {
        #expect(PageLoadingIndicator.sweepDelay == 3.2)
    }

    @MainActor @Test func theReloadSpringStartsAtRest() {
        #expect(ReloadGlyph.spring(0) == 0)
    }

    @MainActor @Test func theReloadSpringSettlesWithinItsEnvelope() {
        #expect(abs(ReloadGlyph.spring(ReloadGlyph.settlingTime) - 1) < 0.001)
    }

    @MainActor @Test func theReloadSpringSettlesInUnderHalfASecond() {
        #expect(ReloadGlyph.settlingTime > 0.3)
        #expect(ReloadGlyph.settlingTime < 0.5)
    }

    @MainActor @Test func theReloadSpringIsUnderdampedWithAnOvershoot() {
        #expect((1...40).map { ReloadGlyph.spring(Double($0) / 200) }.max()! > 1.05)
    }

    @MainActor @Test func theDelaysAreTwoTenthsEnteringAndOneTenthLeaving() {
        #expect(ReloadGlyph.delay(enteringLoading: true) == 0.2)
        #expect(ReloadGlyph.delay(enteringLoading: false) == 0.1)
    }

    @MainActor @Test func theGlyphFrameClipAndActionSpinConstants() {
        #expect(ReloadGlyph.clipCornerRadius == 6)
        #expect(ReloadGlyph.actionRotation == 2 * .pi)
        #expect(ReloadGlyph.actionResponse == 0.4)
        #expect(ReloadGlyph.actionDamping == 0.6)
    }

    @MainActor @Test func theClickSpinLastsLongerThanTheStopCrossfade() {
        #expect(ReloadGlyph.actionSettlingTime > ReloadGlyph.settlingTime)
    }

    @MainActor @Test func anUnanimatedSwitchToStopSettlesTheGlyph() {
        _ = NSApplication.shared
        let glyph = ReloadGlyph(view: NSView(), pointSize: SidebarChromeLayout.navigationGlyphPointSize, rasterized: true)
        glyph.update(loading: true, forceReload: false, animated: false)
        #expect(glyph.progress == 1)
        #expect(glyph.loading)
    }

    @MainActor @Test func theForceDefaultSwitchesTheIdleGlyph() {
        _ = NSApplication.shared
        let glyph = ReloadGlyph(view: NSView(), pointSize: SidebarChromeLayout.navigationGlyphPointSize, rasterized: true)
        glyph.update(loading: false, forceReload: true, animated: false)
        #expect(glyph.progress == 0)
        #expect(glyph.forceReload)
    }

    @MainActor @Test func glyphsAreSixteenPointMedium() {
        _ = NSApplication.shared
        let glyph = ReloadGlyph(view: NSView(), pointSize: SidebarChromeLayout.navigationGlyphPointSize, rasterized: true)
        #expect(SidebarChromeLayout.navigationGlyphPointSize == 16)
        #expect(glyph.pointSize == 16)
    }

    @MainActor @Test func theArrowAndStopAreOneXAndTwoXTemplates() {
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        #expect(arrow?.isTemplate == true)
        #expect(arrow?.representations.count == 2)
        #expect(NavigationControlArtwork.symbol("xmark", pointSize: 16) != nil)
    }

    @MainActor @Test func theGlyphFrameIsWholePoints() {
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        #expect(arrow.map { $0.size.width == $0.size.width.rounded() && $0.size.height == $0.size.height.rounded() } == true)
    }

    @MainActor @Test func aSymbolIsRenderedOncePerSymbolAndSize() {
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        #expect(NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16) === arrow)
    }

    @MainActor @Test func theNavigationArtworkLivesInTheBundlesNavigationControlsResources() {
        #expect(NavigationControlArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("NavigationControls", isDirectory: true))
    }

    @MainActor @Test func thePillCountsAsOnScreenOnlyInAVisibleUnminimizedWindowWhileShown() {
        #expect(PageLoadingIndicator.isVisible(occlusion: .visible, miniaturized: false, hidden: false))
        #expect(!PageLoadingIndicator.isVisible(occlusion: [], miniaturized: false, hidden: false))
        #expect(!PageLoadingIndicator.isVisible(occlusion: .visible, miniaturized: true, hidden: false))
        #expect(!PageLoadingIndicator.isVisible(occlusion: .visible, miniaturized: false, hidden: true))
    }

    private typealias Skip = PageLoadingPresentationSkip

    @MainActor @Test func theFirstFingerprintNeverSkips() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        #expect(Skip.shouldSkip(previous: nil, next: empty) == false)
    }

    @MainActor @Test func anIdenticalEmptyThirdSettledPresentationSkips() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        #expect(Skip.shouldSkip(previous: empty, next: empty))
    }

    @MainActor @Test func strokeGrowthMustPresent() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        let growing = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0.5), barOpacity: 0.92, hidden: false)
        #expect(Skip.shouldSkip(previous: empty, next: growing) == false)
    }

    @MainActor @Test func aLoadingPulseChangeMustPresent() {
        let a = PageLoadingIndicator.presentation(pulse: 0.40, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        let b = PageLoadingIndicator.presentation(pulse: 0.41, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        #expect(Skip.shouldSkip(previous: a, next: b) == false)
    }

    @MainActor @Test func theFillOpacityPerPhase() {
        let empty = PageLoadingIndicator.presentation(pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        let pulse = PageLoadingIndicator.presentation(pulse: 0.40, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        #expect(Self.near(CGFloat(pulse.fillOpacity), 0.368))
        #expect(Self.near(CGFloat(empty.fillOpacity), 0.276))
    }

    @MainActor @Test func thePerPhaseTrackSizes() {
        #expect(PageLoadingIndicator.trackSize(sweeping: false) == CGSize(width: 48, height: 4))
        #expect(PageLoadingIndicator.trackSize(sweeping: true) == CGSize(width: 128, height: 4))
    }

    @MainActor private static func spaceHost(_ appearance: NSAppearance.Name) -> (PageLoadingIndicatorHost, UUID, UUID) {
        _ = NSApplication.shared
        let a = UUID(), b = UUID()
        let host = PageLoadingIndicatorHost(frame: NSRect(x: 0, y: 0, width: 400, height: 10))
        host.appearance = NSAppearance(named: appearance)
        host.update([.init(id: a, minX: 0, width: 200, loading: false), .init(id: b, minX: 200, width: 200, loading: true)])
        return (host, a, b)
    }

    @MainActor private static func colors(_ host: PageLoadingIndicatorHost, _ id: UUID) -> (fill: CGColor, bar: CGColor) {
        let layers = host.indicators[id]!.layer!.sublayers!.first!.sublayers!
        return (layers.first!.backgroundColor!, (layers.last as! CAShapeLayer).strokeColor!)
    }

    @MainActor private static func showsLight(_ host: PageLoadingIndicatorHost, _ id: UUID) -> Bool {
        let (fill, bar) = colors(host, id)
        return fill == bar && fill.colorSpace?.name == CGColorSpace.displayP3 && fill.components == [14.0 / 255, 15.0 / 255, 16.0 / 255, 0.9]
    }

    @MainActor private static func showsDark(_ host: PageLoadingIndicatorHost, _ id: UUID) -> Bool {
        let (fill, bar) = colors(host, id)
        return fill == bar && fill.colorSpace?.name == CGColorSpace.sRGB && fill.components == [1, 1, 1, 0.8]
    }

    @MainActor @Test func lightContentFillsAndBarsAreDisplayP3NearBlackAtPointNine() {
        let (host, a, b) = Self.spaceHost(.aqua)
        #expect(host.indicators.count == 2)
        #expect(Self.showsLight(host, a))
        #expect(Self.showsLight(host, b))
    }

    @MainActor @Test func darkContentFillsAndBarsAreWhiteAtPointEight() {
        let (host, a, b) = Self.spaceHost(.aqua)
        host.appearance = NSAppearance(named: .darkAqua)
        #expect(Self.showsDark(host, a))
        #expect(Self.showsDark(host, b))
    }

    @MainActor @Test func returningToLightContentRestoresNearBlack() {
        let (host, a, b) = Self.spaceHost(.aqua)
        host.appearance = NSAppearance(named: .darkAqua)
        host.appearance = NSAppearance(named: .aqua)
        #expect(Self.showsLight(host, a))
        #expect(Self.showsLight(host, b))
    }

    @MainActor private static func reloadMenu(_ chosen: @escaping (ReloadOptionsMenu.Choice) -> Void) -> NSMenu {
        ReloadOptionsMenu.make(state: .forceReload, canReload: true, canForceReload: true, canClearCookies: false, choose: chosen)
    }

    @MainActor @Test func theReloadMenuItems() {
        let menu = Self.reloadMenu { _ in }
        #expect(menu.items.map(\.title) == ["Reload", "Refresh (Ignore Cache)", "", "Clear Cookies and Refresh"])
        #expect(menu.items[2].isSeparatorItem)
    }

    @MainActor @Test func theStoredDefaultIsChecked() {
        let menu = Self.reloadMenu { _ in }
        #expect(menu.items[0].state == .off)
        #expect(menu.items[1].state == .on)
    }

    @MainActor @Test func theMenuReflectsAvailability() {
        let menu = Self.reloadMenu { _ in }
        #expect(menu.items[3].isEnabled == false)
        #expect(menu.items[0].isEnabled)
    }

    @MainActor @Test func itemsRunTheirChoices() {
        var chosen: [ReloadOptionsMenu.Choice] = []
        let menu = Self.reloadMenu { chosen.append($0) }
        for index in [0, 1] {
            let item = menu.items[index]
            _ = (item.target as? NSObject)?.perform(item.action)
        }
        #expect(chosen == [.reload, .forceReload])
    }

    private static let lights = CGSize(width: 60, height: 14)

    @MainActor @Test func theDeveloperReloadPairIsNineteenPlusFourteenPoints() {
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true, developerReload: true)
        #expect(developer.reload?.width == 19)
        #expect(developer.reloadOptions?.width == 14)
        #expect(developer.reload?.maxX == developer.reloadOptions?.minX)
    }

    @MainActor @Test func theChevronSharesReloadsTrailingEdge() {
        let regular = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true)
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true, developerReload: true)
        #expect(developer.reloadOptions?.maxX == regular.reload?.maxX)
    }

    @MainActor @Test func regularSpacingPrecedesThePair() {
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true, developerReload: true)
        #expect(developer.forward.map { $0.maxX + 2 } == developer.reload?.minX)
        #expect(developer.forward?.width == 32)
    }

    @MainActor @Test func thereIsNoChevronOutsideDeveloperMode() {
        #expect(SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true).reloadOptions == nil)
    }

    @MainActor @Test func aNarrowRowKeepsItsOrdinaryReload() {
        #expect(SidebarChromeLayout.toolbar(width: 200, windowButtons: Self.lights, showsNavigation: true, developerReload: true).reloadOptions == nil)
    }
}
