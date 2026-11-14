enum HistorySwipeTargets {
    struct Pane<Page: AnyObject> {
        var easelPage: Page?
        var page: Page?
        var isInternal: Bool
        var isHidden: Bool
    }

    static func page<Page>(of pane: Pane<Page>) -> Page? {
        if let easelPage = pane.easelPage { return easelPage }
        guard !pane.isInternal, !pane.isHidden else { return nil }
        return pane.page
    }

    static func pages<Page: AnyObject>(peek: Page?, peekShown: Bool, panes: [Pane<Page>]) -> [Page] {
        guard let peek else { return panes.compactMap(page(of:)) }
        return peekShown ? [peek] : []
    }
}
