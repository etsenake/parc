import AppKit
import Combine

extension BrowserWindowController {
    @discardableResult
    func selectTab(_ id: UUID, extendingSplit: Bool = false) -> Bool {
        sidebarPreviews?.dismiss()
        guard !isPopupWindow || (id == currentTabID && !extendingSplit) else { return false }
        if let retry = transferRecoveries[id] { retry(); return false }
        guard presentation.isReady else { return false }
        let members: [UUID] = {
            guard !extendingSplit, let tab = store.state.tab(id) else { return [id] }
            let space = tab.kind == .favorite ? activeSpaceID : tab.spaceID
            return SidebarSplitItems.groups(in: store.state, spaceID: space).first { $0.tabIDs.contains(id) }?.tabIDs ?? [id]
        }()
        guard let elsewhere = PageReparenting.pagesToMove(members,
                usableHere: { $0 == id && extendingSplit ? ownership.canUse($0, owner: presentationID) : switcherCanUse($0) },
                movable: canMovePageHere) else { return false }
        if !elsewhere.isEmpty {
            return movePagesHere(elsewhere[...]) { [weak self] in self?.selectTab(id, extendingSplit: extendingSplit) ?? false }
        }
        if extendingSplit {
            let space = activeSpaceID, profile = activeProfileID
            var plan: (ids: [UUID: UUID], documents: [UUID: SidebarDocumentReference])?
            performWindowCommand(selectNativePage: false) {
                guard let made = splitHomePlan(store.splitExtensionHomes(id)) else { return }
                plan = made
                store.selectTab(id, extendingSplit: true, savedHomeIDs: made.ids, documents: made.documents)
            }
            guard let plan else { return false }
            if selectedTabIDs.contains(id) { openSplitHomes(plan.ids, profileID: profile, originatingSpaceID: space) }
        } else {
            let previous = selectedTabIDs
            let expected: [UUID] = {
                guard let tab = store.state.tab(id) else { return [id] }
                let space = tab.kind == .favorite ? activeSpaceID : tab.spaceID
                return SidebarSplitItems.groups(in: store.state, spaceID: space)
                    .first { $0.tabIDs.contains(id) }?.tabIDs ?? [id]
            }()
            var committed = false
            let removal = previous == expected ? nil
                : presentationSetMediaRemoval(capturing: previous, remaining: { Set(self.selectedTabIDs) }) {
                    self.selectedTabIDs == expected && self.store.state.selectedTabIDs == expected
                }
            performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
                store.selectTab(id, extendingSplit: false)
                committed = store.state.selectedTabIDs == expected
            }
        }
        if selectedTabIDs.contains(id) {
            focusedTabID = id; updateNavigation(); requestNativeSelection(); focusSelectedContent(); return true
        }
        return false
    }

    var ownsSpaceCommandFocus: Bool {
        guard let window, NSApp.isActive, window.isVisible, !window.isMiniaturized else { return false }
        return window.isKeyWindow
    }

    var windowCommandSecurityAvailable: Bool {
        guard let window, let binding = nativeBinding, binding.window === window else { return false }
        return binding.canParticipateInPageTransfer
    }

    var ownsWindowCommandFocus: Bool {
        guard let window, NSApp.isActive, window.isVisible, !window.isMiniaturized else { return false }
        return ownsSpaceCommandFocus || (window.isMainWindow && navigationHistory?.ownsKeyWindow(in: window) == true)
    }

    func prepareLibraryMenuCommand() -> Bool {
        let profileID = activeProfileID
        guard let original = window, ownsWindowCommandFocus,
              windowCommandSecurityAvailable, canOwnDownloadDialog(for: profileID) else { return false }
        func current() -> Bool {
            window === original && activeProfileID == profileID && ownsWindowCommandFocus
                && windowCommandSecurityAvailable && canOwnDownloadDialog(for: profileID)
        }
        if navigationHistory?.ownsKeyWindow(in: original) == true {
            navigationHistory?.dismiss()
            guard current() else { return false }
        }
        if commandBar?.hasFocus == true {
            commandBar?.dismiss()
            guard current() else { return false }
        }
        return original.isKeyWindow && current()
    }

    private var canCloseBrowserWindow: Bool {
        presentation.isReady && nativeBinding != nil && !isClosing
            && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && ownsSpaceCommandFocus
    }
    func prepareCloseWindowMenuItem(_ item: NSMenuItem) -> Bool {
        guard let original = window else { item.representedObject = nil; return false }
        let command = BrowserWindowCloseCommand(window: original,
            ownerIsAvailable: { [weak self, weak original] in
                guard let self, let original, self.window === original else { return false }
                return self.canCloseBrowserWindow
            }, prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) })
        item.representedObject = command.isAvailable ? command : nil
        return command.isAvailable
    }

    func prepareExitMenuItem(_ item: NSMenuItem) -> Bool {
        item.representedObject = nil
        guard let original = window, let binding = nativeBinding else { return false }
        let common: () -> Bool = { [weak self, weak original, weak binding] in
            guard let self, let original, let binding, self.window === original,
                  self.nativeBinding === binding, binding.window === original else { return false }
            return self.presentation.isReady && self.ownsSpaceCommandFocus
                && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.windowCloseApproved && self.closingTabIDs.isEmpty
                && self.modelRetirementIDs.isEmpty && self.peekRetirementParents.isEmpty
                && self.transferringTabIDs.isEmpty && self.resolvingTransfers.isEmpty
                && self.transferRecoveries.isEmpty && self.pageCapture == nil
                && self.tabSwitcher == nil && self.navigationHistory == nil
                && self.themePopover == nil && !self.siteControlCenterDefers
                && PCNativeBrowserApplication.canUseWindowUndo(in: original)
        }
        guard common() else { return false }
        let available: () -> Bool
        let execute: () -> Bool
        if let session = spaceCreation {
            available = { [weak self, weak session] in
                guard let self, let session else { return false }
                return common() && self.creationOwnerIsCurrent(session)
                    && !session.committing && !session.view.hasMarkedText
            }
            execute = { [weak self, weak session] in
                guard let self, let session, self.creationOwnerIsCurrent(session),
                      !session.committing, !session.view.hasMarkedText else { return false }
                self.cancelSpaceCreation(); return true
            }
        } else if let peek = activePeek {
            available = { [weak self, weak peek] in
                guard let self, let peek else { return false }
                return common() && self.activePeek === peek && self.presentedPeek(for: peek.page) === peek
                    && self.selectedNativePage() === peek.page && peek.canPrepareExit
            }
            execute = { [weak peek] in
                guard let peek, peek.canRequestExit else { return false }
                peek.requestDismiss(.exit); return true
            }
        } else if let page = selectedNativePage(), let native = binding.prepareFullscreenExit(for: page) {
            available = { [weak self, weak page] in
                guard let self, let page else { return false }
                return common() && self.activePeek == nil && self.selectedNativePage() === page && native.isAvailable
            }
            execute = { native.perform() }
        } else {
            guard nativeFullscreenTabID == nil,
                  original.styleMask.contains(.fullScreen) else { return false }
            let fullscreen = BrowserWindowFullscreenCommand(window: original,
                ownerIsAvailable: { [weak self, weak original] in
                    guard let self, let original else { return false }
                    return common() && self.activePeek == nil && self.nativeFullscreenTabID == nil
                        && original.styleMask.contains(.fullScreen)
                })
            available = {
                let validation = NSMenuItem(title: "Exit Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
                return fullscreen.validate(validation)
            }
            execute = { fullscreen.perform(nil) }
        }
        let command = BrowserExitCommand(window: original, targetIsAvailable: available,
            prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) }, execute: execute)
        item.representedObject = command.isAvailable ? command : nil
        return command.isAvailable
    }

    func prepareFullscreenMenuItem(_ item: NSMenuItem) -> Bool {
        guard let original = window else { item.representedObject = nil; return false }
        let command = BrowserWindowFullscreenCommand(window: original,
            ownerIsAvailable: { [weak self, weak original] in
                guard let self, let original, self.window === original else { return false }
                return self.presentation.isReady && self.nativeBinding != nil && !self.isClosing
                    && !self.wholeWindowClose && !self.windowClosePending && !self.windowCloseApproved
                    && self.ownsSpaceCommandFocus
            }, prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) })
        let available = command.validate(item)
        item.representedObject = available ? command : nil
        return available
    }

    var spaceStateAvailable: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose
            && !windowClosePending && !windowCloseApproved && nativeFullscreenTabID == nil
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && tabSwitcher == nil && themePopover == nil
    }
    var spaceCommandsAvailable: Bool {
        guard spaceStateAvailable, ownsSpaceCommandFocus,
              let window, window.attachedSheet == nil else { return false }
        return PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
    }

    func canSelectSpace(_ id: UUID, profileID: UUID? = nil) -> Bool {
        if isPrivateBrowsing { return false }
        return spaceCommandsAvailable && store.state.spaces.contains { space in
            space.id == id && (profileID == nil || space.profileID == profileID)
                && store.state.profiles.contains(where: { $0.id == space.profileID })
        }
    }

    @discardableResult
    func selectSpaceFromUser(_ id: UUID, profileID: UUID? = nil) -> Bool {
        guard canSelectSpace(id, profileID: profileID) else { return false }
        commandBar?.dismiss()
        guard canSelectSpace(id, profileID: profileID), let window,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
        cancelSpaceCreation(restoreFocus: false)
        guard activeSpaceID != id else { return true }
        navigationHistory?.dismiss()
        sidebarPreviews?.dismiss()
        closeLibrary(restoreFocus: false)
        selectSpace(id)
        return activeSpaceID == id
    }

    private func adjacentSpace(forward: Bool) -> BrowserSpace? {
        let spaces = store.state.spaces
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return nil }
        return spaces[(index + (forward ? 1 : spaces.count - 1)) % spaces.count]
    }

    func canCycleSpace(forward: Bool) -> Bool {
        guard let destination = adjacentSpace(forward: forward) else { return false }
        return canSelectSpace(destination.id, profileID: destination.profileID)
    }

    func cycleSpace(forward: Bool) {
        guard let destination = adjacentSpace(forward: forward) else { return }
        selectSpaceFromUser(destination.id, profileID: destination.profileID)
    }

    func selectSpace(_ id: UUID) {
        cancelSpaceCreation(restoreFocus: false)
        sidebarPreviews?.dismiss()
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else { return }
        let previousProfile = activeProfileID
        let outgoing = renderedPaneIDs
        let removal = presentationSetMediaRemoval(capturing: outgoing, remaining: { Set(self.renderedPaneIDs) }) {
            self.activeSpaceID == id
        }
        presentation.recordFocusedTab(currentTabID)
        pendingNativeSelection = nil
        presentation.selectSpace(id, state: store.state) { ownership.canUse($0, owner: presentationID) }
        focusedTabID = presentation.preferredFocusedTabID
        onSessionRecordChange?()
        let restoredLayout = presentation.splitLayout
        prepareStoreContext(restoringSplitLayout: restoredLayout)
        render(store.state)
        removal?()
        requestNativeSelection()
        focusSelectedContent()
        if previousProfile != activeProfileID { downloadReview?.dismiss() }
        refreshDownloads()
        if !isPopupWindow && !isPrivateBrowsing { store.linkRouting.noteVisitedSpace(activeSpaceID) }
        noteReturnGate()
    }

    func recordRecentTabSelection() {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              transferringTabIDs.isEmpty, !selectedTabIDs.isEmpty else { return }
        presentation.recordSelectionForReturn(currentTabID, state: store.state)
        recentTabOrder.record(selectedTabIDs, focus: currentTabID)
        if let first = selectedTabIDs.first, selectedTabIDs.allSatisfy({ switcherCanUse($0) }) {
            closedItems.recordSelection(selectedTabIDs, focusedTabID: currentTabID ?? first, state: store.state)
            onSessionRecordChange?()
            if TabSelectionHistory.isEnabled { tabSelectionHistory.record(.init(tabIDs: selectedTabIDs, focusedTabID: currentTabID ?? first,
                spaceID: activeSpaceID, profileID: activeProfileID,
                orientation: activeSplitLayout?.orientation ?? .horizontal)) }
        }
        tabSwitcher?.dismissIfInvalid()
    }

    func switcherCanUse(_ id: UUID) -> Bool {
        ownership.canUse(id, owner: presentationID) && !closingTabIDs.contains(id)
            && !modelRetirementIDs.contains(id) && !transferringTabIDs.contains(id)
            && !store.retiringTabIDs.contains(id) && transferRecoveries[id] == nil
    }
    func canUseOrMoveHere(_ id: UUID) -> Bool { switcherCanUse(id) || canMovePageHere(id) }
    func canCloseOrMoveHere(_ id: UUID) -> Bool { ownership.canUse(id, owner: presentationID) || canMovePageHere(id) }

    private var tabCommandsAvailable: Bool {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              let window else { return false }
        return PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
    }

    private func canSelectTabCommandItem(_ item: RecentTabOrder.Item) -> Bool {
        item.spaceID == activeSpaceID && item.profileID == activeProfileID
            && item.tabIDs != selectedTabIDs && !item.tabIDs.isEmpty
            && item.tabIDs.allSatisfy { id in
                canUseOrMoveHere(id) && store.state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == item.profileID
                        && ($0.kind == .favorite || $0.spaceID == item.spaceID) })
            }
    }

    private func positionalDestination(forward: Bool) -> RecentTabOrder.Item? {
        let items = PositionalTabNavigation.items(state: store.state, spaceID: activeSpaceID,
            selected: selectedTabIDs, focused: currentTabID, available: { self.canUseOrMoveHere($0) })
        return PositionalTabNavigation.destination(items, selected: selectedTabIDs, forward: forward)
    }

    func canSelectAdjacentTab(forward: Bool) -> Bool {
        tabCommandsAvailable && tabSwitcher == nil
    }

    func selectAdjacentTab(forward: Bool) {
        guard canSelectAdjacentTab(forward: forward), let item = positionalDestination(forward: forward),
              canSelectTabCommandItem(item) else { return }
        sidebarPreviews?.dismiss()
        selectRecentItem(item)
    }

    private func sidebarItemDestination(number: Int) -> RecentTabOrder.Item? {
        let defaults = UserDefaults.standard
        let items = PositionalTabNavigation.items(state: store.state, spaceID: activeSpaceID,
            selected: selectedTabIDs, focused: currentTabID,
            includeFavorites: !defaults.bool(forKey: NumberedTarget.excludeFavoritesKey), available: { _ in true })
        return NumberedTarget.destination(items, number: number,
                                          ninthItemEnabled: defaults.bool(forKey: NumberedTarget.ninthItemKey))
    }

    func canSelectSidebarItem(number: Int) -> Bool {
        guard tabCommandsAvailable, tabSwitcher == nil, let item = sidebarItemDestination(number: number) else { return false }
        return item.tabIDs == selectedTabIDs || canSelectTabCommandItem(item)
    }

    func selectSidebarItem(number: Int) {
        guard canSelectSidebarItem(number: number), let item = sidebarItemDestination(number: number),
              item.tabIDs != selectedTabIDs else { return }
        sidebarPreviews?.dismiss()
        _ = selectRecentItem(item)
    }

    func canCycleTabHistory(forward: Bool) -> Bool {
        TabSelectionHistory.isEnabled && tabCommandsAvailable && tabSwitcher == nil
    }

    func cycleTabHistory(forward: Bool) {
        guard canCycleTabHistory(forward: forward) else { return }
        sidebarPreviews?.dismiss()
        let previous = tabSelectionHistory
        guard let item = tabSelectionHistory.move(in: activeSpaceID, forward: forward, available: canSelectTabCommandItem) else { return }
        if !selectRecentItem(item) { tabSelectionHistory = previous }
    }

    var canShowRecentTabSwitcher: Bool {
        guard tabCommandsAvailable else { return false }
        if tabSwitcher != nil { return true }
        var order = recentTabOrder
        return order.items(state: store.state, selected: selectedTabIDs, currentSpace: activeSpaceID,
                           available: { self.canUseOrMoveHere($0) }).count > 1
    }

    func cycleRecentTab(forward: Bool) {
        sidebarPreviews?.dismiss()
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
        if let tabSwitcher { tabSwitcher.cycle(forward: forward); return }
        recordRecentTabSelection()
        let selections = recentTabOrder.items(state: store.state, selected: selectedTabIDs,
            currentSpace: activeSpaceID, available: { self.canUseOrMoveHere($0) })
        guard !selections.isEmpty, selections.count > 1 || selectedTabIDs.isEmpty else { return }
        let items = recentSwitcherItems(selections, in: window)
        var sourceIDs = selectedTabIDs, sourceSpace = activeSpaceID
        var confirmedClosedIDs = Set<UUID>()
        let event = shortcutInvocationEvent ?? NSApp.currentEvent
        let controller = RecentTabSwitcher(items: items, currentTabIDs: sourceIDs, parent: window, theme: windowPaletteTheme,
            forward: forward, event: event,
            next: KeyboardShortcuts.shared.activeShortcut(for: "cycleToNextRecentTab:"),
            previous: KeyboardShortcuts.shared.activeShortcut(for: "cycleToPreviousRecentTab:"))
        controller.isCurrent = { [weak self, weak window] items in
            guard let self, let window, self.window === window,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                  !self.windowClosePending, self.transferringTabIDs.isEmpty,
                  self.resolvingTransfers.isEmpty, self.selectedTabIDs == sourceIDs,
                  self.activeSpaceID == sourceSpace else { return false }
            return items.allSatisfy { item in
                if let overlay = item.overlay {
                    guard let page = overlay.page, !page.isClosed,
                          let peek = self.peeks[page.identifier], peek.identity == overlay.id,
                          peek.page === page, !peek.closePending,
                          item.selection.tabIDs == [peek.parentTabID],
                          self.browsers[peek.parentTabID]?.nativePage === peek.parentPage,
                          !self.peekRetirementParents.contains(peek.parentTabID) else { return false }
                }
                return self.store.state.spaces.contains { $0.id == item.selection.spaceID && $0.profileID == item.selection.profileID }
                    && item.components.allSatisfy { component in
                        self.canUseOrMoveHere(component.id)
                            && self.store.state.containsTab(component.id, where: { $0.archivedAt == nil
                                && $0.profileID == item.selection.profileID
                                && ($0.kind == .favorite || $0.spaceID == item.selection.spaceID) })
                            && self.browsers[component.id]?.nativePage === component.page
                    }
            }
        }
        controller.onComplete = { [weak self, weak controller] selection in
            guard let self, let controller, self.tabSwitcher === controller else { return }
            self.tabSwitcher = nil
            self.noteReturnGate()
            if let selection { self.selectRecentItem(selection) }
        }
        controller.onCloseItem = { [weak self, weak controller, weak window] selection, completion in
            guard let self, let controller, self.tabSwitcher === controller,
                  let window, self.window === window,
                  selection.tabIDs.allSatisfy({ self.canUseOrMoveHere($0) }),
                  self.retirementUnavailableReason?(Set(selection.tabIDs)) == nil else { completion(nil); return }
            let elsewhere = selection.tabIDs.filter { !self.ownership.canUse($0, owner: self.presentationID) }
            if !elsewhere.isEmpty {
                completion(nil)
                guard elsewhere.allSatisfy(self.canMovePageHere) else { self.refuseTabMove(); return }
                _ = self.movePagesHere(elsewhere[...]) { [weak self] in
                    guard let self, selection.tabIDs.allSatisfy({ self.ownership.canUse($0, owner: self.presentationID) }),
                          self.retirementUnavailableReason?(Set(selection.tabIDs)) == nil else { return false }
                    self.prepareStoreContext()
                    self.closeTabsWithReopen(Set(selection.tabIDs)) { [weak self] approved in
                        guard let self, !self.isClosing else { return }
                        guard approved else { selection.tabIDs.forEach(self.returnIfUnshown); return }
                        for id in selection.tabIDs { self.presentation.remove(id) }
                        self.render(self.store.state); self.requestNativeSelection()
                    }
                    return true
                }
                return
            }
            self.prepareStoreContext()
            self.closeTabsWithReopen(Set(selection.tabIDs)) { [weak self, weak controller, weak window] approved in
                guard let self else { completion(nil); return }
                guard approved else { completion(.refused); return }
                confirmedClosedIDs.formUnion(selection.tabIDs)
                for id in selection.tabIDs { self.presentation.remove(id) }
                self.render(self.store.state); self.requestNativeSelection()
                guard let controller, self.tabSwitcher === controller,
                      let window, self.window === window else { completion(nil); return }
                sourceIDs = self.selectedTabIDs; sourceSpace = self.activeSpaceID
                let available = self.recentTabOrder.items(state: self.store.state,
                    selected: sourceIDs, currentSpace: sourceSpace, available: {
                        !confirmedClosedIDs.contains($0) && self.canUseOrMoveHere($0)
                    })
                completion(.closed(self.recentSwitcherItems(available, in: window), theme: self.windowPaletteTheme))
            }
        }
        tabSwitcher = controller
        controller.start(event: event)
    }

    private func recentSwitcherItems(_ selections: [RecentTabOrder.Item], in window: NSWindow) -> [RecentTabSwitcher.Item] {
        let privateWindow = store.isEphemeral
        return selections.map { selection in
            let components = selection.tabIDs.compactMap { id -> RecentTabSwitcher.Component? in
                guard let tab = store.state.tab(id) else { return nil }
                var preview: NSImage? = store.placeholderImages.image(for: id, in: presentationID).map { NSImage(cgImage: $0, size: .zero) }
                if preview == nil, InternalPage(urlString: tab.url) == nil, browsers[id] == nil, let pane = panes[id], pane.window === window,
                   !pane.isHiddenOrHasHiddenAncestor,
                   let bitmap = pane.bitmapImageRepForCachingDisplay(in: pane.bounds) {
                    pane.cacheDisplay(in: pane.bounds, to: bitmap)
                    let image = NSImage(size: pane.bounds.size); image.addRepresentation(bitmap); preview = image
                }
                let title = tab.title.isEmpty ? (tab.url.isEmpty ? "New Tab" : tab.url) : tab.title
                var component = RecentTabSwitcher.Component(id: id, title: title,
                    page: browsers[id]?.nativePage, localPreview: preview)
                switch InternalPage(urlString: tab.url) {
                case .note?: component.template = RecentSwitcherArtwork.note.map { .init(image: $0, title: title) }
                case .easel?: component.template = RecentSwitcherArtwork.easel.map { .init(image: $0, title: title) }
                case nil: if privateWindow { component.template = RecentSwitcherArtwork.incognito.map { .init(image: $0, title: nil) } }
                }
                if let page = InternalPage(urlString: tab.url) {
                    component.favicon = DocumentDefaultIcon.fallback(named: page.sidebarFallbackSymbol)
                    if let note = page.noteURL {
                        switch NoteTabIconArt.shared.art(forNote: note) {
                        case .image(let image): component.favicon = image
                        case .pending:
                            component.faviconRequest = { completion in
                                NoteTabIconArt.shared.requestImage(forNote: note, completion: completion)
                            }
                        case .standard: break
                        }
                    }
                } else if let page = browsers[id]?.nativePage, !page.isClosed, let icon = page.favicon {
                    component.favicon = icon
                } else if !privateWindow, mayReadCachedFavicons, let url = URL(string: tab.url) {
                    let path = store.independentEngineProfilePath(for: tab.profileID)
                    component.faviconRequest = { [weak self] completion in
                        PCNativeBrowserApplication.favicon(for: url, profilePath: path) { [weak self] image in
                            MainActor.assumeIsolated {
                                guard let self, !self.isClosing,
                                      self.store.state.containsTab(id, where: { $0.url == tab.url
                                          && $0.profileID == tab.profileID && $0.archivedAt == nil }) else { completion(nil); return }
                                completion(image)
                            }
                        }
                    }
                }
                if let capture = capturePresentations[id] {
                    component.isRecordingMedia = FavoriteTileOverlayRules.isRecording(camera: capture.camera,
                        microphone: capture.microphone, tab: capture.tab, window: capture.window,
                        display: capture.display, mirrored: capture.mirrored, shared: capture.shared)
                }
                return component
            }
            var item = RecentTabSwitcher.Item(selection: selection, components: components,
                spaceName: store.state.spaces.first(where: { $0.id == selection.spaceID })?.name ?? "")
            if selection.tabIDs.count > 1,
               let layout = store.state.splitLayouts.first(where: { Set($0.tabIDs) == Set(selection.tabIDs) }),
               SidebarSplitCellLayout.usesCustomInfo(title: layout.customTitle, hasIcon: layout.customIcon != nil, editing: false) {
                let title = layout.customTitle.flatMap { $0.isEmpty ? nil : $0 }
                    ?? SidebarSplitCellLayout.defaultTitle(count: selection.tabIDs.count)
                item.customInfo = .init(icon: layout.customIcon?.image(size: SidebarSplitCellLayout.countIconSize), title: title)
            }
            if selection.tabIDs.count == 1, let id = selection.tabIDs.first, !peekRetirementParents.contains(id),
               let page = browsers[id]?.nativePage,
               let peek = peeks.values.filter({ $0.parentTabID == id && $0.parentPage === page
                   && !$0.page.isClosed && !$0.closePending })
                   .min(by: { $0.identity.uuidString < $1.identity.uuidString }) {
                item.overlay = RecentTabSwitcher.Component(id: peek.identity, title: peek.page.title,
                                                           page: peek.page, localPreview: nil)
            }
            return item
        }
    }

    @discardableResult
    func selectRecentItem(_ item: RecentTabOrder.Item) -> Bool {
        guard store.state.spaces.contains(where: { $0.id == item.spaceID && $0.profileID == item.profileID }),
              item.tabIDs.allSatisfy({ id in store.state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == item.profileID
                      && ($0.kind == .favorite || $0.spaceID == item.spaceID) }) }),
              let elsewhere = PageReparenting.pagesToMove(item.tabIDs, usableHere: switcherCanUse, movable: canMovePageHere)
        else { return false }
        if !elsewhere.isEmpty { return movePagesHere(elsewhere[...]) { [weak self] in self?.selectRecentItem(item) ?? false } }
        let previous = selectedTabIDs
        let expected = item.tabIDs
        var committed = false
        let removal = previous == expected ? nil
            : presentationSetMediaRemoval(capturing: previous, remaining: { Set(self.selectedTabIDs) }) {
                self.selectedTabIDs == expected && self.store.state.selectedTabIDs == expected
            }
        performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
            store.selectSpace(item.spaceID)
            store.setSplit(item.tabIDs)
            committed = store.state.selectedTabIDs == expected
        }
        guard selectedTabIDs == item.tabIDs else { return false }
        focusedTabID = item.focusedTabID
        recordRecentTabSelection()
        updateNavigation(); requestNativeSelection(); focusSelectedContent()
        return true
    }
    func restoreClosedTab() {
        guard let original = window, ownsWindowCommandFocus, windowCommandSecurityAvailable,
              let step = reopenClosedStep else { return }
        func isCurrent() -> Bool {
            window === original && original.isKeyWindow && original.attachedSheet == nil
                && PCNativeBrowserApplication.canPresentTabSwitcher(in: original)
                && reopenClosedStep?.id == step.id
        }
        if navigationHistory?.ownsKeyWindow(in: original) == true {
            navigationHistory?.dismiss()
            guard window === original, ownsWindowCommandFocus, windowCommandSecurityAvailable else { return }
        }
        commandBar?.dismiss()
        guard WindowOwnerSequence.run(while: isCurrent, steps: [
            { self.navigationHistory?.dismiss() },
            { self.closeLibrary(restoreFocus: false) }
        ]) else { return }
        switch step {
        case .items(let record): restoreClosedRecord(record)
        case .folder(let undo): reopenDeletedFolder(undo)
        case .peek(let record): reopenClosedPeek(record)
        }
    }
    private func reopenDeletedFolder(_ undo: FolderDeletionUndo) {
        guard let window else { return }
        do {
            let committed = try store.undoFolderDeletion(undo, shouldCommit: { [weak self, weak window] in
                guard let self, let window, self.window === window, self.folderUndoContextAvailable,
                      !self.folderUndo.isBusy else { return false }
                return undo.tabs.allSatisfy { self.switcherCanUse($0.id) }
            })
            guard committed else { return }
            _ = closedItems.consume(stepID: undo.id)
            let focused = presentation.finishFolderUndo(undo, state: store.state, available: { self.switcherCanUse($0) })
            if focused { focusedTabID = undo.focusedTabID }
            render(store.state); updateNavigation()
            if focused { requestNativeSelection(); focusSelectedLocalContent() }
        } catch { showError(error) }
    }
    private func reopenClosedPeek(_ record: ClosedPeekRecord) {
        if canMovePageHere(record.parentTabID) {
            movePeekParentHere(record.parentTabID, then: { [weak self] in self?.reopenClosedPeek(record) })
            return
        }
        guard selectTab(record.parentTabID), currentTabID == record.parentTabID,
              let binding = nativeBinding, let page = closedPeekParentPage(record),
              nativeBrowser(binding, canPresentPeekFrom: page), openClosedPeek(record, over: page) else { return }
        _ = closedItems.consume(stepID: record.id)
        for operation in peekUndoOperations.allObjects { operation.didReopen(record) }
    }
    private func restoreClosedRecord(_ record: ClosedItemRecord) {
        var restored = false
        store.closedPageHistory.restore(record.tabIDs)
        performWindowCommand(selectNativePage: false) {
            do { restored = try store.restoreClosedItem(record, regroupable: { self.canUseOrMoveHere($0) }) }
            catch {
                if let window { ParcDialog.inform(in: window, .init(title: "This tab couldn’t be reopened", message: error.localizedDescription)) }
            }
        }
        guard restored else { store.closedPageHistory.unrestore(record.tabIDs); return }
        _ = closedItems.consume(record)
        for operation in closeUndoOperations.allObjects { operation.didReopen(record) }
        focusedTabID = record.focusedTabID
        if SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(record.focusedTabID) })?
               .tabIDs.contains(where: canMovePageHere) == true {
            _ = selectTab(record.focusedTabID)
        }
        updateNavigation(); requestNativeSelection(); focusSelectedLocalContent()
    }
    func toggleSplit() {
        guard let last = selectedTabIDs.last else { return }
        beginSplitInsertion(activeSplitLayout?.orientation == .vertical ? .addBelow : .addAfter, paneID: last)
    }
    var currentURLForCopy: String? {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return nil }
        let url: String?
        if let commandBar { url = commandBar.selectedURL?.absoluteString }
        else { url = currentBrowser?.url?.absoluteString ?? currentTabID.flatMap { id in store.state.tab(id)?.url } }
        return url.flatMap { $0.isEmpty ? nil : $0 }
    }
    var canCopyCurrentURL: Bool {
        guard currentURLForCopy != nil else { return false }
        if commandBar != nil { return true }
        if let page = selectedNativePage() { return page.canCopyLink(as: .plain) }
        return true
    }
}
