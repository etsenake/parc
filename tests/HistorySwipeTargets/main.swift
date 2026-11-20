final class Page {}

typealias Pane = HistorySwipeTargets.Pane<Page>

let selected = Page(), other = Page(), peek = Page(), easel = Page(), hidden = Page(), internalPage = Page()
var checks = 0
func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
func same(_ actual: [Page], _ expected: [Page]) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy { $0 === $1 }
}
func web(_ page: Page?, isInternal: Bool = false, isHidden: Bool = false) -> Pane {
    Pane(easelPage: nil, page: page, isInternal: isInternal, isHidden: isHidden)
}

let split = [web(selected), web(other)]
expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: split), [selected, other]),
       "every visible split pane can swipe, not only the selected one")
expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [web(selected), web(hidden, isHidden: true)]),
            [selected]), "a hidden pane never swipes")
expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [web(internalPage, isInternal: true), web(other)]),
            [other]), "an internal page never swipes")
expect(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [web(nil), web(nil, isInternal: true, isHidden: true)]).isEmpty,
       "a pane without a live page has nothing to swipe")
let easelPane = Pane(easelPage: easel, page: nil, isInternal: true, isHidden: true)
expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [easelPane, web(other)]), [easel, other]),
       "an Easel pane swipes its selected page")
expect(same(HistorySwipeTargets.pages(peek: peek, peekShown: true, panes: split), [peek]),
       "an open Peek covers every pane, so only the Peek can swipe")
expect(HistorySwipeTargets.pages(peek: peek, peekShown: false, panes: split).isEmpty,
       "a Peek that is not shown yet still covers the panes")
expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: true, panes: [web(other)]), [other]),
       "without a Peek the shown flag changes nothing")
expect(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Pane]()).isEmpty,
       "no visible page leaves nothing to swipe")
typealias Room = HistorySwipeTargets.ScrollRoom
expect(!HistorySwipeTargets.scrollsHorizontally([]), "a note with no scroll views lets a sideways swipe through")
expect(!HistorySwipeTargets.scrollsHorizontally([Room(content: 640, visible: 640), Room(content: 640, visible: 700)]),
       "a note that fits its width never eats a history swipe")
expect(HistorySwipeTargets.scrollsHorizontally([Room(content: 1200, visible: 600), Room(content: 600, visible: 600)]),
       "a wide table or code block keeps the sideways scroll for itself")
expect(!HistorySwipeTargets.scrollsHorizontally([Room(content: 600.4, visible: 600)]),
       "sub-point rounding doesn't count as room to scroll")
precondition(checks == 13)
