import Foundation
import Testing
@testable import ParcCore

struct TabPeekSplitAdmissionTests {
    private static func refusal(_ edit: (inout TabPeekSplitFacts) -> Void) -> TabPeekSplitRefusal? {
        var facts = TabPeekSplitFacts()
        edit(&facts)
        return TabPeekSplit.refusal(facts)
    }

    @Test func aTabBackedPeekOverASinglePageOffersSplitView() {
        #expect(Self.refusal { _ in } == nil)
    }

    @Test func aPeekOverAThreePageSplitStillOffersSplitView() {
        #expect(Self.refusal { $0.panes = 3 } == nil)
    }

    @Test func fourPagesIsAsFullAsSplitViewGets() {
        #expect(Self.refusal { $0.panes = 4 } == .full)
    }

    @Test func aFullSplitSaysSoEvenWhileTheWindowIsBusy() {
        #expect(Self.refusal { $0.panes = 4; $0.windowReady = false } == .full)
    }

    @Test func aPeekThatIsNotTheWindowsLivePeekCannotSplit() {
        #expect(Self.refusal { $0.peekInteractive = false } == .unavailable)
    }

    @Test func aTabThatIsClosingMovingOrGoneCannotJoinTheSplit() {
        #expect(Self.refusal { $0.tabUsable = false } == .unavailable)
    }

    @Test func thePageUnderneathMustBeOnScreenToSplitWith() {
        #expect(Self.refusal { $0.parentSelected = false } == .unavailable)
    }

    @Test func aPopupFullScreenPageOrOpenLibraryRefuses() {
        #expect(Self.refusal { $0.windowReady = false } == .unavailable)
    }

    @Test func aPeekThatCannotActIsUnavailableBeforeItIsFull() {
        #expect(Self.refusal { $0.peekInteractive = false; $0.panes = 4 } == .unavailable)
    }

    @Test func theFullTooltipSaysWhy() {
        #expect(TabPeekSplitRefusal.full.toolTip.contains("four pages"))
    }

    @Test func eachRefusalHasItsOwnTooltip() {
        #expect(!TabPeekSplitRefusal.unavailable.toolTip.isEmpty)
        #expect(TabPeekSplitRefusal.unavailable.toolTip != TabPeekSplitRefusal.full.toolTip)
    }
}
