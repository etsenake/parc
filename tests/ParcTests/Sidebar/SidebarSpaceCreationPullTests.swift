import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarSpaceCreationPullTests {
    typealias G = SidebarSpaceCreationGesture
    typealias Strip = SidebarSpacePagerTests.Strip

    @MainActor final class Lone {
        let only = SidebarSpacePager.Page(id: UUID(), profileID: UUID())
        var selected: UUID
        var feedback = G()
        var feedbackTime: CFTimeInterval = 13
        var created = 0
        var clock: CFTimeInterval = 13
        let pager = SidebarSpacePager()
        init() {
            selected = only.id
            pager.pages = { [weak self] in self.map { [$0.only] } ?? [] }
            pager.selectedID = { [weak self] in self?.selected }
            pager.pageWidth = { 240 }
            pager.canBegin = { true }
            pager.offersCreation = { true }
            pager.canSelect = { _ in true }
            pager.select = { [weak self] in self?.selected = $0.id }
            pager.setOffset = { [weak self] offset in
                guard let self else { return }
                let overscroll = G.overscroll(selected: 0, offset: offset, width: 240, count: 1)
                _ = feedback.update(progress: G.progress(overscroll), pulling: pager.isTracking, now: feedbackTime)
            }
            pager.trackingEnded = { [weak self] in
                guard let self else { return }
                if feedback.release(now: feedbackTime) { created += 1 }
            }
            pager.now = { [weak self] in self?.clock ?? 0 }
            pager.reducesMotion = { false }
        }
        func gesture(_ phase: NSEvent.Phase, _ dx: CGFloat, at time: CFTimeInterval) -> Bool {
            feedbackTime = time
            return pager.gesture(phase: phase, momentum: false, dx: dx, dy: 0, time: time)
        }
        func rest() { clock += 2; pager.tick() }
    }

    @Test func aLoneSpaceReachesTheCreateThresholdAndCreatesWithoutPaging() {
        let l = Lone()
        #expect(l.gesture(.began, -2, at: 13))
        #expect(l.gesture(.changed, -45, at: 13.01) && l.pager.offset == -22.5 && l.feedback.isActivated)
        #expect(l.gesture(.ended, 0, at: 13.2) && l.created == 1 && l.selected == l.only.id)
        l.rest()
        #expect(l.pager.offset == 0 && !l.pager.isAnimating)
    }

    @Test func aShortLoneSpaceSwipeCreatesNothingAndSpringsBack() {
        let l = Lone()
        _ = l.gesture(.began, -2, at: 14); _ = l.gesture(.changed, -20, at: 14.01); _ = l.gesture(.ended, 0, at: 14.05)
        #expect(l.created == 0 && l.pager.isAnimating)
        l.rest()
        #expect(l.pager.offset == 0 && l.selected == l.only.id)
    }

    @Test func aLoneSpaceResistsABackwardDragLikeTheFirstSpace() {
        let l = Lone()
        _ = l.gesture(.began, 2, at: 15); _ = l.gesture(.changed, 120, at: 15.01)
        #expect(l.pager.offset > 0 && l.pager.offset < 24)
        _ = l.gesture(.ended, 0, at: 15.2)
        l.rest()
        #expect(l.pager.offset == 0 && l.created == 0)
    }

    @Test func aReleasePastTheLastSpaceStaysAndReportsTheEndWhereItWasReleased() {
        let s = Strip(selected: 2)
        var ends: [UUID] = []
        s.pager.trackingEnded = { ends.append(s.selected) }
        s.gesture(.began, -2, at: 30); s.drag(-15, steps: 6, from: 30.01, every: 0.01)
        #expect(s.overscroll() == 45)
        s.gesture(.ended, 0, at: 30.2)
        #expect(s.selections.isEmpty && ends == [s.id(2)])
        #expect(s.overscroll() == 45)
    }

    @Test func aReleaseReportsAfterSelectingTheLastSpaceStill30PointsPastIt() {
        let s = Strip(selected: 1)
        var ends: [UUID] = [], overscroll: CGFloat?
        s.pager.trackingEnded = { ends.append(s.selected); overscroll = s.overscroll() }
        s.gesture(.began, -2, at: 32); s.drag(-15, steps: 36, from: 32.01, every: 0.01); s.gesture(.ended, 0, at: 32.4)
        #expect(ends.last == s.id(2) && overscroll == 30)
    }

    @Test func aCancelledDragReportsNoRelease() {
        let s = Strip(selected: 2)
        var ends = 0
        s.pager.trackingEnded = { ends += 1 }
        s.gesture(.began, -2, at: 33); s.gesture(.changed, -90, at: 33.01)
        #expect(s.pager.isTracking && s.overscroll() == 45)
        s.gesture(.cancelled, 0, at: 33.3)
        #expect(ends == 0)
    }

    @Test func aGestureThatTurnsVerticalReportsNoEnd() {
        let s = Strip(selected: 2)
        var ends = 0
        s.pager.trackingEnded = { ends += 1 }
        s.gesture(.mayBegin, 0, at: 34); s.gesture(.began, 0, dy: 5, at: 34.01)
        #expect(ends == 0)
    }

    @Test func withoutACreationOfferTheLastSpaceResistsLikeAnyEnd() {
        let s = Strip(selected: 2)
        s.offers = false
        s.gesture(.began, -2, at: 35); s.drag(-15, steps: 6, from: 35.01, every: 0.01)
        let unoffered = s.overscroll()
        #expect(unoffered > 0 && unoffered < 45 * 0.55 && G.progress(unoffered) < 1)
    }

    @MainActor final class Ring {
        let s: Strip
        var ring = G(), eager = G(), ringClock: CFTimeInterval = 50
        var taps: [Bool] = [], eagerTaps: [Bool] = [], seen: [CGFloat] = [], created = 0
        init(selected index: Int, selects: Bool = true) {
            s = Strip(selected: index)
            s.pager.setOffset = { [weak self] in self?.feel($0) }
            s.pager.select = { [weak self] page in
                guard let self else { return }
                s.selections.append(page.id)
                if selects { s.selected = page.id }
                seen.append(G.overscroll(selected: s.index, offset: s.pager.offset, width: 240, count: 3))
                feel(s.pager.offset)
            }
            s.pager.trackingEnded = { [weak self] in
                guard let self else { return }
                if ring.release(now: ringClock) { created += 1 }
            }
        }
        func feel(_ offset: CGFloat) {
            let progress = G.progress(G.overscroll(selected: s.index, offset: offset, width: 240, count: 3))
            if ring.update(progress: progress, pulling: s.pager.isTracking, now: ringClock) { taps.append(ring.isActivated) }
            if eager.update(progress: progress, pulling: true, now: ringClock) { eagerTaps.append(eager.isActivated) }
        }
        func saw(_ expected: [CGFloat]) -> Bool { seen.count == expected.count && zip(seen, expected).allSatisfy { abs($0 - $1) < 1e-9 } }
        func settle(each: (() -> Void)? = nil) {
            let from = s.clock
            for k in 1...120 { s.clock = from + Double(k) / 120; ringClock += 1.0 / 120; s.pager.tick(); each?() }
        }
    }

    @Test func aSwipeOntoTheLastSpaceNeverFillsTheRing() {
        let r = Ring(selected: 1)
        r.s.gesture(.began, -2, at: 50)
        for k in 1...20 { r.s.gesture(.changed, -14.4, at: 50 + Double(k) * 0.01) }
        r.s.gesture(.ended, 0, at: 50.4)
        #expect(r.s.selections == [r.s.id(2)] && r.saw([-96]))
        r.settle()
        #expect(r.taps.isEmpty && r.eagerTaps.isEmpty && r.created == 0 && r.s.pager.offset == 0)
    }

    @Test func aFlicksSettleSwingPastTheEndStaysQuietWhenTheFingersNeverFilledTheRing() {
        let r = Ring(selected: 1)
        r.s.gesture(.began, -2, at: 52)
        for k in 1...20 { r.s.gesture(.changed, -21.6, at: 52 + Double(k) * 0.005) }
        r.s.gesture(.ended, 0, at: 52.1)
        #expect(r.s.selections == [r.s.id(2)] && r.saw([-24]))
        var furthest: CGFloat = 0
        r.settle { furthest = max(furthest, G.overscroll(selected: 2, offset: r.s.pager.offset, width: 240, count: 3)) }
        #expect(furthest >= G.progressDistance && r.eagerTaps == [true, false])
        #expect(r.taps.isEmpty && !r.ring.isActivated && r.created == 0 && r.s.pager.offset == 0)
    }

    @Test func aRealPullPastTheLastSpaceTapsCreatesAndTapsAgainAsItEmpties() {
        let r = Ring(selected: 2)
        r.s.gesture(.began, -2, at: 54)
        for k in 1...6 { r.s.gesture(.changed, -15, at: 54 + Double(k) * 0.01) }
        #expect(r.taps == [true] && r.ring.isActivated)
        r.ringClock += 0.2
        r.s.gesture(.ended, 0, at: 54.3)
        #expect(r.created == 1 && r.s.selections.isEmpty)
        r.settle()
        #expect(r.taps == [true, false] && r.taps == r.eagerTaps)
    }

    @Test func aPullFromTheSpaceBeforeTheLastSelectsItAndCreatesWithoutAStrayHaptic() {
        let r = Ring(selected: 1)
        r.s.gesture(.began, -2, at: 56)
        for k in 1...36 { r.s.gesture(.changed, -15, at: 56 + Double(k) * 0.01) }
        #expect(r.taps == [true])
        r.ringClock += 0.2
        r.s.gesture(.ended, 0, at: 56.6)
        #expect(r.s.selections == [r.s.id(2)] && r.saw([30]) && r.created == 1 && r.taps == [true])
        r.settle()
        #expect(r.taps == [true, false] && r.taps == r.eagerTaps)
    }

    @Test func aRefusedSelectionMeasuresFromTheSpaceItStaysOnSoTheArmedRingHolds() {
        let r = Ring(selected: 1, selects: false)
        r.s.gesture(.began, -2, at: 57)
        for k in 1...36 { r.s.gesture(.changed, -15, at: 57 + Double(k) * 0.01) }
        r.ringClock += 0.2
        r.s.gesture(.ended, 0, at: 57.6)
        #expect(r.s.selections == [r.s.id(2)] && r.saw([30]) && r.taps == [true] && r.ring.isActivated)
        #expect(r.created == 1 && abs(r.s.pager.offset + 270) < 1e-9)
    }

    @Test func aPageFlipHandsOverTheStripMeasuredFromTheNewSpace() {
        let r = Ring(selected: 1)
        #expect(r.s.pager.swipe(deltaX: -1) && r.saw([-240]) && r.taps.isEmpty)
    }
}
