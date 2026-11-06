import Foundation

@main struct SidebarHoverModelTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarHoverModel: \(message)") }
    }
    typealias R = SidebarHoverRegion
    static func zones(_ info: SidebarHoverInfo, _ presentation: SidebarHoverZones.Presentation = .hidden,
                      toolbar: Bool = false) -> [R: CGRect] {
        SidebarHoverZones.rects(size: CGSize(width: 1200, height: 800), presentation: presentation, sidebarWidth: 228,
                                showingToolbar: toolbar, trafficLightHeight: 50, info: info)
    }
    /// Moves to an unflipped point and resizes the zones until containment settles, as WindowHoverTracker does.
    static func move(_ tracking: inout SidebarHoverTracking, to point: CGPoint,
                     _ presentation: SidebarHoverZones.Presentation = .hidden) -> [R] {
        var entered: [R] = []
        for _ in 0..<4 {
            let rects = zones(tracking.info, presentation), before = tracking.info
            entered += tracking.update { rects[$0]?.contains(point) ?? false }
            if tracking.info == before { break }
        }
        return entered
    }
    static func main() {
        check(R.window.fidelity == .inside && R.sidebar.fidelity == .hasLingered, "window and sidebar fidelity")
        check([R.innerLeftEdge, .outerLeftEdge, .innerTopLeftEdge, .trafficLight].allSatisfy { $0.fidelity == .hasStopped }, "edge fidelity")
        check(R.allCases.allSatisfy { $0.lingerRequirement == ($0 == .outerLeftEdge ? 0.16 : 0.15) }, "0.15 s linger, 0.16 s off the edge")
        check(SidebarHoverTracking.stopDelay == 0.08, "0.08 s stop")

        // Outside the window every edge zone is in its wide form.
        let outside = zones(SidebarHoverInfo())
        check(outside[.window] == CGRect(x: 0, y: 0, width: 1200, height: 800), "window bounds")
        check(outside[.innerLeftEdge] == CGRect(x: -20, y: 0, width: 35, height: 800), "inner edge reaches 20 pt out, 15 pt in")
        check(outside[.outerLeftEdge] == CGRect(x: -50, y: 0, width: 50, height: 800), "50 pt off the left edge")
        check(outside[.innerTopLeftEdge] == CGRect(x: 0, y: 784, width: 40, height: 6), "top-left strip unreachable from outside")
        check(outside[.trafficLight] == CGRect(x: -50, y: 800, width: 140, height: 50), "above the window from −50 to 90")
        check(outside[.sidebar]?.width == 0, "a hidden sidebar has no zone")
        var held = SidebarHoverInfo(); held[.window] = .inside
        let inside = zones(held)
        check(inside[.innerLeftEdge] == CGRect(x: 0, y: 0, width: 6, height: 800), "inside the window the edge is 6 pt")
        check(inside[.outerLeftEdge] == CGRect(x: -250, y: 0, width: 250, height: 800), "the outer edge widens to 250 pt")
        check(inside[.innerTopLeftEdge] == CGRect(x: 0, y: 780, width: 40, height: 35), "top-left reaches 15 pt above the top")
        held[.innerLeftEdge] = .hasLingered
        check(zones(held)[.innerLeftEdge] == CGRect(x: -20, y: 0, width: 35, height: 800), "a held inner edge stays wide")
        check(zones(held, toolbar: true)[.innerLeftEdge]?.height == 784 && zones(held, toolbar: true)[.outerLeftEdge]?.height == 784,
              "the toolbar keeps the edge zones 16 pt below the top")
        check(zones(held, .floating)[.sidebar] == CGRect(x: 0, y: 0, width: 308, height: 800), "floating zone is width + 5 + 75")
        check(zones(held, .locked)[.sidebar]?.width == 228, "locked zone is the sidebar")

        typealias Z = SidebarHoverZones
        check(Z.trafficLightHeight(windowMaxY: 800, screenHeight: 1000, menuBarHeight: 24) == 50, "at most 50 pt above")
        check(Z.trafficLightHeight(windowMaxY: 960, screenHeight: 1000, menuBarHeight: 24) == 16, "clipped at the menu bar")
        check(Z.trafficLightHeight(windowMaxY: 966, screenHeight: 1000, menuBarHeight: 24) == 0, "10 pt or less is no zone")
        check(Z.trafficLightHeight(windowMaxY: 976, screenHeight: 1000, menuBarHeight: 24) == 0, "a window at the menu bar has none")

        // Region state machine.
        var t = SidebarHoverTracking()
        check(move(&t, to: CGPoint(x: 600, y: 400)).isEmpty && t.info[.window] == .inside, "the window region needs no linger")
        check(!t.needsStopPromotion, "in-page window hover cannot stop-promote")
        check(t.info[.innerLeftEdge] == .none, "the page is outside the edge")
        check(move(&t, to: CGPoint(x: 8, y: 400)).isEmpty && t.info[.innerLeftEdge] == .none, "8 pt in is outside the 6 pt edge")
        check(move(&t, to: CGPoint(x: 3, y: 400)) == [.innerLeftEdge] && t.info[.innerLeftEdge] == .inside, "entering starts a linger")
        check(t.needsStopPromotion, "an inside edge can stop-promote")
        check(move(&t, to: CGPoint(x: 12, y: 400)).isEmpty && t.info[.innerLeftEdge] == .inside, "the held edge reaches 15 pt")
        check(t.linger(.innerLeftEdge) && t.info[.innerLeftEdge] == .hasLingered, "linger promotes a region still inside")
        check(t.needsStopPromotion, "a lingered edge can still stop-promote")
        check(!t.linger(.innerLeftEdge) && !t.linger(.window), "no second promotion; the window never lingers")
        check(t.stop() && t.info[.innerLeftEdge] == .hasStopped && t.info[.window] == .inside, "a stop promotes the edge only")
        check(!t.needsStopPromotion, "hasStopped ends stop promotion")
        check(move(&t, to: CGPoint(x: 13, y: 300)).isEmpty && t.info[.innerLeftEdge] == .hasStopped, "moving inside keeps the state")
        check(move(&t, to: CGPoint(x: 16, y: 300)).isEmpty && t.info[.innerLeftEdge] == .none, "leaving is immediate")
        check(!t.linger(.innerLeftEdge), "a late linger cannot promote an exited region")
        _ = move(&t, to: CGPoint(x: 2, y: 300))
        check(t.stop() && t.info[.innerLeftEdge] == .hasStopped, "a stop needs no linger first")
        _ = move(&t, to: CGPoint(x: -30, y: 300))
        check(t.info[.window] == .none && t.info[.innerLeftEdge] == .none && t.info[.outerLeftEdge] == .inside,
              "leaving left lands in the widened outer edge")
        _ = move(&t, to: CGPoint(x: -200, y: 300))
        check(t.info[.outerLeftEdge] == .inside, "the held outer edge stays 250 pt wide")
        _ = move(&t, to: CGPoint(x: -260, y: 300))
        check(t.info[.outerLeftEdge] == .none, "beyond it the outer edge is left")
        var far = SidebarHoverTracking()
        _ = move(&far, to: CGPoint(x: -200, y: 300))
        check(far.info[.outerLeftEdge] == .none, "approaching from outside meets the 50 pt strip")
        _ = move(&far, to: CGPoint(x: -40, y: 300))
        check(far.info[.outerLeftEdge] == .inside && far.info[.innerLeftEdge] == .none, "then the outer edge")
        _ = move(&far, to: CGPoint(x: -15, y: 300))
        check(far.info[.outerLeftEdge] == .inside && far.info[.innerLeftEdge] == .inside, "the inner edge reaches 20 pt outside")
        var f = SidebarHoverTracking()
        _ = move(&f, to: CGPoint(x: 100, y: 400), .floating)
        check(f.linger(.sidebar) && f.info[.sidebar] == .hasLingered, "the sidebar lingers")
        check(!f.stop() && f.info[.sidebar] == .hasLingered, "the sidebar never reaches hasStopped")
        _ = move(&f, to: CGPoint(x: 300, y: 400), .floating)
        check(f.info[.sidebar] == .hasLingered, "the floating zone extends 75 pt past the sidebar")
        _ = move(&f, to: CGPoint(x: 309, y: 400), .floating)
        check(f.info[.sidebar] == .none, "beyond it the sidebar zone is left")
        f.reset()
        check(f.info == SidebarHoverInfo(), "a reset tracker starts empty")

        // Activation.
        typealias A = SidebarHoverActivation
        var info = SidebarHoverInfo()
        info[.window] = .inside; info[.innerLeftEdge] = .inside
        check(!A.isActive(wasActive: false, info: info, fullscreen: false, includesTopLeft: true), "inside alone does not reveal")
        check(A.isActive(wasActive: true, info: info, fullscreen: false, includesTopLeft: true), "inside keeps an active region")
        info[.innerLeftEdge] = .hasLingered
        check(A.isActive(wasActive: false, info: info, fullscreen: false, includesTopLeft: true), "lingering reveals")
        check(!A.isActive(wasActive: false, info: info, fullscreen: true, includesTopLeft: true), "fullscreen needs a stop")
        info[.innerLeftEdge] = .hasStopped
        check(A.isActive(wasActive: false, info: info, fullscreen: true, includesTopLeft: true), "a stop reveals in fullscreen")
        var page = SidebarHoverInfo(); page[.window] = .inside
        check(!A.isActive(wasActive: true, info: page, fullscreen: false, includesTopLeft: true), "the window region never keeps it")
        var top = SidebarHoverInfo(); top[.trafficLight] = .hasLingered
        check(A.isActive(wasActive: false, info: top, fullscreen: false, includesTopLeft: true), "the traffic-light zone reveals")
        check(!A.isActive(wasActive: false, info: top, fullscreen: false, includesTopLeft: false), "not while the toolbar shows")
        top = SidebarHoverInfo(); top[.innerTopLeftEdge] = .inside
        check(A.isActive(wasActive: true, info: top, fullscreen: false, includesTopLeft: true)
              && !A.isActive(wasActive: true, info: top, fullscreen: false, includesTopLeft: false), "top-left keeps only without the toolbar")
        var kept = SidebarHoverInfo(); kept[.sidebar] = .inside; kept[.outerLeftEdge] = .none
        check(A.isActive(wasActive: true, info: kept, fullscreen: true, includesTopLeft: false), "the sidebar zone keeps it")
        kept[.sidebar] = .none; kept[.outerLeftEdge] = .inside
        check(A.isActive(wasActive: true, info: kept, fullscreen: false, includesTopLeft: false), "off the left edge keeps it")

        // Parc's presentation rule over the activation (an inferred update rule).
        typealias P = SidebarHoverPresentationRule
        func decide(_ stored: Bool, _ presentation: SidebarHoverZones.Presentation, _ info: SidebarHoverInfo,
                    key: Bool = true, owner: Bool = false, interaction: Bool = false) -> P.Decision {
            P.decide(stored: stored, presentation: presentation, info: info, fullscreen: false, includesTopLeft: true,
                     isKeyWindow: key, ownerDefers: owner, interactionDefers: interaction)
        }
        var edge = SidebarHoverInfo(); edge[.window] = .inside; edge[.innerLeftEdge] = .inside
        check(decide(true, .locked, edge) == P.Decision(isActive: false, action: .keep), "a locked sidebar ignores hover")
        check(decide(true, .hidden, edge) == P.Decision(isActive: false, action: .keep),
              "a stale stored value cannot reveal at the inside level")
        edge[.innerLeftEdge] = .hasLingered
        check(decide(false, .hidden, edge) == P.Decision(isActive: true, action: .reveal), "a lingered edge reveals")
        check(decide(false, .hidden, edge, key: false) == P.Decision(isActive: false, action: .keep), "only the key window reveals")
        var over = SidebarHoverInfo(); over[.window] = .inside; over[.sidebar] = .inside
        check(decide(true, .floating, over) == P.Decision(isActive: true, action: .keep), "the floating zone keeps it")
        check(decide(false, .floating, over) == P.Decision(isActive: false, action: .dismiss),
              "without the stored input a floating sidebar needs a lingered zone")
        over[.sidebar] = .hasLingered
        check(decide(false, .floating, over) == P.Decision(isActive: true, action: .keep), "a lingered sidebar zone holds it")
        check(decide(true, .floating, page) == P.Decision(isActive: false, action: .dismiss),
              "a pointer outside every keep zone dismisses, however the sidebar was revealed")
        check(decide(true, .floating, page, owner: true) == P.Decision(isActive: true, action: .keep), "an owner guard defers and holds")
        check(decide(true, .floating, page, interaction: true) == P.Decision(isActive: true, action: .keep),
              "an interaction guard defers in the key window")
        check(decide(true, .floating, page) == P.Decision(isActive: false, action: .dismiss),
              "the guard's end recomputes from the current states")
        let reset = SidebarHoverInfo()
        check(decide(true, .floating, reset, key: false) == P.Decision(isActive: false, action: .dismiss),
              "resigning key reports none and dismisses")
        check(decide(true, .floating, reset, key: false, interaction: true) == P.Decision(isActive: false, action: .dismiss),
              "interaction guards do not hold outside the key window")
        check(decide(true, .floating, reset, key: false, owner: true) == P.Decision(isActive: true, action: .keep),
              "an owner guard holds across the resignation")
        print("SidebarHoverModel: \(count) assertions passed")
    }
}
