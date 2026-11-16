import AppKit

@MainActor
func run() {
    var count = 0
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }
    typealias M = SidebarSpacePagingModel
    expect(M.isGestural(phase: .began, momentumPhase: [], precise: true), "a phased precise scroll is a gesture")
    expect(M.isGestural(phase: [], momentumPhase: .changed, precise: true), "momentum is part of a gesture")
    expect(!M.isGestural(phase: .began, momentumPhase: [], precise: false), "a coarse wheel is not a gesture")
    expect(!M.isGestural(phase: [], momentumPhase: [], precise: true), "an unphased scroll is not a gesture")

    expect(M.target(position: 120, velocity: 6, width: 200, count: 4, begin: 0) == 1, "a forward fling goes next")
    expect(M.target(position: 120, velocity: -6, width: 200, count: 4, begin: 1) == 0, "a backward fling goes previous")
    expect(M.target(position: 90, velocity: 1, width: 200, count: 4, begin: 0) == 0, "a slow short drag stays")
    expect(M.target(position: 110, velocity: 1, width: 200, count: 4, begin: 0) == 1, "a slow long drag passes halfway")
    expect(M.target(position: 700, velocity: 900, width: 200, count: 4, begin: 1) == 2, "never more than one page")
    expect(M.target(position: -80, velocity: -900, width: 200, count: 4, begin: 0) == 0, "never before the first page")
    expect(M.target(position: 650, velocity: 900, width: 200, count: 4, begin: 3) == 3, "never past the last page")

    var model = M()
    expect(model.discrete(deltaX: 0.6, inverted: false, now: 10) == 0, "one small delta waits")
    expect(model.discrete(deltaX: 0.6, inverted: false, now: 10.02) == -1, "accumulated positive delta goes back")
    expect(model.discrete(deltaX: -3, inverted: false, now: 10.1) == 0, "the 0.25 s cooldown holds")
    expect(model.discrete(deltaX: -3, inverted: false, now: 10.3) == 1, "negative delta goes forward")
    expect(model.discrete(deltaX: 0.8, inverted: false, now: 11) == 0, "a fresh delta waits")
    expect(model.discrete(deltaX: 0.8, inverted: false, now: 11.2) == 0, "a gap over 0.05 s restarts the sum")
    expect(model.discrete(deltaX: -2, inverted: true, now: 12) == -1, "inverted devices reverse the direction")
    expect(M.swipeStep(deltaX: 1) == -1 && M.swipeStep(deltaX: -1) == 1 && M.swipeStep(deltaX: 0) == 0,
           "a legacy swipe right goes back")
    expect(M.settleVelocity(50, position: 100, targetOrigin: 0) == 0, "velocity away from the target is dropped")
    expect(M.settleVelocity(-50, position: 100, targetOrigin: 0) == -50, "velocity toward the target is kept")

    expect(abs(M.velocity([(1.0, 0), (1.05, 10)], at: 1.05) - 200) < 0.001, "velocity is strip points per second")
    expect(M.velocity([(1.0, 0), (1.05, 10)], at: 1.3) == 0, "a paused release has no velocity")
    expect(abs(M.springValue(from: 100, velocity: 0, time: 0) - 100) < 0.001, "the spring starts at its offset")
    expect(abs(M.springValue(from: 100, velocity: 0, time: 1.2)) < 0.5, "the 0.4 s spring settles")
    expect(M.springValue(from: 100, velocity: 0, time: 0.2) > 0, "a critically damped spring does not overshoot")

    let ids = (0..<3).map { _ in SidebarSpacePager.Page(id: UUID(), profileID: UUID()) }
    var selected = ids[1].id
    var selections: [UUID] = []
    var available = true
    var accepts = true
    var offsets: [CGFloat] = []
    var clock: CFTimeInterval = 100
    var offers = true
    let pager = SidebarSpacePager()
    pager.pages = { ids }
    pager.selectedID = { selected }
    pager.pageWidth = { 240 }
    pager.canBegin = { true }
    pager.offersCreation = { offers }
    pager.canSelect = { _ in available }
    pager.select = { selections.append($0.id); if accepts { selected = $0.id } }
    pager.setOffset = { offsets.append($0) }
    SystemOverrides.install()
    SystemOverrides.reduceMotion = false
    pager.now = { clock }

    expect(pager.gesture(phase: .mayBegin, momentum: false, dx: 0, dy: 0, time: 1), "may-begin arms tracking")
    expect(pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 1.01), "a horizontal began continues")
    for k in 0..<30 { _ = pager.gesture(phase: .changed, momentum: false, dx: -9, dy: 0, time: 1.02 + Double(k) * 0.02) }
    expect(pager.offset == -135, "the strip follows at half the finger distance")
    expect(pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 2), "the release is the pager's")
    expect(selections == [ids[2].id], "the next Space is selected")
    expect(pager.offset == 105, "the arriving page continues from the strip position")
    expect(pager.isAnimating, "the page springs to rest")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && !pager.isAnimating, "the spring settles at rest")
    expect(pager.gesture(phase: [], momentum: true, dx: -5, dy: 0, time: 2.1), "momentum after the gesture is consumed")

    expect(pager.gesture(phase: .mayBegin, momentum: false, dx: 0, dy: 0, time: 3), "armed again")
    expect(!pager.gesture(phase: .began, momentum: false, dx: 1, dy: 6, time: 3.01), "vertical began passes on")
    expect(!pager.isTracking, "tracking ended")

    selected = ids[1].id; accepts = false; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: 4, dy: 0, time: 4)
    for k in 0..<10 { _ = pager.gesture(phase: .changed, momentum: false, dx: 30, dy: 0, time: 4.01 + Double(k) * 0.01) }
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 4.1)
    expect(selections == [ids[0].id], "the previous Space was requested")
    expect(pager.offset == 150, "the original page stays where it was dragged")
    clock += 2; pager.tick()
    expect(pager.offset == 0, "and springs back")

    accepts = true; selections = []
    expect(pager.swipe(deltaX: -1), "a legacy swipe left pages")
    expect(selections == [ids[2].id] && pager.offset == 240, "the next page arrives from the right")
    clock += 2; pager.tick()
    available = false; selections = []
    expect(pager.swipe(deltaX: 1), "the swipe is still the pager's")
    expect(selections.isEmpty, "an unavailable Space is not selected")
    SystemOverrides.reduceMotion = true; available = true; selected = ids[1].id
    expect(pager.swipe(deltaX: 1) && pager.offset == 0, "Reduce Motion places the page at rest")

    expect(SidebarSpacePagingPresentationSkip.shouldSkip(previous: 12, next: 12),
           "identical fingerprint is a no-op")
    expect(!SidebarSpacePagingPresentationSkip.shouldSkip(previous: 12, next: 12.1),
           "a changed offset still presents")
    expect(!SidebarSpacePagingPresentationSkip.shouldSkip(previous: nil, next: 0),
           "the first present is never skipped")

    offsets = []; selected = ids[1].id; accepts = true; available = true
    SystemOverrides.reduceMotion = false
    expect(pager.swipe(deltaX: -1), "a swipe starts the spring for skip checks")
    expect(offsets == [240], "the arriving page presents once")
    let beforeFrozen = offsets.count
    pager.tick()
    expect(offsets.count == beforeFrozen && pager.offset == 240 && pager.isAnimating,
           "t=0 spring sample matching the placed offset skips identical layout")
    pager.tick()
    expect(offsets.count == beforeFrozen && pager.isAnimating,
           "a frozen-clock spring tick skips identical layout while the timer stays armed")
    clock += 1.0 / 120
    pager.tick()
    expect(offsets.count == beforeFrozen + 1 && offsets.last != 240,
           "an advancing spring sample that changes presentation still presents")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && !pager.isAnimating && offsets.last == 0,
           "settle still presents rest and idle-stops the spring")
    let afterSettle = offsets.count
    pager.tick()
    expect(offsets.count == afterSettle, "ticks after settle do no layout work")
    pager.cancel()
    expect(offsets.count == afterSettle, "cancel at rest skips an identical zero present")

    func pages(_ selectedIndex: Int, _ offset: CGFloat) -> (left: Int, progress: CGFloat)? {
        M.themePages(selected: selectedIndex, offset: offset, width: 240, count: 3)
    }
    func same(_ a: (left: Int, progress: CGFloat)?, _ b: (left: Int, progress: CGFloat)?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.left == b.left && abs(a.progress - b.progress) < 1e-9
    }
    expect(same(pages(1, -96), (1, 0.4)) && same(pages(1, 96), (0, 0.6)), "the next page is right of the selected one, the previous left")
    expect(same(pages(1, -96), pages(2, 144)), "a commit re-bases the offset but keeps the pages and progress")
    expect(same(pages(0, -312), (1, 0.3)), "past one page the pages either side of the position, neither selected")
    expect(same(pages(2, 264), (0, 0.9)), "a second page during the first one's spring")
    expect(same(pages(0, 72), (0, 0)) && same(pages(2, -72), (1, 1)), "beyond the strip's ends its end page alone")
    expect(M.themePages(selected: 0, offset: 10, width: 240, count: 1) == nil
           && M.themePages(selected: 0, offset: 10, width: 0, count: 3) == nil, "no pair without two pages and a width")
    func swiped(_ selectedIndex: Int, _ offset: CGFloat) -> (left: Int, progress: CGFloat)? {
        M.themePages(selected: selectedIndex, offset: offset, width: 240, count: 3, within: pager.reach)
    }
    expect(M.reach(begin: 0, count: 3) == 0...1 && M.reach(begin: 1, count: 3) == 0...2 && M.reach(begin: 2, count: 3) == 1...2
           && M.reach(begin: 0, count: 1) == 0...0, "a swipe reaches its own Space and the Spaces either side")
    expect(same(M.themePages(selected: 0, offset: -312, width: 240, count: 3, within: 0...1), (0, 1))
           && same(M.themePages(selected: 2, offset: 312, width: 240, count: 3, within: 1...2), (1, 0)),
           "within a swipe's reach a drag past the neighbour rests on its colour instead of blending toward the next")
    expect(same(M.themePages(selected: 1, offset: -40, width: 240, count: 3, within: 0...1), (0, 1)),
           "re-based onto the neighbour, the colour stays the swipe's two Spaces")
    expect(same(M.themePages(selected: 1, offset: 96, width: 240, count: 3, within: 0...2), pages(1, 96))
           && same(M.themePages(selected: 1, offset: -96, width: 240, count: 3, within: 0...2), pages(1, -96)),
           "inside the reach the colour is unchanged")

    expect(M.stretch(0, width: 240) == 0 && M.stretch(-5, width: 240) == 0 && M.stretch(30, width: 0) == 0,
           "nothing stretches at or inside an edge")
    expect(abs(M.stretch(0.01, width: 240) / 0.01 - 0.55) < 0.001,
           "the stretch starts at 0.55 of the drag, so the strip slows at the edge without stopping dead")
    let stretches = stride(from: 10, through: 4000, by: 10).map { M.stretch(CGFloat($0), width: 240) }
    let gains = zip(stretches.dropFirst(), stretches).map { $0 - $1 }
    expect(zip(gains.dropFirst(), gains).allSatisfy { $0 > 0 && $0 < $1 } && stretches.last! < 24,
           "it keeps giving, ever more stiffly, and never reaches a tenth of the page")
    expect(abs(M.stretch(100, width: 480) - 2 * M.stretch(50, width: 240)) < 1e-9, "the stretch scales with the sidebar's width")
    let middle = M.Edges(reach: 0...1, width: 240, opensPastEnd: false, holding: 120)
    expect(middle.resisted(315) == 240 + M.stretch(75, width: 240) && middle.resisted(-60) == -M.stretch(60, width: 240)
           && middle.resisted(130) == 130, "the strip follows the drag between its ends and stretches past them")
    let pastEnd = M.Edges(reach: 1...2, width: 240, opensPastEnd: true, holding: 360)
    expect(pastEnd.last == nil && pastEnd.resisted(525) == 525 && pastEnd.resisted(200) == 240 - M.stretch(40, width: 240),
           "past the last Space the create-Space pull still follows the drag")
    let edgeHeld = M.Edges(reach: 0...1, width: 240, opensPastEnd: false, holding: -10)
    expect(edgeHeld.first == -10 && edgeHeld.resisted(-10) == -10 && edgeHeld.resisted(30) == 30
           && edgeHeld.resisted(-400) > -24 && edgeHeld.resisted(-400) < -10,
           "picked up past an edge, the strip starts where it is and only spends what is left of the give")
    let edgeSpent = M.Edges(reach: 1...2, width: 240, opensPastEnd: false, holding: 197)
    expect(edgeSpent.first == 197 && edgeSpent.firstGive == 0 && edgeSpent.resisted(100) == 197 && edgeSpent.resisted(230) == 230,
           "beyond the whole give it goes no further out, yet follows the fingers back")
    expect(edgeSpent.held(100) == 197 && edgeSpent.held(230) == 230 && abs(edgeHeld.held(-9000) - (-10 - 14 * 19 / 0.55)) < 1e-9
           && middle.held(-5000) < -800 && middle.held(5000) > 1000 && abs(M.stretch(-middle.held(-5000), width: 240) - 0.95 * 24) < 1e-9,
           "pull past nineteen-twentieths of the give is not banked, so a spent edge answers as soon as the fingers turn")
    expect(M.widened(1...2, toward: 197, width: 240, count: 3) == 0...2 && M.widened(0...1, toward: 120, width: 240, count: 3) == 0...1
           && M.widened(1...2, toward: 600, width: 240, count: 3) == 1...2 && M.widened(0...1, toward: -30, width: 240, count: 3) == 0...1,
           "a reach widens only toward Spaces that exist")

    selected = ids[0].id; accepts = true; available = true; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 20)
    var strip: [CGFloat] = []
    for k in 0..<30 {
        _ = pager.gesture(phase: .changed, momentum: false, dx: -21, dy: 0, time: 20.02 + Double(k) * 0.02)
        strip.append(-pager.offset)
    }
    let advances = zip(strip.dropFirst(), strip).map { $0 - $1 }
    expect(Array(strip.prefix(22)) == (1...22).map { CGFloat($0) * 10.5 },
           "up to the neighbouring Space the strip follows at half the finger distance")
    expect(strip.last! > 240 && strip.allSatisfy { $0 < 240 + 24 },
           "a long drag stops at the neighbour, never showing more than a tenth of a page of empty strip past it")
    expect(advances.suffix(7).allSatisfy { $0 > 0 && $0 < 10.5 * 0.55 } && zip(advances.suffix(6), advances.suffix(7)).allSatisfy { $0 < $1 },
           "past it each step meets more resistance")
    expect(pager.reach == 0...1 && same(swiped(0, pager.offset), (0, 1)),
           "the colour rests on the neighbouring Space instead of blending toward the one after it")
    let held = pager.offset
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 20.61)
    expect(selections == [ids[1].id], "the release still moves exactly one Space")
    expect(abs(pager.offset - (240 + held)) < 1e-9 && pager.reach == 0...1 && pager.isAnimating,
           "the strip re-bases from where it was let go and keeps the swipe's two Spaces")
    expect(same(swiped(1, pager.offset), (0, 1)) && pager.reach?.contains(2) == false,
           "settling back, neither the strip nor the colour reaches the Space beyond")
    clock += 0.1; pager.tick()
    expect(pager.offset < 0 && pager.offset > 240 + held && pager.reach == 0...1, "it springs back out of the stretch")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && !pager.isAnimating && pager.reach == nil, "the reach ends at rest")

    selected = ids[2].id; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: 2, dy: 0, time: 22)
    for k in 0..<40 { _ = pager.gesture(phase: .changed, momentum: false, dx: 15, dy: 0, time: 22.01 + Double(k) * 0.01) }
    expect(pager.offset > 240 && pager.offset < 264 && pager.reach == 1...2,
           "a long backward drag stops at the previous Space the same way")
    expect(same(swiped(2, pager.offset), (1, 0)), "keeping only those two Spaces' colours")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 22.45)
    expect(selections == [ids[1].id], "and its release moves one Space back")
    clock += 2; pager.tick()

    selected = ids[0].id; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: 2, dy: 0, time: 24)
    var edge: [CGFloat] = []
    for k in 0..<20 {
        _ = pager.gesture(phase: .changed, momentum: false, dx: 12, dy: 0, time: 24.01 + Double(k) * 0.01)
        edge.append(pager.offset)
    }
    expect(edge.first! > 0 && edge.first! < 6 * 0.55 && edge.last! < 24 && zip(edge.dropFirst(), edge).allSatisfy { $0 > $1 },
           "at the first Space a backward drag meets the rubber band from its first step")
    expect(same(swiped(0, edge.last!), (0, 0)), "and keeps the first Space's colour alone")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 24.25)
    expect(selections.isEmpty && pager.isAnimating && pager.offset == edge.last!, "letting go stays put and springs back")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && pager.reach == nil, "at rest on the first Space")

    selected = ids[0].id; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: 2, dy: 0, time: 25)
    _ = pager.gesture(phase: .changed, momentum: false, dx: 120, dy: 0, time: 25.01)
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 25.3)
    clock += 0.05; pager.tick()
    let relaxing = pager.offset
    expect(relaxing > 0 && relaxing < M.stretch(60, width: 240) && pager.reach == 0...1, "the stretch springs back")
    _ = pager.gesture(phase: .began, momentum: false, dx: 2, dy: 0, time: 25.4)
    expect(pager.offset == relaxing, "picking the strip up mid-settle leaves it in place")
    _ = pager.gesture(phase: .changed, momentum: false, dx: 4, dy: 0, time: 25.41)
    expect(abs(pager.offset - (relaxing + M.stretch(2, limit: 24 - relaxing))) < 1e-9 && pager.offset - relaxing < 2 * 0.55,
           "pulling further only spends what is left of the give, without a jump")
    _ = pager.gesture(phase: .changed, momentum: false, dx: -24, dy: 0, time: 25.42)
    expect(abs(pager.offset - (relaxing - 10)) < 1e-9, "and pushing back follows the fingers from where it was picked up")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 25.7)
    clock += 2; pager.tick()
    expect(selections.isEmpty && pager.offset == 0, "still on the first Space")
    var widest: CGFloat = 0
    for round in 0..<6 {
        let at = 25.8 + Double(round) * 0.1
        _ = pager.gesture(phase: .began, momentum: false, dx: 2, dy: 0, time: at)
        _ = pager.gesture(phase: .changed, momentum: false, dx: 600, dy: 0, time: at + 0.01)
        widest = max(widest, pager.offset)
        _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: at + 0.05)
        clock += 0.01; pager.tick()
    }
    expect(widest > 0 && widest < 24 && selections.isEmpty, "quick repeated pulls at the first Space never stretch past a tenth of a page")
    clock += 2; pager.tick()

    selected = ids[0].id
    expect(pager.swipe(deltaX: -1), "a page flip")
    clock += 0.2; pager.tick()
    expect(pager.swipe(deltaX: -1) && selected == ids[2].id && pager.offset > 264, "a second flip mid-spring overshoots the previous Space")
    let flipped = pager.offset, flippedTheme = pages(2, flipped)
    selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 27)
    expect(pager.offset == flipped && same(swiped(2, flipped), flippedTheme),
           "a swipe started while the flip still springs takes the strip and colour from where they are")
    _ = pager.gesture(phase: .changed, momentum: false, dx: -40, dy: 0, time: 27.01)
    expect(abs(pager.offset - (flipped - 20)) < 1e-9, "and follows the fingers at the usual pace rather than treating the overshoot as a stretch")
    _ = pager.gesture(phase: .changed, momentum: false, dx: 80, dy: 0, time: 27.02)
    expect(abs(pager.offset - flipped) < 1e-9, "going back past where it started goes no further than the flip already showed")
    _ = pager.gesture(phase: .changed, momentum: false, dx: -10, dy: 0, time: 27.03)
    expect(abs(pager.offset - (flipped - 5)) < 1e-9, "and answers at once when the fingers turn back")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 27.3)
    expect(selections == [ids[1].id], "its release lands where the unresisted drag says")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && pager.reach == nil, "and settles")

    selected = ids[1].id
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 28)
    _ = pager.gesture(phase: .changed, momentum: false, dx: -20, dy: 0, time: 28.01)
    expect(pager.reach == 0...2, "a swipe holds its reach")
    pager.cancel()
    expect(pager.reach == nil && pager.offset == 0, "cancelling ends it")
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 28.1)
    _ = pager.gesture(phase: .changed, momentum: false, dx: -300, dy: 0, time: 28.11)
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 28.12)
    expect(selected == ids[2].id && pager.isAnimating && pager.reach == 0...2, "the reach lasts through the settle")
    expect(pager.slideIn(from: 2, to: 0) && pager.reach == nil, "a Space switch from elsewhere ends it")
    clock += 2; pager.tick()
    selected = ids[0].id
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 29)
    _ = pager.gesture(phase: .changed, momentum: false, dx: -300, dy: 0, time: 29.01)
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 29.02)
    expect(selected == ids[1].id && pager.reach == 0...1, "settling onto the next Space")
    expect(pager.swipe(deltaX: -1) && selected == ids[2].id && pager.reach == nil, "a page flip ends it too")
    clock += 2; pager.tick()

    selected = ids[0].id; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 29.5)
    for k in 1...20 { _ = pager.gesture(phase: .changed, momentum: false, dx: -21.6, dy: 0, time: 29.5 + Double(k) * 0.005) }
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 29.6)
    expect(selections == [ids[1].id] && abs(pager.offset - 24) < 1e-9, "a brisk flick lands on the next Space from just short of it")
    let flicked = clock
    var deepest: CGFloat = 0, unguarded: CGFloat = 0, deepestRaw: CGFloat = 0
    for k in 1...60 {
        clock = flicked + Double(k) * 0.005; pager.tick()
        let raw = M.springValue(from: 24, velocity: -2160, time: CGFloat(k) * 0.005)
        if pager.offset < deepest { deepest = pager.offset; deepestRaw = raw }
        unguarded = min(unguarded, raw)
    }
    expect(unguarded < -24 && deepest < 0 && deepest > -24 && abs(deepest + M.stretch(-deepestRaw, width: 240)) < 0.01,
           "its overshoot toward the Space outside the swipe stretches like the edge instead of sliding into empty strip")
    expect(pager.reach == 0...1 && same(swiped(1, deepest), (0, 1)), "with the colour still on the two Spaces")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && pager.reach == nil, "and it settles")

    for begin in 0..<3 {
        for finger: CGFloat in [-1400, -900, -500, -250, -60, 60, 250, 500, 900, 1400] {
            for pause in [false, true] {
                selected = ids[begin].id; selections = []
                let start: CFTimeInterval = 26
                _ = pager.gesture(phase: .began, momentum: false, dx: finger > 0 ? -2 : 2, dy: 0, time: start)
                for k in 1...20 {
                    _ = pager.gesture(phase: .changed, momentum: false, dx: -finger / 20, dy: 0, time: start + Double(k) * 0.01)
                }
                let drag = CGFloat(begin) * 240 + 0.5 * finger
                let expected = M.target(position: drag, velocity: pause ? 0 : 0.5 * finger / 20 / 0.01, width: 240, count: 3, begin: begin)
                _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: start + 0.2 + (pause ? 0.2 : 0))
                let landed = ids.firstIndex { $0.id == selected }!
                expect(landed == expected && abs(landed - begin) <= 1,
                       "release targets follow the unresisted drag: from \(begin), \(finger) points\(pause ? " after a pause" : "")")
                clock += 2; pager.tick()
            }
        }
    }
    selected = ids[0].id
    expect(pager.swipe(deltaX: -1), "a first page")
    clock += 0.2; pager.tick()
    let springing = pages(1, pager.offset)
    expect(pager.offset > 0 && pager.offset < 240, "still springing")
    expect(pager.swipe(deltaX: -1) && selected == ids[2].id, "a second page")
    expect(same(pages(2, pager.offset), springing), "the second page continues from the same pair and progress")
    clock += 2; pager.tick()

    clock += 2; pager.tick()
    selections.removeAll()
    expect(!pager.slideIn(from: 1, to: 1), "the same Space doesn't slide")
    expect(pager.slideIn(from: 0, to: 2) && pager.offset == 240 && pager.isAnimating && selections.isEmpty,
           "a later Space arrives from the right without the pager selecting anything")
    clock += 0.2; pager.tick()
    let midway = pager.offset
    expect(midway > 0 && midway < 240, "and springs toward rest")
    expect(pager.slideIn(from: 2, to: 1) && abs(pager.offset - (midway - 240)) < 0.001,
           "a switch mid-slide continues from where the page it left is")
    clock += 2; pager.tick()
    expect(pager.offset == 0 && !pager.isAnimating, "the slide settles")
    expect(pager.slideIn(from: 2, to: 0) && pager.offset == -240, "an earlier Space arrives from the left")
    clock += 2; pager.tick()
    expect(pager.slideIn(from: 0, to: 1), "a slide to the right")
    clock += 0.1; pager.tick()
    expect(pager.slideIn(from: 1, to: 2) && pager.offset == 240,
           "a second one the same way starts a page out, never past the page the strip can show")
    clock += 2; pager.tick()
    SystemOverrides.reduceMotion = true
    expect(!pager.slideIn(from: 0, to: 1) && pager.offset == 0, "Reduce Motion switches without a slide")
    SystemOverrides.reduceMotion = false

    typealias G = SidebarSpaceCreationGesture
    expect(G.overscroll(selected: 2, offset: -30, width: 240, count: 3) == 30, "the last page dragged left is past the end")
    expect(G.overscroll(selected: 1, offset: -270, width: 240, count: 3) == 30, "a drag from the page before reaches past it too")
    expect(G.overscroll(selected: 1, offset: 0, width: 240, count: 3) < 0 && G.overscroll(selected: 2, offset: 0, width: 240, count: 3) == 0,
           "at rest nothing is past the end")
    expect(G.presentation(7.5) == 0.5 && G.presentation(40) == 1 && G.presentation(-3) == 0, "the edge slides in over 15 points")
    expect(G.progress(11.25) == 0.5 && G.progress(22.5) == 1 && G.progress(-3) == 0, "the ring fills over 22.5 points")
    var gesture = G()
    expect(!gesture.update(progress: 0.6, now: 10) && !gesture.isActivated, "a partial ring is not activated")
    expect(gesture.update(progress: 1, now: 10.01) && gesture.isActivated, "filling the ring activates it, with a haptic")
    expect(!gesture.update(progress: 1, now: 10.05), "staying full plays nothing more")
    expect(!gesture.release(now: 10.1), "a release within 0.1 s of filling creates nothing")
    expect(gesture.update(progress: 0.4, now: 10.2) && !gesture.isActivated, "emptying the ring deactivates it, with a haptic")
    _ = gesture.update(progress: 1, now: 11)
    _ = gesture.update(progress: 0.9, now: 11.05)
    _ = gesture.update(progress: 1, now: 11.1)
    expect(!gesture.release(now: 11.15), "dipping below full restarts the hold")
    _ = gesture.update(progress: 1, now: 12)
    expect(gesture.release(now: 12.2), "a release held full for over 0.1 s creates a Space")
    expect(!gesture.release(now: 12.3), "and only once")

    let only = SidebarSpacePager.Page(id: UUID(), profileID: UUID())
    var onlySelected = only.id
    var onlyFeedback = G()
    var onlyFeedbackTime: CFTimeInterval = 13
    var onlyCreated = 0
    var onlyClock: CFTimeInterval = 13
    let onlyPager = SidebarSpacePager()
    onlyPager.pages = { [only] }
    onlyPager.selectedID = { onlySelected }
    onlyPager.pageWidth = { 240 }
    onlyPager.canBegin = { true }
    onlyPager.offersCreation = { true }
    onlyPager.canSelect = { _ in true }
    onlyPager.select = { onlySelected = $0.id }
    onlyPager.setOffset = { offset in
        let overscroll = G.overscroll(selected: 0, offset: offset, width: 240, count: 1)
        _ = onlyFeedback.update(progress: G.progress(overscroll), now: onlyFeedbackTime)
    }
    onlyPager.trackingEnded = {
        if onlyFeedback.release(now: onlyFeedbackTime) { onlyCreated += 1 }
    }
    onlyPager.now = { onlyClock }
    expect(onlyPager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 13),
           "a phased swipe starts with one Space")
    onlyFeedbackTime = 13.01
    expect(onlyPager.gesture(phase: .changed, momentum: false, dx: -45, dy: 0, time: 13.01)
           && onlyPager.offset == -22.5 && onlyFeedback.isActivated,
           "one Space reaches the same create threshold")
    onlyFeedbackTime = 13.2
    expect(onlyPager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 13.2)
           && onlyCreated == 1 && onlySelected == only.id,
           "releasing the held edge creates without paging to a missing Space")
    onlyClock += 2; onlyPager.tick()
    expect(onlyPager.offset == 0 && !onlyPager.isAnimating, "the lone Space settles back after creation")
    onlyFeedbackTime = 14
    _ = onlyPager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 14)
    onlyFeedbackTime = 14.01
    _ = onlyPager.gesture(phase: .changed, momentum: false, dx: -20, dy: 0, time: 14.01)
    onlyFeedbackTime = 14.05
    _ = onlyPager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 14.05)
    expect(onlyCreated == 1 && onlyPager.isAnimating, "a short lone-Space swipe creates nothing and springs back")
    onlyClock += 2; onlyPager.tick()
    expect(onlyPager.offset == 0 && onlySelected == only.id, "the short swipe settles on the only Space")
    _ = onlyPager.gesture(phase: .began, momentum: false, dx: 2, dy: 0, time: 15)
    _ = onlyPager.gesture(phase: .changed, momentum: false, dx: 120, dy: 0, time: 15.01)
    expect(onlyPager.offset > 0 && onlyPager.offset < 24, "a lone Space resists a backward drag like the first Space")
    _ = onlyPager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 15.2)
    onlyClock += 2; onlyPager.tick()
    expect(onlyPager.offset == 0 && onlyCreated == 1, "and springs back without creating")

    var spring = SidebarSpring(response: 0.4, damping: 0.8)
    spring.retarget(1, now: 0)
    let before = spring.value(at: 0.1), speed = spring.speed(at: 0.1)
    expect(before > 0 && before < 1 && speed > 0, "the edge springs toward its target")
    spring.retarget(0.2, now: 0.1)
    expect(abs(spring.value(at: 0.1) - before) < 1e-9 && abs(spring.speed(at: 0.1) - speed) < 1e-9,
           "a new target continues from the same place and speed")
    expect(!spring.isSettled(at: 0.2) && spring.isSettled(at: 2) && abs(spring.value(at: 2) - 0.2) < 0.001, "and settles there")
    let omega = 2 * CGFloat.pi / 0.4
    expect(abs(M.springValue(from: 1, velocity: 0, time: 0.3) - (1 + omega * 0.3) * exp(-omega * 0.3)) < 1e-12,
           "the paging spring stays critically damped")

    var ends: [UUID?] = []
    pager.trackingEnded = { ends.append(selected) }
    selected = ids[2].id; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 30)
    for k in 0..<6 { _ = pager.gesture(phase: .changed, momentum: false, dx: -15, dy: 0, time: 30.01 + Double(k) * 0.01) }
    expect(G.overscroll(selected: 2, offset: pager.offset, width: 240, count: 3) == 45, "the strip follows past the last Space at half the finger distance")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 30.2)
    expect(selections.isEmpty && ends == [ids[2].id], "the release stays on the last Space and reports the end")
    expect(G.overscroll(selected: 2, offset: pager.offset, width: 240, count: 3) == 45, "the end sees the strip where it was released")
    clock += 2; pager.tick()
    var endOverscroll: CGFloat?
    pager.trackingEnded = {
        ends.append(selected)
        endOverscroll = G.overscroll(selected: ids.firstIndex { $0.id == selected }!, offset: pager.offset, width: 240, count: 3)
    }
    selected = ids[1].id
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 32)
    for k in 0..<36 { _ = pager.gesture(phase: .changed, momentum: false, dx: -15, dy: 0, time: 32.01 + Double(k) * 0.01) }
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 32.4)
    expect(ends.last == ids[2].id && endOverscroll == 30, "the release reports after selecting the last Space, still 30 points past it")
    clock += 2; pager.tick()
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 33)
    _ = pager.gesture(phase: .changed, momentum: false, dx: -90, dy: 0, time: 33.01)
    expect(pager.isTracking && G.overscroll(selected: 2, offset: pager.offset, width: 240, count: 3) == 45,
           "a cancelled drag first tracks past the last Space")
    _ = pager.gesture(phase: .cancelled, momentum: false, dx: 0, dy: 0, time: 33.3)
    expect(ends.count == 2, "a cancelled gesture reports no release")
    clock += 2; pager.tick()
    _ = pager.gesture(phase: .mayBegin, momentum: false, dx: 0, dy: 0, time: 34)
    _ = pager.gesture(phase: .began, momentum: false, dx: 0, dy: 5, time: 34.01)
    expect(ends.count == 2, "a gesture that turns vertical reports no end")
    offers = false; selected = ids[2].id
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 35)
    for k in 0..<6 { _ = pager.gesture(phase: .changed, momentum: false, dx: -15, dy: 0, time: 35.01 + Double(k) * 0.01) }
    let unoffered = G.overscroll(selected: 2, offset: pager.offset, width: 240, count: 3)
    expect(unoffered > 0 && unoffered < 45 * 0.55 && G.progress(unoffered) < 1,
           "where no new Space is offered, the last Space resists like any other end")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 35.2)
    clock += 2; pager.tick()
    offers = true
    pager.trackingEnded = {}

    _ = NSApplication.shared
    final class Sidebar: NSView {
        var received = 0
        override func scrollWheel(with event: NSEvent) { received += 1 }
    }
    final class Flipped: NSView { override var isFlipped: Bool { true } }
    func scroll(_ dx: Int32, _ dy: Int32, phase: Int64?, at time: UInt64) -> NSEvent {
        let units: CGScrollEventUnit = phase == nil ? .line : .pixel
        let event = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        if let phase {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        }
        event.timestamp = time
        return NSEvent(cgEvent: event)!
    }
    func list<V: NSScrollView>(_ view: V) -> (V, Sidebar, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        let sidebar = Sidebar(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        view.frame = sidebar.bounds
        view.hasVerticalScroller = true; view.horizontalScrollElasticity = .none
        view.documentView = Flipped(frame: NSRect(x: 0, y: 0, width: 240, height: 2000))
        sidebar.addSubview(view); window.contentView = sidebar
        return (view, sidebar, window)
    }
    let (plain, plainSidebar, plainWindow) = list(NSScrollView())
    plain.scrollWheel(with: scroll(-3, 0, phase: nil, at: 1))
    expect(plainSidebar.received == 0, "a plain scroll view keeps a horizontal scroll from the sidebar")
    _ = plainWindow

    let tablistPager = SidebarSpacePager()
    var tablistSelected = ids[0].id
    tablistPager.pages = { ids }
    tablistPager.selectedID = { tablistSelected }
    tablistPager.pageWidth = { 240 }
    tablistPager.canBegin = { true }
    tablistPager.canSelect = { _ in true }
    tablistPager.select = { tablistSelected = $0.id }
    tablistPager.now = { clock }
    let (tablist, _, tablistWindow) = list(SidebarPagingScrollView())
    var declined = 0
    tablist.offerScroll = { event in
        let used = tablistPager.scrollWheel(event)
        if !used { declined += 1 }
        return used
    }
    let second: UInt64 = 1_000_000_000
    tablist.scrollWheel(with: scroll(0, 0, phase: 128, at: 40 * second))
    tablist.scrollWheel(with: scroll(-4, 0, phase: 1, at: 40 * second + second / 100))
    for k in 0..<12 { tablist.scrollWheel(with: scroll(-12, 0, phase: 2, at: 40 * second + UInt64(k + 2) * second / 100)) }
    expect(tablistPager.isTracking && tablistPager.offset == -72, "a horizontal swipe over the list drags the Space strip")
    expect(tablist.contentView.bounds.origin == .zero, "and doesn't scroll the list")
    tablist.scrollWheel(with: scroll(0, 0, phase: 4, at: 41 * second))
    expect(!tablistPager.isTracking, "the release ends the swipe")
    clock += 2; tablistPager.tick()
    expect(declined == 0, "every event of the swipe was the pager's")
    tablist.scrollWheel(with: scroll(0, 0, phase: 128, at: 42 * second))
    tablist.scrollWheel(with: scroll(0, -6, phase: 1, at: 42 * second + second / 100))
    tablist.scrollWheel(with: scroll(0, -9, phase: 2, at: 42 * second + second / 50))
    tablist.scrollWheel(with: scroll(0, 0, phase: 4, at: 42 * second + second / 20))
    tablist.scrollWheel(with: scroll(0, -3, phase: nil, at: 43 * second))
    expect(declined == 4 && !tablistPager.isTracking && tablistPager.offset == 0,
           "a vertical swipe and a wheel go on to the list's own scrolling")
    _ = tablistWindow

    print("SidebarSpacePaging: \(count) checks passed")
}

MainActor.assumeIsolated { exitOnFailure(run) }
