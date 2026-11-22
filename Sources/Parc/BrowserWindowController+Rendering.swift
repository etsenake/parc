import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func render(_ sharedState: BrowserState) {
        reconcileSpaceCreation()
        favoriteRename?.reconcile(); favoriteSplitRename?.reconcile(); splitIconPicker?.reconcile(); spaceIconPicker?.reconcile()
        pageHost.validateDrop()
        if splitDropView?.drag.isValid == false { splitDropView?.drag.end() }
        if splitInsertion?.isValid == false { cancelSplitInsertion(restoreFocus: false) }
        if pendingCommandSplitValidation?() == false { cancelPendingCommandSplit() }
        tabSwitcher?.dismissIfInvalid()
        defer { reconcileFind(); pageCapture?.reconcile(); easelImageDestination?.dismissIfInvalid(); sidebarPreviews?.reconcile(); reconcileCommandBar(); checkPanePresentation() }
        guard canRender else { return }
        let presentedRevision = store.stateRevision
        let previousSession = sessionRecord
        presentation.reconcile(sharedState) { ownership.canUse($0, owner: presentationID) }
        clearEmptyPinnedFolds(sharedState)
        if sessionRecord != previousSession { onSessionRecordChange?() }
        if let libraryView, libraryView.profileID != activeProfileID { closeLibrary(restoreFocus: false) }
        let state = presentation.projected(sharedState)
        rendering = true
        defer { rendering = false }
        reconcileCoveredPages(state)
        let liveIDs = Set(state.openTabs.map(\.id))
        for id in Array(browsers.keys) where !liveIDs.contains(id)
            || state.tab(id)?.profileID != browserProfiles[id]
            || state.tab(id).map({ InternalPage.isInternal($0.url) }) == true {
            retireBrowserAfterModelChange(id)
        }
        for id in Array(noteEditors.keys) {
            guard let cached = noteEditors[id] else { continue }
            let tab = state.tab(id, where: { $0.archivedAt == nil })
            let page = tab.flatMap { InternalPage(urlString: $0.url) }
            let sameNote = page == .note(cached.url) || (page?.noteURL != nil && page == InternalPage(urlString: cached.originalTab.url))
            if tab?.profileID != cached.profileID || !sameNote {
                if !(NoteEmbeddedPages.pool(for: cached.editor)?.pages.isEmpty ?? true) {
                    retireNoteAfterModelChange(id, cached: cached); continue
                }
                guard cached.editor.prepareToClose() else {
                    _ = store.restoreLiveTab(cached.originalTab, replacing: store.state.tab(id))
                    continue
                }
                retireNoteEditor(id)
            } else if let tab {
                noteEditors[id] = NotePane(profileID: cached.profileID, editor: cached.editor, originalTab: tab)
            }
        }
        noteFailures = noteFailures.filter { presentation.displayedTabIDs.contains($0.key) }
        for id in Array(easelEditors.keys) {
            guard let cached = easelEditors[id] else { continue }
            let tab = state.tab(id, where: { $0.archivedAt == nil })
            if tab?.profileID != cached.profileID || tab.flatMap({ InternalPage(urlString: $0.url)?.easelID }) != cached.documentID {
                if !embeddedPages(forTabID: id).isEmpty {
                    retireEaselAfterModelChange(id, cached: cached); continue
                }
                cached.editor.retirePageOwner()
                panes[id]?.clearNativeContent()
                easelEditors.removeValue(forKey: id)
            } else if let tab {
                easelEditors[id] = EaselPane(documentID: cached.documentID, profileID: cached.profileID,
                                             editor: cached.editor, originalTab: tab)
            }
        }
        for id in Array(panes.keys) where !liveIDs.contains(id) && browsers[id] == nil && easelEditors[id] == nil && noteEditors[id] == nil {
            ownership.release(id, owner: presentationID)
            panes[id]?.removeFromSuperview(); panes.removeValue(forKey: id)
            failures.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
            if renderedPaneIDs.contains(id) { renderedPaneIDs = [] }
        }
        let placeholderIDs = presentation.displayedPlaceholders
        syncPlaceholderImageHolders()
        for (id, pane) in Array(panes) where pane.showsPlaceholder && !presentation.showsPlaceholder(id)
            && browsers[id] == nil && noteEditors[id] == nil && easelEditors[id] == nil {
            pane.removeFromSuperview(); panes.removeValue(forKey: id)
            if renderedPaneIDs.contains(id) { renderedPaneIDs = [] }
        }
        let selected = presentation.displayedTabIDs.compactMap { id in state.tab(id, where: { $0.archivedAt == nil }) }
        let displayed = nativeFullscreenTabID.map { id in selected.filter { $0.id == id } } ?? selected
        let displayedIDs = displayed.map(\.id)
        reconcileTabPeek(displaying: displayedIDs)
        preserveHostlessPeeks()
        notePeekSplitBlockers()
        shownSinceArrival.formIntersection(returnableIDs)
        shownSinceArrival.formUnion(displayedIDs.filter { !placeholderIDs.contains($0) })
        heldReturns.formIntersection(returnableIDs); heldReturns.subtract(displayedIDs)
        failedReturns.formIntersection(returnableIDs); failedReturns.subtract(displayedIDs)
        if renderedPaneIDs != displayedIDs || splitView.arrangedSubviews.isEmpty
            || renderedSpaceCreationID != spaceCreation?.draft.spaceID
            || renderedSplitInsertionID != splitInsertion?.id {
            updateSplitArrangement(displayed: displayed, displayedIDs: displayedIDs)
        } else {
            for (id, pane) in panes {
                pane.contentResize.mode = displayedIDs.contains(id) ? contentResizeReasons.mode : .intrinsic
            }
        }
        let layout = placeholderIDs.isEmpty ? activeSplitLayout : presentation.displayedSplitLayout
        splitMarginHandle.windowAllows = displayed.count == 1 && layout == nil
            && splitInsertion == nil && spaceCreation == nil && !isPopupWindow
        let pending = splitInsertion?.request
        let pendingLayout = pending?.previewLayout
        splitView.configure(orientation: pendingLayout?.orientation ?? pending?.orientation ?? layout?.orientation ?? .horizontal,
                            factors: pendingLayout?.widthFactors ?? pending?.previewFactors ?? layout?.widthFactors ?? [1],
                            stacks: pending == nil ? layout?.stacks : pendingLayout?.stacks)
        for tab in selected {
            if placeholderIDs.contains(tab.id) {
                panes[tab.id]?.showPlaceholder(store.placeholderImages.image(for: tab.id, in: presentationID), title: tab.title) { [weak self] in
                    self?.pullBackPlaceholder(tab.id)
                }
                continue
            }
            if closingTabIDs.contains(tab.id), easelEditors[tab.id] != nil { continue }
            guard ownership.claim(tab.id, owner: presentationID), let pane = panes[tab.id] else { continue }
            if InternalPage.isInternal(tab.url) {
                showInternalPage(tab, in: pane)
            } else if rendersBlank(tab) {
                pane.showBlank()
            } else {
                var restoredHistory: NSObject?
                if browsers[tab.id] == nil {
                    guard !applyingNativeSelection, !store.retiringTabIDs.contains(tab.id) else { continue }
                    restoredHistory = visitHistory(store.closedPageHistory.takeRestored(tab.id) as? NSObject ?? launchHistory(for: tab), for: tab)
                    pane.layoutSubtreeIfNeeded()
                    let enginePath = store.independentEngineProfilePath(for: tab.profileID)
                    let browser = PCBrowserView(frame: pane.contentBounds, profilePath: enginePath)
                    browser.delegate = self
                    browsers[tab.id] = browser
                    browserProfiles[tab.id] = tab.profileID
                    liveTabModels[tab.id] = tab
                    pane.browser = browser
                }
                refreshPagePresentation(tab.id)
                if !applyingNativeSelection, !closingTabIDs.contains(tab.id), requestedURLs[tab.id] != tab.url, let url = URL(string: tab.url) {
                    failures.removeValue(forKey: tab.id)
                    refreshPagePresentation(tab.id)
                    requestedURLs[tab.id] = tab.url
                    let restoredBehind = restoredHistory.flatMap { history in
                        tab.noteVisit.flatMap { $0.leaving ? URL(string: $0.pageUnderShown.url) : nil }
                            .map { browsers[tab.id]?.restoreNavigationState(history, url: $0) == true }
                    } ?? false
                    if let navigation = pendingSearchNavigations.removeValue(forKey: tab.id), BrowserInternalURL.publicString(navigation.url.absoluteString) == BrowserInternalURL.publicString(url.absoluteString) {
                        browsers[tab.id]?.loadSearchNavigation(navigation)
                    } else if restoredBehind {
                        browsers[tab.id]?.loadURL(url)
                    } else if let history = restoredHistory, browsers[tab.id]?.restoreNavigationState(history, url: url) == true {
                    } else {
                        browsers[tab.id]?.loadURL(url)
                    }
                }
            }
        }
        for (id, browser) in browsers where !closingTabIDs.contains(id) {
            if let tab = state.tab(id, where: { $0.archivedAt == nil }),
               tab.profileID == browserProfiles[id], !InternalPage.isInternal(tab.url) {
                liveTabModels[id] = tab
                if browser.nativePage?.isClosed == true { releaseClosedTab(id, updateSavedTab: false) }
            }
        }
        reconcileCloseFade()
        refreshPageHostBacking()
        if let context = themeEditingContextSpaceID, context != activeSpaceID { themePopover?.performClose(nil) }
        synchronizeThemeEditor()
        let preview = themePreview.flatMap { $0.spaceID == activeSpaceID ? $0.theme : nil }
        applyChromeTheme(spaceCreation?.draft.theme ?? preview ?? activeSpace.theme)
        layoutChrome()
        attachOwnedPages()
        updateNavigation()
        lastChromeState = sharedState
        lastChromeRevision = presentedRevision
        noteReturnGate()
        refreshStartPage()
        refreshPendingPaneSidebar()
        scheduleUntargetedReturns()
    }

    private var canRender: Bool {
        presentation.isReady && !isClosing && !wholeWindowClose && !rendering && !promotingPeek
            && transferringTabIDs.isEmpty && collectionTransfer == nil
    }
    func rendersBlank(_ tab: BrowserTab) -> Bool {
        (tab.url == "about:blank" || tab.url.isEmpty) && browsers[tab.id]?.nativePage == nil
            && pendingSearchNavigations[tab.id] == nil
    }

    private func checkPanePresentation() {
        guard canRender else { return }
        guard panesMissingTheirPage() else {
            panePresentationRetries = 0
            return
        }
        guard !panePresentationRetryPending, panePresentationRetries < 4 else { return }
        panePresentationRetries += 1
        panePresentationRetryPending = true
        let delay = 0.05 * Double(1 << (panePresentationRetries - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.panePresentationRetryPending = false
            guard self.canRender else { self.panePresentationRetries -= 1; return }
            if self.panesMissingTheirPage() { self.render(self.store.state) } else { self.panePresentationRetries = 0 }
        }
    }
    private func panesMissingTheirPage() -> Bool {
        let placeholderIDs = presentation.displayedPlaceholders
        for id in presentation.displayedTabIDs {
            guard let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
                  !placeholderIDs.contains(id), !(closingTabIDs.contains(id) && easelEditors[id] != nil),
                  ownership.canUse(id, owner: presentationID), let pane = panes[id],
                  !InternalPage.isInternal(tab.url), !rendersBlank(tab) else { continue }
            guard let browser = browsers[id] else {
                if !applyingNativeSelection && !store.retiringTabIDs.contains(id) { return true }
                continue
            }
            if pane.browser === browser, pane.showsLocalContent || (!pane.showsFailure && browser.isHidden) {
                return true
            }
        }
        return false
    }

    var pendingPaneHoldsSidebar: Bool {
        PendingSplitPaneSidebarRule.holdsSidebar(pendingSplitPane: splitInsertion != nil, creatingSpace: spaceCreation != nil,
                                                 popup: isPopupWindow, library: libraryView != nil)
    }
    func refreshPendingPaneSidebar() {
        let holds = pendingPaneHoldsSidebar
        defer { sidebarHeldByPendingPane = holds }
        switch PendingSplitPaneSidebarRule.refresh(sidebarPresentation, pendingPane: holds, heldBefore: sidebarHeldByPendingPane) {
        case .keep: break
        case .float: setSidebarPresentation(.floating)
        case .applyHover: refreshSidebarPointer()
        }
    }

    func applyPublishedState(_ sharedState: BrowserState) {
        if rendering { return }
        if favoriteRename == nil, favoriteSplitRename == nil, splitIconPicker == nil, spaceIconPicker == nil,
           spaceCreation == nil, splitInsertion == nil,
           presentation.isReady, !isClosing, !wholeWindowClose, !promotingPeek,
           transferringTabIDs.isEmpty, collectionTransfer == nil,
           let previous = lastChromeState, sharedState.preservesChromeLayout(relativeTo: previous),
           !needsNativeLoad(sharedState) {
            if store.stateRevision == lastChromeRevision { return }
            applyLivePageMetadata(sharedState)
            return
        }
        render(sharedState)
    }

    private func needsNativeLoad(_ sharedState: BrowserState) -> Bool {
        let state = presentation.projected(sharedState)
        if coveredPages.keys.contains(where: { id in
            state.tab(id, where: { $0.archivedAt == nil }).map { !$0.showsNoteOverPage } ?? true
        }) { return true }
        return state.tabs.contains { tab in
            tab.archivedAt == nil && !InternalPage.isInternal(tab.url)
                && browsers[tab.id] != nil && !closingTabIDs.contains(tab.id)
                && !applyingNativeSelection && !store.retiringTabIDs.contains(tab.id)
                && requestedURLs[tab.id] != tab.url && URL(string: tab.url) != nil
        }
    }

    func applyLivePageMetadata(_ sharedState: BrowserState) {
        let presentedRevision = store.stateRevision
        let state = presentation.projected(sharedState)
        for (id, browser) in browsers where !closingTabIDs.contains(id) {
            if let tab = state.tab(id, where: { $0.archivedAt == nil }),
               tab.profileID == browserProfiles[id], !InternalPage.isInternal(tab.url) {
                liveTabModels[id] = tab
                if browser.nativePage?.isClosed == true { releaseClosedTab(id, updateSavedTab: false) }
            }
        }
        if !refreshLivePageChrome() { render(sharedState); return }
        lastChromeState = sharedState
        lastChromeRevision = presentedRevision
    }

    func refreshLivePageChromeOrRender() {
        if refreshLivePageChrome() { return }
        if !rendering { render(store.state) }
    }

    @discardableResult
    private func refreshLivePageChrome() -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return true }
        refreshSidebarBanners()
        navigationHistory?.validate()
        refreshExtensionControls()
        refreshPaymentControls()
        refreshCaptureIndicators()
        refreshMiniPlayers()
        let leading = renderedPaneIDs.first
        for (id, pane) in panes where selectedTabIDs.contains(id) {
            let developerPage = pane.browser?.nativePage?.developerModeSiteHost
                .map { DeveloperModePreferences.shared.isEnabled(host: $0) } == true
            let topBar = paneTopBarDisplayed && !developerPage
            configurePaneDeveloperToolbar(pane,
                visible: selectedTabIDs.contains(id) && activePeek == nil && nativeFullscreenTabID == nil)
            if let browser = pane.livePage {
                configureBrowserToolbar(pane.browserToolbar, browser: browser, visible: topBar,
                                        failing: pane.showsFailure, themeBackground: rootView.palette.background,
                                        leading: id == leading, tabID: id)
            } else {
                configureDocumentToolbar(pane, tabID: id, visible: topBar, leading: id == leading)
            }
        }
        for peek in presentedPeeks {
            configureDeveloperToolbar(peek.view.developerToolbar, browser: peek.browser,
                visible: activePeek === peek)
            configureBrowserToolbar(peek.view.browserToolbar, browser: peek.browser,
                visible: PaneTopBarAdmission.peekDisplayed(
                    toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible,
                    isActivePeek: activePeek === peek,
                    developerToolbarHidden: peek.view.developerToolbar.isHidden),
                failing: peek.showsFailure, themeBackground: nil)
        }
        applySidebarToolbarOwnership()
        refreshBlockedContent()
        let state = presentedState
        refreshFavoriteOverlays(from: state)
        let published = publishedShareableAndAudio()
        if !sidebar.applyLivePageMetadata(state: state, focusedTabID: currentTabID, loading: loadingTabs,
            canBack: navigationCanShowBack,
            canForward: navigationCanShowForward,
            captures: capturePresentations, shareable: published.shareable, audio: published.audio,
            applyShareableAudio: published.changed) {
            return false
        }
        if published.changed {
            rememberAppliedShareableAudio(shareable: published.shareable, audio: published.audio)
        }
        refreshDownloads()
        refreshNavigationControls()
        let tab = store.state.tabs.first { $0.id == currentTabID }
        window?.title = activePeek.map { "\($0.title) — Peek — Parc" } ?? tab.map { "\($0.title) — Parc" } ?? "Parc"
        refreshLoadingIndicators()
        checkPanePresentation()
        return true
    }

    func showInternalPage(_ tab: BrowserTab, in pane: BrowserPane) {
        guard let page = InternalPage(urlString: tab.url) else {
            pane.showError(InternalPage.isRetiredNoteAddress(tab.url)
                ? NoteTabError.retiredAddress.localizedDescription : "This internal address is not supported.")
            return
        }
        if case let .note(url) = page {
            showNote(tab, url: url, in: pane)
            if let file = noteEditors[tab.id]?.editor.file { NoteTabIcons.shared.follow(file) }
            return
        }
        guard let documentID = page.easelID else { return }
        if let cached = easelEditors[tab.id], cached.documentID == documentID, cached.profileID == tab.profileID {
            EaselTabIcons.shared.follow(cached.editor.session)
            pane.showNativeContent(cached.editor.view)
            return
        }
        let destination = tab.profileID.uuidString + ":" + page.urlString
        if let failure = easelFailures[tab.id], failure.destination == destination { pane.showError(failure.message); return }
        do {
            let editor = try EaselEditorViewController(directory: store.easelsDirectory(for: tab.profileID), documentID: documentID)
            easelEditors[tab.id] = EaselPane(documentID: documentID, profileID: tab.profileID, editor: editor, originalTab: tab)
            easelFailures.removeValue(forKey: tab.id)
            pane.showNativeContent(editor.view)
            configureEaselOwner(tab, documentID: documentID, editor: editor)

        } catch {
            easelFailures[tab.id] = (destination, error.localizedDescription)
            pane.showError(error.localizedDescription)
        }
    }

    @discardableResult func configureEaselOwner(_ tab: BrowserTab, documentID: UUID, editor: EaselEditorViewController,
                                                       windowTransfer: EaselBrowserObjects.WindowTransfer? = nil) -> Bool {
            EaselTabIcons.shared.follow(editor.session)
            editor.onTitleChange = { [weak self] title in
                self?.store.updateEaselTitle(id: documentID, profileID: tab.profileID, title: title)
            }
            editor.onKeyboardStructureChange = { [weak self, weak editor] in
                guard let self, let editor, self.easelEditors[tab.id]?.editor === editor,
                      editor.view.window === self.window, !self.isClosing else { return }
                self.windowKeyViews.relink()
            }
            editor.onOpenURL = { [weak self] url in
                guard let self, self.documentTakesInput(tab.id), self.activeProfileID == tab.profileID,
                      self.easelEditors[tab.id]?.documentID == documentID,
                      !self.isClosing, !self.wholeWindowClose,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") || InternalPage(urlString: url.absoluteString) != nil else { return }
                self.openInput(url.absoluteString)
            }
            editor.onOpenNote = { [weak self] url in
                guard let self, self.currentTabID == tab.id, self.activeProfileID == tab.profileID,
                      self.easelEditors[tab.id]?.documentID == documentID,
                      !self.isClosing, !self.wholeWindowClose else { return }
                _ = self.openNote(url: url)
            }
            editor.notesFolder = { NoteFolderPreferences.folder(for: tab.profileID) }
            editor.exportAdmission = { [weak self, weak editor] in
                guard let self, let editor else { return false }
                return self.currentEaselEditor === editor
            }
            configureEaselPageMenu(editor, tab: tab, documentID: documentID)
            if let binding = nativeBinding, !isPrivateBrowsing {
                return editor.configurePages(binding: binding,
                    profilePath: store.independentEngineProfilePath(for: tab.profileID),
                    validOwner: { [weak self, weak editor, weak binding] in
                        guard let self, let editor, let binding,
                              self.easelEditors[tab.id]?.editor === editor,
                              binding === self.nativeBinding, editor.view.window === self.window,
                              let actual = self.store.state.tab(tab.id, where: { $0.archivedAt == nil }),
                              actual.profileID == tab.profileID,
                              InternalPage(urlString: actual.url)?.easelID == documentID,
                              !self.store.isProfileRemovalPending(tab.profileID),
                              !self.transferringTabIDs.contains(tab.id) else { return false }
                        return !self.isClosing && !self.wholeWindowClose && !self.windowCloseApproved
                    }, activeOwner: { [weak self] in
                        guard let self else { return false }
                        return !self.transferringTabIDs.contains(tab.id) && self.documentTakesInput(tab.id) && self.libraryView == nil
                            && self.commandBar == nil && !self.windowClosePending && !self.isClosing
                    }, selectionChanged: { [weak self] in
                        guard let self, !self.isClosing else { return }
                        self.nativeBinding?.synchronizeSelectionAndLayout()
                        self.refreshCaptureIndicators(); self.refreshNavigationControls()
                        self.windowKeyViews.relink()
                    }, metadataChanged: { [weak self] in self?.refreshLivePageChromeOrRender() },
                    contextImage: { [weak self] view, image in self?.browserView(view, addContextImageToEasel: image) },
                    windowTransfer: windowTransfer)
            }
        return windowTransfer == nil
    }

    func applyChromeTheme(_ theme: SpaceTheme) {
        rootView.theme = theme
        sidebarContainer.theme = theme
        sidebar.palette = rootView.palette
        sidebar.plusMenuTheme = rootView.paletteTheme
        commandBar?.theme = rootView.paletteTheme
        commandBar?.contentAppearance = rootView.palette.contentAppearance
        loadedStartPage?.theme = theme
        residentCommandBar?.theme = rootView.paletteTheme
    }
    var windowPaletteTheme: SpaceTheme { rootView.incognito ? IncognitoWindowTheme.paletteTheme : activeSpace.theme }
    var windowBasicBackground: NSColor? { rootView.incognito ? IncognitoWindowTheme.background : nil }

    func refreshWebsiteTheme(enabled: Bool? = nil) {
        guard !isClosing else { return }
        let allowed = (enabled ?? WebsiteThemePreferences.shared.state.isEnabled)
            && !WebsiteThemePreferences.shared.loadError
        guard let binding = nativeBinding else { return }
        let stylesheet = allowed ? rootView.palette.websiteStylesheet(
            theme: rootView.theme, basicBackground: windowBasicBackground) : nil
        let identity = ObjectIdentifier(binding)
        if let last = lastPushedWebsiteTheme,
           last.binding == identity,
           last.stylesheet == stylesheet {
            return
        }
        binding.setWebsiteThemeStylesheet(stylesheet)
        lastPushedWebsiteTheme = (identity, stylesheet)
    }

    var canEditThemeFromMenu: Bool {
        guard let window else { return false }
        if let session = spaceCreation {
            return creationOwnerIsCurrent(session) && !session.committing
                && session.view.themeAnchor.window === window
        }
        guard managementSpace(activeSpaceID) != nil else { return false }
        let manager = libraryView?.kind == .spaces ? librarySpaceManager : nil
        return (manager?.anchor(for: activeSpaceID) ?? sidebar.spaceAppearanceAnchor(activeSpaceID))?.window === window
    }

    func editTheme() {
        if let session = spaceCreation { chooseCreationTheme(session, from: session.view.themeAnchor); return }
        editTheme(spaceID: activeSpaceID)
    }
    func editTheme(spaceID: UUID) {
        guard !isPrivateBrowsing, managementSpace(spaceID) != nil else { return }
        themePopover?.performClose(nil)
        guard !isClosing, let window, let original = managementSpace(spaceID) else { return }
        let profileID = original.profileID
        let manager = libraryView?.kind == .spaces ? librarySpaceManager : nil
        if manager == nil { revealSidebarForEditing() }
        guard let anchor = manager?.anchor(for: spaceID) ?? sidebar.spaceAppearanceAnchor(spaceID), anchor.window === window else { return }
        let editor = makeThemeEditor(theme: original.theme)
        editor.windowThemeUndo = folderUndo
        editor.onPreview = { [weak self, weak editor] theme in
            guard let self, let editor, self.themeEditor === editor,
                  self.store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return }
            self.librarySpaceManager?.previewTheme(theme, spaceID: spaceID)
            guard self.activeSpaceID == spaceID, self.activeProfileID == profileID else { return }
            self.themePreview = (spaceID, theme)
            self.applyChromeTheme(theme)
        }
        editor.onSetAppearance = { [weak self, weak editor] appearance in
            guard let self, let editor, self.themeEditor === editor,
                  self.themeEditingSpaceID == spaceID,
                  self.managementSpace(spaceID, profileID: profileID) != nil, !self.isClosing, self.window?.attachedSheet == nil else { return }
            self.setThemeEditorAppearance(appearance)
        }
        editor.onCommitChange = { [weak self, weak editor] previous, theme in
            guard let self else { return previous }
            let current = self.store.state.spaces.first { $0.id == spaceID && $0.profileID == profileID }?.theme
            guard let editor, self.themeEditor === editor, current != nil,
                  !self.folderUndo.isBusy else { return current ?? previous }
            do {
                if let change = try self.store.saveSpaceTheme(spaceID: spaceID, profileID: profileID,
                                                              previous: previous, theme: theme) {
                    self.folderUndo.appendSpaceThemeChange(change, store: self.store,
                        available: { [weak self] in self?.windowUndoContextAvailable == true },
                        onApplied: { [weak self] in
                            guard let self else { return }
                            self.synchronizeThemeEditor()
                            self.applyChromeTheme(self.activeSpace.theme)
                        }, onError: { [weak self] in self?.showError($0) })
                }
            } catch {
                if (error as NSError).code != CocoaError.userCancelled.rawValue { showError(error) }
            }
            return self.store.state.spaces.first { $0.id == spaceID && $0.profileID == profileID }?.theme ?? previous
        }
        let content = NSViewController(); content.view = editor
        let popover = NSPopover()
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 356, height: 508)
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        editor.onDismiss = { [weak popover] in popover?.performClose(nil) }
        themeEditor = editor; themePopover = popover; themeEditingSpaceID = spaceID; themeEditingProfileID = profileID
        themeEditingContextSpaceID = activeSpaceID
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        editor.window?.makeFirstResponder(editor)
    }

    func makeThemeEditor(theme: SpaceTheme) -> SpaceThemeEditorView {
        let editor = SpaceThemeEditorView(theme: theme, presetPage: themeEditorPresetPage)
        editor.onPresetPageChange = { [weak self] page in self?.themeEditorPresetPage = page }
        editor.onTooltipThemeChange = { [weak editor] theme in
            guard let window = editor?.window else { return }
            TooltipController.controller(for: window).palette = TooltipColorPalette(theme: theme)
        }
        return editor
    }

    func setThemeEditorAppearance(_ appearance: AppAppearance) {
        let previous = AppAppearance.current
        guard AppAppearance.apply(appearance) else { return }
        registerAppearanceUndo(from: previous, to: appearance)
    }

    private func synchronizeThemeEditor() {
        guard let editor = themeEditor, let spaceID = themeEditingSpaceID,
              let profileID = themeEditingProfileID else { return }
        guard let space = store.state.spaces.first(where: { $0.id == spaceID && $0.profileID == profileID }),
              !store.isProfileRemovalPending(profileID) else {
            themePopover?.performClose(nil); return
        }
        if editor.synchronizeTheme(space.theme) { themePreview = nil }
    }

    func popoverWillClose(_ notification: Notification) {
        if let session = spaceCreation, notification.object as? NSPopover === session.themePopover {
            session.themeEditor?.finishEditing()
            session.themeEditor = nil; session.themePopover = nil
            if !session.committing, window?.isKeyWindow == true, window?.attachedSheet == nil {
                session.view.focusName()
            }
            return
        }
        guard notification.object as? NSPopover === themePopover else { return }
        themeEditor?.finishEditing()
        themePreview = nil; themeEditor = nil; themePopover = nil; themeEditingSpaceID = nil; themeEditingProfileID = nil; themeEditingContextSpaceID = nil
        libraryView?.spaceManager.reload(store.state)
        applyChromeTheme(activeSpace.theme)
        refreshSidebarPointerIfKey()
    }
    func refreshSidebarPointerIfKey() {
        if window?.isKeyWindow == true { refreshSidebarPointer() }
    }
    func reloadTab(_ id: UUID) {
        failures.removeValue(forKey: id); easelFailures.removeValue(forKey: id); noteFailures.removeValue(forKey: id)
        if let tab = store.state.tab(id), InternalPage.isInternal(tab.url) {
            if let cached = easelEditors[id] {
                cached.editor.refreshPageVisibility(); render(store.state); return
            }
            panes[id]?.clearNativeContent()
            render(store.state)
        } else if let browser = browsers[id] {
            refreshPagePresentation(id)
            browser.reload()
        }
    }

    func rendererPresentation(_ browser: PCBrowserView) -> RendererCrashPresentation? {
        guard let page = browser.nativePage, !page.isClosed,
              let crash = browser.rendererCrash else { return nil }
        return RendererCrashPresentation(pageIdentifier: page.identifier, identity: crash,
            terminationStatus: crash.terminationStatus, errorCode: crash.errorCode)
    }

    private func currentRendererPresentation(_ id: UUID, _ expected: RendererCrashPresentation,
                                             selected: Bool = false) -> (PCBrowserView, PCNativeRendererCrash)? {
        guard !isClosing, !wholeWindowClose, !closingTabIDs.contains(id),
              !modelRetirementIDs.contains(id), !transferringTabIDs.contains(id),
              ownership.canUse(id, owner: presentationID),
              let browser = browsers[id], let page = browser.nativePage, !page.isClosed,
              page.identifier == expected.pageIdentifier, page.observer === browser,
              let crash = browser.rendererCrash, crash === expected.identity,
              let binding = nativeBinding, PCNativeBrowserApplication.owner(of: page) === binding,
              let window, window.isVisible, !window.isMiniaturized,
              browser.window === window, page.nativeView.window === window,
              page.nativeView.isDescendant(of: browser), attachedPageIDs.contains(page.identifier),
              let pane = panes[id], pane.window === window,
              renderedPaneIDs.contains(id), !pane.isHiddenOrHasHiddenAncestor,
              pane.rendererPresentation == expected,
              !selected || selectedNativePage() === page else { return nil }
        return (browser, crash)
    }

    func refreshPagePresentation(_ id: UUID) {
        defer { checkPanePresentation() }
        guard !isClosing, !wholeWindowClose, !transferringTabIDs.contains(id),
              let browser = browsers[id], let pane = panes[id] else { return }
        let rendererHadFocus = browser.window?.firstResponder as? NSView
        let moveFocusToError = rendererHadFocus.map { $0 === browser || $0.isDescendant(of: browser) } ?? false
        let restorePageFocus = pane.rendererFailureOwnsFocus
        let crash = rendererPresentation(browser)
        if let crash {
            if pane.rendererPresentation != crash { failures.removeValue(forKey: id) }
            pane.showRendererFailure(crash)
        }
        else if let message = failures[id] { pane.showError(message) }
        else { pane.showBrowser() }
        synchronizeNativeLayout()
        guard browsers[id] === browser else { return }
        if let crash, moveFocusToError {
            focusRendererFailure(id, crash)
        } else if crash == nil, restorePageFocus, failures[id] == nil,
                  let page = browser.nativePage, !page.isClosed, page.rendererCrash == nil,
                  selectedNativePage() === page, let binding = nativeBinding,
                  PCNativeBrowserApplication.owner(of: page) === binding,
                  let window, browser.window === window, !browser.isHiddenOrHasHiddenAncestor {
            window.makeFirstResponder(page.nativeView)
        }
    }

    func focusRendererFailure(_ id: UUID, _ expected: RendererCrashPresentation) {
        guard currentRendererPresentation(id, expected, selected: true) != nil else { return }
        panes[id]?.focusRendererFailure(expected)
    }

    func refreshPageHostBacking() {
        let translucentPane = closeFade != nil || splitView.arrangedSubviews.contains {
            guard let pane = $0 as? BrowserPane else { return false }
            return pane.showsNoteCanvas || pane.showsTopBar || pane.showsPlaceholder
        }
        let showsEmpty = splitView.arrangedSubviews.count == 1
            && (splitView.arrangedSubviews.first is SplitPanePlaceholder || splitView.arrangedSubviews.first === loadedStartPage)
        let backing = (splitView.arrangedSubviews.first as? BrowserPane)?.contentBacking ?? .white
        splitView.configureBacking(in: pageHost, hasTranslucentPane: translucentPane || showsEmpty, backing: backing)
        refreshPageShadow()
        refreshSplitPaneHighlights()
    }
    func refreshPageShadow() {
        pageShadow.isHidden = splitView.arrangedSubviews.count > 1 || nativeFullscreenTabID != nil
    }

    func refreshNoteCanvasTheme(_ palette: ThemeChromePalette) {
        for pane in panes.values { pane.inheritNoteCanvasTheme(palette.contentAppearance, focus: palette.focus) }
    }

    func refreshSplitPaneHighlights() {
        let palette = rootView.palette
        let color = palette.isDark ? palette.shaded : palette.shadedDark
        let shown = splitView.arrangedSubviews
        let placeholder = splitInsertion?.placeholder
        let focused: NSView? = commandBar != nil && commandBarCreatesNewTab ? nil
            : placeholder.flatMap { $0.superview === splitView ? $0 : nil } ?? currentTabID.flatMap { panes[$0] }
        let proposedPane: NSView? = splitDropReplacementID.flatMap { renderedPaneIDs.contains($0) ? panes[$0] : nil }
        for view in shown {
            let highlight: SplitPaneHighlight
            if let pane = view as? BrowserPane { highlight = pane.splitHighlight }
            else if let pending = view as? SplitPanePlaceholder { highlight = pending.splitHighlight }
            else { continue }
            let state = SplitPaneHighlightState.resolve(
                isProposedDropTarget: proposedPane != nil && view === proposedPane,
                isFocused: view === focused, paneCount: shown.count, dragEditActive: splitView.isInteractivePaneEditing)
            highlight.color = color
            highlight.layout(bounds: view.bounds, cornerRadius: view.layer?.cornerRadius ?? 0)
            highlight.update(display: state.display, width: state.width)
        }
        for pane in panes.values where !shown.contains(where: { $0 === pane }) {
            pane.splitHighlight.update(display: false, width: 2)
        }
    }

    func setSplitDropProposal(_ target: SplitDropTarget?, selection: [UUID]) {
        if case .replace(let index)? = target, selection.indices.contains(index) {
            splitDropReplacementID = selection[index]
        } else { splitDropReplacementID = nil }
        refreshSplitPaneHighlights()
    }
    func splitPaneEditDidChange(_ active: Bool) {
        if !active { splitDropReplacementID = nil }
        refreshSplitPaneHighlights()
    }
    private func updateSplitArrangement(displayed: [BrowserTab], displayedIDs: [UUID]) {
        var wanted: [NSView] = displayed.map { tab in
            let pane = panes[tab.id] ?? makePane(tab)
            panes[tab.id] = pane
            return pane
        }
        if let draft = splitInsertion, draft.isValid {
            let index = min(max(0, draft.request.index), wanted.count)
            wanted.insert(draft.placeholder, at: index)
        }
        if wanted.isEmpty {
            if spaceCreation != nil {
                wanted = [LayoutView()]
            } else {
                wanted = [startPage]
            }
        }
        let previous = splitView.arrangedSubviews
        let leaving = splitView.reconcileArrangedSubviews(wanted)
        for view in leaving where !(view is BrowserPane) {
            if view === loadedStartPage { playStartPageDeparture() } else { view.removeFromSuperview() }
        }
        let arriving = wanted.filter { view in !previous.contains { $0 === view } }.compactMap { $0 as? BrowserPane }
        let drawing = displayed.compactMap { tab in drawsReportedFrame(tab) ? panes[tab.id] : nil }
        let leavingPanes = leaving.compactMap { $0 as? BrowserPane }
        let hold = switchHold.hold
        let parking = switchHold.rearrange(leaving: leavingPanes, arriving: arriving, drawing: drawing,
                                           canHold: canHoldPageSwitch, now: ProcessInfo.processInfo.systemUptime)
        for case let pane as BrowserPane in wanted { pane.heldOverSwitch = false }
        retirePages(leavingPanes)
        for pane in switchHold.held { pane.heldOverSwitch = true }
        parkPanes(parking)
        if switchHold.isHolding {
            if let binding = nativeBinding {
                for pane in switchHold.waiting {
                    if let page = pane.browser?.nativePage { binding.reportNextFrame(of: page) }
                }
            }
            if switchHold.hold != hold { scheduleSwitchHoldCap() }
        }
        for (id, pane) in panes {
            pane.contentResize.mode = displayedIDs.contains(id) ? contentResizeReasons.mode : .intrinsic
        }
        renderedPaneIDs = displayedIDs
        renderedSplitInsertionID = splitInsertion?.id
        renderedSpaceCreationID = spaceCreation?.draft.spaceID
    }
    func makePane(_ tab: BrowserTab) -> BrowserPane {
        let pane = BrowserPane()
        pane.inheritNoteCanvasTheme(rootView.palette.contentAppearance, focus: rootView.palette.focus)
        pane.onContentBackingChange = { [weak self] in self?.refreshPageHostBacking() }
        pane.onReload = { [weak self] in self?.reloadTab(tab.id) }
        pane.onRendererPresented = { [weak self] expected in
            guard let self, let (browser, crash) = self.currentRendererPresentation(tab.id, expected) else { return false }
            return browser.rendererCrashDidPresent(crash)
        }
        pane.onRetryRenderer = { [weak self] expected in
            guard let self, let (browser, crash) = self.currentRendererPresentation(tab.id, expected) else { return }
            _ = browser.performRendererCrashAction(crash)
        }
        return pane
    }
}
