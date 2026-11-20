import AppKit

@MainActor
final class CoveredPage {
    let browser: PCBrowserView
    let profileID: UUID
    var requestedURL: String?
    var closing = false
    init(browser: PCBrowserView, profileID: UUID, requestedURL: String?) {
        self.browser = browser; self.profileID = profileID; self.requestedURL = requestedURL
    }
}

extension BrowserWindowController {
    func reconcileCoveredPages(_ state: BrowserState) {
        for (id, browser) in Array(browsers) where !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) {
            guard let tab = state.tab(id, where: { $0.archivedAt == nil }), tab.profileID == browserProfiles[id],
                  tab.showsNoteOverPage, InternalPage.isInternal(tab.url), peekPages(forTabID: id).isEmpty,
                  nativeFullscreenTabID != id, let page = browser.nativePage, !page.isClosed else { continue }
            browsers.removeValue(forKey: id)
            coveredPages[id] = CoveredPage(browser: browser, profileID: tab.profileID,
                                           requestedURL: requestedURLs.removeValue(forKey: id))
            browserProfiles.removeValue(forKey: id); liveTabModels.removeValue(forKey: id); loadingTabs.remove(id)
            if pendingNativeSelection?.tabID == id { pendingNativeSelection = nil }
            browser.isHidden = true
            scheduleTabHistoryCapture(id)
        }
        for (id, covered) in Array(coveredPages) where !covered.closing
            && !transferringTabIDs.contains(id) && !closingTabIDs.contains(id) {
            guard covered.browser.nativePage?.isClosed == false else { releaseCoveredPage(id); continue }
            guard let tab = state.tab(id, where: { $0.archivedAt == nil }), tab.profileID == covered.profileID,
                  ownership.canUse(id, owner: presentationID) else { retireCoveredPage(id); continue }
            if InternalPage.isInternal(tab.url) {
                if !tab.showsNoteOverPage { retireCoveredPage(id) }
            } else if browsers[id] == nil {
                coveredPages.removeValue(forKey: id)
                browsers[id] = covered.browser
                browserProfiles[id] = covered.profileID
                liveTabModels[id] = tab
                requestedURLs[id] = covered.requestedURL ?? tab.url
                if covered.browser.nativePage?.loading == true { loadingTabs.insert(id) }
                if let pane = panes[id], pane.browser !== covered.browser { pane.browser = covered.browser }
            } else {
                retireCoveredPage(id)
            }
        }
    }

    func coveredTabID(for browser: PCBrowserView) -> UUID? {
        coveredPages.first { $0.value.browser === browser }?.key
    }

    func retireCoveredPage(_ id: UUID) {
        guard let covered = coveredPages[id], !covered.closing else { return }
        covered.closing = true
        let history = covered.browser.nativePage.flatMap { page in
            page.responds(to: #selector(PCNativePage.captureNavigationState)) ? page.captureNavigationState() : nil
        }
        covered.browser.requestClose { [weak self] result in
            guard let self, self.coveredPages[id] === covered else { return }
            covered.closing = false
            guard result == .closed else { return }
            if let history, self.store.state.tab(id, where: { $0.archivedAt == nil })?.showsNoteOverPage == true {
                self.store.closedPageHistory.closed(id, state: history)
                self.store.closedPageHistory.restore([id])
            }
            self.releaseCoveredPage(id)
        }
    }

    func releaseCoveredPage(_ id: UUID) {
        guard let covered = coveredPages.removeValue(forKey: id) else { return }
        if let page = covered.browser.nativePage { attachedPageIDs.remove(page.identifier) }
        covered.browser.delegate = nil
        if panes[id]?.browser === covered.browser { panes[id]?.browser = nil } else { covered.browser.removeFromSuperview() }
    }

    func followCoveredPage(_ view: PCBrowserView, title: String? = nil, url: URL? = nil) -> Bool {
        guard let id = coveredTabID(for: view) else { return false }
        if let url { coveredPages[id]?.requestedURL = url.absoluteString }
        store.updatePageUnderNote(id, title: title, url: url?.absoluteString)
        if url != nil { scheduleTabHistoryCapture(id) }
        return true
    }

    func noteVisitTarget(_ action: PCNativeNavigationAction) -> UUID? {
        guard action == .back || action == .forward, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, activePeek == nil, libraryView == nil, window?.attachedSheet == nil,
              let id = currentTabID, !transferringTabIDs.contains(id), !closingTabIDs.contains(id),
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }), tab.profileID == activeProfileID else { return nil }
        if action == .back { return tab.showsNoteOverPage && renderedPaneIDs.contains(id) ? id : nil }
        guard tab.hasNoteAhead, let page = navigationPage, browsers[id]?.nativePage === page else { return nil }
        return id
    }

    var navigationCanShowBack: Bool {
        noteVisitTarget(.back) != nil || (navigationPage?.canShowBackHistory ?? false)
    }
    var navigationCanShowForward: Bool {
        noteVisitTarget(.forward) != nil || (navigationPage?.canShowForwardHistory ?? false)
    }

    @discardableResult
    func stepNoteVisit(_ id: UUID, forward: Bool) -> Bool {
        if !forward, let note = noteEditors[id], !note.editor.prepareToClose() { return false }
        navigationHistory?.dismiss()
        var stepped = false
        performWindowCommand { stepped = store.stepNoteVisit(id, forward: forward) }
        if stepped { focusSelectedLocalContent() }
        return stepped
    }

    func noteVisitInteraction(_ kind: NavigationControlKind) -> NavigationControlInteraction? {
        guard kind != .reload else { return nil }
        let action: PCNativeNavigationAction = kind == .back ? .back : .forward
        guard let id = noteVisitTarget(action) else { return nil }
        return NavigationControlInteraction(activate: { [weak self] alternate in
            guard let self, self.noteVisitTarget(action) == id else { return }
            self.chooseNoteVisitStep(id, forward: action == .forward, alternate: alternate)
        }, showHistory: { [weak self] anchor in
            self?.showNoteVisitHistory(id, forward: action == .forward, from: anchor)
        })
    }

    private func chooseNoteVisitStep(_ id: UUID, forward: Bool, alternate: Bool) {
        guard noteVisitTarget(forward ? .forward : .back) == id else { return }
        if alternate {
            _ = forward ? openNoteAheadInBackground(id) : openPageUnderNoteInBackground(id)
        } else {
            stepNoteVisit(id, forward: forward)
        }
    }

    private func showNoteVisitHistory(_ id: UUID, forward: Bool, from anchor: NSView) {
        let action: PCNativeNavigationAction = forward ? .forward : .back
        guard let window, noteVisitTarget(action) == id,
              let visit = store.state.tab(id, where: { $0.archivedAt == nil })?.noteVisit else { return }
        let page = forward ? navigationPage : coveredPages[id]?.browser.nativePage
        let snapshot = page?.navigationHistory(back: !forward)
        let leading: NavigationHistoryStepRow
        if forward {
            leading = NavigationHistoryStepRow(
                title: visit.note.title, icon: visit.noteFile.flatMap { NoteTabIconArt.shared.image(forNote: $0) },
                url: visit.noteFile) { [weak self] alternate in self?.chooseNoteVisitStep(id, forward: true, alternate: alternate) }
        } else {
            leading = NavigationHistoryStepRow(
                title: visit.page.title, icon: page?.favicon, url: URL(string: visit.page.url)) { [weak self] alternate in
                self?.chooseNoteVisitStep(id, forward: false, alternate: alternate)
            }
        }
        navigationHistory?.dismiss()
        sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        let history = NavigationHistoryController(page: page, snapshot: snapshot?.isValid == true ? snapshot : nil,
                                                  leading: leading, window: window, theme: windowPaletteTheme)
        history.stillSelected = { [weak self, weak page] in
            guard let self, self.noteVisitTarget(action) == id else { return false }
            return !forward || (page != nil && self.navigationPage === page)
        }
        if !forward {
            history.beforeEntry = { [weak self] alternate in
                guard let self else { return false }
                return alternate || self.stepNoteVisit(id, forward: false)
            }
        }
        history.onClose = { [weak self, weak history] in
            guard let self, self.navigationHistory === history else { return }
            self.navigationHistory = nil; self.refreshSidebarPointer()
        }
        navigationHistory = history
        history.show(from: anchor)
    }

    @discardableResult
    func openPageUnderNoteInBackground(_ id: UUID) -> Bool {
        guard let tab = store.state.tab(id, where: { $0.archivedAt == nil }), let visit = tab.noteVisit,
              visit.showsNote, let page = coveredPages[id]?.browser.nativePage, !page.isClosed else { return false }
        navigationHistory?.dismiss()
        let history = page.responds(to: #selector(PCNativePage.captureNavigationState)) ? page.captureNavigationState() : nil
        let creation = TabCreationProvenance(referrerID: id, activeTabID: currentTabID,
                                             profileID: tab.profileID, state: store.state)
        var opened: UUID?
        performWindowCommand(selectNativePage: false) {
            opened = store.adoptNativePage(url: URL(string: visit.page.url), title: visit.page.title,
                                           profilePath: page.profilePath, preferredSpaceID: tab.spaceID,
                                           select: false, creation: creation)
            guard let created = opened else { return }
            if let history {
                store.closedPageHistory.closed(created, state: history)
                store.closedPageHistory.restore([created])
            }
            presentation.recordCreation(created, state: store.state)
        }
        return opened != nil
    }

    @discardableResult
    func openNoteAheadInBackground(_ id: UUID) -> Bool {
        guard canCreateNote, let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              let visit = tab.noteVisit, !visit.showsNote, let file = visit.noteFile,
              NoteFilePaths.isOpenableFile(file) else { return false }
        navigationHistory?.dismiss()
        let creation = TabCreationProvenance(referrerID: id, activeTabID: currentTabID,
                                             profileID: activeProfileID, state: store.state)
        var opened: UUID?
        performWindowCommand(selectNativePage: false) {
            let existing = Set(store.state.tabs.map(\.id))
            opened = store.openNote(url: file, title: visit.note.title, inBackground: true, creation: creation)
            if let created = opened, !existing.contains(created) { presentation.recordCreation(created, state: store.state) }
        }
        return opened != nil
    }

    func openNoteOverPage(_ file: URL, url: URL, sourceID: UUID, page: PCNativePage) -> Bool {
        guard browsers[sourceID]?.nativePage === page, peekPages(forTabID: sourceID).isEmpty,
              nativeFullscreenTabID != sourceID, !closingTabIDs.contains(sourceID),
              !transferringTabIDs.contains(sourceID), !store.retiringTabIDs.contains(sourceID) else { return false }
        closeLibrary(restoreFocus: false)
        let title = NoteFileSession.session(for: file)?.title ?? file.deletingPathExtension().lastPathComponent
        var opened = false
        performWindowCommand { opened = store.openNoteOverPage(sourceID, url: file, title: title) }
        guard opened else { return false }
        focusSelectedLocalContent()
        if let anchor = url.fragment, !anchor.isEmpty { revealNoteAnchor(anchor, inTab: sourceID) }
        return true
    }
}
