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

    static func pageHistory(_ page: PCNativePage) -> TabNoteVisit.PageHistory? {
        guard page.responds(to: #selector(getter: PCNativePage.historyEntries)) else { return nil }
        let live = page.historyEntries
        let entries = live.map { entry in
            TabNoteVisit.PageEntry(id: entry.persistentIdentifier,
                                   url: BrowserInternalURL.publicString(entry.url?.absoluteString ?? ""), title: entry.title)
        }
        let history = TabNoteVisit.PageHistory(entries: entries, current: page.currentHistoryIndex,
                                               navigating: page.historyNavigationPending)
        return history.isValid ? history : nil
    }

    func visitHistory(_ state: NSObject?, for tab: BrowserTab) -> NSObject? {
        guard let state, let visit = tab.noteVisit,
              let target = visit.leaving ? visit.pageUnderShown : visit.shownPage, !target.id.isEmpty,
              PCNativePage.responds(to: #selector(PCNativePage.navigationState(_:at:endingAt:))) else { return state }
        return PCNativePage.navigationState(state, at: target.id, endingAt: visit.pageEntryIDs.last) ?? state
    }

    func browserViewDidChangeHistory(_ view: PCBrowserView) {
        guard let id = id(for: view) ?? coveredTabID(for: view), let page = view.nativePage, !page.isClosed,
              store.state.tab(id)?.noteVisit != nil, let history = Self.pageHistory(page) else { return }
        store.syncPageHistory(id, history: history)
    }

    func noteVisitMenuTarget(_ action: PCNativeNavigationAction) -> UUID? {
        guard action == .back || action == .forward, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, activePeek == nil, libraryView == nil, window?.attachedSheet == nil,
              let id = currentTabID, !transferringTabIDs.contains(id), !closingTabIDs.contains(id),
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }), tab.profileID == activeProfileID,
              let visit = tab.noteVisit else { return nil }
        let back = action == .back
        if tab.showsNoteOverPage {
            guard renderedPaneIDs.contains(id) else { return nil }
            return (back ? visit.behind : visit.ahead).isEmpty ? nil : id
        }
        guard !InternalPage.isInternal(tab.url), visit.hasDocument(towardBack: back),
              let page = navigationPage, browsers[id]?.nativePage === page else { return nil }
        return id
    }

    func noteVisitTarget(_ action: PCNativeNavigationAction) -> UUID? {
        guard let id = noteVisitMenuTarget(action), let visit = store.state.tab(id)?.noteVisit else { return nil }
        if visit.showsNote { return id }
        return (action == .back ? visit.behind.first : visit.ahead.first)?.document != nil ? id : nil
    }

    var navigationCanShowBack: Bool {
        noteVisitMenuTarget(.back) != nil || (navigationPage?.canShowBackHistory ?? false)
    }
    var navigationCanShowForward: Bool {
        noteVisitMenuTarget(.forward) != nil || (navigationPage?.canShowForwardHistory ?? false)
    }

    @discardableResult
    func stepNoteVisit(_ id: UUID, forward: Bool) -> Bool {
        stepNoteVisit(id, by: forward ? 1 : -1)
    }

    @discardableResult
    func stepNoteVisit(_ id: UUID, by offset: Int) -> Bool {
        guard let tab = store.state.tab(id, where: { $0.archivedAt == nil }), let visit = tab.noteVisit,
              let target = visit.step(offset) else { return false }
        if tab.showsNoteOverPage, let note = noteEditors[id], !note.editor.prepareToClose() { return false }
        navigationHistory?.dismiss()
        guard moveVisitPage(id, visit: visit, offset: offset, target: target) else { return false }
        var stepped = false
        performWindowCommand { stepped = store.stepNoteVisit(id, by: offset) }
        if stepped { focusSelectedLocalContent() }
        return stepped
    }

    private func moveVisitPage(_ id: UUID, visit: TabNoteVisit, offset: Int, target: TabNoteVisit.Step) -> Bool {
        guard let page = nativePage(forTabID: id) else { return true }
        if visit.leaving, offset < 0, browsers[id]?.nativePage === page { browsers[id]?.stop() }
        guard let anchor = visit.anchor(afterMovingBy: offset), !anchor.id.isEmpty,
              page.responds(to: #selector(PCNativePage.goToHistoryEntry(_:))) else { return true }
        let entries = page.historyEntries, index = page.currentHistoryIndex
        let currentID = entries.indices.contains(index) ? entries[index].persistentIdentifier : nil
        if currentID != anchor.id {
            guard entries.contains(where: { $0.persistentIdentifier == anchor.id }), page.goToHistoryEntry(anchor.id) else {
                if let history = Self.pageHistory(page) { store.syncPageHistory(id, history: history) }
                return false
            }
        }
        if case .page(let entry) = target {
            if let covered = coveredPages[id] { covered.requestedURL = entry.url } else if browsers[id] != nil { requestedURLs[id] = entry.url }
        }
        return true
    }

    func noteVisitInteraction(_ kind: NavigationControlKind) -> NavigationControlInteraction? {
        guard kind != .reload else { return nil }
        let action: PCNativeNavigationAction = kind == .back ? .back : .forward
        guard let id = noteVisitMenuTarget(action) else { return nil }
        return NavigationControlInteraction(activate: { [weak self] alternate in
            guard let self, self.noteVisitMenuTarget(action) == id else { return }
            if self.noteVisitTarget(action) == id {
                self.chooseNoteVisitStep(id, offset: action == .forward ? 1 : -1, alternate: alternate)
            } else if let page = self.navigationPage, self.browsers[id]?.nativePage === page,
                      page.performNavigation(action, inNewTab: alternate), !alternate {
                self.failures.removeValue(forKey: id)
                self.refreshPagePresentation(id)
            }
        }, showHistory: { [weak self] anchor in
            self?.showNoteVisitHistory(id, forward: action == .forward, from: anchor)
        })
    }

    private func chooseNoteVisitStep(_ id: UUID, offset: Int, alternate: Bool) {
        guard noteVisitMenuTarget(offset > 0 ? .forward : .back) == id,
              let step = store.state.tab(id, where: { $0.archivedAt == nil })?.noteVisit?.step(offset) else { return }
        guard alternate else { stepNoteVisit(id, by: offset); return }
        switch step {
        case .document(let entry): openNoteStepInBackground(id, entry: entry)
        case .page(let entry): openPageEntryInBackground(id, entry: entry)
        }
    }

    func noteVisitRows(_ visit: TabNoteVisit, forward: Bool, page: PCNativePage?) -> [(step: TabNoteVisit.Step, title: String, icon: NSImage?)] {
        let live = page.map { $0.responds(to: #selector(getter: PCNativePage.historyEntries)) ? $0.historyEntries : [] } ?? []
        return (forward ? visit.ahead : visit.behind).map { step in
            let entry = step.page.flatMap { shown in live.first { !shown.id.isEmpty && $0.persistentIdentifier == shown.id } }
            let title = entry.map { $0.title.isEmpty ? step.title : $0.title } ?? step.title
            let profile = activeProfileID
            return (step, title, step.document.map { Self.noteVisitIcon($0, profile: profile) } ?? entry?.favicon)
        }
    }

    private func showNoteVisitHistory(_ id: UUID, forward: Bool, from anchor: NSView) {
        let action: PCNativeNavigationAction = forward ? .forward : .back
        guard let window, noteVisitMenuTarget(action) == id,
              let visit = store.state.tab(id, where: { $0.archivedAt == nil })?.noteVisit else { return }
        let page = nativePage(forTabID: id)
        let rows = noteVisitRows(visit, forward: forward, page: page).enumerated().map { index, row in
            let offset = forward ? index + 1 : -(index + 1)
            return NavigationHistoryStepRow(title: row.title, icon: row.icon, url: URL(string: row.step.url)) { [weak self] alternate in
                self?.chooseNoteVisitStep(id, offset: offset, alternate: alternate)
            }
        }
        navigationHistory?.dismiss()
        sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        let history = NavigationHistoryController(page: page, snapshot: nil, leading: rows, window: window, theme: windowPaletteTheme)
        let position = visit.position, leaving = visit.leaving, count = visit.steps.count
        history.stillSelected = { [weak self] in
            guard let self, self.noteVisitMenuTarget(action) == id,
                  let current = self.store.state.tab(id)?.noteVisit else { return false }
            return current.position == position && current.leaving == leaving && current.steps.count == count
        }
        history.onClose = { [weak self, weak history] in
            guard let self, self.navigationHistory === history else { return }
            self.navigationHistory = nil; self.refreshSidebarPointer()
        }
        navigationHistory = history
        history.show(from: anchor)
    }

    @discardableResult
    func openPageEntryInBackground(_ id: UUID, entry: TabNoteVisit.PageEntry) -> Bool {
        guard let tab = store.state.tab(id, where: { $0.archivedAt == nil }), tab.noteVisit != nil else { return false }
        navigationHistory?.dismiss()
        let page = nativePage(forTabID: id)
        let captured = page.flatMap { $0.responds(to: #selector(PCNativePage.captureNavigationState)) ? $0.captureNavigationState() : nil }
        let history = captured.flatMap { state -> NSObject? in
            guard !entry.id.isEmpty else { return state }
            guard PCNativePage.responds(to: #selector(PCNativePage.navigationState(_:at:endingAt:))) else { return nil }
            return PCNativePage.navigationState(state, at: entry.id, endingAt: nil)
        }
        let creation = TabCreationProvenance(referrerID: id, activeTabID: currentTabID,
                                             profileID: tab.profileID, state: store.state)
        var opened: UUID?
        performWindowCommand(selectNativePage: false) {
            opened = store.adoptNativePage(url: URL(string: entry.url), title: entry.title,
                                           profilePath: page?.profilePath ?? store.independentEngineProfilePath(for: tab.profileID),
                                           preferredSpaceID: tab.spaceID, select: false, creation: creation)
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
    func openNoteStepInBackground(_ id: UUID, entry: TabNoteVisit.Entry) -> Bool {
        guard canCreateNote, let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              tab.noteVisit?.documents.contains(entry) == true, let document = TabNoteVisit.document(entry) else { return false }
        if let file = document.noteURL, !NoteFilePaths.isOpenableFile(file) { return false }
        navigationHistory?.dismiss()
        let creation = TabCreationProvenance(referrerID: id, activeTabID: currentTabID,
                                             profileID: tab.profileID, state: store.state)
        var opened: UUID?
        performWindowCommand(selectNativePage: false) {
            let existing = Set(store.state.tabs.map(\.id))
            switch document {
            case .note(let file):
                opened = store.openNote(url: file, title: entry.title, inBackground: true, creation: creation)
            case .easel(let easel):
                opened = store.openEasel(id: easel, title: entry.title, inBackground: true, creation: creation)
            }
            if let created = opened, !existing.contains(created) { presentation.recordCreation(created, state: store.state) }
        }
        return opened != nil
    }

    func noteFileTitle(_ file: URL) -> String {
        NoteFileSession.session(for: file)?.title ?? file.deletingPathExtension().lastPathComponent
    }

    static func noteVisitIcon(_ entry: TabNoteVisit.Entry, profile: UUID) -> NSImage? {
        guard let subject = NoteTabIconArt.Subject(address: entry.url, profile: profile) else { return nil }
        let image = NoteTabIconArt.shared.image(for: subject)
        if case .easel = subject { return image ?? subject.mark.image(size: NoteTabIconArt.side) }
        return image
    }

    func openDocumentOverPage(_ document: InternalPage, title: String, sourceID: UUID, page: PCNativePage?,
                              anchor: String? = nil) -> Bool {
        guard let tab = store.state.tab(sourceID, where: { $0.archivedAt == nil }), peekPages(forTabID: sourceID).isEmpty,
              nativeFullscreenTabID != sourceID, !closingTabIDs.contains(sourceID),
              !transferringTabIDs.contains(sourceID), !store.retiringTabIDs.contains(sourceID) else { return false }
        if tab.showsNoteOverPage {
            guard prepareNotesToClose([sourceID]) else { return false }
        } else {
            guard let page, browsers[sourceID]?.nativePage === page else { return false }
        }
        closeLibrary(restoreFocus: false)
        let live = nativePage(forTabID: sourceID)
        let history = live.flatMap(Self.pageHistory)
        var opened = false
        performWindowCommand { opened = store.openDocumentOverPage(sourceID, page: document, title: title, history: history) }
        guard opened else { return false }
        if let live, let history, store.state.tab(sourceID)?.noteVisit?.pageUnderShown.id == history.entries[history.current].id,
           live.responds(to: #selector(PCNativePage.removeHistoryEntriesAfterCurrent)) {
            _ = live.removeHistoryEntriesAfterCurrent()
        }
        focusSelectedLocalContent()
        if let anchor, !anchor.isEmpty { revealNoteAnchor(anchor, inTab: sourceID) }
        return true
    }
}
