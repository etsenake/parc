import AppKit
import Testing
@testable import Parc

struct PageSwitchHoldTests {
    final class Pane {}

    private static func same(_ panes: [Pane], _ expected: [Pane]) -> Bool {
        panes.count == expected.count && zip(panes, expected).allSatisfy { $0 === $1 }
    }

    private typealias Hold = PageSwitchHold<Pane>

    @Test func aTabSwitchParksNothingWhileTheIncomingPageHasNotDrawn() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        #expect(Self.same(hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0), []))
    }

    @Test func theOutgoingPaneIsHeldOverTheIncomingOne() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        #expect(Self.same(hold.held, [a]))
        #expect(Self.same(hold.waiting, [b]))
    }

    @Test func aReportFromAPageNobodyWaitsForEndsNothing() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        #expect(Self.same(hold.presented(a), []))
    }

    @Test func theIncomingFrameParksTheOutgoingPane() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        #expect(Self.same(hold.presented(b), [a]))
        #expect(!hold.isHolding)
    }

    @Test func aLateSecondReportEndsNothing() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        _ = hold.presented(b)
        #expect(Self.same(hold.presented(b), []))
    }

    @Test func theHoldEndsASecondAfterItBegan() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 10)
        #expect(hold.deadline == 10 + Hold.cap)
    }

    @Test func aPaneThatArrivedUnderTheHoldWasNeverSeenAndParksAtOnce() {
        let a = Pane(), b = Pane(), c = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 10)
        #expect(Self.same(hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true, now: 10.3), [b]))
    }

    private static func rapid() -> (hold: Hold, a: Pane, e: Pane, first: Int) {
        let a = Pane(), b = Pane(), c = Pane(), d = Pane(), e = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 10)
        let first = hold.hold
        _ = hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true, now: 10.3)
        _ = hold.rearrange(leaving: [c], arriving: [d], drawing: [d], canHold: true, now: 10.6)
        _ = hold.rearrange(leaving: [d], arriving: [e], drawing: [e], canHold: true, now: 10.9)
        return (hold, a, e, first)
    }

    @Test func rapidSwitchesKeepTheSameHoldAndItsOriginalDeadline() {
        let r = Self.rapid()
        #expect(Self.same(r.hold.held, [r.a]))
        #expect(Self.same(r.hold.waiting, [r.e]))
        #expect(r.hold.hold == r.first)
        #expect(r.hold.deadline == 10 + Hold.cap)
    }

    @Test func theHoldLastsUntilItsDeadline() {
        var r = Self.rapid()
        #expect(Self.same(r.hold.expire(at: 10.99), []))
        #expect(r.hold.isHolding)
    }

    @Test func aHoldThatSurvivedRapidSwitchesEndsOneSecondAfterItBegan() {
        var r = Self.rapid()
        #expect(Self.same(r.hold.expire(at: 11), [r.a]))
        #expect(!r.hold.isHolding)
        #expect(r.hold.deadline == nil)
    }

    @Test func aSwitchAfterTheDeadlineEndsTheHoldBeforeItsTimerRuns() {
        let a = Pane(), b = Pane(), c = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        #expect(Self.same(hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true, now: 1.2), [a, b]))
        #expect(!hold.isHolding)
    }

    @Test func theNextSwitchBeginsANewHoldWithItsOwnDeadline() {
        let a = Pane(), b = Pane(), c = Pane(), d = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        _ = hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true, now: 1.2)
        #expect(Self.same(hold.rearrange(leaving: [c], arriving: [d], drawing: [d], canHold: true, now: 1.3), []))
        #expect(hold.hold == 2)
        #expect(hold.deadline == 1.3 + Hold.cap)
    }

    @Test func switchingStraightBackShowsTheHeldPageWhichNeverLeftTheScreen() {
        let a = Pane(), b = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        #expect(Self.same(hold.rearrange(leaving: [b], arriving: [a], drawing: [a], canHold: true, now: 0.1), [b]))
        #expect(!hold.isHolding)
    }

    @Test func switchingToContentThatReportsNoFrameIsImmediate() {
        let a = Pane(), note = Pane()
        var hold = Hold()
        #expect(Self.same(hold.rearrange(leaving: [a], arriving: [note], drawing: [], canHold: true, now: 0), [a]))
        #expect(!hold.isHolding)
    }

    @Test func addingASplitPaneHoldsNothingBecauseNothingLeftTheScreen() {
        let b = Pane()
        var hold = Hold()
        #expect(Self.same(hold.rearrange(leaving: [], arriving: [b], drawing: [b], canHold: true, now: 0), []))
        #expect(!hold.isHolding)
    }

    @Test func aWindowThatCannotHoldParksAtOnce() {
        let a = Pane(), c = Pane()
        var hold = Hold()
        #expect(Self.same(hold.rearrange(leaving: [a], arriving: [c], drawing: [c], canHold: false, now: 0), [a]))
        #expect(!hold.isHolding)
    }

    private static func split() -> (hold: Hold, a: Pane, b: Pane, c: Pane, d: Pane) {
        let a = Pane(), b = Pane(), c = Pane(), d = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a, b], arriving: [c, d], drawing: [c, d], canHold: true, now: 0)
        return (hold, a, b, c, d)
    }

    @Test func aSplitSwitchWaitsForEveryIncomingPage() {
        var s = Self.split()
        #expect(Self.same(s.hold.presented(s.c), []))
        #expect(s.hold.isHolding)
    }

    @Test func anIncomingPageThatDrewUnderTheHoldStillParksAtOnceWhenItLeaves() {
        var s = Self.split()
        _ = s.hold.presented(s.c)
        #expect(Self.same(s.hold.rearrange(leaving: [s.c], arriving: [], drawing: [], canHold: true, now: 0.1), [s.c]))
        #expect(s.hold.isHolding)
    }

    @Test func theLastIncomingFrameParksEveryHeldPane() {
        var s = Self.split()
        _ = s.hold.presented(s.c)
        _ = s.hold.rearrange(leaving: [s.c], arriving: [], drawing: [], canHold: true, now: 0.1)
        #expect(Self.same(s.hold.presented(s.d), [s.a, s.b]))
        #expect(!s.hold.isHolding)
    }

    @Test func leavingForContentWithNoFrameEndsTheHoldAndParksEverythingThatLeft() {
        let a = Pane(), b = Pane(), note = Pane()
        var hold = Hold()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        #expect(Self.same(hold.rearrange(leaving: [b], arriving: [note], drawing: [], canHold: true, now: 0.1), [a, b]))
        #expect(!hold.isHolding)
    }

    @MainActor private static func area() -> (NSView, NSView) {
        let area = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        area.autoresizesSubviews = false
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        area.addSubview(page)
        return (area, page)
    }

    @MainActor @Test func aHeldPaneDrawsOnTopAndFollowsThePageAreasSize() {
        let (_, page) = Self.area()
        HeldPaneLayout.apply(true, to: page)
        #expect(page.autoresizingMask == HeldPaneLayout.followsPageArea)
        #expect(page.layer?.zPosition == 1)
    }

    @MainActor @Test func oneSideOfAHeldSplitGrowsByItsShareOfThePageArea() {
        let (area, page) = Self.area()
        HeldPaneLayout.apply(true, to: page)
        area.setFrameSize(NSSize(width: 1000, height: 700))
        page.resize(withOldSuperviewSize: NSSize(width: 800, height: 600))
        #expect(abs(page.frame.width - 500) < 1)
        #expect(abs(page.frame.height - 700) < 1)
        #expect(abs(page.frame.minX) < 1)
    }

    @MainActor @Test func releasingAHeldPaneClearsItsResizingAndStacking() {
        let (_, page) = Self.area()
        HeldPaneLayout.apply(true, to: page)
        HeldPaneLayout.apply(false, to: page)
        #expect(page.autoresizingMask == [])
        #expect(page.layer?.zPosition == 0)
    }
}
