import AppKit
import Combine

extension BrowserWindowController {
    func prepareStoreContext(restoringSplitLayout: BrowserSplitLayout? = nil) {
        presentation.reconcile(store.state) { ownership.canUse($0, owner: presentationID) }
        let restoredLayout = restoringSplitLayout.flatMap {
            $0.spaceID == activeSpaceID && $0.tabIDs == selectedTabIDs ? $0 : nil
        }
        if store.activeSpaceID != activeSpaceID || store.state.selectedTabIDs != selectedTabIDs
            || (restoredLayout != nil && store.activeSplitLayout != restoredLayout) {
            store.setWindowPresentation(spaceID: activeSpaceID, selectedTabIDs: selectedTabIDs,
                                        splitLayout: restoredLayout ?? presentation.splitLayout)
        }
    }

    func performWindowCommand<T>(selectNativePage: Bool = true, afterCapture: (() -> Void)? = nil, _ action: () -> T) {
        cancelSpaceCreation(restoreFocus: false)
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else { return }
        pendingNativeSelection = nil
        let previousFocus = focusedTabID
        prepareStoreContext()
        _ = action()
        presentation.captureCommand(store.state) { ownership.canUse($0, owner: presentationID) }
        afterCapture?()
        focusedTabID = previousFocus.flatMap { selectedTabIDs.contains($0) ? $0 : nil } ?? selectedTabIDs.last
        presentation.recordSelectionForReturn(currentTabID, state: store.state)
        onSessionRecordChange?()
        render(store.state)
        if selectNativePage { requestNativeSelection() }
        if !isPopupWindow && !isPrivateBrowsing { store.linkRouting.noteVisitedSpace(activeSpaceID) }
    }

    func cancelPendingCommandSplit() {
        guard pendingCommandSplitValidation != nil else { return }
        commandSubmissionRevision = UUID()
        pendingCommandSplitValidation = nil; pendingCommandSplitBrowser = nil
    }

    func openInput(_ input: String, typedText: String? = nil) {
        if isPopupWindow { onRequestBrowserTab?(input); return }
        resolveInput(input, typedText: typedText, replacing: nil)
    }

    func openAddress(_ url: URL) {
        if isPopupWindow { openInput(url.absoluteString) } else { openExactAddress(url) }
    }

    func resolveInput(_ input: String, typedText: String? = nil, replacing tabID: UUID?) {
        if openLocalNoteAddress(input) { return }
        if let tabID, !prepareNotesToClose([tabID]) { return }
        let spaceID = activeSpaceID
        let profileID = activeProfileID
        let originalPage = tabID.flatMap { browsers[$0]?.nativePage }
        let originalURL = tabID.flatMap { id in store.state.tab(id)?.url }
        let revision = UUID()
        if let tabID { inputRevisions[tabID] = revision }
        PCNativeBrowserApplication.resolveSearchInput(input, typedText: typedText,
            profilePath: store.independentEngineProfilePath(for: profileID), page: currentBrowser?.nativePage, window: nativeBinding) { [weak self, weak originalPage] navigation, error in
            MainActor.assumeIsolated {
                guard let self, self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                      !self.isClosing, !self.wholeWindowClose else { return }
                if let tabID {
                    guard self.currentTabID == tabID, self.inputRevisions[tabID] == revision,
                          self.browsers[tabID]?.nativePage === originalPage,
                          self.store.state.tab(tabID)?.url == originalURL else { return }
                    self.inputRevisions.removeValue(forKey: tabID)
                }
                guard let navigation else {
                    self.showSearchError(error?.localizedDescription ?? "Search is unavailable for this Space.")
                    return
                }
                self.openSearchNavigation(navigation, replacing: tabID)
            }
        }
    }

    func showSearchError(_ message: String) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(title: "Couldn’t open search", message: message))
    }

    func creationProvenance(activeTabID: UUID?) -> TabCreationProvenance {
        TabCreationProvenance(referrerID: nil, activeTabID: activeTabID,
            profileID: activeProfileID, state: store.state)
    }

    func creationSourceTab(_ page: PCNativePage) -> UUID? {
        guard !page.isClosed,
              let binding = PCNativeBrowserApplication.owner(of: page),
              let original = binding.client as? BrowserWindowController,
              original.store === store, original.ownership === ownership,
              binding === original.nativeBinding,
              !original.isClosing, !original.wholeWindowClose,
              !original.windowClosePending, !original.windowCloseApproved,
              let window = original.window, page.nativeView.window === window,
              let id = original.browsers.first(where: { $0.value.nativePage === page })?.key
                  ?? original.peekSource(of: page),
              original.ownership.canUse(id, owner: original.presentationID),
              !original.closingTabIDs.contains(id), !original.modelRetirementIDs.contains(id),
              !original.transferringTabIDs.contains(id), !store.retiringTabIDs.contains(id) else { return nil }
        return id
    }
    func alternateNavigationReceipt(_ page: PCNativePage) -> (referrer: UUID?, top: Bool)? {
        guard page.responds(to: #selector(getter: PCNativePage.alternateNavigationSourcePage)),
              let source = page.alternateNavigationSourcePage,
              let binding = nativeBinding,
              PCNativeBrowserApplication.owner(of: source) === binding else { return nil }
        let top = page.alternateNavigationPlacesAtTop
        let referrer = creationSourceTab(source)
        if top, let referrer, browsers[referrer]?.nativePage !== source { return (nil, true) }
        return (referrer, top)
    }

    private func peekSource(of page: PCNativePage) -> UUID? {
        guard let peek = peeks[page.identifier], peek.page === page, !page.isClosed, let parentPage = peek.parentPage,
              !parentPage.isClosed, browsers[peek.parentTabID]?.nativePage === parentPage,
              PCNativeBrowserApplication.owner(of: parentPage) === nativeBinding,
              parentPage.profilePath == page.profilePath,
              !peekRetirementParents.contains(peek.parentTabID) else { return nil }
        return peek.parentTabID
    }

    func openSearchNavigation(_ navigation: PCNativeSearchNavigation, replacing tabID: UUID?) {
        guard navigation.profilePath == store.independentEngineProfilePath(for: activeProfileID),
              presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else { return }
        if openLocalNoteAddress(navigation.url.absoluteString) { return }
        if let tabID {
            guard currentTabID == tabID, !store.retiringTabIDs.contains(tabID), !closingTabIDs.contains(tabID) else { return }
            performWindowCommand {
                pendingSearchNavigations[tabID] = navigation
                requestedURLs.removeValue(forKey: tabID)
                store.updateTab(tabID, url: navigation.url.absoluteString)
            }
        } else {
            let id = UUID()
            let creation = creationProvenance(activeTabID: currentTabID)
            performWindowCommand {
                pendingSearchNavigations[id] = navigation
                store.openResolvedURL(navigation.url, id: id, creation: creation)
                presentation.recordCreation(id, state: store.state)
            }
        }
    }

    var canAcceptExternalLink: Bool {
        !isPrivateBrowsing && !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose &&
        !windowClosePending && !windowCloseApproved && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
    }

    @discardableResult
    func openExternalURL(_ url: URL, inSpace spaceID: UUID) -> Bool {
        guard canAcceptExternalLink,
              store.state.spaces.contains(where: { $0.id == spaceID }) else { return false }
        if activeSpaceID != spaceID { selectSpace(spaceID) }
        else { cancelSpaceCreation(restoreFocus: false); sidebarPreviews?.dismiss() }
        guard activeSpaceID == spaceID, canAcceptExternalLink else { return false }
        if InternalPage.noteFile(url) != nil { return openNote(url: url) }
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.openResolvedURL(url, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
        return true
    }

    var canShowLibrary: Bool {
        if isPrivateBrowsing { return false }
        return !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose && nativeFullscreenTabID == nil
    }
    var canShowMedia: Bool {
        if !isPrivateBrowsing { return canShowLibrary }
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, nativeFullscreenTabID == nil,
              privateCaptureContextIsValid, let parent = store.privateParentProfileID,
              let catalog = downloadCatalog, !catalog.isEphemeral else { return false }
        return catalog.state.profiles.contains(where: { $0.id == parent }) && !catalog.isProfileRemovalPending(parent)
    }
    var canShowDownloads: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose && nativeFullscreenTabID == nil
            && (!isPrivateBrowsing || nativeBinding?.privateDownloadsAvailable == true)
    }
    func showLibrary(_ kind: LibraryView.Kind) {
        cancelSpaceCreation(restoreFocus: false)
        sidebarPreviews?.dismiss()
        guard kind == .downloads ? canShowDownloads : kind == .captures ? canShowMedia : canShowLibrary else { return }
        pageCapture?.dismiss(restoreFocus: false)
        if let libraryView, libraryView.profileID == activeProfileID {
            libraryView.show(kind); return
        }
        closeLibrary(restoreFocus: false)
        commandBar?.dismiss()
        let profileID = activeProfileID
        let privateMedia: LibraryView.PrivateMediaContext?
        if isPrivateBrowsing, let parent = store.privateParentProfileID, let catalog = downloadCatalog {
            if privateMediaSource?.catalog !== catalog || privateMediaSource?.profileID != parent {
                privateMediaSource = (catalog, parent, ExternalMediaLibrary(
                    directory: catalog.capturesDirectory(for: parent), preferencesAreEphemeral: true))
            }
            guard let media = privateMediaSource?.media else { return }
            privateMedia = .init(store: catalog, profileID: parent, media: media, isValid: { [weak self, weak catalog] in
                guard let self, let catalog else { return false }
                return self.downloadCatalog === catalog && self.store.privateParentProfileID == parent
                    && self.activeProfileID == profileID && self.canShowMedia
            })
        } else { privateMedia = nil }
        let view = LibraryView(store: store, kind: kind, profileID: profileID, downloadStore: downloadStore,
                               privateMediaContext: privateMedia)
        view.onCreateNote = { [weak self] in self?.createNote() }
        view.onOpenDocument = { [weak self] page, title in
            guard let self, self.activeProfileID == profileID else { return }
            switch page { case .note(let url): self.openNote(url: url)
            case .easel(let id): self.closeLibrary(restoreFocus: false); self.openEasel(id: id, title: title) }
        }
        view.onRenameDocument = { [weak self] page, title in
            guard let self else { return }
            switch page { case .note(let url): self.store.updateNoteFile(from: url, to: url, title: title)
            case .easel(let id): self.store.updateEaselTitle(id: id, profileID: profileID, title: title) }
        }
        view.onDeleteDocument = { [weak self, weak view] page, done in
            guard let self, let view, self.libraryView === view, self.activeProfileID == profileID else { done(CocoaError(.userCancelled)); return }
            let ownerValid: () -> Bool = { [weak self, weak view] in
                guard let self, let view else { return false }
                return self.libraryView === view && self.activeProfileID == profileID && !self.isClosing
            }
            switch page {
            case .note(let file):
                self.store.deleteLocalDocument(page, profileID: profileID, ownerValid: ownerValid) { error in
                    if error == nil { NoteReminderCenter.shared.forget(document: file) }
                    done(error)
                }
            case .easel(let id):
                do {
                    let easel = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID)).load(id)
                    let easelSnapshot = easel.document
                    self.store.deleteLocalDocument(page, profileID: profileID, ownerValid: {
                        ownerValid() && easel.document == easelSnapshot
                    }, deleteDocument: {
                        try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID)).delete(id)
                    }, completion: done)
                } catch { done(error) }
            }
        }
        view.palette = rootView.palette
        view.onClose = { [weak self] in self?.closeLibrary() }
        view.onToast = { [weak self, weak view] content in
            guard let self, let view, self.libraryView === view else { return }
            self.showToast(content, at: .window)
        }
        view.onOpenURLs = { [weak self, weak view] urls in
            guard let self, let view, self.libraryView === view, self.activeProfileID == profileID,
                  !self.isPrivateBrowsing || (view.kind == .captures && self.canShowMedia) else { return }
            self.openLibraryURLs(urls, profileID: profileID)
        }
        view.archiveOwnerValid = { [weak self, weak view] in
            guard let self, let view else { return false }
            return self.libraryView === view && self.activeProfileID == profileID && !self.isClosing
                && !self.wholeWindowClose && !self.windowClosePending
        }
        view.onRestore = { [weak self, weak view] ids, destination in
            guard let self, let view, self.libraryView === view, self.activeProfileID == profileID else { return }
            if let peek = self.activePeek, let lease = self.archivePreviews[peek.identity],
               ids.contains(where: { id in lease.tabs.contains { $0.id == id } }) {
                if ids.count == 1 { self.promotePeek(peek, split: false) }
                return
            }
            self.restoreArchivedTabs(ids, profileID: profileID,
                destination: .putBack(currentSpaceID: self.activeSpaceID, requestedSpaceID: destination))
        }
        view.onPreview = { [weak self, weak view] id in
            guard let self, let view, self.libraryView === view, view.kind == .archive,
                  self.activeProfileID == profileID else { return false }
            return self.previewArchivedItem(id, profileID: profileID)
        }
        view.onDownloadAction = { [weak self, weak view] item, action in
            guard let self, let view, self.libraryView === view, view.kind == .downloads,
                  self.activeProfileID == profileID else { return false }
            return self.performLibraryDownload(item, action: action)
        }
        view.onLoadDownloads = { [weak self, weak view] in
            guard let self, let view, self.libraryView === view, view.kind == .downloads else { return }
            self.refreshDownloadProfiles()
        }
        view.downloadFileURL = { [weak self, weak view] item in
            guard let self, let view, self.libraryView === view, view.kind == .downloads,
                  self.activeProfileID == profileID else { return nil }
            return self.libraryDownloadFileURL(item)
        }
        libraryView = view
        libraryContentWidth = view.contentWidth
        view.onContentWidthChange = { [weak self, weak view] in
            guard let self, let view, self.libraryView === view else { return }
            self.setLibraryContentWidth(view.contentWidth)
        }
        configureSpaceManager(view)
        view.onShowKind = { [weak self] kind in self?.recordLibraryPage(kind) }
        recordLibraryPage(view.kind)
        sidebar.libraryDidOpen()
        view.requestIcon = { [weak self, weak view] url, requestedProfile, completion in
            guard let self, let view, self.libraryView === view,
                  requestedProfile == profileID, self.activeProfileID == profileID else { return }
            let path = self.store.independentEngineProfilePath(for: profileID)
            PCNativeBrowserApplication.favicon(for: url, profilePath: path) { [weak self, weak view] image in
                MainActor.assumeIsolated {
                    guard let self, let view, self.libraryView === view,
                          self.activeProfileID == profileID, !self.isClosing else { return }
                    completion(image)
                }
            }
        }
        rootView.addSubview(view)
        layoutChrome()
        refreshLibraryDownloadActivity()
        view.focusSearch()
        if kind == .downloads { refreshDownloadProfiles() }
    }

    func refreshHandoffActivity() {
        let url = isPrivateBrowsing || isClosing || wholeWindowClose ? nil : store.state.tabs.first { $0.id == currentTabID }
            .flatMap { URL(string: $0.url) }.flatMap(HandoffActivity.publishable)
        guard userActivity?.webpageURL != url else { return }
        userActivity?.invalidate()
        userActivity = url.map(HandoffActivity.browsing)
    }

    func updateNavigation() {
        refreshHandoffActivity()
        refreshSidebarBanners()
        navigationHistory?.validate()
        refreshDeveloperToolbars()
        synchronizeNativeLayout()
        refreshExtensionControls()
        refreshPaymentControls()
        refreshBlockedContent()
        refreshCaptureIndicators()
        refreshMiniPlayers()
        let state = presentedState
        refreshFavoriteOverlays(from: state)
        let published = publishedShareableAndAudio()
        let canBack = navigationPage?.canShowBackHistory ?? false
        let canForward = navigationPage?.canShowForwardHistory ?? false
        if !sidebar.applyLivePageMetadata(state: state, focusedTabID: currentTabID,
                                          loading: loadingTabs, canBack: canBack, canForward: canForward,
                                          captures: capturePresentations, shareable: published.shareable,
                                          audio: published.audio, applyShareableAudio: published.changed) {
            sidebar.render(state: state, focusedTabID: currentTabID, loading: loadingTabs,
                           canBack: canBack, canForward: canForward, captures: capturePresentations,
                           shareable: published.shareable, audio: published.audio)
        }
        if published.changed {
            rememberAppliedShareableAudio(shareable: published.shareable, audio: published.audio)
        }
        refreshDownloads()
        let tab = store.state.tabs.first { $0.id == currentTabID }
        refreshNavigationControls()
        window?.title = activePeek.map { "\($0.browser.title) — Peek — Parc" } ?? tab.map { "\($0.title) — Parc" } ?? "Parc"
        refreshLoadingIndicators()
        noteReturnGate()
        if let window {
            NotificationCenter.default.post(name: NSNotification.Name(PCNativeLinkOutcomeInputsDidChangeNotification),
                                            object: window)
        }
    }

    func refreshLoadingIndicators() {
        for (id, observer) in paneFrameObservers where panes[id] == nil {
            NotificationCenter.default.removeObserver(observer); paneFrameObservers.removeValue(forKey: id)
        }
        guard !isPopupWindow, !isClosing, !wholeWindowClose, libraryView == nil else { loadingIndicator.update([]); return }
        let ids = renderedPaneIDs.filter { panes[$0]?.superview === splitView }
        let eligible = PageLoadingIndicatorHost.eligible(ids, stacked: !splitView.isVertical && ids.count > 1)
        loadingIndicator.update(eligible.compactMap { id in
            guard let pane = panes[id] else { return nil }
            if paneFrameObservers[id] == nil {
                paneFrameObservers[id] = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: pane, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshLoadingIndicators() }
                }
            }
            let rect = pane.convert(pane.bounds, to: pageHost)
            return PageLoadingIndicatorHost.Pane(id: id, minX: rect.minX, width: rect.width, loading: loadingTabs.contains(id))
        })
    }

    func refreshNavigationControls() {
        sidebar.updateSpaceAvailability()
        let page = navigationPage, loading = page?.loading == true
        sidebar.updateNavigation(canBack: navigationPage?.canShowBackHistory ?? false,
                                 canForward: navigationPage?.canShowForwardHistory ?? false,
                                 loading: loading, enabled: canPerformNavigation(loading ? .stop : reloadAction),
                                 developerReload: developerReloadPage != nil,
                                 forceReload: DeveloperReloadPreference.state == .forceReload)
        popupChrome.update(url: page?.url, canGoBack: navigationPage?.canShowBackHistory ?? false, loading: loading)
    }

    private func performNavigation(_ action: PCNativeNavigationAction) {
        navigationHistory?.dismiss()
        if let page = navigationPage {
            if page.performNavigation(action, inNewTab: false), action != .stop { navigationRequested(on: page) }
        }
        else if action == .reload, canPerformNavigation(action), let id = currentTabID { reloadTab(id) }
    }
    private func navigationRequested(on page: PCNativePage) {
        guard navigationPage === page, let id = currentTabID, browsers[id]?.nativePage === page else { return }
        failures.removeValue(forKey: id)
        refreshPagePresentation(id)
    }
    private var developerReloadPage: PCNativePage? {
        guard let page = navigationPage, let host = page.developerModeSiteHost,
              DeveloperModePreferences.shared.isEnabled(host: host) else { return nil }
        return page
    }
    private var reloadAction: PCNativeNavigationAction {
        developerReloadPage != nil && DeveloperReloadPreference.state == .forceReload ? .reloadBypassingCache : .reload
    }
    func showReloadOptions(from anchor: NSView) {
        guard let page = developerReloadPage, anchor.window === window else { return }
        let browser = currentBrowser
        let isOriginal: () -> Bool = { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.developerReloadPage === page
        }
        let menu = ReloadOptionsMenu.make(state: DeveloperReloadPreference.state,
                                          canReload: page.canPerformNavigation(.reload),
                                          canForceReload: page.canPerformNavigation(.reloadBypassingCache),
                                          canClearCookies: canPerformPageTool(.clearCookiesAndRefresh)) { [weak self, weak page, weak browser] choice in
            guard let self, let page, isOriginal() else { return }
            switch choice {
            case .reload, .forceReload:
                let action: PCNativeNavigationAction = choice == .reload ? .reload : .reloadBypassingCache
                DeveloperReloadPreference.state = choice == .reload ? .reload : .forceReload
                self.navigationHistory?.dismiss()
                if page.performNavigation(action, inNewTab: false) { self.navigationRequested(on: page) }
                self.refreshNavigationControls()
            case .clearCookies:
                guard let browser, self.currentBrowser === browser, browser.nativePage === page,
                      self.canPerformPageTool(.clearCookiesAndRefresh) else { return }
                _ = browser.performPageTool(.clearCookiesAndRefresh)
            }
        }
        ReloadOptionsMenu.present(menu, from: anchor)
    }
    func goBack() { performNavigation(.back) }
    func goForward() { performNavigation(.forward) }
    func reload() { performNavigation(.reload) }
    func forceReload() { performNavigation(.reloadBypassingCache) }
    func stopLoading() { performNavigation(.stop) }

    func prepareNavigationInteraction(_ kind: NavigationControlKind) -> NavigationControlInteraction? {
        guard let page = navigationPage else {
            guard kind == .reload, canPerformNavigation(.reload), let id = currentTabID else { return nil }
            return NavigationControlInteraction(activate: { [weak self] alternate in
                guard let self, !alternate, self.currentTabID == id, self.navigationPage == nil,
                      self.canPerformNavigation(.reload) else { return }
                self.reloadTab(id)
            })
        }
        let action: PCNativeNavigationAction = kind == .back ? .back : kind == .forward ? .forward : page.loading ? .stop : reloadAction
        let snapshot = kind == .reload ? nil : page.navigationHistory(back: kind == .back)
        let isOriginal: () -> Bool = { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.navigationPage === page
        }
        return NavigationControlInteraction(activate: { [weak self, weak page] alternate in
            guard isOriginal(), let page else { return }
            if kind != .reload, snapshot?.isValid != true { return }
            self?.navigationHistory?.dismiss()
            if page.performNavigation(action, inNewTab: alternate), !alternate, action != .stop {
                self?.navigationRequested(on: page)
            }
        }, showHistory: snapshot.map { snapshot in
            { [weak self, weak page] anchor in
                guard let self, let page, let window = self.window,
                      isOriginal(), snapshot.isValid, !snapshot.entries.isEmpty else { return }
                self.navigationHistory?.dismiss()
                self.sidebarPreviews?.dismiss(); self.tabSwitcher?.cancel()
                let history = NavigationHistoryController(page: page, snapshot: snapshot, window: window,
                    theme: self.windowPaletteTheme)
                history.stillSelected = isOriginal
                history.onNavigate = { [weak self, weak page] in
                    if let page { self?.navigationRequested(on: page) }
                }
                history.onClose = { [weak self, weak history] in
                    guard let self, self.navigationHistory === history else { return }
                    self.navigationHistory = nil; self.refreshSidebarPointer()
                }
                self.navigationHistory = history
                history.show(from: anchor)
            }
        })
    }
    var hasSidebarCommandSelection: Bool { sidebar.hasCommandSelection }
    func prepareSidebarSelectionCommand(_ kind: SidebarSelectionCommandKind) -> SidebarSelectionCommandTarget? {
        sidebar.prepareSelectionCommand(kind)
    }

    var closeTabMenuTitle: String {
        if activePeek != nil { return "Close Peek" }
        if isPopupWindow { return "Close Window" }
        if isPrivateBrowsing { return "Close Tab" }
        return visibleTabs.first(where: { $0.id == currentTabID })?.kind == .today ? "Archive Tab" : "Close Tab"
    }
    var canCloseCurrentTab: Bool {
        guard !isClosing, !wholeWindowClose, !windowClosePending,
              window?.attachedSheet == nil else { return false }
        if isPopupWindow { return true }
        guard let id = currentTabID else { return false }
        return !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) && !store.retiringTabIDs.contains(id)
    }
    var reopenClosedStep: ClosedItemStep? {
        guard !isPopupWindow, !isPrivateBrowsing, presentation.isReady,
              !isClosing, !wholeWindowClose, !windowClosePending,
              window?.attachedSheet == nil, activePeek == nil, closeFade?.isClosing != true,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              let step = closedItems.nextStep(in: store.state, restorable: { store.canUndoFolderDeletion($0) })
        else { return nil }
        switch step {
        case .items(let record):
            return record.tabIDs.allSatisfy({ id in
                !store.retiringTabIDs.contains(id) && !closingTabIDs.contains(id)
                    && !ownership.isClaimed(id) && browsers[id] == nil
            }) ? step : nil
        case .folder(let undo):
            let ids = Set(undo.tabs.map(\.id))
            return !folderUndo.isBusy && folderUndoContextAvailable && undo.documentsAreAvailable
                && ids.isDisjoint(with: store.retiringTabIDs) && ids.allSatisfy({ switcherCanUse($0) }) ? step : nil
        case .peek(let record):
            let parent = record.parentTabID
            return canUseOrMoveHere(parent) && !peeks.values.contains(where: { $0.parentTabID == parent }) ? step : nil
        }
    }
    var canRestoreClosedTab: Bool { reopenClosedStep != nil }
}
