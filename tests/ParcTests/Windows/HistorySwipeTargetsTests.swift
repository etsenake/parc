import Testing
@testable import Parc
@testable import ParcKit

struct HistorySwipeTargetsTests {
    final class Page {}

    private typealias Pane = HistorySwipeTargets.Pane<Page>
    private typealias Room = HistorySwipeTargets.ScrollRoom

    private static func same(_ actual: [Page], _ expected: [Page]) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy { $0 === $1 }
    }

    private static func web(_ page: Page?, isInternal: Bool = false, isHidden: Bool = false) -> Pane {
        Pane(easelPage: nil, page: page, isInternal: isInternal, isHidden: isHidden)
    }

    @Test func everyVisibleSplitPaneCanSwipeNotOnlyTheSelectedOne() {
        let selected = Page(), other = Page()
        #expect(Self.same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Self.web(selected), Self.web(other)]), [selected, other]))
    }

    @Test func aHiddenPaneNeverSwipes() {
        let selected = Page(), hidden = Page()
        #expect(Self.same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Self.web(selected), Self.web(hidden, isHidden: true)]), [selected]))
    }

    @Test func anInternalPageNeverSwipes() {
        let internalPage = Page(), other = Page()
        #expect(Self.same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Self.web(internalPage, isInternal: true), Self.web(other)]), [other]))
    }

    @Test func aPaneWithoutALivePageHasNothingToSwipe() {
        #expect(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Self.web(nil), Self.web(nil, isInternal: true, isHidden: true)]).isEmpty)
    }

    @Test func anEaselPaneSwipesItsSelectedPage() {
        let easel = Page(), other = Page()
        let easelPane = Pane(easelPage: easel, page: nil, isInternal: true, isHidden: true)
        #expect(Self.same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [easelPane, Self.web(other)]), [easel, other]))
    }

    @Test func anOpenPeekCoversEveryPaneSoOnlyThePeekCanSwipe() {
        let peek = Page()
        #expect(Self.same(HistorySwipeTargets.pages(peek: peek, peekShown: true, panes: [Self.web(Page()), Self.web(Page())]), [peek]))
    }

    @Test func aPeekThatIsNotShownYetStillCoversThePanes() {
        #expect(HistorySwipeTargets.pages(peek: Page(), peekShown: false, panes: [Self.web(Page()), Self.web(Page())]).isEmpty)
    }

    @Test func withoutAPeekTheShownFlagChangesNothing() {
        let other = Page()
        #expect(Self.same(HistorySwipeTargets.pages(peek: nil, peekShown: true, panes: [Self.web(other)]), [other]))
    }

    @Test func noVisiblePageLeavesNothingToSwipe() {
        #expect(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Pane]()).isEmpty)
    }

    @Test func aNoteWithNoScrollViewsLetsASidewaysSwipeThrough() {
        #expect(!HistorySwipeTargets.scrollsHorizontally([]))
    }

    @Test func aNoteThatFitsItsWidthNeverEatsAHistorySwipe() {
        #expect(!HistorySwipeTargets.scrollsHorizontally([Room(content: 640, visible: 640), Room(content: 640, visible: 700)]))
    }

    @Test func aWideTableOrCodeBlockKeepsTheSidewaysScrollForItself() {
        #expect(HistorySwipeTargets.scrollsHorizontally([Room(content: 1200, visible: 600), Room(content: 600, visible: 600)]))
    }

    @Test func subPointRoundingDoesNotCountAsRoomToScroll() {
        #expect(!HistorySwipeTargets.scrollsHorizontally([Room(content: 600.4, visible: 600)]))
    }
}
