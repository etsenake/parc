import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func configureSidebarPreviews() {
        guard !isPrivateBrowsing, let window else { return }
        let previews = SidebarPreviewController(sidebar: sidebar, host: rootView, window: window)
        sidebarPreviews = previews
        previews.permitted = { [weak self] in
            guard let self, let window = self.window else { return false }
            return self.presentation.isReady && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.isPopupWindow && self.libraryView == nil && self.nativeFullscreenTabID == nil
                && self.sidebarPresentation != .hidden && !self.sidebarMotion.isAnimating && !self.isSidebarResizing
                && self.commandBar == nil && self.themePopover == nil && !self.siteControlCenterDefers && self.tabSwitcher == nil
                && self.transferringTabIDs.isEmpty && self.resolvingTransfers.isEmpty
                && (self.activePeek?.modalPhase ?? .presented) == .presented
                && PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
        }
        previews.source = { [weak self] target in self?.sidebarPreviewSource(target) }
        previews.onPresentationChange = { [weak self] in self?.refreshSidebarPointer() }
        previews.openSettings = { [weak self] in
            guard let self else { return }
            self.showSettings(pane: .general)
            self.settings?.showPreviewSettings()
        }
        previews.perform = { [weak self] source, row, action in self?.performSidebarPreview(source, row: row, action: action) }
        previews.offers = { [weak self] source, row, action in
            guard let self, action == .peek, let id = row.tabID, source.rows.contains(row),
                  self.sidebarPreviewSource(source.target) == source else { return false }
            return self.offersTabInPeek(id)
        }
        previews.requestRecent = { [weak self] domain, profileID, completion in
            guard let self, self.activeProfileID == profileID, !self.isClosing else { return nil }
            let path = self.store.independentEngineProfilePath(for: profileID)
            guard let query = PCNativeBrowserApplication.recentPages(forDomain: domain.rawValue, profilePath: path, completion: { pages in
                MainActor.assumeIsolated {
                    completion(pages.map { SidebarPreviewRow(id: $0.url.absoluteString, tabID: nil,
                        title: $0.title, url: $0.url, visitedAt: $0.visitedAt) })
                }
            }) else { return nil }
            return { query.invalidate() }
        }
        previews.requestPicture = { [weak self] id, deliver in
            guard let self, let window = self.window, let page = self.browsers[id]?.nativePage, !page.isClosed,
                  let lease = page.observePreview(in: window, handler: deliver) else { return nil }
            return { lease.invalidate() }
        }
        previews.requestDocument = { [weak self] source, kind, deliver in
            guard let self, let window = self.window, self.activeProfileID == source.profileID, !self.isClosing else { return nil }
            let profileID = source.profileID
            let lease = SidebarDocumentThumbnails.shared.observe(kind, title: source.title,
                appearance: self.rootView.palette.contentAppearance ?? window.effectiveAppearance,
                easels: { [weak self] in
                    guard let self else { throw EaselStoreError.missingDocument }
                    return try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID))
                },
                noteEasels: { [weak self] url in
                    guard let editor = self?.noteEditors.values.first(where: { NoteFilePaths.sameItem($0.url, url) })?.editor.editor else { return nil }
                    return NoteEaselHost.host(for: editor)
                }, deliver: deliver)
            return { lease.invalidate() }
        }
        previews.favicon = { [weak self] url, profileID, completion in
            guard let self, self.activeProfileID == profileID, !self.isClosing else { return }
            switch SidebarDocumentKind(url: url) {
            case .note(let file)?:
                NoteTabIconArt.shared.requestImage(forNote: file, completion: completion); return
            case .easel(let id)?:
                NoteTabIconArt.shared.requestImage(for: .easel(directory: self.store.easelsDirectory(for: profileID), id: id), completion: completion); return
            case nil: break
            }
            PCNativeBrowserApplication.favicon(for: url, profilePath: self.store.independentEngineProfilePath(for: profileID)) { image in
                MainActor.assumeIsolated { completion(image) }
            }
        }
        sidebar.onPreview = { [weak previews] target in previews?.showFromKeyboard(target) }
        sidebar.onPreviewPreferencesChanged = { [weak self] in
            guard let self else { return }
            self.sidebarPreviews?.dismiss(); self.render(self.store.state)
        }
    }

    private func sidebarPreviewSource(_ target: SidebarPreviewTarget) -> SidebarPreviewSource? {
        guard !isClosing, presentation.isReady, !wholeWindowClose else { return nil }
        let profileID = activeProfileID
        switch target {
        case .tab(let id):
            guard let tab = visibleTabs.first(where: { $0.id == id }), tab.profileID == profileID,
                  !store.retiringTabIDs.contains(id), !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
                  ownership.canUse(id, owner: presentationID), let url = URL(string: tab.url) else { return nil }
            if SidebarPreviewPreference.recentPages.isEnabled, let domain = SidebarRecentDomain.matching(url) {
                return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                    selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: domain.title, domain: domain, originalURL: url, rows: [])
            }
            guard SidebarPreviewPreference.tabPictures.isEnabled, !selectedTabIDs.contains(id) else { return nil }
            let title = SidebarPreviewRow.folderTitle(custom: tab.customTitle, url: url, title: tab.title)
            if let document = SidebarDocumentKind(url: url) {
                return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                    selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: title,
                    domain: nil, originalURL: url,
                    rows: [SidebarPreviewRow(id: id.uuidString, tabID: id, title: title, url: url, visitedAt: nil)], document: document)
            }
            guard let page = browsers[id]?.nativePage, !page.isClosed else { return nil }
            return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: title,
                domain: nil, originalURL: url,
                rows: [SidebarPreviewRow(id: id.uuidString, tabID: id, title: title, url: url, visitedAt: nil)])
        case .folder(let id):
            guard SidebarPreviewPreference.folders.isEnabled,
                  let folder = store.state.folders.first(where: { $0.id == id && $0.spaceID == activeSpaceID }) else { return nil }
            let orderedIDs = SidebarHierarchy.tabIDs(in: .folder(id), state: store.state, spaceID: activeSpaceID)
            let rows = orderedIDs.compactMap { tabID -> SidebarPreviewRow? in
                guard let tab = store.state.tab(tabID) else { return nil }
                guard tab.archivedAt == nil, tab.spaceID == activeSpaceID, tab.profileID == profileID,
                      tab.kind != .favorite, !store.retiringTabIDs.contains(tab.id), !closingTabIDs.contains(tab.id),
                      !transferringTabIDs.contains(tab.id),
                      let url = URL(string: tab.url) else { return nil }
                return SidebarPreviewRow(id: tab.id.uuidString, tabID: tab.id,
                    title: SidebarPreviewRow.folderTitle(custom: tab.customTitle, url: url, title: tab.title),
                    url: url, visitedAt: tab.lastAccessed)
            }
            return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: folder.name,
                domain: nil, originalURL: nil, rows: SidebarPreviewRow.newestFirst(rows))
        }
    }

    private func performSidebarPreview(_ source: SidebarPreviewSource, row: SidebarPreviewRow, action: SidebarPreviewAction) {
        guard activeProfileID == source.profileID, activeSpaceID == source.spaceID,
              sidebarPreviewSource(source.target) == source, !isClosing, !wholeWindowClose else { return }
        if let id = row.tabID {
            guard source.rows.contains(row), let tab = visibleTabs.first(where: { $0.id == id }),
                  tab.profileID == source.profileID, tab.url == row.url.absoluteString,
                  !store.retiringTabIDs.contains(id) else { return }
            switch action {
            case .activate(let modifiers):
                switch SidebarPreviewActivation.folderItem(modifiers) {
                case .selectOriginal(let split):
                    revealPreviewTab(id)
                    if !split || !insertPreviewSplit(tabID: id) { selectTab(id) }
                case .duplicate:
                    guard !SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).contains(where: { $0.tabIDs.contains(id) }) else { return }
                    _ = prepareSidebarDuplicate([.tab(id)])?()
                case .reveal:
                    if revealPreviewTab(id) { render(store.state) }
                case .excludedMiniWindow, .navigateSource, .openNewTab: break
                }
            case .split: openTabInSplitView(id)
            case .archive:
                closeTabsWithReopen(Set([id]), reason: .manual)
            case .duplicate:
                guard !SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).contains(where: { $0.tabIDs.contains(id) }) else { return }
                _ = prepareSidebarDuplicate([.tab(id)])?()
            case .peek: openTabInPeek(id)
            case .copyURL, .copyIssueID, .create: break
            }
        } else {
            guard let domain = source.domain, case .tab(let sourceID) = source.target,
                  let sourceTab = visibleTabs.first(where: { $0.id == sourceID }),
                  let activation = action.activation(for: row) else { return }
            switch action {
            case .create: guard row.url == domain.createURL else { return }
            case .activate: guard SidebarRecentDomain.matching(row.url) == domain else { return }
            case .split, .duplicate, .archive, .copyURL, .copyIssueID, .peek: return
            }
            openRecentPreviewURL(row.url, from: sourceTab, activation: activation)
        }
    }

    private func openRecentPreviewURL(_ url: URL, from sourceTab: BrowserTab, activation: SidebarPreviewActivation) {
        func openNewTab(split: Bool) {
            let creation = TabCreationProvenance(referrerID: sourceTab.id, activeTabID: currentTabID,
                                                 profileID: activeProfileID, state: store.state)
            if split, insertPreviewSplit(url: url, creation: creation) { return }
            performWindowCommand {
                let id = store.openResolvedURL(url, creation: creation)
                presentation.recordCreation(id, state: store.state)
            }
        }
        switch activation {
        case .openNewTab(let split): openNewTab(split: split)
        case .navigateSource(let split):
            let page = browsers[sourceTab.id]?.nativePage
            let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs.contains(sourceTab.id) }
            let route = SidebarPreviewSourceRoute.route(to: url, isSavedItem: sourceTab.kind == .pinned || sourceTab.kind == .favorite,
                inSplit: group != nil, currentHost: page?.url?.host ?? URL(string: sourceTab.url)?.host,
                savedHost: URL(string: sourceTab.savedURL)?.host, authenticationUnlocked: page?.authenticationFlowUnlocked == true)
            guard route == .inPlace else { openNewTab(split: split); return }
            guard canPerformSidebarTabAction(sourceTab, closing: false),
                  let elsewhere = PageReparenting.pagesToMove(group?.tabIDs ?? [sourceTab.id],
                      usableHere: switcherCanUse, movable: canMovePageHere) else { return }
            if !elsewhere.isEmpty {
                _ = movePagesHere(elsewhere[...]) { [weak self] in
                    self?.openRecentPreviewURL(url, from: sourceTab, activation: activation); return self != nil
                }
                return
            }
            requestedURLs.removeValue(forKey: sourceTab.id)
            performWindowCommand(selectNativePage: false) { store.updateTab(sourceTab.id, url: url.absoluteString) }
            selectTab(sourceTab.id)
        case .selectOriginal, .duplicate, .reveal, .excludedMiniWindow: break
        }
    }

    @discardableResult
    func openTabInSplitView(_ id: UUID) -> Bool { selectTab(id, extendingSplit: true) }

    @discardableResult
    private func revealPreviewTab(_ id: UUID) -> Bool {
        guard !store.isEphemeral, window != nil else { return false }
        let item = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs.contains(id) }
            .map { SidebarItemReference.split($0.id) } ?? .tab(id)
        guard let reveal = SidebarItemReveal(item: item, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) else { return false }
        do { return try store.revealSidebarItem(reveal) }
        catch { showError(error); return false }
    }

    func insertPreviewSplit(tabID existing: UUID? = nil, url: URL? = nil, creation: TabCreationProvenance? = nil,
                                    after anchor: UUID? = nil) -> Bool {
        let selection = selectedTabIDs, id = existing ?? UUID()
        guard splitCommandsAvailable, splitInsertion == nil, !isPopupWindow,
              nativeFullscreenTabID == nil, let focus = anchor ?? currentTabID, selection.allSatisfy({ switcherCanUse($0) }),
              selection.contains(id) || selection.count < 4, existing != nil || url != nil else { return false }
        if let existing {
            guard switcherCanUse(existing), transferRecoveries[existing] == nil,
                  visibleTabs.contains(where: { $0.id == existing }) else { return false }
        }
        var inserted = false
        performWindowCommand(selectNativePage: false) {
            inserted = store.insertCommandBarSplit(after: focus, expectedSelection: selection, tabID: id,
                newURL: existing == nil ? url : nil, creation: creation)
            if inserted && existing == nil { presentation.recordCreation(id, state: store.state) }
        }
        guard inserted, selectedTabIDs.contains(id) else { return false }
        focusedTabID = id
        render(store.state); requestNativeSelection(); focusSelectedLocalContent()
        return true
    }

    func joinOriginalSplitPage(_ id: UUID, page: PCNativePage, source: PCNativePage,
                                       browser: PCNativeBrowserWindow, lease: SplitLinkLease) -> Bool {
        guard switcherCanUse(id), browsers[id]?.nativePage === page,
              nativeBrowser(browser, isSplitLinkLeaseCurrent: lease, for: source) else { return false }
        let selection = lease.snapshot.selection, focused = lease.snapshot.focusedID
        var inserted = false
        performWindowCommand(selectNativePage: false) {
            guard let homes = store.commandBarSplitHomes(after: focused, expectedSelection: selection,
                    tabID: id, isNew: false), let plan = splitHomePlan(homes),
                  page.splitLinkLease as? SplitLinkLease === lease, page.creationSourcePage === source,
                  browsers[id]?.nativePage === page,
                  nativeBrowser(browser, isSplitLinkLeaseCurrent: lease, for: source) else { return }
            inserted = store.insertCommandBarSplit(after: focused, expectedSelection: selection, tabID: id,
                savedHomeIDs: plan.ids, documents: plan.documents)
        }
        guard inserted, selectedTabIDs.contains(id) else { return false }
        focusedTabID = id
        render(store.state); requestNativeSelection(); focusSelectedLocalContent()
        return true
    }

    func wireSidebar() {
        sidebar.onAddress = { [weak self] in
            guard let self else { return }; self.focusAddress(anchor: self.sidebar.addressEditorAnchor)
        }
        sidebar.onNewTab = { [weak self] in self?.newTab() }
        sidebar.onNavigation = { [weak self] kind in self?.prepareNavigationInteraction(kind) }
        sidebar.onReloadOptions = { [weak self] anchor in self?.showReloadOptions(from: anchor) }
        sidebar.onSettings = { [weak self] in self?.showSettings() }
        sidebar.onBannerRelinquishFocus = { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(nil)
            guard !self.isClosing, !self.wholeWindowClose, window.isKeyWindow,
                  window.attachedSheet == nil, self.commandBar == nil,
                  self.libraryView == nil else { return }
            if self.currentTabID == nil { self.sidebar.focusIfPresented() }
            else { self.focusSelectedContent() }
        }
        sidebar.onLibrary = { [weak self] page in self?.showLibraryFromEntry(page) }
        sidebar.onLibraryItem = { [weak self] action in self?.performLibraryFlyout(action) ?? false }
        sidebar.libraryDownloadFileURL = { [weak self] item in self?.libraryDownloadFileURL(item) }
        sidebar.onLibraryHover = { LibraryFolderPrompts.shared.ask() }
        sidebar.onToggle = { [weak self] in self?.toggleSidebar() }
        sidebar.onNewSpace = { [weak self] in self?.createSpace() }
        sidebar.prepareSidebarNewSpace = { [weak self] items in self?.prepareSidebarNewSpace(items) }
        sidebar.prepareTurnFolderIntoSpace = { [weak self] id in self?.prepareTurnFolderIntoSpace(id) }
        sidebar.onEditTheme = { [weak self] in self?.editTheme() }
        sidebar.onNewFolder = { [weak self] in self?.createFolder() }
        sidebar.onNewEasel = { [weak self] in self?.createEaselFromPlusMenu() }
        sidebar.onNewNote = { [weak self] in self?.createNote() }
        sidebar.onOpenNoteFiles = { [weak self] files, placement in self?.openDroppedNoteFiles(files, placement: placement) ?? false }
        sidebar.onNewSplit = { [weak self] in self?.toggleSplit() }
        sidebar.plusMenuCanCreateEasel = { [weak self] in self?.canCreateNote ?? false }
        sidebar.plusMenuCanCreateNote = { [weak self] in self?.canCreateNote ?? false }
        sidebar.plusMenuCanSplit = { [weak self] in
            guard let self, !self.isPopupWindow, self.splitInsertion == nil else { return false }
            return self.splitCommandIsAvailable(.add(.addAfter))
        }
        sidebar.onSelectTab = { [weak self] id in self?.selectTab(id) }
        sidebar.onCloseTab = { [weak self] id in _ = self?.closeTab(id) }
        sidebar.prepareResetTab = { [weak self] tab in self?.prepareSavedTabReset(tab) }
        sidebar.prepareIconReset = { [weak self] tab, separating in self?.prepareSavedTabIconReset(tab, separating: separating) }
        sidebar.requestTabFavicon = { [weak self] tab, completion in self?.requestSidebarFavicon(tab, completion: completion) }
        sidebar.requestSavedFavicon = { [weak self] tab, completion in self?.requestSidebarSavedFavicon(tab, completion: completion) }
        sidebar.prepareTabMute = { [weak self] tab, audio in self?.prepareSidebarTabMute(tab, audio: audio) }
        sidebar.prepareTabActivation = { [weak self] tab in self?.prepareSidebarTabAction(tab, closing: false) }
        sidebar.prepareTabClose = { [weak self] tab in self?.prepareSidebarTabAction(tab, closing: true) }
        sidebar.prepareTabRename = { [weak self] tab in self?.prepareSidebarTitleEdit(tab) }
        sidebar.prepareSplitRename = { [weak self] target in self?.prepareSidebarSplitTitleEdit(target) }
        sidebar.revealForEditing = { [weak self] in self?.revealSidebarForEditing() }
        sidebar.prepareFavoriteSplitRename = { [weak self] in self?.prepareFavoriteSplitRename($0) }
        sidebar.prepareSplitAppearance = { [weak self] in self?.prepareSplitAppearance($0, reset: $1) }
        sidebar.onTitleEditFinished = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosing else { return }
                self.render(self.store.state)
                self.refreshSidebarPointer()
            }
        }
        sidebar.onOutlineInvalidated = { [weak self] in
            guard let self, !self.isClosing else { return }
            self.render(self.store.state)
            self.refreshSidebarPointer()
        }
        sidebar.prepareFavoriteRename = { [weak self] tab in self?.prepareFavoriteRename(tab) }
        sidebar.prepareFavoritePointerAction = { [weak self] tab, intent in
            self?.prepareFavoritePointerAction(tab, intent: intent)
        }
        sidebar.prepareFavoriteActivation = { [weak self] tab in self?.prepareFavoriteActivation(tab) }
        sidebar.prepareFavoriteClose = { [weak self] tab in self?.prepareFavoriteAction(tab, closing: true) }
        sidebar.dismissFavoritesEmptyState = { [weak self] profileID in self?.store.dismissFavoritesEmptyState(profileID: profileID) }
        sidebar.toggleSpaceHeaderOnSingleUnnamedSpaces = { [weak self] in self?.store.toggleSpaceHeaderOnSingleUnnamedSpaces() }
        sidebar.onArchiveTabs = { [weak self] anchor, order, ids in
            self?.archiveTodayTabs(anchor: anchor, order: order, ids: ids)
        }
        sidebar.prepareSeparateSplitTab = { [weak self] id in self?.prepareSeparateSplitTab(id) }
        sidebar.prepareWindowDrop = { [weak self] session, location, before in
            self?.prepareSidebarWindowDrop(session, to: location, before: before)
        }
        sidebar.prepareCopyDrop = { [weak self] session, items, location, before in
            self?.prepareSidebarCopyDrop(session, items: items, to: location, before: before)
        }
        sidebar.prepareDockDrop = { [weak self] session, items, location, before in
            self?.prepareSidebarDockDrop(session, items: items, to: location, before: before)
        }
        sidebar.onBeginSplitDrag = { [weak self] id in self?.beginSidebarSplitDrag(id) }
        sidebar.onSplitTab = { [weak self] id in self?.selectTab(id, extendingSplit: true) }
        sidebar.prepareSidebarSpaceMove = { [weak self] items, space in self?.prepareSidebarSpaceMove(items, to: space) }
        sidebar.prepareSidebarMove = { [weak self] item in self?.prepareSidebarMove(item) }
        sidebar.prepareSidebarMoves = { [weak self] items in self?.prepareSidebarMoves(items) }
        sidebar.canSelectItems = { [weak self] in
            guard let self else { return false }
            return self.spaceCommandsAvailable && self.commandBar == nil && self.libraryView == nil
        }
        sidebar.prepareSidebarCopy = { [weak self] items, format in
            guard let self, let lease = self.prepareSidebarMoves(items),
                  let links = FolderLinks.links(in: self.store.state, items: items,
                    spaceID: self.activeSpaceID, profileID: self.activeProfileID), !links.isEmpty else { return nil }
            let spaceID = self.activeSpaceID, profileID = self.activeProfileID
            return { [weak self] in
                guard let self, lease.isValid,
                      let current = FolderLinks.links(in: self.store.state, items: items, spaceID: spaceID, profileID: profileID),
                      !current.isEmpty else { return false }
                self.copyLinkOperation = UUID()
                let copied = LinkPasteboard.write(current, format: format)
                if copied { self.showToast(.copiedLinks(current.compactMap { URL(string: $0.url) })) }
                return copied
            }
        }
        sidebar.holdsOnlyEmptyFolders = { [weak self] items in
            guard let self else { return false }
            return SidebarKeyboardCloseTarget(items: items, spaceID: self.activeSpaceID,
                profileID: self.activeProfileID, state: self.store.state)?.holdsOnlyEmptyFolders == true
        }
        sidebar.prepareSidebarClose = { [weak self] items in
            guard let self, let current = self.sidebar.itemSelectionValidator(items),
                  let target = SidebarKeyboardCloseTarget(items: items, spaceID: self.activeSpaceID,
                      profileID: self.activeProfileID, state: self.store.state) else { return nil }
            return self.prepareSidebarRootsClose(items, archive: target.archivesItems,
                requiresConfirmation: target.requiresConfirmation, isSelectionCommand: true, selectionIsCurrent: current)
        }
        sidebar.prepareSplitClose = { [weak self] id in
            guard let self, let action = self.splitCellCloseAction(id) else { return nil }
            return self.prepareSidebarRootsClose([.split(id)], archive: action == .close, requiresConfirmation: false,
                                                 isSelectionCommand: false, selectionIsCurrent: { true })
        }
        sidebar.canCloseSplit = { [weak self] id in self?.splitCellCloseAvailable(id) ?? false }
        sidebar.prepareSplitCellCommand = { [weak self] id, command in self?.prepareSplitCellCommand(id, command) }
        sidebar.prepareSplitCellClose = { [weak self] id, archive in
            self?.prepareSidebarRootsClose([.split(id)], archive: archive, requiresConfirmation: false,
                                           isSelectionCommand: false, selectionIsCurrent: { true })
        }
        sidebar.hasPresentedContent = { [weak self] id in self?.hasPresentedContent(id) ?? false }

        sidebar.canSelectSpace = { [weak self] id, profile in self?.canSelectSpace(id, profileID: profile) ?? false }
        sidebar.onSelectSpace = { [weak self] id, profile in _ = self?.selectSpaceFromUser(id, profileID: profile) }
        sidebar.onPagingTheme = { [weak self] transition in
            self?.rootView.pagingTransition = transition; self?.sidebarContainer.pagingTransition = transition
            self?.loadedStartPage?.pagingTransition = transition
        }
        sidebar.onToggleFolder = { [weak self] id in self?.store.toggleFolder(id) }
        sidebar.onCopyFolderLinks = { [weak self] target, format in
            self?.copyFolderLinks(target, format: format)
        }
        sidebar.onRenameFolder = { [weak self] id in self?.renameFolder(id) }
        sidebar.prepareFolderRename = { [weak self] folder in self?.prepareFolderInlineRename(folder) }
        sidebar.prepareFolderFromSelection = { [weak self] items in self?.prepareFolderFromItems(items) }
        sidebar.prepareFolderIcon = { [weak self] folder in self?.prepareFolderIconChange(folder) }
        sidebar.prepareSidebarDeletion = { [weak self] items in
            guard let self, let current = self.sidebar.itemSelectionValidator(items) else { return nil }
            return self.prepareSidebarDeletion(items, isSelectionCommand: true, selectionIsCurrent: current)
        }
        sidebar.prepareFolderDeletion = { [weak self] id in self?.prepareFolderDeletion(id) }
        sidebar.prepareFolderDuplicate = { [weak self] id in self?.prepareFolderDuplicate(id) }
        sidebar.prepareSidebarDuplicate = { [weak self] items in self?.prepareSidebarDuplicate(items) }
        sidebar.onNewSubfolder = { [weak self] id in self?.createFolder(parentID: id) }
        sidebar.onRenameSpace = { [weak self] id in self?.renameSpace(id) }
        sidebar.makeSpaceManagementMenu = { [weak self] id in self?.spaceManagementMenu(id) }
        sidebar.onChangeSpaceIcon = { [weak self] id in self?.changeSpaceIcon(id) }
        sidebar.onClearToday = { [weak self] in self?.clearToday() }
        sidebar.onPageMenu = { [weak self] in self?.showSiteControlCenter() }
        sidebar.onFolderPeeksChange = { [weak self] peeks in
            guard let self, !self.isPopupWindow else { return }
            self.savedFolderPeeks = peeks
            self.onSessionRecordChange?()
        }
        sidebar.onPageActionsMenu = { [weak self] in self?.showPageMenu() }
        sidebar.onPaymentMenu = { [weak self] anchor in self?.showPaymentControls(anchor: anchor) }
    }

    private func requestSidebarFavicon(_ expected: BrowserTab, completion: @escaping (NSImage?) -> Void) {
        let spaceID = activeSpaceID
        func current() -> Bool {
            !isClosing && !wholeWindowClose && presentation.isReady && activeSpaceID == spaceID
                && activeProfileID == expected.profileID && expected.archivedAt == nil
                && sidebarFaviconTabMatches(expected) && isSidebarFaviconTabVisible(expected.id)
                && !store.isProfileRemovalPending(expected.profileID) && !store.retiringTabIDs.contains(expected.id)
                && !closingTabIDs.contains(expected.id) && !transferringTabIDs.contains(expected.id)
                && !resolvingTransfers.contains(expected.id) && transferRecoveries[expected.id] == nil
        }
        guard current(), InternalPage(urlString: expected.url) == nil else { completion(nil); return }
        if let browser = browsers[expected.id] {
            guard browserProfiles[expected.id] == expected.profileID,
                  ownership.canUse(expected.id, owner: presentationID),
                  let page = browser.nativePage, !page.isClosed, page.url?.absoluteString == expected.url else { completion(nil); return }
            completion(page.favicon)
            return
        }
        guard mayReadCachedFavicons, let url = URL(string: expected.url) else { completion(nil); return }
        PCNativeBrowserApplication.favicon(for: url,
            profilePath: store.independentEngineProfilePath(for: expected.profileID)) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, !self.isClosing, !self.wholeWindowClose,
                      self.activeSpaceID == spaceID, self.activeProfileID == expected.profileID,
                      self.sidebarFaviconTabMatches(expected), self.browsers[expected.id] == nil,
                      !self.store.isProfileRemovalPending(expected.profileID), !self.store.retiringTabIDs.contains(expected.id),
                      !self.closingTabIDs.contains(expected.id), !self.transferringTabIDs.contains(expected.id),
                      !self.resolvingTransfers.contains(expected.id), self.transferRecoveries[expected.id] == nil else { return }
                completion(image)
            }
        }
    }
    private func requestSidebarSavedFavicon(_ expected: BrowserTab, completion: @escaping (NSImage?) -> Void) {
        let spaceID = activeSpaceID
        guard sidebarSavedFaviconIsCurrent(expected, spaceID: spaceID), mayReadCachedFavicons,
              let destination = expected.resetDestination else { completion(nil); return }
        PCNativeBrowserApplication.favicon(for: destination,
            profilePath: store.independentEngineProfilePath(for: expected.profileID)) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, self.sidebarSavedFaviconIsCurrent(expected, spaceID: spaceID) else { return }
                completion(image)
            }
        }
    }
    var mayReadCachedFavicons: Bool {
        guard !store.isEphemeral, let binding = nativeBinding, !binding.isPrivateBrowsing else { return false }
        return binding.browsingContextKind == .regular || binding.browsingContextKind == .unavailable
    }
    private func isSidebarFaviconTabVisible(_ id: UUID) -> Bool {
        let spaceID = activeSpaceID, profileID = activeProfileID
        return store.state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == profileID
            && ($0.kind == .favorite || $0.spaceID == spaceID) })
    }
    private func sidebarFaviconTabMatches(_ expected: BrowserTab) -> Bool {
        store.state.containsTab(expected.id, where: { $0.url == expected.url && $0.profileID == expected.profileID
                && $0.archivedAt == nil })
    }
    private func sidebarSavedFaviconIsCurrent(_ expected: BrowserTab, spaceID: UUID) -> Bool {
        !isClosing && !wholeWindowClose && presentation.isReady && activeSpaceID == spaceID
            && activeProfileID == expected.profileID && sidebarFaviconTabMatches(expected)
            && isSidebarFaviconTabVisible(expected.id)
            && !store.isProfileRemovalPending(expected.profileID) && !store.retiringTabIDs.contains(expected.id)
            && !closingTabIDs.contains(expected.id) && !transferringTabIDs.contains(expected.id)
            && !resolvingTransfers.contains(expected.id) && transferRecoveries[expected.id] == nil
    }

    func refreshSidebarBanners() {
        let presentable = !isPrivateBrowsing && !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose
        let mayActOnReady: () -> Bool = { [weak self] in
            guard let self else { return false }
            return Self.updateReadyToInstall && !self.isClosing && !self.wholeWindowClose
                && self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
        }
        sidebar.onRestartAndUpdate = { guard mayActOnReady() else { return }; SoftwareUpdater.shared.installAndRelaunch() }
        sidebar.onToggleAutomaticUpdates = { [weak self] in
            guard mayActOnReady() else { return }
            SoftwareUpdater.shared.automaticallyInstallsUpdates.toggle()
            self?.refreshSidebarBanners()
        }
        let ready = presentable && Self.updateReadyToInstall
        sidebar.showUpdateReady(ready, automaticUpdates: ready ? SoftwareUpdater.shared.automaticallyInstallsUpdates : nil)

        let updateComplete = SoftwareUpdateBanner.shared
        let completeVisible = presentable && updateComplete.showsCompletedUpdate && !Self.updateReadyToInstall
        if completeVisible && sidebarPresentation != .hidden && libraryView == nil && nativeFullscreenTabID == nil {
            updateComplete.markCompletedUpdateShown()
        }
        let mayActOnUpdate: () -> Bool = { [weak self] in
            guard let self else { return false }
            return updateComplete.showsCompletedUpdate && !self.isClosing && !self.wholeWindowClose
                && self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
        }
        sidebar.onSeeWhatsNew = { [weak self] in
            guard mayActOnUpdate(), let self, self.canOpenPageInNewTab, self.windowCommandSecurityAvailable else { return }
            self.openReleaseNotes(fragment: updateComplete.completedUpdateFragment)
            updateComplete.retireCompletedUpdate()
        }
        sidebar.onDismissUpdateComplete = { guard mayActOnUpdate() else { return }; updateComplete.retireCompletedUpdate() }
        sidebar.showUpdateComplete(completeVisible)

        let visible = store.autoArchiveEducationPending && !updateComplete.showsCompletedUpdate
            && !Self.updateReadyToInstall && presentable
        let originalSpace = activeSpaceID, originalProfile = activeProfileID
        let mayAct: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.store.autoArchiveEducationPending && !self.isClosing && !self.wholeWindowClose
                && !self.isPrivateBrowsing && !self.isPopupWindow && self.spaceCreation == nil
                && self.activeSpaceID == originalSpace && self.activeProfileID == originalProfile
                && self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
        }
        sidebar.onDismissAutoArchiveEducation = { [weak self] in
            guard mayAct(), let self else { return }
            self.store.dismissAutoArchiveEducation()
            self.refreshSidebarBanners()
        }
        sidebar.onAutoArchiveEducationSettings = { [weak self] in
            guard mayAct(), let self else { return }
            self.showSettings(pane: .spaces)
            guard self.settings?.showAutoArchiveSettings(spaceID: originalSpace) == true else { return }
            self.store.dismissAutoArchiveEducation()
            self.refreshSidebarBanners()
        }
        sidebar.showAutoArchiveEducation(visible)
    }

    func setSidebarPresentation(_ requested: SidebarPresentation, allowsMotion: Bool = true) {
        var presentation = PendingSplitPaneSidebarRule.presentation(for: requested, pendingPane: pendingPaneHoldsSidebar)
        if sidebarResize != nil { sidebarResizeRegion.cancelInteraction() }
        if presentation == .hidden, spaceCreation != nil {
            cancelSpaceCreation(restoreFocus: false)
            presentation = PendingSplitPaneSidebarRule.presentation(for: requested, pendingPane: pendingPaneHoldsSidebar)
        }
        if presentation == .hidden {
            SidebarPlusMenuController.dismiss(in: window)
            if let open = siteControlCenter, !open.isDetached, open.isAnchored(to: sidebar.pageControlsAnchor) {
                dismissSiteControlCenter()
            }
        }
        navigationHistory?.dismiss()
        sidebarPreviews?.dismiss()
        guard !isPopupWindow, !isClosing, libraryView == nil, nativeFullscreenTabID == nil else { return }
        if presentation == .floating { sidebarHoverActive = true }
        guard sidebarPresentation != presentation else { return }
        if presentation == .hidden, commandBar?.isSidebarSession == true { commandBar?.dismiss() }
        let previous = sidebarPresentation
        let moveFocus = presentation == .hidden && sidebarOwnsFirstResponder
        let animated = allowsMotion && window?.isVisible == true && window?.isMiniaturized != true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !rootView.inLiveResize
        if animated {
            let transition = SidebarTransition(from: previous, to: presentation)
            preparingSidebarMotion = true
            sidebarMotionVisible = true
            sidebarFloatingSurface = transition.keepsFloatingSurface
            sidebarRevealsAnchored = transition.revealsAnchored
            sidebarChromePass = .preparation
            layoutChrome()
            sidebarContainer.preparesFloatingDock = transition.docksFloatingSurface
            sidebarChromePass = .geometry
            sidebarMotion.animate(layoutRoot: rootView, views: [sidebarContainer, pageHost, pageShadow, findHost, loadingIndicator],
                                  style: transition.style, flushesPreviousLayout: transition.flushesPreparation) {
                sidebarPresentation = presentation
                layoutChrome()
            } completion: { [weak self] in
                guard let self else { return }
                self.sidebarMotionVisible = false
                self.sidebarFloatingSurface = false
                self.refreshPreviewHover()
                self.layoutChrome()
                if self.sidebarPresentation != .hidden { self.sidebar.retestPointer() }
                if self.sidebarPresentation == .floating { self.refreshSidebarPointer() }
            }
            sidebarChromePass = .full
            refreshPreviewHover()
            sidebarRevealsAnchored = false
            preparingSidebarMotion = false
        } else {
            settleSidebarMotion()
            sidebarPresentation = presentation
            layoutChrome()
        }
        if presentation != .hidden { refreshSidebarBanners() }
        if moveFocus { if window?.isKeyWindow == true { requestNativeSelection() } else { window?.makeFirstResponder(nil) } }
    }
    func sidebarResizeChanged(_ state: NSGestureRecognizer.State, translationX: CGFloat, velocityX: CGFloat) {
        switch state {
        case .began:
            guard sidebarResize == nil, !sidebarMotion.isAnimating, !isClosing, libraryView == nil, !isPopupWindow,
                  nativeFullscreenTabID == nil, sidebarPresentation != .hidden else { return }
            sidebarPreviews?.dismiss()
            sidebarResize = SidebarResizeGesture(width: windowSidebarWidth.width, locked: sidebarPresentation == .locked)
            isSidebarResizing = true
        case .changed:
            guard var gesture = sidebarResize else { return }
            let change = gesture.change(translationX: Double(translationX), velocityX: Double(velocityX))
            sidebarResize = gesture
            sidebarResizeRegion.present(change.events)
            guard change.widthChanged else { return }
            sidebarChromePass = .geometry
            layoutChrome()
            sidebarChromePass = .full
        case .ended, .cancelled, .failed:
            guard let gesture = sidebarResize else { return }
            let completion: SidebarResizeGesture.Completion = state == .ended ? .ended : state == .cancelled ? .cancelled : .failed
            let commit = gesture.end(completion, translationX: Double(translationX))
            sidebarResize = nil
            if let lastUsed = windowSidebarWidth.end(commit, completion) { store.updateSettings { $0.sidebarWidth = lastUsed } }
            isSidebarResizing = false
            if commit.collapses { setSidebarPresentation(.hidden, allowsMotion: false) } else { layoutChrome() }
            refreshSidebarPointer()
        default: break
        }
    }
    func settleSidebarMotion() {
        sidebarMotion.cancel()
        sidebarMotionVisible = false
        sidebarFloatingSurface = false
        refreshPreviewHover()
    }
    var sidebarOwnsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        if responder === sidebar || responder.isDescendant(of: sidebar) { return true }
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSView { return field.isDescendant(of: sidebar) }
        return false
    }
    private var sidebarHoverPresentation: SidebarHoverZones.Presentation {
        switch sidebarPresentation {
        case .locked: .locked
        case .floating: .floating
        case .hidden: .hidden
        }
    }
    var paneTopBarDisplayed: Bool {
        PaneTopBarAdmission.displayed(
            toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible,
            inSplit: activeSplitLayout != nil || splitInsertion != nil,
            isPopup: isPopupWindow,
            hasLibrary: libraryView != nil,
            tabFullscreen: nativeFullscreenTabID != nil)
    }
    private var sidebarHoverShowsToolbar: Bool {
        !isPopupWindow && libraryView == nil && BrowserToolbarPreferences.shared.state.isVisible
    }
    func sidebarHoverRegions(_ info: SidebarHoverInfo) -> [SidebarHoverRegion: NSRect] {
        guard let window, libraryView == nil, !isPopupWindow, !isClosing, nativeFullscreenTabID == nil else { return [:] }
        let bounds = rootView.bounds
        let trafficLight = SidebarHoverZones.trafficLightHeight(windowMaxY: Double(window.frame.maxY),
            screenHeight: Double(window.screen?.frame.height ?? 0), menuBarHeight: Double(NSApp.mainMenu?.menuBarHeight ?? 0))
        let rects = SidebarHoverZones.rects(size: bounds.size, presentation: sidebarHoverPresentation, sidebarWidth: Double(sidebarLayoutWidth),
                                            showingToolbar: sidebarHoverShowsToolbar, trafficLightHeight: trafficLight, info: info)
        return rects.mapValues { NSRect(x: $0.minX, y: bounds.height - $0.maxY, width: $0.width, height: $0.height) }
    }
    func refreshSidebarHoverZones() {
        let key: [CGFloat] = [rootView.bounds.width, rootView.bounds.height, sidebarLayoutWidth,
            sidebarPresentation == .locked ? 0 : sidebarPresentation == .floating ? 1 : 2,
            libraryView == nil && !isPopupWindow && nativeFullscreenTabID == nil ? 1 : 0, sidebarHoverShowsToolbar ? 1 : 0]
        guard sidebarHoverLayoutKey != key else { return }
        sidebarHoverLayoutKey = key
        sidebarHover.setNeedsRefresh()
    }
    func applySidebarHover() {
        guard libraryView == nil, !isPopupWindow, !isClosing, nativeFullscreenTabID == nil, !isSidebarResizing else { return }
        let decision = SidebarHoverPresentationRule.decide(stored: sidebarHoverActive, presentation: sidebarHoverPresentation,
            info: sidebarHover.info, fullscreen: window?.styleMask.contains(.fullScreen) == true,
            includesTopLeft: !sidebarHoverShowsToolbar, isKeyWindow: window?.isKeyWindow == true,
            ownerDefers: navigationHistory != nil || commandBar != nil || themePopover != nil || siteControlCenterDefers
                || frameCrank != nil
                || spaceIconPicker != nil || SidebarPlusMenuController.isShown(in: window)
                || window?.attachedSheet != nil,
            interactionDefers: sidebarOwnsFirstResponder || sidebarPointerDown || sidebarPreviews?.holdsSidebarOpen == true
                || menuTrackingDepth > 0)
        sidebarHoverActive = decision.isActive
        switch decision.action {
        case .keep: break
        case .reveal: setSidebarPresentation(.floating)
        case .dismiss: setSidebarPresentation(.hidden)
        }
    }
    func refreshSidebarPointer() {
        sidebarHover.refresh()
        applySidebarHover()
    }
    var navigationPage: PCNativePage? {
        guard !isClosing, !wholeWindowClose, !windowClosePending, libraryView == nil,
              let page = selectedNativePage(), page.nativeView.window === window, !page.isClosed else { return nil }
        return page
    }
    func canPerformNavigation(_ action: PCNativeNavigationAction) -> Bool {
        if noteVisitTarget(action) != nil { return true }
        if let page = navigationPage { return page.canPerformNavigation(action) }
        return action == .reload && !isClosing && !wholeWindowClose && !windowClosePending &&
            libraryView == nil && activePeek == nil && window?.attachedSheet == nil &&
            currentTabID.flatMap { id in store.state.tab(id) }
                .map { InternalPage.isInternal($0.url) } == true
    }
}
