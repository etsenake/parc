final class Page {}

let selected = Page(), other = Page(), peek = Page()
var checks = 0
func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
func same(_ actual: [Page], _ expected: [Page]) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy { $0 === $1 }
}

expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [selected, other]), [selected, other]),
       "every visible split pane can swipe, not only the selected one")
expect(same(HistorySwipeTargets.pages(peek: peek, peekShown: true, panes: [selected, other]), [peek]),
       "an open Peek covers every pane, so only the Peek can swipe")
expect(HistorySwipeTargets.pages(peek: peek, peekShown: false, panes: [selected, other]).isEmpty,
       "a Peek that is not shown yet still covers the panes")
expect(same(HistorySwipeTargets.pages(peek: nil, peekShown: true, panes: [other]), [other]),
       "without a Peek the shown flag changes nothing")
expect(HistorySwipeTargets.pages(peek: nil, peekShown: false, panes: [Page]()).isEmpty,
       "no visible page leaves nothing to swipe")
precondition(checks == 5)
