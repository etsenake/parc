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

    @Test func theTrackerPromotesEdgesThroughLingerAndStopAndWidensTheOuterEdge() {
        let t = Tracker()
        #expect(move(t, to: CGPoint(x: 600, y: 400)).isEmpty && t.info[.window] == .inside, "the window region needs no linger")
        #expect(!t.needsStopPromotion, "in-page window hover cannot stop-promote")
        #expect(t.info[.innerLeftEdge] == .none, "the page is outside the edge")
        #expect(move(t, to: CGPoint(x: 8, y: 400)).isEmpty && t.info[.innerLeftEdge] == .none, "8 pt in is outside the 6 pt edge")
        #expect(move(t, to: CGPoint(x: 3, y: 400)) == [.innerLeftEdge] && t.info[.innerLeftEdge] == .inside, "entering starts a linger")
        #expect(t.needsStopPromotion, "an inside edge can stop-promote")
        #expect(move(t, to: CGPoint(x: 12, y: 400)).isEmpty && t.info[.innerLeftEdge] == .inside, "the held edge reaches 15 pt")
        #expect(t.linger(.innerLeftEdge) && t.info[.innerLeftEdge] == .hasLingered, "linger promotes a region still inside")
        #expect(t.needsStopPromotion, "a lingered edge can still stop-promote")
        #expect(!t.linger(.innerLeftEdge) && !t.linger(.window), "no second promotion; the window never lingers")
        #expect(t.stop() && t.info[.innerLeftEdge] == .hasStopped && t.info[.window] == .inside, "a stop promotes the edge only")
        #expect(!t.needsStopPromotion, "hasStopped ends stop promotion")
        #expect(move(t, to: CGPoint(x: 13, y: 300)).isEmpty && t.info[.innerLeftEdge] == .hasStopped, "moving inside keeps the state")
        #expect(move(t, to: CGPoint(x: 16, y: 300)).isEmpty && t.info[.innerLeftEdge] == .none, "leaving is immediate")
        #expect(!t.linger(.innerLeftEdge), "a late linger cannot promote an exited region")
        _ = move(t, to: CGPoint(x: 2, y: 300))
        #expect(t.stop() && t.info[.innerLeftEdge] == .hasStopped, "a stop needs no linger first")
        _ = move(t, to: CGPoint(x: -30, y: 300))
        #expect(t.info[.window] == .none && t.info[.innerLeftEdge] == .none && t.info[.outerLeftEdge] == .inside,
              "leaving left lands in the widened outer edge")
        _ = move(t, to: CGPoint(x: -200, y: 300))
        #expect(t.info[.outerLeftEdge] == .inside, "the held outer edge stays 250 pt wide")
        _ = move(t, to: CGPoint(x: -260, y: 300))
        #expect(t.info[.outerLeftEdge] == .none, "beyond it the outer edge is left")
        let far = Tracker()
        _ = move(far, to: CGPoint(x: -200, y: 300))
        #expect(far.info[.outerLeftEdge] == .none, "approaching from outside meets the 50 pt strip")
        _ = move(far, to: CGPoint(x: -40, y: 300))
        #expect(far.info[.outerLeftEdge] == .inside && far.info[.innerLeftEdge] == .none, "then the outer edge")
        _ = move(far, to: CGPoint(x: -15, y: 300))
        #expect(far.info[.outerLeftEdge] == .inside && far.info[.innerLeftEdge] == .inside, "the inner edge reaches 20 pt outside")
    }

    @Test func theSidebarRegionLingersButNeverStops() {
        let f = Tracker()
        _ = move(f, to: CGPoint(x: 100, y: 400), .floating)
        #expect(f.linger(.sidebar) && f.info[.sidebar] == .hasLingered, "the sidebar lingers")
        #expect(!f.stop() && f.info[.sidebar] == .hasLingered, "the sidebar never reaches hasStopped")
        _ = move(f, to: CGPoint(x: 300, y: 400), .floating)
        #expect(f.info[.sidebar] == .hasLingered, "the floating zone extends 75 pt past the sidebar")
        _ = move(f, to: CGPoint(x: 309, y: 400), .floating)
        #expect(f.info[.sidebar] == .none, "beyond it the sidebar zone is left")
        f.reset()
        #expect(f.info == SidebarHoverInfo(), "a reset tracker starts empty")
    }

    @Test func activationNeedsTheRightFidelityPerRegion() {
        var info = SidebarHoverInfo()
        info[.window] = .inside; info[.innerLeftEdge] = .inside
        #expect(!A.isActive(wasActive: false, info: info, fullscreen: false, includesTopLeft: true), "inside alone does not reveal")
        #expect(A.isActive(wasActive: true, info: info, fullscreen: false, includesTopLeft: true), "inside keeps an active region")
        info[.innerLeftEdge] = .hasLingered
        #expect(A.isActive(wasActive: false, info: info, fullscreen: false, includesTopLeft: true), "lingering reveals")
        #expect(!A.isActive(wasActive: false, info: info, fullscreen: true, includesTopLeft: true), "fullscreen needs a stop")
        info[.innerLeftEdge] = .hasStopped
        #expect(A.isActive(wasActive: false, info: info, fullscreen: true, includesTopLeft: true), "a stop reveals in fullscreen")
        var page = SidebarHoverInfo(); page[.window] = .inside
        #expect(!A.isActive(wasActive: true, info: page, fullscreen: false, includesTopLeft: true), "the window region never keeps it")
        var top = SidebarHoverInfo(); top[.trafficLight] = .hasLingered
        #expect(A.isActive(wasActive: false, info: top, fullscreen: false, includesTopLeft: true), "the traffic-light zone reveals")
        #expect(!A.isActive(wasActive: false, info: top, fullscreen: false, includesTopLeft: false), "not while the toolbar shows")
        top = SidebarHoverInfo(); top[.innerTopLeftEdge] = .inside
        #expect(A.isActive(wasActive: true, info: top, fullscreen: false, includesTopLeft: true)
              && !A.isActive(wasActive: true, info: top, fullscreen: false, includesTopLeft: false), "top-left keeps only without the toolbar")
        var kept = SidebarHoverInfo(); kept[.sidebar] = .inside; kept[.outerLeftEdge] = .none
        #expect(A.isActive(wasActive: true, info: kept, fullscreen: true, includesTopLeft: false), "the sidebar zone keeps it")
        kept[.sidebar] = .none; kept[.outerLeftEdge] = .inside
        #expect(A.isActive(wasActive: true, info: kept, fullscreen: false, includesTopLeft: false), "off the left edge keeps it")
    }

    @Test func thePresentationRuleRevealsKeepsAndDismissesBySidebarState() {
        var edge = SidebarHoverInfo(); edge[.window] = .inside; edge[.innerLeftEdge] = .inside
        #expect(decide(true, .locked, edge) == P.Decision(isActive: false, action: .keep), "a locked sidebar ignores hover")
        #expect(decide(true, .hidden, edge) == P.Decision(isActive: false, action: .keep),
              "a stale stored value cannot reveal at the inside level")
        edge[.innerLeftEdge] = .hasLingered
        #expect(decide(false, .hidden, edge) == P.Decision(isActive: true, action: .reveal), "a lingered edge reveals")
        #expect(decide(false, .hidden, edge, key: false) == P.Decision(isActive: false, action: .keep), "only the key window reveals")
        var over = SidebarHoverInfo(); over[.window] = .inside; over[.sidebar] = .inside
        #expect(decide(true, .floating, over) == P.Decision(isActive: true, action: .keep), "the floating zone keeps it")
        #expect(decide(false, .floating, over) == P.Decision(isActive: false, action: .dismiss),
              "without the stored input a floating sidebar needs a lingered zone")
        over[.sidebar] = .hasLingered
        #expect(decide(false, .floating, over) == P.Decision(isActive: true, action: .keep), "a lingered sidebar zone holds it")
        #expect(decide(true, .floating, page) == P.Decision(isActive: false, action: .dismiss),
              "a pointer outside every keep zone dismisses, however the sidebar was revealed")
        #expect(decide(true, .floating, page, owner: true) == P.Decision(isActive: true, action: .keep), "an owner guard defers and holds")
        #expect(decide(true, .floating, page, interaction: true) == P.Decision(isActive: true, action: .keep),
              "an interaction guard defers in the key window")
        #expect(decide(true, .floating, page) == P.Decision(isActive: false, action: .dismiss),
              "the guard's end recomputes from the current states")
        let reset = SidebarHoverInfo()
        #expect(decide(true, .floating, reset, key: false) == P.Decision(isActive: false, action: .dismiss),
              "resigning key reports none and dismisses")
        #expect(decide(true, .floating, reset, key: false, interaction: true) == P.Decision(isActive: false, action: .dismiss),
              "interaction guards do not hold outside the key window")
        #expect(decide(true, .floating, reset, key: false, owner: true) == P.Decision(isActive: true, action: .keep),
              "an owner guard holds across the resignation")

    }
}
