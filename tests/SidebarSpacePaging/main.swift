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

    //
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

    // A lone Space still tracks past its trailing edge so the same feedback
    // can fill, hold and create; without activation it springs back in place.
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
    onlyPager.canTrackSinglePageCreation = { true }
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

    // The spring the create-Space edge slides on (response 0.4, damping 0.8).
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
           "the paging spring stays the critically damped one")

    // The pager reports a tracked release after its page is chosen, and only then.
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
    // From the page before, past the last one: the end sees the new page and the strip unmoved.
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
    pager.trackingEnded = {}

    // The tablist hands the pager its scrolls first. A plain scroll view keeps
    // a horizontal scroll it can't use instead of passing it to the sidebar,
    // which is why swipes over the list never paged.
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

MainActor.assumeIsolated { run() }
