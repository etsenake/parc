package enum HistorySwipeTargets {
    package struct Pane<Page: AnyObject> {
        package var easelPage: Page?
        package var page: Page?
        package var isInternal: Bool
        package var isHidden: Bool
        package init(easelPage: Page? = nil, page: Page? = nil, isInternal: Bool, isHidden: Bool) {
            self.easelPage = easelPage
            self.page = page
            self.isInternal = isInternal
            self.isHidden = isHidden
        }
    }

    static func page<Page>(of pane: Pane<Page>) -> Page? {
        if let easelPage = pane.easelPage { return easelPage }
        guard !pane.isInternal, !pane.isHidden else { return nil }
        return pane.page
    }

    package struct ScrollRoom {
        package var content: Double
        package var visible: Double
        package init(content: Double, visible: Double) {
            self.content = content
            self.visible = visible
        }
    }

    package static func scrollsHorizontally(_ ancestors: [ScrollRoom]) -> Bool {
        ancestors.contains { $0.content > $0.visible + 0.5 }
    }

    package static func pages<Page: AnyObject>(peek: Page?, peekShown: Bool, panes: [Pane<Page>]) -> [Page] {
        guard let peek else { return panes.compactMap(page(of:)) }
        return peekShown ? [peek] : []
    }
}
