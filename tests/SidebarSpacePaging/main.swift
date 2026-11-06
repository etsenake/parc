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

    // Release target: fling chooses direction, slow release the nearest page, one page from the beginning.
    expect(M.target(position: 120, velocity: 6, width: 200, count: 4, begin: 0) == 1, "a forward fling goes next")
    expect(M.target(position: 120, velocity: -6, width: 200, count: 4, begin: 1) == 0, "a backward fling goes previous")
    expect(M.target(position: 90, velocity: 1, width: 200, count: 4, begin: 0) == 0, "a slow short drag stays")
    expect(M.target(position: 110, velocity: 1, width: 200, count: 4, begin: 0) == 1, "a slow long drag passes halfway")
    expect(M.target(position: 700, velocity: 900, width: 200, count: 4, begin: 1) == 2, "never more than one page")
    expect(M.target(position: -80, velocity: -900, width: 200, count: 4, begin: 0) == 0, "never before the first page")
    expect(M.target(position: 650, velocity: 900, width: 200, count: 4, begin: 3) == 3, "never past the last page")

    // Non-gestural accumulation, gap reset and cooldown.
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

    // Pager wiring with a manual clock and no events.
    let ids = (0..<3).map { _ in SidebarSpacePager.Page(id: UUID(), profileID: UUID()) }
    var selected = ids[1].id
    var selections: [UUID] = []
    var available = true
    var accepts = true
    var offsets: [CGFloat] = []
    var clock: CFTimeInterval = 100
    let pager = SidebarSpacePager()
    pager.pages = { ids }
    pager.selectedID = { selected }
    pager.pageWidth = { 240 }
    pager.canBegin = { true }
    pager.canSelect = { _ in available }
    pager.select = { selections.append($0.id); if accepts { selected = $0.id } }
    pager.setOffset = { offsets.append($0) }
    SystemOverrides.install()
    SystemOverrides.reduceMotion = false
    pager.now = { clock }

    // A slow drag to the left past halfway lands on the next Space.
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

    // A vertical began after may-begin ends tracking without paging.
    expect(pager.gesture(phase: .mayBegin, momentum: false, dx: 0, dy: 0, time: 3), "armed again")
    expect(!pager.gesture(phase: .began, momentum: false, dx: 1, dy: 6, time: 3.01), "vertical began passes on")
    expect(!pager.isTracking, "tracking ended")

    // A refused switch springs back from the tracked offset.
    selected = ids[1].id; accepts = false; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: 4, dy: 0, time: 4)
    for k in 0..<10 { _ = pager.gesture(phase: .changed, momentum: false, dx: 30, dy: 0, time: 4.01 + Double(k) * 0.01) }
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 4.1)
    expect(selections == [ids[0].id], "the previous Space was requested")
    expect(pager.offset == 150, "the original page stays where it was dragged")
    clock += 2; pager.tick()
    expect(pager.offset == 0, "and springs back")

    // Discrete paging and availability.
    accepts = true; selections = []
    expect(pager.swipe(deltaX: -1), "a legacy swipe left pages")
    expect(selections == [ids[2].id] && pager.offset == 240, "the next page arrives from the right")
    clock += 2; pager.tick()
    available = false; selections = []
    expect(pager.swipe(deltaX: 1), "the swipe is still the pager's")
    expect(selections.isEmpty, "an unavailable Space is not selected")
    SystemOverrides.reduceMotion = true; available = true; selected = ids[1].id
    expect(pager.swipe(deltaX: 1) && pager.offset == 0, "Reduce Motion places the page at rest")

    // True no-op presentation skip: identical strip fingerprints must not
    // re-enter setOffset; changed offsets and settle still present.
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

    //
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

    // Through the pager: a long drag past one page and its release.
    selected = ids[0].id; accepts = true; available = true; selections = []
    _ = pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 20)
    for k in 0..<30 { _ = pager.gesture(phase: .changed, momentum: false, dx: -21, dy: 0, time: 20.02 + Double(k) * 0.02) }
    let dragged = pages(0, pager.offset)
    expect(pager.offset < -240 && dragged.map { $0.left == 1 } == true, "a long drag's theme pairs the two pages beyond the first")
    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: 20.61)
    expect(selections == [ids[1].id] && same(pages(1, pager.offset), dragged), "its release keeps the same pair and progress")
    clock += 2; pager.tick()
    // A second discrete page while the first one springs.
    selected = ids[0].id
    expect(pager.swipe(deltaX: -1), "a first page")
    clock += 0.2; pager.tick()
    let springing = pages(1, pager.offset)
    expect(pager.offset > 0 && pager.offset < 240, "still springing")
    expect(pager.swipe(deltaX: -1) && selected == ids[2].id, "a second page")
    expect(same(pages(2, pager.offset), springing), "the second page continues from the same pair and progress")
    clock += 2; pager.tick()

    // A Space chosen elsewhere (keyboard, menu, dock) slides in from the one it left.
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

    print("SidebarSpacePaging: \(count) checks passed")
}

MainActor.assumeIsolated { run() }
