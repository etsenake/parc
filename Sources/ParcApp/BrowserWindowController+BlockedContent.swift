import AppKit

extension BrowserWindowController {
    func setupBlockedContent() {
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name(PCNativePageBlockedContentDidChangeNotification), object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let page = notification.object as? PCNativePage else { return }
                self.blockedContentDidChange(page)
            }
        })
    }

    func blockedContent(for page: PCNativePage?) -> BlockedPageContent? {
        guard let page, !page.isClosed,
              page.responds(to: #selector(getter: PCNativePage.blockedContent)) else { return nil }
        return BlockedPageContent(snapshot: page.blockedContent)
    }

    private func blockedContentDidChange(_ page: PCNativePage) {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !page.isClosed,
              peeks[page.identifier] != nil || browsers.values.contains(where: { $0.nativePage === page }) else { return }
        refreshBlockedContent()
        for (id, pane) in panes where selectedTabIDs.contains(id) && pane.browser?.nativePage === page {
            pane.browserToolbar.updateBlockedContent(blockedContent(for: page))
            if let toolbar = pane.loadedDeveloperToolbar, !toolbar.isHidden { toolbar.updateBlockedContent(blockedContent(for: page)) }
        }
        if let peek = peeks[page.identifier] {
            peek.view.browserToolbar.updateBlockedContent(blockedContent(for: page))
            if !peek.view.developerToolbar.isHidden { peek.view.developerToolbar.updateBlockedContent(blockedContent(for: page)) }
        }
        announceBlockedContent(page)
    }

    func refreshBlockedContent() {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return }
        let live = Set(browsers.values.compactMap { $0.nativePage?.identifier }).union(peeks.keys)
        blockedContentAnnouncements = blockedContentAnnouncements.filter { live.contains($0.key) }
        let current = blockedContent(for: currentBrowser?.nativePage)
        if isPopupWindow { popupChrome.updateBlockedContent(current) } else { sidebar.updateBlockedContent(current) }
        if let controller = siteControlCenter, let page = extensionControlsPage {
            controller.model.updateBlocked(blockedContent(for: page))
        }
    }

    private func announceBlockedContent(_ page: PCNativePage) {
        guard let window, window.isKeyWindow, currentBrowser?.nativePage === page,
              let content = blockedContent(for: page),
              blockedContentAnnouncements[page.identifier] != content.revision else { return }
        blockedContentAnnouncements[page.identifier] = content.revision
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: content.summary,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    func wireBlockedContent(_ controller: SiteControlCenterController, page: PCNativePage,
                            current: @escaping () -> Bool, afterDismissal: @escaping () -> Bool) {
        let model = controller.model
        model.onBlockedOpen = { [weak self, weak controller, weak page] item in
            guard current(), let self, let controller, self.siteControlCenter === controller,
                  let revision = controller.model.blocked?.revision else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { [weak page] in
                guard let page, !page.isClosed,
                      page.responds(to: #selector(PCNativePage.openBlockedContentItem(kind:identifier:revision:))) else { return }
                _ = page.openBlockedContentItem(kind: item.kind.rawValue, identifier: item.identifier, revision: revision)
            }
        }
        model.onBlockedOpenAll = { [weak self, weak controller, weak page] in
            guard current(), let self, let controller, self.siteControlCenter === controller,
                  let revision = controller.model.blocked?.revision else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { [weak page] in
                guard let page, !page.isClosed,
                      page.responds(to: #selector(PCNativePage.openAllBlockedPopups(revision:))) else { return }
                _ = page.openAllBlockedPopups(revision: revision)
            }
        }
        model.onBlockedAllow = { [weak self, weak controller, weak page] in
            guard current(), let self, let controller, let page, self.siteControlCenter === controller,
                  let revision = controller.model.blocked?.revision,
                  page.responds(to: #selector(PCNativePage.allowBlockedPopups(revision:))) else { return }
            if page.allowBlockedPopups(revision: revision) { self.refreshBlockedContent() }
        }
        model.onBlockedSettings = { [weak self, weak controller] in
            guard current(), let self, let controller, self.siteControlCenter === controller else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { [weak self] in
                guard let self, let url = URL(string: "parc://settings/content/popups") else { return }
                self.openAddress(url)
            }
        }
    }
}
