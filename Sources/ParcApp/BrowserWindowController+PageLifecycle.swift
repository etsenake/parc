import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func releaseClosedTab(_ id: UUID, updateSavedTab: Bool) {
        pendingSearchNavigations.removeValue(forKey: id)
        inputRevisions.removeValue(forKey: id)
        if let retry = transferRecoveries[id] { retry(); return }
        guard browsers[id] != nil || panes[id] != nil || store.state.containsTab(id) else { return }
        let shown = selectedTabIDs.contains(id), pushedByClose = store.retiringTabIDs.contains(id)
        let closedItself = updateSavedTab && shown
        let replacement = closedItself ? closedPageReplacement(id) : nil
        if pendingNativeSelection?.tabID == id { pendingNativeSelection = nil }
        if let browser = browsers.removeValue(forKey: id) {
            if let page = browser.nativePage { attachedPageIDs.remove(page.identifier) }
            browser.delegate = nil
            browser.removeFromSuperview()
        }
        closingTabIDs.remove(id); modelRetirementIDs.remove(id)
        liveTabModels.removeValue(forKey: id); browserProfiles.removeValue(forKey: id)
        requestedURLs.removeValue(forKey: id); failures.removeValue(forKey: id); loadingTabs.remove(id)
        panes[id]?.browser = nil
        easelEditors[id]?.editor.retirePageOwner()
        panes[id]?.clearNativeContent(); easelEditors.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
        if nativeFullscreenTabID == id { restoreNativeFullscreenPresentation() }
        presentation.closePage(id)
        if let replacement, presentation.finishFolderRemoval(replacement, state: store.state, available: { self.switcherCanUse($0) }) {
            focusedTabID = replacement.focusedTabID
        }
        ownership.release(id, owner: presentationID)
        tabHistoryChanged.remove(id)
        if updateSavedTab { store.closeTab(id) }
        if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
        guard shown, closedItself || !pushedByClose else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose else { return }
            guard closedItself else { self.requestNativeSelection(); return }
            self.render(self.store.state); self.requestNativeSelection(); self.focusSelectedLocalContent()
        }
    }

    private func closedPageReplacement(_ id: UUID) -> FolderRemovalSelection? {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose else { return nil }
        return FolderRemovalSelection.resolve(removing: [id], spaceID: activeSpaceID, profileID: activeProfileID,
            state: store.state, selected: selectedTabIDs, focused: focusedTabID, referrerPool: presentation.referrerPool,
            previouslySelectedItemID: presentation.previouslySelectedItemID, available: { self.switcherCanUse($0) })
    }

    func retireBrowserAfterModelChange(_ id: UUID) {
        if let page = browsers[id]?.nativePage, !peekPages(forTabID: id).isEmpty {
            closePageAndPeeks(id, page: page, updateSavedTab: false); return
        }
        guard !closingTabIDs.contains(id), !transferringTabIDs.contains(id), let browser = browsers[id] else { return }
        let original = liveTabModels[id]
        let expected = store.state.tab(id)
        closingTabIDs.insert(id); modelRetirementIDs.insert(id)
        browser.requestClose { [weak self, weak browser] result in
            guard let self, let browser, self.browsers[id] === browser else { return }
            self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
            if result == .closed { self.releaseClosedTab(id, updateSavedTab: false) }
            else if let original {
                if !self.store.restoreLiveTab(original, replacing: expected) {
                    self.failures[id] = "This page is still open because closing was cancelled."
                }
            }
            self.render(self.store.state)
        }
    }

    func retirePages(_ leaving: [BrowserPane]) {
        for pane in leaving {
            if let page = pane.browser?.nativePage, let binding = nativeBinding, attachedPageIDs.contains(page.identifier) {
                if binding.responds(to: #selector(PCNativeBrowserWindow.pageWillPark(_:))) {
                    if !binding.pageWillPark(page) { attachedPageIDs.remove(page.identifier) }
                } else {
                    attachedPageIDs.remove(page.identifier)
                    binding.pageWillDetach(page)
                }
            }
            resignFocus(in: pane)
        }
    }
    func parkPanes(_ leaving: [BrowserPane]) {
        for pane in leaving where pane.superview === splitView && !splitView.arrangedSubviews.contains(where: { $0 === pane }) {
            resignFocus(in: pane)
            parkedPages.addSubview(pane)
        }
    }
    private func resignFocus(in pane: BrowserPane) {
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: pane) {
            window?.makeFirstResponder(nil)
        }
    }
    var canHoldPageSwitch: Bool {
        guard let window, window.isVisible, !window.isMiniaturized, !isClosing, !wholeWindowClose,
              let binding = nativeBinding else { return false }
        return binding.responds(to: #selector(PCNativeBrowserWindow.reportNextFrame(of:)))
    }
    func drawsReportedFrame(_ tab: BrowserTab) -> Bool {
        guard !InternalPage.isInternal(tab.url), !rendersBlank(tab), !presentation.showsPlaceholder(tab.id),
              failures[tab.id] == nil, !closingTabIDs.contains(tab.id),
              let page = browsers[tab.id]?.nativePage, !page.isClosed, page.rendererCrash == nil,
              attachedPageIDs.contains(page.identifier),
              page.responds(to: #selector(getter: PCNativePage.pageBackgroundColor)) else { return false }
        return page.pageBackgroundColor != nil
    }
    func scheduleSwitchHoldCap() {
        guard let deadline = switchHold.deadline else { return }
        let hold = switchHold.hold
        let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.switchHold.hold == hold, self.switchHold.isHolding else { return }
            let ended = self.switchHold.expire(at: ProcessInfo.processInfo.systemUptime)
            if ended.isEmpty { self.scheduleSwitchHoldCap() } else { self.finishPageSwitch(ended) }
        }
    }
    func finishPageSwitch(_ ended: [BrowserPane]) {
        guard !ended.isEmpty else { return }
        guard !rendering else {
            DispatchQueue.main.async { [weak self] in self?.finishPageSwitch(ended) }
            return
        }
        parkPanes(ended)
        attachOwnedPages()
        synchronizeNativeLayout()
    }

    func attachOwnedPages() {
        guard !attachingOwnedPages, let binding = nativeBinding, let window else { return }
        attachingOwnedPages = true
        defer { attachingOwnedPages = false; flushPendingNativeSelection() }
        for (id, browser) in browsers {
            guard !transferringTabIDs.contains(id), let page = browser.nativePage, !page.isClosed,
                  browser.window === window, !attachedPageIDs.contains(page.identifier) else { continue }
            guard ownership.claim(id, owner: presentationID, page: page.identifier) else { continue }
            if binding.pageDidAttach(page, container: browser) { attachedPageIDs.insert(page.identifier) }
            else { failures[id] = "The page could not attach to its browser window." }
        }
    }

    func synchronizeNativeLayout() {
        guard !synchronizingNativeLayout, !isClosing else { return }
        synchronizingNativeLayout = true
        defer { synchronizingNativeLayout = false }
        nativeBinding?.synchronizeLayout()
    }

    func requestNativeSelection() {
        reconcileCommandBar()
        navigationHistory?.validate()
        guard !applyingNativeSelection else { return }
        if let peek = activePeek, !peek.view.isHidden, !isClosing, !wholeWindowClose,
           !windowClosePending, !peek.page.isClosed {
            pendingNativeSelection = nil
            pushNativeSelection()
            refreshNavigationControls()
            return
        }
        closedItems.selected(selectedTabIDs)
        if currentBrowser == nil, selectedNativePage()?.isEmbedded == true {
            pendingNativeSelection = nil; pushNativeSelection(); refreshNavigationControls(); return
        }
        recordRecentTabSelection()
        pendingNativeSelection = nil
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              transferringTabIDs.isEmpty else { return }
        if presentation.isLocalSelection(currentTabID, state: store.state,
                                         hasNativeWrapper: currentBrowser != nil) {
            pendingNativeSelection = .local(currentTabID)
        } else {
            guard let id = currentTabID, let view = browsers[id],
                  !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
                  !store.retiringTabIDs.contains(id) else { return }
            pendingNativeSelection = .page(NativePageSelectionRequest(
                tabID: id, view: view, pageIdentifier: view.nativePage?.identifier))
        }
        flushPendingNativeSelection()
    }

    private func pushNativeSelection() {
        guard let binding = nativeBinding else { return }
        binding.synchronizeSelectionAndLayout()
        presentation.engineSelectionSynchronized()
    }

    private func flushPendingNativeSelection() {
        guard !applyingNativeSelection, !synchronizingNativeLayout, !attachingOwnedPages,
              let pending = pendingNativeSelection else { return }
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              transferringTabIDs.isEmpty, pending.tabID == currentTabID,
              let binding = nativeBinding, let window, binding.window === window else {
            pendingNativeSelection = nil
            return
        }
        switch pending {
        case .local(let id):
            guard presentation.isLocalSelection(id, state: store.state,
                                                hasNativeWrapper: currentBrowser != nil),
                  selectedNativePage() == nil else {
                pendingNativeSelection = nil
                return
            }
        case .page(var request):
            guard let view = request.view, browsers[request.tabID] === view,
                  !closingTabIDs.contains(request.tabID), !modelRetirementIDs.contains(request.tabID),
                  !store.retiringTabIDs.contains(request.tabID) else {
                pendingNativeSelection = nil
                return
            }
            guard let page = view.nativePage else { return }
            guard request.pageIdentifier == nil || request.pageIdentifier == page.identifier,
                  existingNativeSelection(binding, page)?.1 === view else {
                pendingNativeSelection = nil
                return
            }
            request.pageIdentifier = page.identifier
            pendingNativeSelection = .page(request)
            guard attachedPageIDs.contains(page.identifier),
                  page.nativeView.window === window, page.nativeView.isDescendant(of: view) else { return }
        }
        pendingNativeSelection = nil
        synchronizingNativeLayout = true
        defer { synchronizingNativeLayout = false }
        binding.synchronizeSelectionAndLayout()
        presentation.engineSelectionSynchronized()
        refreshNavigationControls()
    }

    func embeddedPages(forTabID id: UUID) -> [PCNativePage] { embeddedPagePool(forTabID: id)?.pages ?? [] }
    func embeddedPageOwner(_ page: PCNativePage) -> (UUID, EmbeddedPagePool)? {
        for (id, pane) in easelEditors {
            if let objects = pane.editor.pageObjects, objects.contains(page) { return (id, objects) }
        }
        for (id, note) in noteEditors {
            if let pool = NoteEmbeddedPages.pool(for: note.editor), pool.contains(page) { return (id, pool) }
        }
        return nil
    }
    func embeddedPagePool(containing page: PCNativePage) -> EmbeddedPagePool? {
        embeddedPageOwner(page)?.1 ?? NoteEmbeddedPages.lingering(containing: page)
    }
    func retireEaselAfterModelChange(_ id: UUID, cached: EaselPane) {
        guard !closingTabIDs.contains(id), let objects = cached.editor.pageObjects else { return }
        let pages = objects.pages, expected = store.state.tab(id)
        closingTabIDs.insert(id); modelRetirementIDs.insert(id)
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: { [weak self, weak objects] in
            MainActor.assumeIsolated {
                guard let self, let objects else { return false }
                return !self.isClosing && self.easelEditors[id]?.editor.pageObjects === objects
                    && self.store.state.tab(id) == expected
            }
        }, completion: { [weak self, weak objects] allowed in
            MainActor.assumeIsolated {
                guard let self, let objects, self.easelEditors[id]?.editor.pageObjects === objects else { return }
                self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
                if allowed {
                    cached.editor.retirePageOwner(); self.panes[id]?.clearNativeContent(); self.easelEditors.removeValue(forKey: id)
                } else { _ = self.store.restoreLiveTab(cached.originalTab, replacing: expected) }
                self.render(self.store.state); self.requestNativeSelection()
            }
        })
    }

    func easelPagesCanSleep(_ pane: EaselPane) -> Bool {
        guard pane.editor.canPrepareForProfileRelocation, let objects = pane.editor.pageObjects,
              !objects.hasPendingCreation, !objects.pages.isEmpty else { return false }
        return objects.ownedViews.values.allSatisfy { $0.automaticArchiveProtectionState == .eligible }
    }

    func releaseIdleEaselPages(_ id: UUID, cached: EaselPane) {
        guard !closingTabIDs.contains(id), let objects = cached.editor.pageObjects,
              cached.editor.prepareForPreviewClose() else { return }
        let pages = objects.pages, expected = store.state.tab(id)
        closingTabIDs.insert(id)
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: { [weak self, weak objects] in
            MainActor.assumeIsolated {
                guard let self, let objects, let current = self.easelEditors[id], current.editor.pageObjects === objects else { return false }
                let shown = self.renderedPaneIDs.contains(id) || self.selectedTabIDs.contains(id) || self.pendingNativeSelection?.tabID == id
                return !self.isClosing && !self.wholeWindowClose && !shown && !self.transferringTabIDs.contains(id)
                    && self.store.state.tab(id) == expected && self.easelPagesCanSleep(current)
            }
        }, completion: { [weak self, weak objects] allowed in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closingTabIDs.remove(id)
                if allowed, let objects, self.easelEditors[id]?.editor.pageObjects === objects {
                    cached.editor.retirePageOwner(); self.panes[id]?.clearNativeContent(); self.easelEditors.removeValue(forKey: id)
                }
                guard !self.isClosing else { return }
                self.render(self.store.state); self.requestNativeSelection()
            }
        })
    }

    func peekPages(forTabID id: UUID) -> [PCNativePage] {
        peeks.values.filter { $0.parentTabID == id && $0.parentPage != nil && !$0.page.isClosed }.map(\.page)
    }

    func canAcceptNativeLinkRoute(profileID: UUID) -> Bool {
        if isPrivateBrowsing { return false }
        return !isPopupWindow && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && window?.attachedSheet == nil
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && activeProfileID == profileID && !store.isProfileRemovalPending(profileID)
    }

    func prepareNativeLinkDestination(profileID: UUID) -> PCNativeBrowserWindow? {
        guard canAcceptNativeLinkRoute(profileID: profileID), let nativeBinding else { return nil }
        if !presentation.isReady && browsers.isEmpty { preparedForRoutedPage = true }
        return nativeBinding
    }
}
