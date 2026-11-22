import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class FadeHarness {
    var time: TimeInterval = 100
    var pending: [(at: TimeInterval, body: @MainActor () -> Void)] = []
    var hops: [() -> Void] = []
    var requests = 0, restored = 0
    var input: [Bool] = []
    let page = NSView(), start = NSView()
    let fade: TabCloseFade

    init(reducesMotion: Bool = false) {
        fade = TabCloseFade(tabID: UUID(), page: page, startPage: start)
        fade.now = { [unowned self] in self.time }
        fade.reducesMotion = { reducesMotion }
        fade.schedule = { [unowned self] delay, body in self.pending.append((self.time + delay, body)) }
        fade.hop = { [unowned self] work in self.hops.append(work) }
        fade.onRequestClose = { [unowned self] in self.requests += 1 }
        fade.onRestored = { [unowned self] in self.restored += 1 }
        fade.passesInput = { [unowned self] in self.input.append($0) }
    }

    func advance(_ seconds: TimeInterval) {
        time += seconds
        let due = pending.filter { $0.at <= time }
        pending.removeAll { $0.at <= time }
        for item in due { item.body() }
        fade.paint()
    }

    func runHops() {
        let work = hops
        hops = []
        for item in work { item() }
    }

    var locked: Bool { abs(page.alphaValue + start.alphaValue - 1) < 1e-6 }
}

@MainActor struct TabCloseFadeTests {
    private let duration = PeekDismissalTiming.fade

    @Test func theFadeStartsFromThePageWithTheStartPageUnseen() {
        let h = FadeHarness()
        h.fade.begin()
        #expect(h.page.alphaValue == 1 && h.start.alphaValue == 0)
    }

    @Test func theClosingPageStopsTakingInputAsTheFadeStarts() {
        let h = FadeHarness()
        h.fade.begin()
        #expect(h.input == [true])
    }

    @Test func theRealCloseWaitsForThePeekCloseFade() {
        let h = FadeHarness()
        h.fade.begin()
        #expect(h.pending.count == 1 && abs(h.pending[0].at - h.time - duration) < 1e-9 && h.requests == 0)
    }

    @Test(arguments: [0.05, 0.1, 0.15])
    func thePageFollowsThePeekFadesQuadOutCurveWhileTheStartPageFadesInExactlyAsItGoesOut(elapsed: TimeInterval) {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(elapsed)
        let u = (h.time - 100) / duration
        #expect(abs(h.page.alphaValue - CGFloat((1 - u) * (1 - u))) <= 0.001)
        #expect(h.locked)
    }

    @Test func theFadesOverlapMidWay() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.15)
        #expect(h.start.alphaValue > 0.4 && h.start.alphaValue < 1 && h.page.alphaValue > 0)
    }

    @Test func theCloseStartsOnceThePageIsInvisible() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.21)
        #expect(h.requests == 1 && h.fade.phase == .closing)
        #expect(h.page.alphaValue == 0 && h.start.alphaValue == 1)
    }

    @Test func aSecondCloseRequestDuringTheFadeChangesNothing() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.21)
        h.fade.begin()
        #expect(h.pending.isEmpty && h.requests == 1)
    }

    @Test func leaveSiteBringsThePageBackUnderTheQuestion() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.21)
        h.fade.sheetBegan()
        h.advance(0.1)
        #expect(h.page.alphaValue > 0.5 && h.locked && h.requests == 1)
        h.advance(0.11)
        #expect(h.page.alphaValue == 1 && h.start.alphaValue == 0)
    }

    @Test func afterLeaveThePageGoesAtOnceAndInputIsHandedBackWithoutARestore() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.21)
        h.fade.sheetBegan()
        h.advance(0.21)
        h.fade.finish()
        #expect(h.page.alphaValue == 0 && h.start.alphaValue == 1)
        #expect(h.input.last == false && h.restored == 0)
    }

    @Test func aRefusedPageTakesInputAgainStraightAway() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(duration + 0.01)
        h.fade.refused()
        #expect(h.input.last == false)
    }

    @Test func aRefusedCloseFadesThePageBackOverTheStartPage() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(duration + 0.01)
        h.fade.refused()
        h.advance(0.1)
        #expect(h.locked && h.page.alphaValue > 0 && h.page.alphaValue < 1 && h.restored == 0)
    }

    @Test func onceARefusedPageIsFullyBackTheStartPageUnderneathCanGo() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(duration + 0.01)
        h.fade.refused()
        h.advance(0.21)
        h.fade.settled()
        #expect(h.page.alphaValue == 1 && h.start.alphaValue == 0 && h.restored == 1)
    }

    @Test func switchingAwayMidFadeHidesThePageAtOnce() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.08)
        h.fade.interrupt()
        #expect(h.page.alphaValue == 0 && h.start.alphaValue == 1)
    }

    @Test func anInterruptedCloseIsRequestedAfterTheCurrentRenderExactlyOnce() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.08)
        h.fade.interrupt()
        #expect(h.requests == 0 && h.hops.count == 1)
        h.runHops()
        h.advance(duration)
        #expect(h.requests == 1)
    }

    @Test func aStartPageTakingOverDuringTheCloseHandsOverFinishedWithoutASecondClose() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(duration + 0.01)
        h.fade.handOff()
        #expect(h.fade.phase == .finished && h.page.alphaValue == 0 && h.start.alphaValue == 1 && h.requests == 1)
    }

    @Test func aStartPageTakingOverMidFadeIsShownInFullAtOnceAndStillClosesTheTabOnce() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(0.08)
        h.fade.handOff()
        #expect(h.fade.phase == .finished && h.page.alphaValue == 0 && h.start.alphaValue == 1)
        h.runHops()
        #expect(h.requests == 1)
    }

    @Test func reduceMotionKeepsTheOpacityOnlyFade() {
        let h = FadeHarness(reducesMotion: true)
        h.fade.begin()
        #expect(abs(h.pending[0].at - h.time - duration) < 1e-9)
    }

    @Test func reduceMotionStillCrossfadesInPlace() {
        let h = FadeHarness(reducesMotion: true)
        h.fade.begin()
        h.advance(0.1)
        #expect(h.locked && h.page.alphaValue > 0 && h.page.alphaValue < 1)
    }

    @Test func withReduceMotionARefusedPageReturnsInThePeeksQuickerFade() {
        let h = FadeHarness(reducesMotion: true)
        h.fade.begin()
        h.advance(duration)
        h.fade.refused()
        h.advance(PeekDismissalTiming.reduced + 0.01)
        #expect(h.page.alphaValue == 1)
    }

    @Test func endingAFadeWhileThePageReturnsSnapsItFullyBack() {
        let h = FadeHarness()
        h.fade.begin()
        h.advance(duration + 0.01)
        h.fade.refused()
        h.advance(0.05)
        h.fade.end()
        #expect(h.page.alphaValue == 1 && h.start.alphaValue == 0 && h.input.last == false)
    }
}
