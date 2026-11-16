import AppKit
import Combine

extension BrowserWindowController {
    func archiveTodayTabs(anchor: BrowserTab, order: [UUID], ids: Set<UUID>) {
        guard !isPopupWindow, !isClosing, !wholeWindowClose, !windowClosePending,
              window?.isKeyWindow == true, window?.attachedSheet == nil,
              anchor.profileID == activeProfileID, anchor.spaceID == activeSpaceID,
              SidebarTodayArchive.admits(anchorID: anchor.id, order: order, ids: ids, state: store.state,
                  spaceID: activeSpaceID, profileID: activeProfileID) else { return }
        archiveTabs(ids, reason: .manual)
    }

    func archiveTabs(_ ids: Set<UUID>, reason: ArchiveReason, in space: BrowserSpace? = nil) {
        guard !isClosing, !wholeWindowClose, !ids.isEmpty else { return }
        if let message = retirementUnavailableReason?(ids) {
            if let window { ParcDialog.inform(in: window, .init(title: "These tabs can’t be closed together yet", message: message)) }
            return
        }
        let originSpace = activeSpaceID, originProfile = activeProfileID
        let spaceID = space?.id ?? originSpace, profileID = space?.profileID ?? originProfile
        prepareStoreContext()
        let undo: CloseUndo = reason == .clearButton
            ? .register(.clear, registered: { [weak self] in self?.showToast(.clearedTabs, at: .window) })
            : .register(.archive)
        closeTabsWithReopen(ids, reason: reason, undo: undo, shouldCommit: { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose,
                  self.activeSpaceID == originSpace, self.activeProfileID == originProfile else { return false }
            return ids.allSatisfy { id in self.store.state.containsTab(id, where: { $0.archivedAt == nil && $0.kind == .today
                    && $0.spaceID == spaceID && $0.profileID == profileID }) }
        }) { [weak self] allowed in
            guard let self, allowed, !self.isClosing else { return }
            for id in ids { self.presentation.remove(id) }
            self.render(self.store.state)
            self.requestNativeSelection()
        }
    }

    private func registerClosedTabsUndo(_ record: ClosedTabsUndo, registered: (() -> Void)?) {
        guard windowUndoOwnerAvailable else { return }
        let operation = folderUndo.appendClosedTabs(record, store: store, canUse: { [weak self] ids, direction in
            guard let self, self.windowUndoContextAvailable else { return false }
            return direction == .undo ? ids.allSatisfy { self.canUseOrMoveHere($0) } : self.retirementUnavailableReason?(ids) == nil
        }, close: { [weak self] ids, current, done in
            guard let self, self.windowUndoContextAvailable else { done(nil); return }
            self.prepareStoreContext()
            self.closeTabsWithReopen(ids, reason: .manual, undo: .redo(record.prompt, done), shouldCommit: { [weak self] in
                guard let self, self.windowUndoOwnerAvailable else { return false }
                return current()
            }) { [weak self] approved in
                guard let self, approved, !self.isClosing else { return }
                for id in ids { self.presentation.remove(id) }
                self.render(self.store.state)
                self.requestNativeSelection()
            }
        }, didUndo: { [weak self] undone in
            guard let self else { return }
            self.store.closedPageHistory.restore(undone.tabs.map(\.id).filter { id in
                self.store.state.containsTab(id, where: { $0.archivedAt == nil })
            })
            let focused = self.presentation.finishClosedTabsUndo(undone, state: self.store.state,
                available: { self.switcherCanUse($0) })
            if focused { self.focusedTabID = undone.focusedTabID }
            self.render(self.store.state)
            if focused { self.requestNativeSelection(); self.focusSelectedLocalContent() }
        }, onError: { [weak self] in self?.showError($0) }) { _ in registered?() }
        closeUndoOperations.add(operation)
    }

    func closeTabsWithReopen(_ ids: Set<UUID>, reason: ArchiveReason = .manual,
                                     undo: CloseUndo = .register(.archive),
                                     completion: ((Bool) -> Void)? = nil) {
        closeTabsWithReopen(ids, reason: reason, undo: undo, shouldCommit: { true }, completion: completion)
    }

    func closeTabsWithReopen(_ ids: Set<UUID>, reason: ArchiveReason = .manual,
                                     undo: CloseUndo = .register(.archive),
                                     shouldCommit: @escaping () -> Bool,
                                     completion: ((Bool) -> Void)? = nil) {
        let originals = store.state.openTabs(where: { ids.contains($0.id) })
        let sourceSpace = originals.first(where: { $0.kind != .favorite })?.spaceID ?? activeSpaceID
        let profile = originals.first?.profileID ?? activeProfileID
        let intent = isPrivateBrowsing ? nil : ClosedItemIntent(ids: ids, state: store.state,
            spaceID: sourceSpace, profileID: profile, focusedTabID: currentTabID)
        let selection = selectedTabIDs, focus = focusedTabID, current = currentTabID
        let originSpace = activeSpaceID, originProfile = activeProfileID
        guard let nextSelection = FolderRemovalSelection.resolve(removing: Set(originals.map(\.id)),
            spaceID: originSpace, profileID: originProfile, state: store.state,
            selected: selection, focused: focus, referrerPool: presentation.referrerPool,
            previouslySelectedItemID: presentation.previouslySelectedItemID,
            available: { self.switcherCanUse($0) }) else {
            if case .redo(_, let done) = undo { done(nil) }
            completion?(false); return
        }
        let prompt: ClosedTabsUndo.Prompt
        switch undo { case .register(let value, _), .redo(let value, _): prompt = value }
        var record: ClosedTabsUndo?
        store.closeTabs(ids, reason: reason, selection: nextSelection, didCommit: { [weak self] before in
            guard let self else { return }
            record = ClosedTabsUndo(prompt: prompt, ids: ids, spaceID: sourceSpace, profileID: profile,
                                    focusedTabID: current, before: before, after: self.store.state)
        }, shouldCommit: { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.activeSpaceID == originSpace, self.activeProfileID == originProfile,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  shouldCommit() else { return false }
            return FolderRemovalSelection.resolve(removing: Set(originals.map(\.id)),
                spaceID: originSpace, profileID: originProfile, state: self.store.state,
                selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
                previouslySelectedItemID: self.presentation.previouslySelectedItemID,
                available: { self.switcherCanUse($0) }) == nextSelection
        }) { [weak self] approved in
            guard let self else {
                if case .redo(_, let done) = undo { done(nil) }
                completion?(false); return
            }
            if approved, !self.isClosing {
                if let intent { self.closedItems.record(intent, in: self.store.state) }
                switch undo {
                case .register(_, let registered): if let record { self.registerClosedTabsUndo(record, registered: registered) }
                case .redo(_, let done): done(record)
                }
                let applied = self.presentation.finishFolderRemoval(nextSelection, state: self.store.state,
                    available: { self.switcherCanUse($0) })
                if applied { self.focusedTabID = nextSelection.focusedTabID }
                for id in ids where !self.selectedTabIDs.contains(id)
                    && self.store.state.containsTab(id, where: { $0.archivedAt == nil }) {
                    if let note = self.noteEditors[id], note.editor.prepareToClose() {
                        note.editor.view.removeFromSuperview(); self.noteEditors.removeValue(forKey: id)
                    }
                    if let easel = self.easelEditors[id], self.embeddedEaselPages(forTabID: id).isEmpty {
                        easel.editor.retirePageOwner(); self.panes[id]?.clearNativeContent()
                        self.easelEditors.removeValue(forKey: id); self.easelFailures.removeValue(forKey: id)
                    }
                }
                if applied && !ids.isDisjoint(with: selection) {
                    self.render(self.store.state); self.requestNativeSelection(); self.focusSelectedLocalContent()
                }
            } else if case .redo(_, let done) = undo { done(nil) }
            completion?(approved)
        }
    }

    @discardableResult
    func closeTab(_ id: UUID) -> Bool {
        guard prepareNotesToClose([id]) else { return false }
        guard !wholeWindowClose, !isClosing, !windowClosePending,
              !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
              ownership.canUse(id, owner: presentationID),
              retirementUnavailableReason?([id]) == nil else { return false }
        prepareStoreContext()
        closeTabsWithReopen([id]) { [weak self] approved in
            guard let self, !self.isClosing else { return }
            guard approved else { self.returnIfUnshown(id); return }
            self.presentation.remove(id)
            if self.focusedTabID == id { self.focusedTabID = self.presentation.preferredFocusedTabID }
            self.render(self.store.state); self.requestNativeSelection()
        }
        return true
    }

    func closeClickedSplitPane(_ id: UUID) {
        guard SplitPaneCloseAdmission.accepts(tabID: id, selected: selectedTabIDs, isPeek: activePeek != nil) else { return }
        closeTab(id)
    }

    func prepareClearTodayMenuItem(_ item: NSMenuItem) -> Bool {
        item.representedObject = nil
        guard let original = window, let binding = nativeBinding else { return false }
        let spaceID = activeSpaceID, profileID = activeProfileID
        let command = BrowserClearTodayCommand(window: original,
            ownerIsAvailable: { [weak self, weak original, weak binding] in
                guard let self, let original, let binding, self.window === original,
                      self.nativeBinding === binding, binding.window === original else { return false }
                return !self.isPopupWindow && self.presentation.isReady && self.ownsSpaceCommandFocus
                    && self.activeSpaceID == spaceID && self.activeProfileID == profileID
                    && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                    && !self.windowCloseApproved && self.closingTabIDs.isEmpty
                    && self.modelRetirementIDs.isEmpty && self.transferringTabIDs.isEmpty
                    && self.resolvingTransfers.isEmpty && self.transferRecoveries.isEmpty
                    && self.spaceCreation == nil && self.pageCapture == nil
                    && self.tabSwitcher == nil && self.navigationHistory == nil
                    && self.themePopover == nil && !self.siteControlCenterDefers
                    && self.visibleTabs.contains { $0.kind == .today }
                    && PCNativeBrowserApplication.canUseWindowUndo(in: original)
            }, prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) },
            clear: { [weak self] in self?.clearToday() })
        item.representedObject = command.isAvailable ? command : nil
        return command.isAvailable
    }

    func clearToday() {
        archiveTabs(SpaceClearToday.ids(in: store.state, spaceID: activeSpaceID, profileID: activeProfileID), reason: .clearButton)
    }

    static func flushCookieStores() {
        if PCNativeBrowserApplication.responds(to: #selector(PCNativeBrowserApplication.flushCookieStores)) {
            PCNativeBrowserApplication.flushCookieStores()
        }
    }

    func persistTabHistory(all: Bool = false) {
        tabHistoryCapture?.cancel(); tabHistoryCapture = nil
        let ids = all ? Set(browsers.keys) : tabHistoryChanged
        tabHistoryChanged.removeAll()
        guard let archive = store.tabHistory,
              PCNativePage.instancesRespond(to: #selector(PCNativePage.archivedNavigationState)) else { return }
        for id in ids where !closingTabIDs.contains(id) {
            guard let page = browsers[id]?.nativePage, !page.isClosed,
                  let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
                  tab.profileID == browserProfiles[id],
                  let navigation = page.archivedNavigationState() else { continue }
            archive.store(.init(url: tab.url, profileID: tab.profileID, navigation: navigation), for: id)
        }
    }

    func scheduleTabHistoryCapture(_ id: UUID) {
        guard store.tabHistory != nil else { return }
        tabHistoryChanged.insert(id)
        guard tabHistoryCapture == nil else { return }
        let capture = DispatchWorkItem { [weak self] in self?.persistTabHistory() }
        tabHistoryCapture = capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: capture)
    }

    func launchHistory(for tab: BrowserTab) -> NSObject? {
        guard let archive = store.tabHistory,
              PCNativePage.responds(to: #selector(PCNativePage.navigationState(archive:profilePath:))),
              let navigation = archive.takeLaunchNavigation(for: tab.id, url: tab.url, profileID: tab.profileID) else { return nil }
        return PCNativePage.navigationState(archive: navigation,
                                            profilePath: store.independentEngineProfilePath(for: tab.profileID))
    }

    func scheduleCookieFlush() {
        guard cookieFlush == nil, !store.isEphemeral else { return }
        let flush = DispatchWorkItem { [weak self] in
            self?.cookieFlush = nil
            Self.flushCookieStores()
        }
        cookieFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: flush)
    }

    func canBeginPageRetirement(_ id: UUID) -> Bool {
        !wholeWindowClose && !isClosing && !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) && (nativePage(forTabID: id) != nil || !embeddedEaselPages(forTabID: id).isEmpty)
    }

    func beginPageRetirement(_ id: UUID) {
        if peeks.values.contains(where: { $0.parentTabID == id }) { peekRetirementParents.insert(id) }
        if let page = nativePage(forTabID: id), page.responds(to: #selector(PCNativePage.captureNavigationState)) {
            retiringPageHistory[id] = page.captureNavigationState()
        }
        closingTabIDs.insert(id)
        modelRetirementIDs.insert(id)
    }

    func canCommitPageRetirement(_ id: UUID, page: PCNativePage) -> Bool {
        !wholeWindowClose && !isClosing && modelRetirementIDs.contains(id)
            && (nativePage(forTabID: id) === page || peekPages(forTabID: id).contains { $0 === page }
                || embeddedEaselPages(forTabID: id).contains { $0 === page })
    }

    func finishPageRetirement(_ id: UUID, page: PCNativePage, closed: Bool) {
        if page.isEmbedded {
            if closed || page.isClosed { easelEditors[id]?.editor.pageObjects?.didClose(page) }
            closingTabIDs.remove(id); modelRetirementIDs.remove(id)
            return
        }
        if let peek = peeks[page.identifier] {
            if closed || page.isClosed { removePeek(peek) }
            else if peek.parentPage.isClosed { promotePeek(peek, split: false, orphaned: true) }
            return
        }
        peekRetirementParents.remove(id)
        closingTabIDs.remove(id)
        modelRetirementIDs.remove(id)
        if let history = retiringPageHistory.removeValue(forKey: id), closed {
            store.closedPageHistory.closed(id, state: history)
        }
        if closed, browsers[id]?.nativePage === page {
            releaseClosedTab(id, updateSavedTab: false)
        }
    }

    func refreshAfterPageRetirement() { render(store.state); requestNativeSelection() }
}
