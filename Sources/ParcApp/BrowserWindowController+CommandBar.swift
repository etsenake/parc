import AppKit
import Combine

extension BrowserWindowController {
    func focusResidentCommandBar() -> Bool {
        guard showsStartPage, libraryView == nil, spaceCreation == nil, splitInsertion == nil,
              let bar = residentCommandBar, let window, ownsWindowCommandFocus, window.attachedSheet == nil else { return false }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        if let open = commandBar { commandBar = nil; open.dismiss(restoreFocus: false) }
        if !window.isKeyWindow { window.makeKey() }
        bar.focusResident()
        refreshResidentTopDomains(bar)
        return true
    }

    var canFocusSidebar: Bool {
        !isPopupWindow && libraryView == nil && nativeFullscreenTabID == nil && activePeek == nil
            && canOwnDownloadDialog(for: activeProfileID) && window.map {
                PCNativeBrowserApplication.canPresentTabSwitcher(in: $0)
            } == true
    }

    func focusSidebar() {
        guard canFocusSidebar else { return }
        presentCommandBar(newTab: true, inSidebar: true)
    }

    private func sidebarKeyboardItems() -> [SidebarKeyboardNavigation.Item] {
        SidebarKeyboardNavigation.items(state: store.state, spaceID: activeSpaceID,
            selected: selectedTabIDs, focused: currentTabID, peeks: sidebar.peekedItems, available: { self.switcherCanUse($0) })
    }

    private func reconcileSidebarKeyboardFocus(scroll: Bool = false) {
        guard sidebarKeyboardCursor != nil else { return }
        let items = sidebarKeyboardItems()
        sidebarKeyboardCursor?.reconcile(items.map(\.id))
        let item = items.first { $0.id == sidebarKeyboardCursor?.highlightedID }
        sidebar.highlightItemForKeyboard(sidebarKeyboardBrowsing ? item?.reference : nil, scrollToHighlight: scroll)
    }

    func splitInsertionTabs(profileID: UUID) -> [BrowserTab] {
        let spaces = Set(store.state.spaces.filter { $0.profileID == profileID }.map(\.id))
        return store.state.openTabs(where: { $0.profileID == profileID && ($0.kind == .favorite || spaces.contains($0.spaceID)) })
    }
    private func commandBarDocuments(profileID: UUID) -> [CommandBarDocument] {
        guard !isPopupWindow, !isPrivateBrowsing, !store.isProfileRemovalPending(profileID),
              let notes = try? NoteStore.sharedStore(directory: store.notesDirectory(for: profileID)),
              let easels = try? EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profileID)) else { return [] }
        let stamp = [store.notesDirectory(for: profileID), easels.documentsDirectory].map {
            (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date) ?? .distantPast
        }
        let all: [CommandBarDocument]
        if let cache = commandBarDocumentCache, cache.profileID == profileID, cache.stamp == stamp {
            all = cache.documents
        } else {
            let noteList = try? notes.list(), easelList = try? easels.list()
            all = (noteList ?? []).map { CommandBarDocument(kind: .note, id: $0.id, title: $0.title) }
                + (easelList ?? []).map { CommandBarDocument(kind: .easel, id: $0.id, title: $0.title) }
            commandBarDocumentCache = noteList != nil && easelList != nil ? (profileID, stamp, all) : nil
        }
        let open = store.state.openTabs(where: { $0.profileID == profileID }).compactMap { InternalPage(urlString: $0.url) }
        return all.filter { !open.contains($0.kind == .note ? .note($0.id) : .easel($0.id)) }
    }
    func deliverCommandBarTopDomains(to panel: CommandBar, profileID: UUID) {
        if let cache = commandBarTopDomainCache, cache.profileID == profileID, cache.revision == store.historyRevision {
            panel.updateTopDomains(cache.domains); return
        }
        let history = commandBarHistory(profileID: profileID), revision = store.historyRevision
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak panel] in
            let domains = CommandBarRanking.topDomains(history.map { ($0.url, $0.title) })
            DispatchQueue.main.async {
                guard let self else { return }
                if self.store.historyRevision == revision { self.commandBarTopDomainCache = (profileID, revision, domains) }
                if let panel, self.presentsCommandBar(panel) { panel.updateTopDomains(domains) }
            }
        }
    }
    private func deliverCommandBarRecentPages(to panel: CommandBar, profileID: UUID) {
        commandBarRecentPages?.query.invalidate()
        commandBarRecentPages = nil
        let path = store.independentEngineProfilePath(for: profileID)
        guard let query = PCNativeBrowserApplication.recentPages(forDomain: "all", profilePath: path, completion: { [weak self, weak panel] pages in
            MainActor.assumeIsolated {
                guard let self, let panel, self.commandBar === panel else { return }
                panel.updateRecentPages(pages.map { ($0.url.absoluteString, $0.title) })
            }
        }) else { return }
        commandBarRecentPages = (query, profileID, store.historyRevision)
    }
    private func commandBarTabs(profileID: UUID, excluding currentID: UUID?) -> [BrowserTab] {
        guard !isPopupWindow else { return [] }
        return store.state.tabs.filter {
            $0.profileID == profileID && $0.id != currentID && $0.archivedAt == nil
                && !closingTabIDs.contains($0.id) && !modelRetirementIDs.contains($0.id)
                && !store.retiringTabIDs.contains($0.id) && !transferringTabIDs.contains($0.id)
        }
    }
    func commandBarTabCaption(_ tab: BrowserTab) -> CommandBarResultText.TabCaption {
        CommandBarResultText.tabCaption(isFavorite: tab.kind == .favorite, isInActiveSpace: tab.spaceID == activeSpaceID,
                                        spaceName: store.state.spaces.first { $0.id == tab.spaceID }?.name,
                                        isInSplit: store.state.splitLayouts.contains { $0.tabIDs.contains(tab.id) })
    }
    func commandBarHistory(profileID: UUID) -> [BrowserHistoryEntry] {
        let currentURL = currentBrowser?.url?.absoluteString ?? store.state.tabs.first(where: { $0.id == currentTabID })?.url
        if let cache = commandBarHistoryCache,
           cache.revision == store.historyRevision,
           cache.profileID == profileID,
           cache.currentURL == currentURL {
            return cache.entries
        }
        let entries = store.state.history.filter { $0.profileID == profileID && $0.url != currentURL }
        commandBarHistoryCache = (store.historyRevision, profileID, currentURL, entries)
        return entries
    }
    private func commandBarSpaceActions() -> [CommandBarSpaceAction] {
        guard !isPrivateBrowsing, !isPopupWindow else { return [] }
        return CommandBarSpaceAction.snapshot(spaces: store.state.spaces, profiles: store.state.profiles)
    }
    private func commandBarFolderActions() -> [CommandBarFolderAction] {
        guard !isPrivateBrowsing, !isPopupWindow else { return [] }
        return CommandBarFolderAction.snapshot(state: store.state, profileID: activeProfileID)
    }
    func reconcileCommandBar() {
        reconcileSidebarKeyboardFocus()
        CommandBarReconcileInputs.withPresentedBar(commandBar) { bar in
            let profileID = activeProfileID
            let currentURL = currentBrowser?.url?.absoluteString ?? store.state.tabs.first(where: { $0.id == currentTabID })?.url
            bar.reconcile(tabs: splitInsertion == nil ? commandBarTabs(profileID: profileID, excluding: currentTabID) : splitInsertionTabs(profileID: profileID).filter { splitInsertion?.candidateIDs.contains($0.id) == true && !selectedTabIDs.contains($0.id) && canUseOrMoveHere($0.id) },
                          history: commandBarHistory(profileID: profileID),
                          historyRevision: store.historyRevision,
                          historyExcludedURL: currentURL,
                          spaces: commandBarSpaceActions(), folders: commandBarFolderActions())
        }
        CommandBarReconcileInputs.withPresentedBar(residentCommandBar) { bar in
            let profileID = activeProfileID
            let stamp = ResidentCommandBarInputs(state: store.stateRevision, history: store.historyRevision, space: activeSpaceID,
                                                 profile: profileID, selection: selectedTabIDs,
                                                 undo: folderUndo.command(.undo)?.name, redo: folderUndo.command(.redo)?.name)
            if residentCommandInputs != stamp {
                residentCommandInputs = stamp
                bar.reconcile(tabs: commandBarTabs(profileID: profileID, excluding: nil),
                              history: commandBarHistory(profileID: profileID),
                              historyRevision: store.historyRevision, historyExcludedURL: nil,
                              spaces: commandBarSpaceActions(), folders: commandBarFolderActions())
                let items = currentSidebarMenuItems
                let commands = commandBarTypedCommands(items: items, profileID: profileID)
                residentTypedCommands = (items, commands)
                bar.updateTypedCommands(commands)
            }
            if bar.hasFocus { refreshResidentTopDomains(bar) }
        }
        if let bar = commandBar, let asked = commandBarRecentPages, asked.revision != store.historyRevision {
            deliverCommandBarRecentPages(to: bar, profileID: asked.profileID)
        }
    }
    func presentCommandBar(newTab: Bool, inSidebar: Bool = false, addressAnchor: NSView? = nil, initialEdit: (String, NSRange)? = nil) {
        let originalProfileID = activeProfileID
        guard let original = window, ownsWindowCommandFocus, original.attachedSheet == nil,
              canOwnDownloadDialog(for: originalProfileID), windowCommandSecurityAvailable else { return }
        if navigationHistory?.ownsKeyWindow(in: original) == true {
            navigationHistory?.dismiss()
            guard window === original, ownsSpaceCommandFocus, windowCommandSecurityAvailable else { return }
        }
        if original.isKeyWindow && !PCNativeBrowserApplication.canPresentTabSwitcher(in: original) { return }
        func stillOwnsInteraction() -> Bool {
            guard window === original, ownsSpaceCommandFocus, original.attachedSheet == nil,
                  canOwnDownloadDialog(for: originalProfileID), windowCommandSecurityAvailable else { return false }
            return !original.isKeyWindow || PCNativeBrowserApplication.canPresentTabSwitcher(in: original)
        }
        guard WindowOwnerSequence.run(while: stillOwnsInteraction, steps: [
            { self.cancelSplitInsertion(restoreFocus: false) },
            { self.cancelSpaceCreation(restoreFocus: false) },
            { self.pageCapture?.dismiss(restoreFocus: false) },
            { self.cancelPendingCommandSplit() },
            { self.commandBar?.dismiss() },
            { self.navigationHistory?.dismiss() },
            { self.sidebarPreviews?.dismiss() },
            { self.tabSwitcher?.cancel() }
        ]), let window, window === original,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
        if inSidebar {
            if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }
            settleSidebarMotion(); layoutChrome()
            let current = sidebarKeyboardItems().first { $0.selection?.tabIDs == selectedTabIDs }
            sidebarKeyboardCursor = SidebarKeyboardCursor(highlightedID: current?.id)
            sidebarKeyboardBrowsing = true
            sidebar.setKeyboardSearchActive(true)
            reconcileSidebarKeyboardFocus(scroll: true)
        }
        let panel = makeCommandBar(in: window, newTab: newTab, inSidebar: inSidebar, addressAnchor: addressAnchor,
                                   initialEdit: initialEdit, resident: false)
        commandBarCreatesNewTab = newTab; commandBarShowsNewTabPlaceholder = newTab && !inSidebar
        commandBar = panel; panel.present()
        if !isPopupWindow, !isPrivateBrowsing {
            deliverCommandBarTopDomains(to: panel, profileID: activeProfileID)
            deliverCommandBarRecentPages(to: panel, profileID: activeProfileID)
        }
    }
    func makeCommandBar(in window: NSWindow, newTab: Bool, inSidebar: Bool, addressAnchor: NSView?,
                                initialEdit: (String, NSRange)?, resident: Bool) -> CommandBar {
        let membershipItems = sidebar.commandBarSelectionItems()
            ?? (selectedTabIDs.count == 1 ? currentTabID.map { [.tab($0)] } : nil) ?? []
        let favoriteAction = !isPrivateBrowsing && !isPopupWindow && activePeek == nil
            ? CommandBarFavoriteAction(items: membershipItems, spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) : nil
        let favoriteOwners: [() -> Bool] = favoriteAction?.tabIDs.map { id in
            let browser = browsers[id], page = browser?.nativePage
            let note = noteEditors[id]?.editor, easel = easelEditors[id]?.editor
            let hadBrowser = browser != nil, hadPage = page != nil
            let hadNote = note != nil, hadEasel = easel != nil
            return { [weak self, weak browser, weak page, weak note, weak easel] in
                guard let self, let tab = self.visibleTabs.first(where: { $0.id == id }),
                      self.canPerformSidebarTabAction(tab, closing: false),
                      !self.modelRetirementIDs.contains(id),
                      hadBrowser == (self.browsers[id] != nil), self.browsers[id] === browser,
                      hadPage == (self.browsers[id]?.nativePage != nil), self.browsers[id]?.nativePage === page,
                      page?.isClosed != true,
                      hadNote == (self.noteEditors[id]?.editor != nil), self.noteEditors[id]?.editor === note,
                      hadEasel == (self.easelEditors[id]?.editor != nil), self.easelEditors[id]?.editor === easel else { return false }
                return true
            }
        } ?? []
        let folderMoveItems = sidebar.commandBarSelectionItems() ?? {
            if let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: {
                $0.tabIDs == selectedTabIDs && $0.sidebarAnchorID != nil
            }) { return [.split(group.id)] }
            return selectedTabIDs.count == 1 ? currentTabID.map { [.tab($0)] } ?? [] : []
        }()
        let folderMoveSource = !isPrivateBrowsing && !isPopupWindow && activePeek == nil
            ? CommandBarFolderMoveSource(items: folderMoveItems, spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) : nil
        let folderMoves = folderMoveSource.map { CommandBarFolderMove.snapshot(source: $0, state: store.state) } ?? []
        let folderMoveOwners = folderMoveSource.flatMap { prepareSidebarSpaceMoveOwners?(Set($0.tabIDs)) }
        let folderMoveClaims = Dictionary(uniqueKeysWithValues: (folderMoveSource?.tabIDs ?? []).map {
            ($0, ownership.claimSnapshot($0))
        })
        let folderMoveFocus = focusedTabID
        let favoriteRenameAction = !isPrivateBrowsing && !isPopupWindow && activePeek == nil
            ? CommandBarFavoriteRenameAction(state: store.state, spaceID: activeSpaceID,
                profileID: activeProfileID, selectedTabIDs: selectedTabIDs) : nil
        let renameBinding = nativeBinding
        let renameNote = favoriteRenameAction.flatMap { noteEditors[$0.tab.id]?.editor }
        let renameEasel = favoriteRenameAction.flatMap { easelEditors[$0.tab.id]?.editor }
        let hadRenameNote = renameNote != nil, hadRenameEasel = renameEasel != nil
        let submissionRevision = UUID()
        if resident { residentCommandSubmissionRevision = submissionRevision } else { commandSubmissionRevision = submissionRevision }
        let submissionIsCurrent: () -> Bool = { [weak self] in
            (resident ? self?.residentCommandSubmissionRevision : self?.commandSubmissionRevision) == submissionRevision
        }
        let commandSelection = selectedTabIDs
        let commandSpace = activeSpaceID
        let commandProfile = activeProfileID
        let commandTab = currentTabID
        let sourcePeek = activePeek
        let commandPeek = newTab ? nil : sourcePeek
        let commandBrowser = currentBrowser
        let commandPage = selectedNativePage()
        let isOriginal: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  self.canOwnDownloadDialog(for: commandProfile),
                  self.activeSpaceID == commandSpace, self.activeProfileID == commandProfile,
                  self.currentTabID == commandTab, self.activePeek === sourcePeek,
                  self.currentBrowser === commandBrowser, self.selectedNativePage() === commandPage,
                  commandPage?.isClosed != true else { return false }
            if resident { return self.showsStartPage }
            guard window.isVisible, !window.isMiniaturized,
                  window.attachedSheet == nil || self.commandBar?.ownsAttachedSheet == true else { return false }
            if inSidebar && (self.libraryView != nil || self.sidebarPresentation == .hidden
                || self.nativeFullscreenTabID != nil) { return false }
            if let id = commandTab {
                return !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                    && !self.store.retiringTabIDs.contains(id)
                    && self.store.state.containsTab(id, where: { $0.profileID == commandProfile && $0.archivedAt == nil })
            }
            return true
        }
        let historyExcludedURL = currentBrowser?.url?.absoluteString
            ?? store.state.tabs.first(where: { $0.id == commandTab })?.url
        let seedURL = newTab ? nil : historyExcludedURL
        let typedItems = currentSidebarMenuItems
        let typedCommands = commandBarTypedCommands(items: typedItems, profileID: commandProfile)
        if resident { residentTypedCommands = (typedItems, typedCommands) }
        let typedSnapshot: () -> (items: [SidebarItemReference]?, commands: [CommandBarTypedCommand]) = { [weak self] in
            resident ? self?.residentTypedCommands ?? (nil, []) : (typedItems, typedCommands)
        }
        let panel = CommandBar(parent: window,
            tabs: commandBarTabs(profileID: commandProfile, excluding: commandTab),
            history: commandBarHistory(profileID: commandProfile),
            historyRevision: store.historyRevision,
            historyExcludedURL: historyExcludedURL,
            spaces: commandBarSpaceActions(), folders: commandBarFolderActions(), favoriteAction: favoriteAction, folderMoves: folderMoves, favoriteRename: favoriteRenameAction,
            documents: { [weak self] in self?.commandBarDocuments(profileID: commandProfile) ?? [] },
            typedCommands: typedCommands, currentURL: seedURL,
            profilePath: store.independentEngineProfilePath(for: commandProfile), page: commandPage, nativeWindow: nativeBinding,
            sidebarAnchor: inSidebar ? sidebar.keyboardSearchAnchor : addressAnchor,
            addressOnly: addressAnchor != nil, popup: isPopupWindow,
            currentPageTitle: currentBrowser?.title ?? store.state.tabs.first(where: { $0.id == commandTab })?.title,
            initialEdit: initialEdit,
            extensionDisposition: isPopupWindow && newTab ? nil : (newTab ? .newForegroundTab : .currentTab),
            theme: windowPaletteTheme, contentAppearance: resident ? nil : rootView.palette.contentAppearance, resident: resident)
        panel.isOwnerValid = isOriginal
        panel.tabCaption = { [weak self] tab in self?.commandBarTabCaption(tab)
            ?? .switchToTab }
        let canPerformTyped: (CommandBarTypedCommand) -> Bool = { [weak self] command in
            guard isOriginal(), let self, submissionIsCurrent(),
                  typedSnapshot().commands.contains(command) else { return false }
            return self.typedCommandIsAvailable(command, items: typedSnapshot().items, profileID: commandProfile)
        }
        panel.canPerformTypedCommand = canPerformTyped
        panel.onPerformTypedCommand = { [weak self] command in
            guard let self, self.commandBar == nil, canPerformTyped(command),
                  let action = self.prepareTypedCommand(command, items: typedSnapshot().items, profileID: commandProfile),
                  action() else { NSSound.beep(); return }
        }
        if PCNativeBrowserApplication.responds(to: #selector(PCNativeBrowserApplication.setAllTabAudioMuted(_:in:))) {
            panel.onMuteAllTabs = { [weak self, weak window] muted in
                guard let self, let window, isOriginal(), self.commandBar == nil,
                      submissionIsCurrent(),
                      self.window === window, window.isKeyWindow, NSApp.isActive,
                      window.attachedSheet == nil,
                      PCNativeBrowserApplication.responds(to: #selector(PCNativeBrowserApplication.setAllTabAudioMuted(_:in:))) else { return false }
                return PCNativeBrowserApplication.setAllTabAudioMuted(muted, in: window)
            }
        }
        let extensionBinding = nativeBinding
        let extensionCandidates: () -> [PCNativeExtensionAction] = { [weak self, weak extensionBinding, weak commandPage] in
            guard let self, let binding = extensionBinding, let page = commandPage,
                  isOriginal(), self.nativeBinding === binding, !page.isClosed else { return [] }
            return binding.extensionActions(for: page)
        }
        panel.extensionLaunchActions = extensionCandidates
        panel.onLaunchExtension = { [weak self, weak extensionBinding, weak commandPage] action in
            guard let self, let binding = extensionBinding, let page = commandPage,
                  isOriginal(), self.commandBar == nil, self.nativeBinding === binding,
                  !page.isClosed else { return false }
            return binding.executeExtensionAction(action, for: page)
        }
        panel.onCopyText = { [weak self, weak panel, weak commandBrowser] text in
            guard let self, let panel, self.presentsCommandBar(panel), isOriginal(), self.currentTabID == commandTab else { return }
            let pageURL = commandBrowser?.url?.absoluteString
                ?? self.store.state.tabs.first(where: { $0.id == commandTab })?.url
            let upsell = SuperCopyUpsell()
            let shortcut = KeyboardShortcuts.shared.activeShortcut(for: "copyCurrentURL:")
            guard let shortcut, let message = upsell.message(copied: text, pageURL: pageURL, shortcut: shortcut) else { return }
            if self.showToast(.superCopyUpsell(shortcut: shortcut.display, message: message)) != nil { upsell.recordShown() }
        }
        let canPerformFavorite: (CommandBarFavoriteAction) -> Bool = { [weak self] action in
            guard isOriginal(), let self, submissionIsCurrent(),
                  action == favoriteAction, action.isCurrent(in: self.store.state),
                  self.selectedTabIDs == commandSelection, self.spaceCommandsAvailable,
                  self.activePeek == nil, !self.isPrivateBrowsing,
                  !favoriteOwners.isEmpty, favoriteOwners.allSatisfy({ $0() }) else { return false }
            return true
        }
        panel.canPerformFavorite = canPerformFavorite
        panel.onPerformFavorite = { [weak self, weak window] action in
            guard let self, let window, self.commandBar == nil, canPerformFavorite(action),
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            do {
                guard try self.store.performFavoriteAction(action) else { return }
                self.render(self.store.state)
            } catch { showError(error) }
        }
        let canMoveToFolder: (CommandBarFolderMove) -> Bool = { [weak self] move in
            guard isOriginal(), let self, submissionIsCurrent(),
                  self.selectedTabIDs == commandSelection, self.focusedTabID == folderMoveFocus,
                  self.spaceCommandsAvailable, self.activePeek == nil,
                  move.source == folderMoveSource, folderMoves.contains(move),
                  self.store.state.tabs.first(where: { $0.id == commandTab })?.folderID != move.folder.folderID,
                  move.isCurrent(in: self.store.state), folderMoveOwners?() == true,
                  move.tabIDs.allSatisfy({ id in
                      !self.store.retiringTabIDs.contains(id)
                          && self.ownership.claimSnapshot(id) == folderMoveClaims[id]
                          && folderMoveClaims[id]?.transfer == nil
                  }), self.store.state.splitLayouts.filter({ move.source.groupIDs.contains($0.id) }).allSatisfy({ group in
                      group.tabIDs.allSatisfy { folderMoveClaims[$0]?.owner == nil || folderMoveClaims[$0]?.owner == self.presentationID }
                  }) else { return false }
            return true
        }
        let copyDestinations: (CommandBarFolderMove) -> SidebarCopySources? = { [weak self] move in
            guard canMoveToFolder(move), let self else { return nil }
            let originals = move.tabIDs.compactMap { id in self.store.state.tab(id) }
            guard originals.count == move.tabIDs.count,
                  let urls = self.resolveSidebarCopyDestinations?(originals), urls.validates(originals) else { return nil }
            return urls
        }
        panel.canCopyToFolder = { copyDestinations($0) != nil }
        var folderCopyConsumed = false
        panel.onCopyToFolder = { [weak self, weak window] move in
            guard let self, let window, !folderCopyConsumed, self.commandBar == nil,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
                  let urls = copyDestinations(move) else { return }
            folderCopyConsumed = true
            do {
                guard let copy = try self.store.copyCommandBarItemsToFolder(move, destinations: urls.destinations, documents: urls.documents,
                    creation: self.creationProvenance(activeTabID: self.currentTabID)) else { return }
                self.registerSidebarCopyUndo(SidebarCopyUndo.folderCopyName, roots: copy.roots,
                    spaceID: move.folder.spaceID, profileID: move.source.profileID, sources: urls,
                    openTabIDs: copy.openTabIDs, originatingSpaceID: commandSpace, window: window)
                self.render(self.store.state)
                self.openDuplicatedChildren(copy.openTabIDs, spaceID: move.folder.spaceID,
                    profileID: move.source.profileID, window: window, originatingSpaceID: commandSpace)
                if let item = copy.roots.first {
                    self.showSidebarMoveNotice(item: item, space: move.folder.spaceID, profile: move.source.profileID,
                        message: "Copied to folder. Click to go there.")
                }
            } catch { showError(error) }
        }
        panel.canMoveToFolder = canMoveToFolder
        var folderMoveConsumed = false
        panel.onMoveToFolder = { [weak self, weak window] move in
            guard let self, let window, !folderMoveConsumed, self.commandBar == nil,
                  canMoveToFolder(move), PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            folderMoveConsumed = true
            do {
                guard try self.store.performCommandBarFolderMove(move) else { return }
                self.render(self.store.state); self.requestNativeSelection()
                self.showToast(.pinnedToFolder(move.folder.name), at: .window)
            } catch { showError(error) }
        }
        let canRenameFavorite: (CommandBarFavoriteRenameAction) -> Bool = { [weak self, weak renameBinding, weak renameNote, weak renameEasel] action in
            guard isOriginal(), let self, let renameBinding, action == favoriteRenameAction,
                  commandTab == action.tab.id, self.nativeBinding === renameBinding,
                  !renameBinding.isPrivateBrowsing, renameBinding.browsingContextKind != .mixed,
                  submissionIsCurrent(),
                  self.favoriteRename == nil, !self.folderUndo.isBusy, !self.sidebar.isEditingTitle,
                  !self.isPrivateBrowsing, self.activePeek == nil, self.spaceCommandsAvailable,
                  let tab = action.currentTab(in: self.store.state, spaceID: self.activeSpaceID,
                      profileID: self.activeProfileID, selectedTabIDs: self.selectedTabIDs),
                  self.canPerformSidebarTabAction(tab, closing: false),
                  hadRenameNote == (self.noteEditors[tab.id]?.editor != nil), self.noteEditors[tab.id]?.editor === renameNote,
                  hadRenameEasel == (self.easelEditors[tab.id]?.editor != nil), self.easelEditors[tab.id]?.editor === renameEasel else { return false }
            return true
        }
        panel.canRenameFavorite = canRenameFavorite
        panel.onRenameFavorite = { [weak self] action in
            guard let self, self.commandBar == nil, canRenameFavorite(action),
                  let tab = action.currentTab(in: self.store.state, spaceID: self.activeSpaceID,
                      profileID: self.activeProfileID, selectedTabIDs: self.selectedTabIDs) else { return }
            _ = self.prepareFavoriteRename(tab, selectOriginal: false)?()
        }
        panel.canFocusSpace = { [weak self] target in
            guard isOriginal(), let self,
                  target.isCurrent(spaces: self.store.state.spaces, profiles: self.store.state.profiles) else { return false }
            return self.canSelectSpace(target.spaceID, profileID: target.profileID)
        }
        panel.onFocusSpace = { [weak self] target in
            guard isOriginal(), let self,
                  target.isCurrent(spaces: self.store.state.spaces, profiles: self.store.state.profiles) else { return }
            _ = self.selectSpaceFromUser(target.spaceID, profileID: target.profileID)
        }
        panel.canOpenFolder = { [weak self] target in
            guard isOriginal(), let self, self.activePeek == nil,
                  target.isCurrent(in: self.store.state, profileID: commandProfile) else { return false }
            return self.canSelectSpace(target.spaceID, profileID: target.profileID)
        }
        panel.onOpenFolder = { [weak self] target in
            guard isOriginal(), let self,
                  target.isCurrent(in: self.store.state, profileID: commandProfile) else { return }
            _ = self.revealSidebarItem(target.reveal.item, spaceID: target.spaceID, profileID: target.profileID)
        }
        if inSidebar {
            panel.onSidebarMove = { [weak self] delta in
                guard isOriginal(), let self else { return }
                self.sidebarKeyboardCursor?.move(delta, in: self.sidebarKeyboardItems().map(\.id))
                self.reconcileSidebarKeyboardFocus(scroll: true)
            }
            panel.onSidebarQueryState = { [weak self] browsing in
                guard isOriginal(), let self else { return }
                self.sidebarKeyboardBrowsing = browsing
                self.reconcileSidebarKeyboardFocus()
            }
            panel.onSidebarCommit = { [weak self, weak panel] in
                guard isOriginal(), let self else { return }
                let target = self.sidebarKeyboardItems().first { $0.id == self.sidebarKeyboardCursor?.highlightedID }
                if let folder = target?.folder {
                    do {
                        guard try self.store.setFolderExpanded(!folder.isExpanded, expected: folder,
                                                               profileID: commandProfile) else { NSSound.beep(); return }
                        self.reconcileSidebarKeyboardFocus(scroll: true)
                    } catch {
                        panel?.dismiss()
                        showError(error)
                    }
                    return
                }
                panel?.dismiss()
                guard isOriginal(), self.canFocusSidebar, let selection = target?.selection else { return }
                if selection.tabIDs == self.selectedTabIDs { self.requestNativeSelection() }
                else { self.selectRecentItem(selection) }
            }
        }
        panel.mayRestoreOriginal = { [weak self] view in
            guard isOriginal(), let self else { return false }
            let find = self.visibleFind.flatMap { self.isCurrentFind($0) && !self.findHost.isHidden ? self.findHost : nil }
            let peek = self.activePeek.flatMap { $0.view.isHidden ? nil : $0.view }
            return ContentFocusRequest.returnsToSaved(view, find: find,
                                                      content: peek ?? self.currentTabID.flatMap { self.panes[$0] })
        }
        panel.restorePageFocus = { [weak self] in
            guard isOriginal(), let self else { return }
            if let find = self.visibleFind, self.isCurrentFind(find), !self.findHost.isHidden,
               self.window?.makeFirstResponder(self.findField) == true { return }
            if let browser = self.currentBrowser { self.window?.makeFirstResponder(browser.nativePage?.nativeView ?? browser); return }
            if !resident, self.activePeek == nil, self.currentTabID == nil, self.showsStartPage {
                self.residentCommandBar?.focusResident(); return
            }
            guard self.activePeek == nil, let id = self.currentTabID, self.renderedPaneIDs.contains(id) else { return }
            if let editor = self.noteEditors[id]?.editor { editor.focusContent() }
            else if let editor = self.easelEditors[id]?.editor { editor.focusContent() }
            else if self.panes[id]?.showsBlank == true { self.window?.makeFirstResponder(nil) }
        }
        panel.onNavigate = { [weak self] input in
            guard isOriginal(), let self else { return }
            if let peek = commandPeek { self.resolvePeekInput(input, peek: peek) }
            else if newTab || commandTab == nil { self.openInput(input) }
            else { self.resolveInput(input, replacing: commandTab) }
        }
        panel.onSearchNavigation = { [weak self] navigation in
            guard isOriginal(), let self else { return }
            if self.isPopupWindow && newTab { return }
            if let peek = commandPeek { peek.browser.loadSearchNavigation(navigation) }
            else { self.openSearchNavigation(navigation, replacing: newTab ? nil : commandTab) }
        }
        panel.onSelectTab = { [weak self] id in
            guard isOriginal(), let self,
                  self.commandBarTabs(profileID: commandProfile, excluding: commandTab).contains(where: { $0.id == id }) else { return }
            self.selectTab(id)
        }
        let canSplit: (UUID?) -> Bool = { [weak self] target in
            guard isOriginal(), let self, submissionIsCurrent(),
                  self.selectedTabIDs == commandSelection, let commandTab,
                  self.activePeek == nil, !self.isPopupWindow, self.libraryView == nil,
                  self.nativeFullscreenTabID == nil, !self.promotingPeek,
                  self.peekRetirementParents.isEmpty,
                  commandSelection.allSatisfy({ id in
                      self.ownership.canUse(id, owner: self.presentationID)
                          && !self.store.retiringTabIDs.contains(id)
                          && !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                  }), commandSelection.contains(commandTab) else { return false }
            if let target {
                guard self.visibleTabs.contains(where: { $0.id == target })
                        || self.splitInsertionTabs(profileID: commandProfile).contains(where: { $0.id == target }),
                      self.ownership.canUse(target, owner: self.presentationID) || self.canMovePageHere(target),
                      !self.transferringTabIDs.contains(target), !self.closingTabIDs.contains(target),
                      !self.modelRetirementIDs.contains(target), !self.store.retiringTabIDs.contains(target) else { return false }
                if commandSelection.contains(target) { return true }
            }
            return commandSelection.count < 4
        }
        let commitSplit: (PCNativeSearchNavigation?, UUID?) -> Void = { [weak self, weak window] navigation, existingID in
            guard let self, let window, let commandTab, self.commandBar == nil,
                  canSplit(existingID), PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            if let navigation {
                guard navigation.profilePath == self.store.independentEngineProfilePath(for: commandProfile) else { return }
            } else if existingID == nil { return }
            let id = existingID ?? UUID()
            if let navigation { self.pendingSearchNavigations[id] = navigation }
            var inserted = false
            var homeIDs: [UUID: UUID] = [:]
            self.performWindowCommand(selectNativePage: false) {
                guard let homes = self.store.commandBarSplitHomes(after: commandTab, expectedSelection: commandSelection,
                          tabID: id, isNew: existingID == nil) ?? (commandSelection.contains(id) ? [] : nil),
                      let plan = self.splitHomePlan(homes) else { return }
                homeIDs = plan.ids
                inserted = self.store.insertCommandBarSplit(after: commandTab,
                    expectedSelection: commandSelection, tabID: id, newURL: navigation?.url,
                    creation: self.creationProvenance(activeTabID: commandTab),
                    savedHomeIDs: plan.ids, documents: plan.documents)
                if inserted && existingID == nil { self.presentation.recordCreation(id, state: self.store.state) }
            }
            guard inserted, self.selectedTabIDs.contains(id) else {
                self.pendingSearchNavigations.removeValue(forKey: id); return
            }
            self.openSplitHomes(homeIDs, profileID: commandProfile, originatingSpaceID: self.activeSpaceID)
            self.focusedTabID = id
            self.render(self.store.state); self.requestNativeSelection()
            self.focusSelectedLocalContent()
        }
        panel.canSplitSelection = canSplit
        panel.onSplitNavigation = { navigation in commitSplit(navigation, nil) }
        panel.onSplitTab = { [weak self] id in
            guard let self, self.canMovePageHere(id), canSplit(id) else { commitSplit(nil, id); return }
            _ = self.movePagesHere([id]) { guard canSplit(id) else { return false }; commitSplit(nil, id); return true }
        }
        panel.onSplitInput = { [weak self, weak commandPage] input in
            guard let self, canSplit(nil) else { return }
            let originalURL = commandBrowser?.url
            self.pendingCommandSplitBrowser = commandBrowser
            self.pendingCommandSplitValidation = { canSplit(nil) && commandBrowser?.url == originalURL }
            PCNativeBrowserApplication.resolveSearchInput(input,
                profilePath: self.store.independentEngineProfilePath(for: commandProfile), page: commandPage, window: self.nativeBinding) { [weak self] navigation, error in
                MainActor.assumeIsolated {
                    guard let self, canSplit(nil), self.commandBar == nil,
                          commandBrowser?.url == originalURL else { return }
                    self.pendingCommandSplitValidation = nil; self.pendingCommandSplitBrowser = nil
                    guard let navigation else {
                        self.showSearchError(error?.localizedDescription ?? "Search is unavailable for this Space.")
                        return
                    }
                    commitSplit(navigation, nil)
                }
            }
        }
        let backgroundOwner: () -> Bool = { [weak self, weak panel] in
            guard isOriginal(), let self, let panel, self.presentsCommandBar(panel),
                  submissionIsCurrent(),
                  self.selectedTabIDs == commandSelection, !self.isPopupWindow,
                  !self.store.isProfileRemovalPending(commandProfile),
                  self.transferringTabIDs.isEmpty else { return false }
            return true
        }
        let background: (PCNativeSearchNavigation, @escaping () -> Bool, @escaping (String?) -> Void) -> Void = { [weak self] request, valid, complete in
            guard let self, backgroundOwner(), valid() else { complete("The original search owner changed."); return }
            self.openCommandBarBackground(request, sourcePage: commandPage, spaceID: commandSpace,
                profileID: commandProfile, selection: commandSelection,
                validate: { backgroundOwner() && valid() }, completion: complete)
        }
        let classifyBackground: (String, @escaping () -> Bool, @escaping (String?) -> Void) -> Void = { [weak self, weak commandPage] input, valid, complete in
            guard let self, backgroundOwner(), valid() else { complete("The original search owner changed."); return }
            PCNativeBrowserApplication.resolveSearchInput(input,
                profilePath: self.store.independentEngineProfilePath(for: commandProfile), page: commandPage, window: self.nativeBinding) { navigation, error in
                MainActor.assumeIsolated {
                    guard backgroundOwner(), valid() else { complete("The original search owner changed."); return }
                    guard let navigation else { complete(error?.localizedDescription ?? "This input cannot open."); return }
                    background(navigation, valid, complete)
                }
            }
        }
        panel.onBackgroundNavigation = background
        panel.onBackgroundInput = classifyBackground
        panel.onBackgroundTab = { [weak self] id, valid, complete in
            guard let self, backgroundOwner(), valid(),
                  let original = self.commandBarTabs(profileID: commandProfile, excluding: commandTab).first(where: { $0.id == id }),
                  !InternalPage.isInternal(original.url) else {
                complete("This tab cannot open as a new background page."); return
            }
            let stillOriginal: () -> Bool = { [weak self] in
                guard let self, valid(), backgroundOwner() else { return false }
                return self.commandBarTabs(profileID: commandProfile, excluding: commandTab).contains {
                    $0.id == original.id && $0.spaceID == original.spaceID && $0.profileID == original.profileID && $0.url == original.url
                }
            }
            classifyBackground(original.url, stillOriginal, complete)
        }
        panel.onManagePasswords = { [weak self] in if isOriginal() { self?.showPasswordManager() } }
        panel.onOpenDocument = { [weak self] document in
            guard isOriginal(), let self else { return }
            switch document.kind {
            case .note: self.openNote(id: document.id, title: document.title)
            case .easel: self.openEasel(id: document.id, title: document.title)
            }
        }
        panel.onManageSiteSearch = { [weak self] in
            guard isOriginal(), let self, !self.isPrivateBrowsing else { return }
            let creation = self.creationProvenance(activeTabID: self.currentTabID)
            self.performWindowCommand {
                let id = self.store.open("parc://settings/searchEngines", creation: creation)
                self.presentation.recordCreation(id, state: self.store.state)
            }
        }
        panel.onSearchSettings = { [weak self] in if isOriginal() { self?.showSettings(pane: .spaces) } }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self else { return }
            if resident {
                if self.residentCommandBar === panel { self.residentCommandBar = nil; self.scheduleStartPageRefresh() }
                return
            }
            guard self.commandBar === panel else { return }
            self.commandBar = nil
            self.commandBarRecentPages?.query.invalidate(); self.commandBarRecentPages = nil
            if inSidebar {
                self.sidebarKeyboardCursor = nil; self.sidebarKeyboardBrowsing = false
                self.sidebar.highlightItemForKeyboard(nil, scrollToHighlight: false)
                self.sidebar.setKeyboardSearchActive(false)
            }
            self.refreshSidebarPointer()
        }
        return panel
    }
    private func openCommandBarBackground(_ navigation: PCNativeSearchNavigation, sourcePage: PCNativePage?,
        spaceID: UUID, profileID: UUID, selection: [UUID], validate: @escaping () -> Bool,
        completion: @escaping (String?) -> Void) {
        guard validate(), let window, !isClosing, !wholeWindowClose, !windowClosePending,
              navigation.profilePath == store.independentEngineProfilePath(for: profileID) else {
            completion("The original search owner changed."); return
        }
        let id = UUID()
        let creation = creationProvenance(activeTabID: currentTabID)
        pendingSearchNavigations[id] = navigation
        var inserted = false
        performWindowCommand(selectNativePage: false) {
            inserted = store.insertCommandBarBackground(tabID: id, url: navigation.url,
                spaceID: spaceID, profileID: profileID, expectedSelection: selection, creation: creation)
            if inserted { presentation.recordCreation(id, state: store.state) }
        }
        guard inserted, let tab = store.state.tab(id),
              ownership.claim(id, owner: presentationID) else {
            pendingSearchNavigations.removeValue(forKey: id)
            completion("The original destination changed."); return
        }
        let pane = makePane(tab)
        pane.frame = pageHost.bounds; panes[id] = pane; parkedPages.addSubview(pane)
        pane.layoutSubtreeIfNeeded()
        let browser = PCBrowserView(frame: pane.contentBounds, profilePath: navigation.profilePath)
        browser.delegate = self
        browsers[id] = browser; browserProfiles[id] = profileID; liveTabModels[id] = tab
        pane.browser = browser; pane.showBrowser(); pane.layoutSubtreeIfNeeded()
        requestedURLs[id] = tab.url
        let admitted = browser.loadBackgroundSearchNavigation(navigation, sourcePage: sourcePage, validateOwner: { [weak self, weak browser, weak window] in
            guard let self, let browser, let window, validate(), self.window === window,
                  self.browsers[id] === browser, self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.ownership.canUse(id, owner: self.presentationID),
                  !self.closingTabIDs.contains(id), !self.store.retiringTabIDs.contains(id),
                  !self.modelRetirementIDs.contains(id), !self.transferringTabIDs.contains(id) else { return false }
            return self.store.state.containsTab(id, where: { $0.spaceID == spaceID && $0.profileID == profileID && $0.archivedAt == nil })
        }) { [weak self, weak browser] success, error in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browsers[id] === browser else { completion("The background page owner closed."); return }
                if success { self.pendingSearchNavigations.removeValue(forKey: id) }
                else {
                    self.failures[id] = error?.localizedDescription ?? "The background page could not open."
                    self.requestedURLs.removeValue(forKey: id)
                }
                self.attachOwnedPages()
                completion(success ? nil : self.failures[id])
            }
        }
        if !admitted {
            failures[id] = "The background page could not open. Select it to retry the original request."
            requestedURLs.removeValue(forKey: id)
            completion(failures[id])
        }
        attachOwnedPages()
    }

    private func resolvePeekInput(_ input: String, peek: PeekController) {
        let revision = UUID(); inputRevisions[peek.identity] = revision
        let originalURL = peek.browser.url
        PCNativeBrowserApplication.resolveSearchInput(input, profilePath: peek.page.profilePath, page: peek.page) { [weak self, weak peek] navigation, error in
            MainActor.assumeIsolated {
                guard let self, let peek, self.activePeek === peek,
                      self.peeks[peek.page.identifier] === peek, !peek.page.isClosed,
                      self.inputRevisions[peek.identity] == revision, peek.browser.url == originalURL else { return }
                self.inputRevisions.removeValue(forKey: peek.identity)
                if let navigation { peek.browser.loadSearchNavigation(navigation) }
                else if let error, let window = self.window { ParcDialog.inform(in: window, .init(error: error)) }
            }
        }
    }

    func toggleSidebar() {
        if libraryView != nil { closeLibrary(); return }
        setSidebarPresentation(sidebarPresentation == .locked ? .hidden : .locked)
    }
    private func commandBarTypedCommands(items: [SidebarItemReference]?, profileID: UUID) -> [CommandBarTypedCommand] {
        guard !isPopupWindow else { return [] }
        var commands: [CommandBarTypedCommand] = []
        if let undo = folderUndo.command(.undo), !undo.name.isEmpty { commands.append(.init(kind: .undo(undo.name))) }
        if let redo = folderUndo.command(.redo), !redo.name.isEmpty { commands.append(.init(kind: .redo(redo.name))) }
        if let items, !isPrivateBrowsing {
            let allSpaces = store.state.spaces
            commands += allSpaces.enumerated().filter { _, space in
                space.id != activeSpaceID && commandBarSpaceMoveIsPossible(items, to: space)
            }.map { offset, space in
                let shared = allSpaces.filter { $0.name == space.name }.count > 1
                return .init(kind: .pinToSpace(space.id, name: space.name, position: shared ? offset + 1 : nil))
            }
            if commandBarFolderCollectionIsPossible(items) {
                commands.append(.init(kind: .pinToNewFolder))
            }
            if commandBarDuplicateIsPossible(items) {
                commands.append(.init(kind: .duplicateCurrentTab))
            }
        }
        commands.append(.init(kind: .replacePinWithCurrentPage))
        commands += CommandBarTypedCommand.splitCommands(paneCount: selectedTabIDs.count,
                                                         vertical: activeSplitLayout?.orientation == .vertical)
        if !isPrivateBrowsing {
            commands += CommandBarWebDocument.available(visitedHosts: commandBarVisitedHosts(profileID: profileID))
                .map { .init(kind: .newWebDocument($0)) }
            commands += [.init(kind: .searchSettings), .init(kind: .airTrafficControl)]
        }
        commands += CommandBarTypedCommand.SettingsPane.allCases.map { .init(kind: .settingsPane($0)) }
        commands += CommandBarTypedCommand.Appearance.allCases.map { .init(kind: .appearance($0)) }
        commands += [.init(kind: .copyAppInfo), .init(kind: .revealAppData), .init(kind: .capturePortrait)]
        if canPerformPageTool(.taskManager) { commands.append(.init(kind: .openTaskManager)) }
        return commands
    }

    private func commandBarVisitedHosts(profileID: UUID) -> Set<String> {
        if let cache = commandBarHostCache, cache.profileID == profileID, cache.revision == store.historyRevision {
            return cache.hosts
        }
        let hosts = Set(store.state.history.lazy.filter { $0.profileID == profileID }
            .compactMap { URL(string: $0.url)?.host?.lowercased() })
        commandBarHostCache = (profileID, store.historyRevision, hosts)
        return hosts
    }

    private func commandBarModelCheck(_ key: String, items: [SidebarItemReference], _ check: () -> Bool) -> Bool {
        if let cache = commandBarModelChecks, cache.revision == store.stateRevision, cache.spaceID == activeSpaceID,
           cache.profileID == activeProfileID, cache.items == items {
            if let answer = cache.answers[key] { return answer }
        } else {
            commandBarModelChecks = (store.stateRevision, activeSpaceID, activeProfileID, items, [:])
        }
        let answer = check()
        commandBarModelChecks?.answers[key] = answer
        return answer
    }
    private func commandBarSpaceMoveIsPossible(_ items: [SidebarItemReference], to space: BrowserSpace) -> Bool {
        commandBarModelCheck("space:" + space.id.uuidString, items: items) { sidebarSpaceMoveIsPossible(items, to: space) }
    }
    private func commandBarFolderCollectionIsPossible(_ items: [SidebarItemReference]) -> Bool {
        commandBarModelCheck("folder", items: items) {
            SidebarMoveCollection(items: items, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) != nil
        }
    }
    private func commandBarDuplicateIsPossible(_ items: [SidebarItemReference]) -> Bool {
        commandBarModelCheck("duplicate", items: items) {
            SidebarDuplicateTarget(items: items, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) != nil
        }
    }

    private func sidebarSpaceMoveIsPossible(_ items: [SidebarItemReference], to space: BrowserSpace) -> Bool {
        guard let source = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let target = SidebarHierarchySnapshot(state: store.state, spaceID: space.id, profileID: space.profileID) else { return false }
        return SidebarSpaceMove(items: items, from: source, to: target, state: store.state) != nil
    }

    private func typedSplitCommand(_ kind: CommandBarTypedCommand.Kind) -> SplitCommand? {
        switch kind {
        case .addSplit(.left): return .add(.addBefore)
        case .addSplit(.right): return .add(.addAfter)
        case .addSplit(.top): return .add(.addAbove)
        case .addSplit(.bottom), .addVerticalSplit: return .add(.addBelow)
        case .convertSplit(let vertical): return .orientation(vertical ? .vertical : .horizontal)
        default: return nil
        }
    }

    private var replaceablePinnedTab: (tab: BrowserTab, url: String)? {
        guard activePeek == nil, !isPrivateBrowsing, let id = currentTabID,
              let tab = visibleTabs.first(where: { $0.id == id }), tab.resetDestination != nil else { return nil }
        let url = browsers[id]?.url?.absoluteString ?? tab.url
        guard !InternalPage.isInternal(url), url != tab.savedURL else { return nil }
        return (tab, url)
    }

    private func typedCommandIsAvailable(_ command: CommandBarTypedCommand, items: [SidebarItemReference]?, profileID: UUID) -> Bool {
        switch command.kind {
        case .undo(let name):
            return windowUndoContextAvailable && folderUndoContextAvailable && folderUndo.command(.undo)?.name == name
        case .redo(let name):
            return windowUndoContextAvailable && folderUndoContextAvailable && folderUndo.command(.redo)?.name == name
        case .pinToSpace(let id, _, _):
            guard let items, let space = store.state.spaces.first(where: { $0.id == id }) else { return false }
            return !store.isEphemeral && !isPrivateBrowsing && spaceCommandsAvailable && activePeek == nil
                && id != activeSpaceID && commandBarSpaceMoveIsPossible(items, to: space)
        case .pinToNewFolder:
            guard let items else { return false }
            return !isPrivateBrowsing && folderUndoContextAvailable && !folderUndo.isBusy
                && spaceCommandsAvailable && activePeek == nil
                && commandBarFolderCollectionIsPossible(items)
        case .duplicateCurrentTab:
            guard let items else { return false }
            return folderDuplicateContextAvailable && spaceCommandsAvailable && activePeek == nil
                && commandBarDuplicateIsPossible(items)
        case .replacePinWithCurrentPage:
            return replaceablePinnedTab != nil
        case .addSplit, .convertSplit, .addVerticalSplit:
            guard let split = typedSplitCommand(command.kind), splitCommandIsAvailable(split) else { return false }
            if case .convertSplit(let vertical) = command.kind {
                return activeSplitLayout.map { ($0.orientation == .vertical) != vertical } == true
            }
            return true
        case .newWebDocument, .searchSettings, .airTrafficControl:
            return !isPrivateBrowsing && !isPopupWindow
        case .settingsPane, .appearance, .copyAppInfo:
            return !isPopupWindow && !isClosing
        case .revealAppData:
            return !store.isEphemeral && !isPrivateBrowsing && !isPopupWindow
        case .capturePortrait:
            return canCapturePage
        case .openTaskManager:
            return canPerformPageTool(.taskManager)
        }
    }

    private func prepareTypedCommand(_ command: CommandBarTypedCommand, items: [SidebarItemReference]?, profileID: UUID) -> (() -> Bool)? {
        guard typedCommandIsAvailable(command, items: items, profileID: profileID) else { return nil }
        switch command.kind {
        case .undo, .redo:
            let direction: FolderUndoManager.Direction
            if case .undo = command.kind { direction = .undo } else { direction = .redo }
            guard let action = folderUndo.command(direction), folderUndo.canPerform(action) else { return nil }
            return { [weak self] in self?.folderUndo.perform(action) == true }
        case .pinToSpace(let id, _, _):
            guard let items, currentSidebarMenuItems == items else { return nil }
            return prepareSidebarSpaceMove(items, to: id, pinsToday: true)
        case .pinToNewFolder:
            guard let items, currentSidebarMenuItems == items else { return nil }
            return prepareFolderFromItems(items)
        case .duplicateCurrentTab:
            guard let items, currentSidebarMenuItems == items else { return nil }
            return prepareSidebarDuplicate(items)
        case .replacePinWithCurrentPage:
            guard let replaceable = replaceablePinnedTab else { return nil }
            let expected = replaceable.tab, url = replaceable.url
            return { [weak self] in
                guard let self, self.replaceablePinnedTab?.tab == expected,
                      self.store.replaceSavedHome(expected, url: url, title: expected.title) else { return false }
                self.render(self.store.state)
                return true
            }
        case .addSplit, .convertSplit, .addVerticalSplit:
            guard let split = typedSplitCommand(command.kind), let target = splitCommandTarget(split) else { return nil }
            return { guard target.isAvailable else { return false }; target.perform(); return true }
        case .newWebDocument(let document):
            return openTypedDestination(document.url)
        case .searchSettings:
            return openTypedDestination("parc://settings/searchEngines")
        case .airTrafficControl:
            return { [weak self] in
                guard let self else { return false }
                self.showSettings(pane: .links)
                return self.settings?.showAirTrafficControl() == true
            }
        case .settingsPane(let pane):
            let destination: SettingsWindow.Pane
            switch pane {
            case .account: destination = .membership
            case .general: destination = .general
            case .profiles: destination = .spaces
            case .shortcuts: destination = .shortcuts
            case .links: destination = .links
            case .appIcon: destination = .icon
            case .advanced: destination = .advanced
            }
            return { [weak self] in
                guard let self else { return false }
                self.showSettings(pane: destination)
                return self.isPrivateBrowsing || self.settings?.window?.isVisible == true
            }
        case .appearance(let appearance):
            let action = NSSelectorFromString(appearance.selectorName)
            return { NSApp.sendAction(action, to: nil, from: nil) }
        case .copyAppInfo:
            return { [weak self] in
                guard let self else { return false }
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(Self.buildInfo, forType: .string) else { return false }
                _ = self.showToast(.copiedBuildInfo)
                return true
            }
        case .revealAppData:
            let directory = store.directory
            return { NSWorkspace.shared.activateFileViewerSelecting([directory]); return true }
        case .capturePortrait:
            return { [weak self] in
                guard let self, self.canCapturePage else { return false }
                self.capturePage(.portrait)
                return self.pageCapture != nil
            }
        case .openTaskManager:
            guard let browser = currentBrowser else { return nil }
            return { [weak self, weak browser] in
                guard let self, let browser, self.currentBrowser === browser,
                      self.canPerformPageTool(.taskManager) else { return false }
                return browser.performPageTool(.taskManager)
            }
        }
    }

    private func openTypedDestination(_ url: String) -> () -> Bool {
        { [weak self] in
            guard let self, !self.isPrivateBrowsing else { return false }
            let creation = self.creationProvenance(activeTabID: self.currentTabID)
            var opened = false
            self.performWindowCommand {
                let id = self.store.open(url, creation: creation)
                self.presentation.recordCreation(id, state: self.store.state)
                opened = true
            }
            return opened
        }
    }
    private var currentRevealSidebarItem: SidebarItemReference? {
        guard activePeek == nil, let id = currentTabID else { return nil }
        if let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(id) }) {
            return .split(group.id)
        }
        return .tab(id)
    }
    var canRevealCurrentTabInSidebar: Bool {
        guard !store.isEphemeral, !isPrivateBrowsing, spaceCommandsAvailable,
              let item = currentRevealSidebarItem else { return false }
        return SidebarItemReveal(item: item, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) != nil
    }
    func revealCurrentTabInSidebar() {
        guard canRevealCurrentTabInSidebar, let item = currentRevealSidebarItem else { return }
        let spaceID = activeSpaceID, profileID = activeProfileID
        commandBar?.dismiss()
        guard canRevealCurrentTabInSidebar, currentRevealSidebarItem == item,
              activeSpaceID == spaceID, activeProfileID == profileID else { return }
        revealSidebarItem(item, spaceID: spaceID, profileID: profileID)
    }
    var canRenameActiveSpace: Bool {
        spaceCommandsAvailable && managementSpace(activeSpaceID) != nil && !sidebar.isEditingSpaceName
    }
    func renameActiveSpace() {
        guard canRenameActiveSpace else { return }
        renameSpace(activeSpaceID)
    }
    var canOpenPageInNewTab: Bool {
        presentation.isReady && !isClosing && !wholeWindowClose && !isPrivateBrowsing && !isPopupWindow
    }
    func openExtensionsPage(addExtension: Bool) {
        openPageInNewTab(addExtension ? "https://chromewebstore.google.com/category/extensions" : "parc://extensions/")
    }
    func openHistoryPage() { openPageInNewTab("parc://history/") }
    func openReleaseNotes(fragment: String? = nil) {
        guard let url = SoftwareUpdateBanner.releaseNotesURL else { return }
        openPageInNewTab(url.absoluteString + (fragment.map { "#" + $0 } ?? ""))
    }
    private func openPageInNewTab(_ address: String) {
        guard canOpenPageInNewTab, window?.isKeyWindow == true, windowCommandSecurityAvailable,
              let url = URL(string: address) else { return }
        openExactAddress(url)
    }
    func openExactAddress(_ url: URL) {
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.openResolvedURL(url, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
    }
}
