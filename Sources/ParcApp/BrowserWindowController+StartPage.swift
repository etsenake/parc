import AppKit
import Combine

extension BrowserWindowController {
    func loadStartPage() -> StartPageView {
        let page = StartPageView()
        page.coordinateSpace = rootView; page.incognito = rootView.incognito
        page.barRestHeight = CommandBar.residentRestHeight
        page.theme = rootView.theme; page.pagingTransition = rootView.pagingTransition
        page.showsWindowButtons = sidebar.showsWindowButtons
        page.onToggleSidebar = { [weak self] in self?.toggleSidebar() }
        loadedStartPage = page
        return page
    }
    func scheduleStartPageRefresh() {
        guard !startPageRefreshScheduled else { return }
        startPageRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startPageRefreshScheduled = false
            if !self.rendering { self.refreshStartPage() }
        }
    }
    func refreshStartPageChrome() {
        guard let page = loadedStartPage else { return }
        let chrome = sidebarPresentation != .locked && nativeFullscreenTabID == nil
        if page.showsWindowChrome != chrome { page.showsWindowChrome = chrome }
        page.sidebarToolbarWidth = sidebarLayoutWidth
        page.sidebarShowsNavigation = !sidebar.usesContentToolbar && !sidebar.navigationInContentToolbar
    }
    func refreshStartPage() {
        guard showsStartPage, let window else {
            startPagePresented = false
            guard !startPageDeparting else { return }
            residentCommandOwner = nil
            if let bar = residentCommandBar { residentCommandBar = nil; bar.dismiss(restoreFocus: false) }
            return
        }
        refreshStartPageChrome()
        let owner = (spaceID: activeSpaceID, profileID: activeProfileID)
        if let bar = residentCommandBar, residentCommandOwner.map({ $0 != owner }) ?? true {
            residentCommandBar = nil; residentCommandOwner = nil; bar.dismiss(restoreFocus: false)
        }
        var rebuilt = false
        if residentCommandBar == nil, canOwnDownloadDialog(for: owner.profileID) {
            let panel = makeCommandBar(in: window, newTab: true, inSidebar: false, addressAnchor: nil, initialEdit: nil, resident: true)
            residentCommandBar = panel; residentCommandOwner = owner; rebuilt = true
            panel.restorePageFocus = { [weak self, weak panel] in
                DispatchQueue.main.async {
                    guard let self, let panel, self.residentCommandBar === panel, self.showsStartPage,
                          let window = self.window, window.isKeyWindow, window.attachedSheet == nil, self.commandBar == nil,
                          ContentFocusRequest.holdsContentFocus(window.firstResponder, window: window, content: self.startPage) else { return }
                    panel.focusResident()
                }
            }
            panel.presentResident(in: startPage.commandBarSlot)
            residentCommandInputs = nil
            refreshResidentTopDomains(panel)
        }
        let arrived = !startPagePresented
        startPagePresented = true
        if arrived { playStartPageArrival() }
        guard arrived || rebuilt else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, self.showsStartPage, window.isKeyWindow,
                  window.attachedSheet == nil, self.commandBar == nil, self.libraryView == nil, self.spaceCreation == nil,
                  ContentFocusRequest.holdsContentFocus(window.firstResponder, window: window, content: self.startPage) else { return }
            self.residentCommandBar?.focusResident()
        }
    }
    func playStartPageDeparture() {
        let frame = startPage.convert(startPage.bounds, to: pageHost)
        guard window?.isVisible == true, window?.isMiniaturized != true, presentation.isReady, !isClosing else {
            startPage.removeFromSuperview(); return
        }
        pageHost.addSubview(startPage, positioned: .above, relativeTo: nil)
        startPage.frame = frame
        startPageDeparting = true
        startPage.isDeparting = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            startPage.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.startPageDeparting = false
                guard self.startPage.superview !== self.splitView else { return }
                self.startPage.isDeparting = false
                self.startPage.removeFromSuperview()
                self.startPage.alphaValue = 1
                self.refreshStartPage()
            }
        })
    }
    private func playStartPageArrival() {
        startPage.isDeparting = false
        let faded = takeCloseFadeArrival()
        let shown = window?.isVisible == true && window?.isMiniaturized != true && presentation.isReady
        if faded {
            startPage.alphaValue = 1
            guard shown else { return }
            let slot = startPage.commandBarSlot
            slot.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                slot.animator().alphaValue = 1
            }
            return
        }
        guard shown else { return }
        startPage.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            startPage.animator().alphaValue = 1
        }
    }
}
