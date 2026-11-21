import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarSpacePagerTests {
    typealias M = SidebarSpacePagingModel
    typealias G = SidebarSpaceCreationGesture

    @MainActor final class Strip {
        let ids: [SidebarSpacePager.Page]
        var selected: UUID
        var selections: [UUID] = []
        var offsets: [CGFloat] = []
        var available = true, accepts = true, offers = true, reduceMotion = false
        var clock: CFTimeInterval = 100
        let pager = SidebarSpacePager()

        init(count: Int = 3, selected index: Int = 1) {
            ids = (0..<count).map { _ in SidebarSpacePager.Page(id: UUID(), profileID: UUID()) }
            selected = ids[index].id
            pager.pages = { [weak self] in self?.ids ?? [] }
            pager.selectedID = { [weak self] in self?.selected }
            pager.pageWidth = { 240 }
            pager.canBegin = { true }
            pager.offersCreation = { [weak self] in self?.offers ?? false }
            pager.canSelect = { [weak self] _ in self?.available ?? false }
            pager.select = { [weak self] page in
                guard let self else { return }
                selections.append(page.id); if accepts { selected = page.id }
            }
            pager.setOffset = { [weak self] in self?.offsets.append($0) }
            pager.now = { [weak self] in self?.clock ?? 0 }
            pager.reducesMotion = { [weak self] in self?.reduceMotion ?? false }
        }

        var index: Int { ids.firstIndex { $0.id == selected }! }
        func select(_ index: Int) { selected = ids[index].id }
        func id(_ index: Int) -> UUID { ids[index].id }

        @discardableResult func gesture(_ phase: NSEvent.Phase, _ dx: CGFloat, dy: CGFloat = 0, at time: CFTimeInterval, momentum: Bool = false) -> Bool {
            pager.gesture(phase: phase, momentum: momentum, dx: dx, dy: dy, time: time)
        }
        func drag(_ dx: CGFloat, steps: Int, from time: CFTimeInterval, every interval: CFTimeInterval, first: Int = 0) {
            for k in 0..<steps { gesture(.changed, dx, at: time + Double(k + first) * interval) }
        }
        func advance(_ seconds: CFTimeInterval) { clock += seconds; pager.tick() }
        func rest() { advance(2) }
        func overscroll() -> CGFloat { G.overscroll(selected: index, offset: pager.offset, width: 240, count: ids.count) }
    }

    private func same(_ a: (left: Int, progress: CGFloat)?, _ b: (left: Int, progress: CGFloat)?) -> Bool { SidebarSpacePagingModelTests.same(a, b) }
    private func pages(_ selected: Int, _ offset: CGFloat) -> (left: Int, progress: CGFloat)? { SidebarSpacePagingModelTests.pages(selected, offset) }
    private func swiped(_ s: Strip, _ selected: Int, _ offset: CGFloat) -> (left: Int, progress: CGFloat)? {
        SidebarSpacePagingModelTests.pages(selected, offset, within: s.pager.reach)
    }

    @Test func aForwardFlingFollowsAtHalfTheFingerAndSelectsTheNextSpace() {
        let s = Strip()
        #expect(s.gesture(.mayBegin, 0, at: 1))
        #expect(s.gesture(.began, -2, at: 1.01))
        s.drag(-9, steps: 30, from: 1.02, every: 0.02)
        #expect(s.pager.offset == -135)
        #expect(s.gesture(.ended, 0, at: 2))
        #expect(s.selections == [s.id(2)])
        #expect(s.pager.offset == 105 && s.pager.isAnimating)
    }

    @Test func theArrivingPageSpringsToRestAndMomentumIsConsumed() {
        let s = Strip()
        s.gesture(.began, -2, at: 1.01); s.drag(-9, steps: 30, from: 1.02, every: 0.02); s.gesture(.ended, 0, at: 2)
        s.rest()
        #expect(s.pager.offset == 0 && !s.pager.isAnimating)
        #expect(s.gesture([], -5, at: 2.1, momentum: true))
    }

    @Test func aVerticalBeganPassesOnAndEndsTracking() {
        let s = Strip()
        #expect(s.gesture(.mayBegin, 0, at: 3))
        #expect(!s.gesture(.began, 1, dy: 6, at: 3.01))
        #expect(!s.pager.isTracking)
    }

    @Test func aRefusedSelectionLeavesThePageWhereItWasDraggedAndSpringsBack() {
        let s = Strip()
        s.accepts = false
        s.gesture(.began, 4, at: 4); s.drag(30, steps: 10, from: 4.01, every: 0.01); s.gesture(.ended, 0, at: 4.1)
        #expect(s.selections == [s.id(0)])
        #expect(s.pager.offset == 150)
        s.rest()
        #expect(s.pager.offset == 0)
    }

    @Test func aLegacySwipeLeftBringsTheNextPageFromTheRight() {
        let s = Strip()
        #expect(s.pager.swipe(deltaX: -1))
        #expect(s.selections == [s.id(2)] && s.pager.offset == 240)
    }

    @Test func anUnavailableSpaceIsNotSelectedButTheSwipeIsStillThePagers() {
        let s = Strip()
        s.available = false
        #expect(s.pager.swipe(deltaX: 1))
        #expect(s.selections.isEmpty)
    }

    @Test func reduceMotionPlacesTheSwipedPageAtRest() {
        let s = Strip()
        s.reduceMotion = true
        #expect(s.pager.swipe(deltaX: 1) && s.pager.offset == 0)
    }

    @Test func theArrivingPagePresentsOnceAndFrozenTicksSkipIdenticalLayout() {
        let s = Strip()
        #expect(s.pager.swipe(deltaX: -1))
        #expect(s.offsets == [240])
        s.pager.tick()
        #expect(s.offsets.count == 1 && s.pager.offset == 240 && s.pager.isAnimating)
        s.pager.tick()
        #expect(s.offsets.count == 1 && s.pager.isAnimating)
    }

    @Test func anAdvancingSpringPresentsUntilItSettlesThenDoesNoMoreWork() {
        let s = Strip()
        _ = s.pager.swipe(deltaX: -1)
        s.advance(1.0 / 120)
        #expect(s.offsets.count == 2 && s.offsets.last != 240)
        s.rest()
        #expect(s.pager.offset == 0 && !s.pager.isAnimating && s.offsets.last == 0)
        let settled = s.offsets.count
        s.pager.tick()
        #expect(s.offsets.count == settled)
        s.pager.cancel()
        #expect(s.offsets.count == settled)
    }

    private func longForwardDrag(_ s: Strip) -> [CGFloat] {
        s.select(0)
        s.gesture(.began, -2, at: 20)
        var strip: [CGFloat] = []
        for k in 0..<30 { s.gesture(.changed, -21, at: 20.02 + Double(k) * 0.02); strip.append(-s.pager.offset) }
        return strip
    }

    @Test func aLongDragStopsAtTheNeighbouringSpaceWithIncreasingResistance() {
        let s = Strip()
        let strip = longForwardDrag(s)
        let advances = zip(strip.dropFirst(), strip).map { $0 - $1 }
        #expect(Array(strip.prefix(22)) == (1...22).map { CGFloat($0) * 10.5 })
        #expect(strip.last! > 240 && strip.allSatisfy { $0 < 240 + 24 })
        #expect(advances.suffix(7).allSatisfy { $0 > 0 && $0 < 10.5 * 0.55 })
        #expect(zip(advances.suffix(6), advances.suffix(7)).allSatisfy { $0 < $1 })
        #expect(s.pager.reach == 0...1 && same(swiped(s, 0, s.pager.offset), (0, 1)))
    }

    @Test func releasingAStretchedDragRebasesAndSpringsBackWithinTheSwipesTwoSpaces() {
        let s = Strip()
        _ = longForwardDrag(s)
        let held = s.pager.offset
        s.gesture(.ended, 0, at: 20.61)
        #expect(s.selections == [s.id(1)])
        #expect(abs(s.pager.offset - (240 + held)) < 1e-9 && s.pager.reach == 0...1 && s.pager.isAnimating)
        #expect(same(swiped(s, 1, s.pager.offset), (0, 1)) && s.pager.reach?.contains(2) == false)
        s.advance(0.1)
        #expect(s.pager.offset < 0 && s.pager.offset > 240 + held && s.pager.reach == 0...1)
        s.rest()
        #expect(s.pager.offset == 0 && !s.pager.isAnimating && s.pager.reach == nil)
    }

    @Test func aLongBackwardDragStopsAtThePreviousSpaceTheSameWay() {
        let s = Strip(selected: 2)
        s.gesture(.began, 2, at: 22); s.drag(15, steps: 40, from: 22.01, every: 0.01)
        #expect(s.pager.offset > 240 && s.pager.offset < 264 && s.pager.reach == 1...2)
        #expect(same(swiped(s, 2, s.pager.offset), (1, 0)))
        s.gesture(.ended, 0, at: 22.45)
        #expect(s.selections == [s.id(1)])
    }

    @Test func atTheFirstSpaceABackwardDragMeetsTheRubberBandAndSpringsBack() {
        let s = Strip(selected: 0)
        s.gesture(.began, 2, at: 24)
        var edge: [CGFloat] = []
        for k in 0..<20 { s.gesture(.changed, 12, at: 24.01 + Double(k) * 0.01); edge.append(s.pager.offset) }
        #expect(edge.first! > 0 && edge.first! < 6 * 0.55 && edge.last! < 24 && zip(edge.dropFirst(), edge).allSatisfy { $0 > $1 })
        #expect(same(swiped(s, 0, edge.last!), (0, 0)))
        s.gesture(.ended, 0, at: 24.25)
        #expect(s.selections.isEmpty && s.pager.isAnimating && s.pager.offset == edge.last!)
        s.rest()
        #expect(s.pager.offset == 0 && s.pager.reach == nil)
    }

    @Test func pickingTheStripUpMidSettleSpendsOnlyTheRemainingGive() {
        let s = Strip(selected: 0)
        s.gesture(.began, 2, at: 25); s.gesture(.changed, 120, at: 25.01); s.gesture(.ended, 0, at: 25.3)
        s.advance(0.05)
        let relaxing = s.pager.offset
        #expect(relaxing > 0 && relaxing < M.stretch(60, width: 240) && s.pager.reach == 0...1)
        s.gesture(.began, 2, at: 25.4)
        #expect(s.pager.offset == relaxing)
        s.gesture(.changed, 4, at: 25.41)
        #expect(abs(s.pager.offset - (relaxing + M.stretch(2, limit: 24 - relaxing))) < 1e-9 && s.pager.offset - relaxing < 2 * 0.55)
        s.gesture(.changed, -24, at: 25.42)
        #expect(abs(s.pager.offset - (relaxing - 10)) < 1e-9)
        s.gesture(.ended, 0, at: 25.7)
        s.rest()
        #expect(s.selections.isEmpty && s.pager.offset == 0)
    }

    @Test func quickRepeatedPullsAtTheFirstSpaceNeverStretchPastATenthOfAPage() {
        let s = Strip(selected: 0)
        var widest: CGFloat = 0
        for round in 0..<6 {
            let at = 25.8 + Double(round) * 0.1
            s.gesture(.began, 2, at: at); s.gesture(.changed, 600, at: at + 0.01)
            widest = max(widest, s.pager.offset)
            s.gesture(.ended, 0, at: at + 0.05)
            s.advance(0.01)
        }
        #expect(widest > 0 && widest < 24 && s.selections.isEmpty)
    }

    @Test func aSwipeStartedDuringAnOvershootingFlipTakesTheStripFromWhereItIs() {
        let s = Strip(selected: 0)
        #expect(s.pager.swipe(deltaX: -1))
        s.advance(0.2)
        #expect(s.pager.swipe(deltaX: -1) && s.selected == s.id(2) && s.pager.offset > 264)
        let flipped = s.pager.offset, theme = pages(2, flipped)
        s.selections = []
        s.gesture(.began, -2, at: 27)
        #expect(s.pager.offset == flipped && same(swiped(s, 2, flipped), theme))
        s.gesture(.changed, -40, at: 27.01)
        #expect(abs(s.pager.offset - (flipped - 20)) < 1e-9)
        s.gesture(.changed, 80, at: 27.02)
        #expect(abs(s.pager.offset - flipped) < 1e-9)
        s.gesture(.changed, -10, at: 27.03)
        #expect(abs(s.pager.offset - (flipped - 5)) < 1e-9)
        s.gesture(.ended, 0, at: 27.3)
        #expect(s.selections == [s.id(1)])
        s.rest()
        #expect(s.pager.offset == 0 && s.pager.reach == nil)
    }

    @Test func aSwipeHoldsItsReachUntilCancelled() {
        let s = Strip()
        s.gesture(.began, -2, at: 28); s.gesture(.changed, -20, at: 28.01)
        #expect(s.pager.reach == 0...2)
        s.pager.cancel()
        #expect(s.pager.reach == nil && s.pager.offset == 0)
    }

    @Test func theReachLastsThroughTheSettleUntilASwitchFromElsewhere() {
        let s = Strip()
        s.gesture(.began, -2, at: 28.1); s.gesture(.changed, -300, at: 28.11); s.gesture(.ended, 0, at: 28.12)
        #expect(s.selected == s.id(2) && s.pager.isAnimating && s.pager.reach == 0...2)
        #expect(s.pager.slideIn(from: 2, to: 0) && s.pager.reach == nil)
    }

    @Test func aPageFlipEndsTheSettlingSwipesReach() {
        let s = Strip(selected: 0)
        s.gesture(.began, -2, at: 29); s.gesture(.changed, -300, at: 29.01); s.gesture(.ended, 0, at: 29.02)
        #expect(s.selected == s.id(1) && s.pager.reach == 0...1)
        #expect(s.pager.swipe(deltaX: -1) && s.selected == s.id(2) && s.pager.reach == nil)
    }

    @Test func aBriskFlicksOvershootOutsideTheSwipeStretchesLikeTheEdge() {
        let s = Strip(selected: 0)
        s.gesture(.began, -2, at: 29.5)
        for k in 1...20 { s.gesture(.changed, -21.6, at: 29.5 + Double(k) * 0.005) }
        s.gesture(.ended, 0, at: 29.6)
        #expect(s.selections == [s.id(1)] && abs(s.pager.offset - 24) < 1e-9)
        let flicked = s.clock
        var deepest: CGFloat = 0, unguarded: CGFloat = 0, deepestRaw: CGFloat = 0
        for k in 1...60 {
            s.clock = flicked + Double(k) * 0.005; s.pager.tick()
            let raw = M.springValue(from: 24, velocity: -2160, time: CGFloat(k) * 0.005)
            if s.pager.offset < deepest { deepest = s.pager.offset; deepestRaw = raw }
            unguarded = min(unguarded, raw)
        }
        #expect(unguarded < -24 && deepest < 0 && deepest > -24 && abs(deepest + M.stretch(-deepestRaw, width: 240)) < 0.01)
        #expect(s.pager.reach == 0...1 && same(swiped(s, 1, deepest), (0, 1)))
        s.rest()
        #expect(s.pager.offset == 0 && s.pager.reach == nil)
    }

    nonisolated static let releases: [(Int, CGFloat, Bool)] = (0..<3).flatMap { begin in
        [-1400, -900, -500, -250, -60, 60, 250, 500, 900, 1400].flatMap { finger in [false, true].map { (begin, CGFloat(finger), $0) } }
    }

    @Test(arguments: releases)
    func releaseTargetsFollowTheUnresistedDrag(begin: Int, finger: CGFloat, pause: Bool) {
        let s = Strip(selected: begin)
        let start: CFTimeInterval = 26
        s.gesture(.began, finger > 0 ? -2 : 2, at: start)
        for k in 1...20 { s.gesture(.changed, -finger / 20, at: start + Double(k) * 0.01) }
        let drag = CGFloat(begin) * 240 + 0.5 * finger
        let expected = M.target(position: drag, velocity: pause ? 0 : 0.5 * finger / 20 / 0.01, width: 240, count: 3, begin: begin)
        s.gesture(.ended, 0, at: start + 0.2 + (pause ? 0.2 : 0))
        #expect(s.index == expected && abs(s.index - begin) <= 1)
    }

    @Test func aSecondPageContinuesFromTheSameThemePairAndProgress() {
        let s = Strip(selected: 0)
        #expect(s.pager.swipe(deltaX: -1))
        s.advance(0.2)
        let springing = pages(1, s.pager.offset)
        #expect(s.pager.offset > 0 && s.pager.offset < 240)
        #expect(s.pager.swipe(deltaX: -1) && s.selected == s.id(2))
        #expect(same(pages(2, s.pager.offset), springing))
    }

    @Test func theSameSpaceDoesNotSlide() {
        #expect(!Strip(selected: 2).pager.slideIn(from: 1, to: 1))
    }

    @Test func aLaterSpaceArrivesFromTheRightWithoutSelecting() {
        let s = Strip(selected: 2)
        #expect(s.pager.slideIn(from: 0, to: 2) && s.pager.offset == 240 && s.pager.isAnimating && s.selections.isEmpty)
        s.advance(0.2)
        #expect(s.pager.offset > 0 && s.pager.offset < 240)
    }

    @Test func aSwitchMidSlideContinuesFromWhereThePageItLeftIs() {
        let s = Strip(selected: 2)
        s.pager.slideIn(from: 0, to: 2)
        s.advance(0.2)
        let midway = s.pager.offset
        #expect(s.pager.slideIn(from: 2, to: 1) && abs(s.pager.offset - (midway - 240)) < 0.001)
        s.rest()
        #expect(s.pager.offset == 0 && !s.pager.isAnimating)
    }

    @Test func anEarlierSpaceArrivesFromTheLeft() {
        let s = Strip(selected: 2)
        #expect(s.pager.slideIn(from: 2, to: 0) && s.pager.offset == -240)
    }

    @Test func aSecondSlideTheSameWayStartsOnePageOut() {
        let s = Strip(selected: 2)
        #expect(s.pager.slideIn(from: 0, to: 1))
        s.advance(0.1)
        #expect(s.pager.slideIn(from: 1, to: 2) && s.pager.offset == 240)
    }

    @Test func reduceMotionSwitchesWithoutASlide() {
        let s = Strip(selected: 2)
        s.reduceMotion = true
        #expect(!s.pager.slideIn(from: 0, to: 1) && s.pager.offset == 0)
    }
}
