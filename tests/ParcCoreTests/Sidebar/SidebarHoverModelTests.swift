import Foundation
import Testing
@testable import ParcCore

struct SidebarHoverModelTests {
    typealias R = SidebarHoverRegion
    typealias Z = SidebarHoverZones
    typealias A = SidebarHoverActivation
    typealias P = SidebarHoverPresentationRule

    func zones(_ info: SidebarHoverInfo, _ presentation: SidebarHoverZones.Presentation = .hidden,
               toolbar: Bool = false) -> [R: CGRect] {
        SidebarHoverZones.rects(size: CGSize(width: 1200, height: 800), presentation: presentation, sidebarWidth: 228,
                                showingToolbar: toolbar, trafficLightHeight: 50, info: info)
    }

    final class Tracker {
        var tracking = SidebarHoverTracking()
        var info: SidebarHoverInfo { tracking.info }
        var needsStopPromotion: Bool { tracking.needsStopPromotion }
        func linger(_ region: SidebarHoverRegion) -> Bool { tracking.linger(region) }
        func stop() -> Bool { tracking.stop() }
        func reset() { tracking.reset() }
        func update(contains: (SidebarHoverRegion) -> Bool) -> [SidebarHoverRegion] { tracking.update(contains: contains) }
    }

    func move(_ tracking: Tracker, to point: CGPoint,
              _ presentation: SidebarHoverZones.Presentation = .hidden) -> [R] {
        var entered: [R] = []
        for _ in 0..<4 {
            let rects = zones(tracking.info, presentation), before = tracking.info
            entered += tracking.update { rects[$0]?.contains(point) ?? false }
            if tracking.info == before { break }
        }
        return entered
    }

    func decide(_ stored: Bool, _ presentation: SidebarHoverZones.Presentation, _ info: SidebarHoverInfo,
                key: Bool = true, owner: Bool = false, interaction: Bool = false) -> P.Decision {
        P.decide(stored: stored, presentation: presentation, info: info, fullscreen: false, includesTopLeft: true,
                 isKeyWindow: key, ownerDefers: owner, interactionDefers: interaction)
    }

    var page: SidebarHoverInfo {
        var page = SidebarHoverInfo()
        page[.window] = .inside
        return page
    }

    @Test func regionsHaveTheirFidelityAndLingerRequirements() {
        #expect(R.window.fidelity == .inside && R.sidebar.fidelity == .hasLingered, "window and sidebar fidelity")
        #expect([R.innerLeftEdge, .outerLeftEdge, .innerTopLeftEdge, .trafficLight].allSatisfy { $0.fidelity == .hasStopped }, "edge fidelity")
        #expect(R.allCases.allSatisfy { $0.lingerRequirement == ($0 == .outerLeftEdge ? 0.16 : 0.15) }, "0.15 s linger, 0.16 s off the edge")
        #expect(SidebarHoverTracking.stopDelay == 0.08, "0.08 s stop")
    }

    @Test func zonesOutsideTheWindowFollowTheEdgeGeometry() {
        let outside = zones(SidebarHoverInfo())
        #expect(outside[.window] == CGRect(x: 0, y: 0, width: 1200, height: 800), "window bounds")
        #expect(outside[.innerLeftEdge] == CGRect(x: -20, y: 0, width: 35, height: 800), "inner edge reaches 20 pt out, 15 pt in")
        #expect(outside[.outerLeftEdge] == CGRect(x: -50, y: 0, width: 50, height: 800), "50 pt off the left edge")
        #expect(outside[.innerTopLeftEdge] == CGRect(x: 0, y: 784, width: 40, height: 6), "top-left strip unreachable from outside")
        #expect(outside[.trafficLight] == CGRect(x: -50, y: 800, width: 140, height: 50), "above the window from −50 to 90")
        #expect(outside[.sidebar]?.width == 0, "a hidden sidebar has no zone")
    }

    @Test func zonesInsideTheWindowWidenAndHeldRegionsStayWide() {
        var held = SidebarHoverInfo(); held[.window] = .inside
        let inside = zones(held)
        #expect(inside[.innerLeftEdge] == CGRect(x: 0, y: 0, width: 6, height: 800), "inside the window the edge is 6 pt")
        #expect(inside[.outerLeftEdge] == CGRect(x: -250, y: 0, width: 250, height: 800), "the outer edge widens to 250 pt")
        #expect(inside[.innerTopLeftEdge] == CGRect(x: 0, y: 780, width: 40, height: 35), "top-left reaches 15 pt above the top")
        held[.innerLeftEdge] = .hasLingered
        #expect(zones(held)[.innerLeftEdge] == CGRect(x: -20, y: 0, width: 35, height: 800), "a held inner edge stays wide")
        #expect(zones(held, toolbar: true)[.innerLeftEdge]?.height == 784 && zones(held, toolbar: true)[.outerLeftEdge]?.height == 784,
              "the toolbar keeps the edge zones 16 pt below the top")
        #expect(zones(held, .floating)[.sidebar] == CGRect(x: 0, y: 0, width: 308, height: 800), "floating zone is width + 5 + 75")
        #expect(zones(held, .locked)[.sidebar]?.width == 228, "locked zone is the sidebar")
    }

    @Test func theTrafficLightZoneIsClippedByTheMenuBar() {
        #expect(Z.trafficLightHeight(windowMaxY: 800, screenHeight: 1000, menuBarHeight: 24) == 50, "at most 50 pt above")
        #expect(Z.trafficLightHeight(windowMaxY: 960, screenHeight: 1000, menuBarHeight: 24) == 16, "clipped at the menu bar")
        #expect(Z.trafficLightHeight(windowMaxY: 966, screenHeight: 1000, menuBarHeight: 24) == 0, "10 pt or less is no zone")
        #expect(Z.trafficLightHeight(windowMaxY: 976, screenHeight: 1000, menuBarHeight: 24) == 0, "a window at the menu bar has none")
    }

    private func tracker(visiting points: [CGPoint], _ presentation: SidebarHoverZones.Presentation = .hidden) -> Tracker {
        let t = Tracker()
        for point in points { _ = move(t, to: point, presentation) }
        return t
    }

    private func lingeredEdgeTracker() -> Tracker {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 3, y: 400)])
        _ = t.linger(.innerLeftEdge)
        return t
    }

    @Test func theWindowRegionNeedsNoLinger() {
        let t = Tracker()
        #expect(move(t, to: CGPoint(x: 600, y: 400)).isEmpty)
        #expect(t.info[.window] == .inside)
    }

    @Test func inPageWindowHoverCannotStopPromote() {
        #expect(!tracker(visiting: [CGPoint(x: 600, y: 400)]).needsStopPromotion)
    }

    @Test func thePageIsOutsideTheEdge() {
        #expect(tracker(visiting: [CGPoint(x: 600, y: 400)]).info[.innerLeftEdge] == SidebarHoverState.none)
    }

    @Test func eightPointsInIsOutsideTheSixPointEdge() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400)])
        #expect(move(t, to: CGPoint(x: 8, y: 400)).isEmpty)
        #expect(t.info[.innerLeftEdge] == SidebarHoverState.none)
    }

    @Test func enteringTheEdgeStartsALinger() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400)])
        #expect(move(t, to: CGPoint(x: 3, y: 400)) == [.innerLeftEdge])
        #expect(t.info[.innerLeftEdge] == .inside)
    }

    @Test func anInsideEdgeCanStopPromote() {
        #expect(tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 3, y: 400)]).needsStopPromotion)
    }

    @Test func aHeldEdgeReachesFifteenPoints() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 3, y: 400)])
        #expect(move(t, to: CGPoint(x: 12, y: 400)).isEmpty)
        #expect(t.info[.innerLeftEdge] == .inside)
    }

    @Test func lingerPromotesARegionStillInside() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 3, y: 400)])
        #expect(t.linger(.innerLeftEdge))
        #expect(t.info[.innerLeftEdge] == .hasLingered)
    }

    @Test func aLingeredEdgeCanStillStopPromote() {
        #expect(lingeredEdgeTracker().needsStopPromotion)
    }

    @Test func thereIsNoSecondPromotionAndTheWindowNeverLingers() {
        let t = lingeredEdgeTracker()
        #expect(!t.linger(.innerLeftEdge))
        #expect(!t.linger(.window))
    }

    @Test func aStopPromotesTheEdgeOnly() {
        let t = lingeredEdgeTracker()
        #expect(t.stop())
        #expect(t.info[.innerLeftEdge] == .hasStopped)
        #expect(t.info[.window] == .inside)
    }

    @Test func hasStoppedEndsStopPromotion() {
        let t = lingeredEdgeTracker()
        _ = t.stop()
        #expect(!t.needsStopPromotion)
    }

    @Test func movingInsideKeepsTheStoppedState() {
        let t = lingeredEdgeTracker()
        _ = t.stop()
        #expect(move(t, to: CGPoint(x: 13, y: 300)).isEmpty)
        #expect(t.info[.innerLeftEdge] == .hasStopped)
    }

    @Test func leavingTheEdgeIsImmediate() {
        let t = lingeredEdgeTracker()
        _ = t.stop()
        #expect(move(t, to: CGPoint(x: 16, y: 300)).isEmpty)
        #expect(t.info[.innerLeftEdge] == SidebarHoverState.none)
    }

    @Test func aLateLingerCannotPromoteAnExitedRegion() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 3, y: 400), CGPoint(x: 16, y: 300)])
        #expect(!t.linger(.innerLeftEdge))
    }

    @Test func aStopNeedsNoLingerFirst() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 2, y: 300)])
        #expect(t.stop())
        #expect(t.info[.innerLeftEdge] == .hasStopped)
    }

    @Test func leavingLeftLandsInTheWidenedOuterEdge() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 2, y: 300), CGPoint(x: -30, y: 300)])
        #expect(t.info[.window] == SidebarHoverState.none)
        #expect(t.info[.innerLeftEdge] == SidebarHoverState.none)
        #expect(t.info[.outerLeftEdge] == .inside)
    }

    @Test func theHeldOuterEdgeStaysTwoHundredFiftyPointsWide() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 2, y: 300), CGPoint(x: -30, y: 300), CGPoint(x: -200, y: 300)])
        #expect(t.info[.outerLeftEdge] == .inside)
    }

    @Test func beyondTheHeldOuterEdgeItIsLeft() {
        let t = tracker(visiting: [CGPoint(x: 600, y: 400), CGPoint(x: 2, y: 300), CGPoint(x: -30, y: 300), CGPoint(x: -260, y: 300)])
        #expect(t.info[.outerLeftEdge] == SidebarHoverState.none)
    }

    @Test func approachingFromOutsideMeetsTheFiftyPointStrip() {
        #expect(tracker(visiting: [CGPoint(x: -200, y: 300)]).info[.outerLeftEdge] == SidebarHoverState.none)
    }

    @Test func approachingFromOutsideThenEntersTheOuterEdge() {
        let t = tracker(visiting: [CGPoint(x: -200, y: 300), CGPoint(x: -40, y: 300)])
        #expect(t.info[.outerLeftEdge] == .inside)
        #expect(t.info[.innerLeftEdge] == SidebarHoverState.none)
    }

    @Test func theInnerEdgeReachesTwentyPointsOutside() {
        let t = tracker(visiting: [CGPoint(x: -200, y: 300), CGPoint(x: -40, y: 300), CGPoint(x: -15, y: 300)])
        #expect(t.info[.outerLeftEdge] == .inside)
        #expect(t.info[.innerLeftEdge] == .inside)
    }

    private func floatingTracker(_ points: CGPoint...) -> Tracker {
        tracker(visiting: points, .floating)
    }

    @Test func theSidebarRegionLingers() {
        let f = floatingTracker(CGPoint(x: 100, y: 400))
        #expect(f.linger(.sidebar))
        #expect(f.info[.sidebar] == .hasLingered)
    }

    @Test func theSidebarNeverReachesHasStopped() {
        let f = floatingTracker(CGPoint(x: 100, y: 400))
        _ = f.linger(.sidebar)
        #expect(!f.stop())
        #expect(f.info[.sidebar] == .hasLingered)
    }

    @Test func theFloatingZoneExtendsSeventyFivePointsPastTheSidebar() {
        let f = floatingTracker(CGPoint(x: 100, y: 400))
        _ = f.linger(.sidebar)
        _ = move(f, to: CGPoint(x: 300, y: 400), .floating)
        #expect(f.info[.sidebar] == .hasLingered)
    }

    @Test func beyondTheFloatingZoneTheSidebarZoneIsLeft() {
        let f = floatingTracker(CGPoint(x: 100, y: 400))
        _ = move(f, to: CGPoint(x: 309, y: 400), .floating)
        #expect(f.info[.sidebar] == SidebarHoverState.none)
    }

    @Test func aResetTrackerStartsEmpty() {
        let f = floatingTracker(CGPoint(x: 100, y: 400))
        f.reset()
        #expect(f.info == SidebarHoverInfo())
    }

    private func info(_ states: [(R, SidebarHoverState)]) -> SidebarHoverInfo {
        var info = SidebarHoverInfo()
        for (region, state) in states { info[region] = state }
        return info
    }

    private func active(was: Bool = false, _ info: SidebarHoverInfo, fullscreen: Bool = false, topLeft: Bool = true) -> Bool {
        A.isActive(wasActive: was, info: info, fullscreen: fullscreen, includesTopLeft: topLeft)
    }

    @Test func anInsideEdgeAloneDoesNotReveal() {
        #expect(!active(info([(.window, .inside), (.innerLeftEdge, .inside)])))
    }

    @Test func anInsideEdgeKeepsAnActiveRegion() {
        #expect(active(was: true, info([(.window, .inside), (.innerLeftEdge, .inside)])))
    }

    @Test func aLingeredEdgeReveals() {
        #expect(active(info([(.window, .inside), (.innerLeftEdge, .hasLingered)])))
    }

    @Test func fullscreenNeedsAStopNotALinger() {
        #expect(!active(info([(.window, .inside), (.innerLeftEdge, .hasLingered)]), fullscreen: true))
    }

    @Test func aStopRevealsInFullscreen() {
        #expect(active(info([(.window, .inside), (.innerLeftEdge, .hasStopped)]), fullscreen: true))
    }

    @Test func theWindowRegionNeverKeepsTheSidebarActive() {
        #expect(!active(was: true, info([(.window, .inside)])))
    }

    @Test func theTrafficLightZoneReveals() {
        #expect(active(info([(.trafficLight, .hasLingered)])))
    }

    @Test func theTrafficLightZoneDoesNotRevealWhileTheToolbarShows() {
        #expect(!active(info([(.trafficLight, .hasLingered)]), topLeft: false))
    }

    @Test func theTopLeftEdgeKeepsTheSidebarWithoutTheToolbar() {
        #expect(active(was: true, info([(.innerTopLeftEdge, .inside)])))
    }

    @Test func theTopLeftEdgeDoesNotKeepTheSidebarWhileTheToolbarShows() {
        #expect(!active(was: true, info([(.innerTopLeftEdge, .inside)]), topLeft: false))
    }

    @Test func theSidebarZoneKeepsTheSidebar() {
        #expect(active(was: true, info([(.sidebar, .inside), (.outerLeftEdge, .none)]), fullscreen: true, topLeft: false))
    }

    @Test func theOuterLeftEdgeKeepsTheSidebar() {
        #expect(active(was: true, info([(.sidebar, .none), (.outerLeftEdge, .inside)]), topLeft: false))
    }

    private var edgeInside: SidebarHoverInfo { info([(.window, .inside), (.innerLeftEdge, .inside)]) }
    private var edgeLingered: SidebarHoverInfo { info([(.window, .inside), (.innerLeftEdge, .hasLingered)]) }
    private var overSidebar: SidebarHoverInfo { info([(.window, .inside), (.sidebar, .inside)]) }
    private let keep = P.Decision(isActive: true, action: .keep)
    private let hold = P.Decision(isActive: false, action: .keep)
    private let dismiss = P.Decision(isActive: false, action: .dismiss)

    @Test func aLockedSidebarIgnoresHover() {
        #expect(decide(true, .locked, edgeInside) == hold)
    }

    @Test func aStaleStoredValueCannotRevealAtTheInsideLevel() {
        #expect(decide(true, .hidden, edgeInside) == hold)
    }

    @Test func aLingeredEdgeRevealsAHiddenSidebar() {
        #expect(decide(false, .hidden, edgeLingered) == P.Decision(isActive: true, action: .reveal))
    }

    @Test func onlyTheKeyWindowReveals() {
        #expect(decide(false, .hidden, edgeLingered, key: false) == hold)
    }

    @Test func theFloatingZoneKeepsAFloatingSidebar() {
        #expect(decide(true, .floating, overSidebar) == keep)
    }

    @Test func withoutTheStoredInputAFloatingSidebarNeedsALingeredZone() {
        #expect(decide(false, .floating, overSidebar) == dismiss)
    }

    @Test func aLingeredSidebarZoneHoldsAFloatingSidebar() {
        #expect(decide(false, .floating, info([(.window, .inside), (.sidebar, .hasLingered)])) == keep)
    }

    @Test func aPointerOutsideEveryKeepZoneDismisses() {
        #expect(decide(true, .floating, page) == dismiss)
    }

    @Test func anOwnerGuardDefersAndHolds() {
        #expect(decide(true, .floating, page, owner: true) == keep)
    }

    @Test func anInteractionGuardDefersInTheKeyWindow() {
        #expect(decide(true, .floating, page, interaction: true) == keep)
    }

    @Test func resigningKeyReportsNoneAndDismisses() {
        #expect(decide(true, .floating, SidebarHoverInfo(), key: false) == dismiss)
    }

    @Test func interactionGuardsDoNotHoldOutsideTheKeyWindow() {
        #expect(decide(true, .floating, SidebarHoverInfo(), key: false, interaction: true) == dismiss)
    }

    @Test func anOwnerGuardHoldsAcrossTheResignation() {
        #expect(decide(true, .floating, SidebarHoverInfo(), key: false, owner: true) == keep)
    }
}
