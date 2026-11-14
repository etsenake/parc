enum HistorySwipeTargets {
    static func pages<Page: AnyObject>(peek: Page?, peekShown: Bool, panes: [Page]) -> [Page] {
        guard let peek else { return panes }
        return peekShown ? [peek] : []
    }
}
