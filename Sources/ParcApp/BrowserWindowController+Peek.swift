import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func canHostPeek(_ browser: PCNativeBrowserWindow, over page: PCNativePage, overLibrary: Bool = false,
                     ignoringCommandBar: Bool = false) -> Bool {
        windowAdmitsPeek(browser, overLibrary: overLibrary, ignoringCommandBar: ignoringCommandBar) && !page.isClosed
            && PCNativeBrowserApplication.owner(of: page) === browser
            && !peeks.values.contains { $0.parentPage === page || ($0.parentPage == nil && browsers[$0.parentTabID]?.nativePage === page) }
            && tabPeeks.current == nil
    }

    func windowAdmitsPeek(_ browser: PCNativeBrowserWindow, overLibrary: Bool = false,
                                  ignoringCommandBar: Bool = false) -> Bool {
        browser === nativeBinding && !isPopupWindow
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved && nativeFullscreenTabID == nil
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && (commandBar == nil || ignoringCommandBar) && (libraryView == nil || overLibrary)
            && window?.attachedSheet == nil && window?.isKeyWindow == true
    }

    @discardableResult
    func previewArchivedItem(_ id: UUID, profileID: UUID) -> Bool {
        if let peek = activePeek, archivePreviews[peek.identity] != nil {
            guard archivePreviews[peek.identity]?.tabs.first?.id != id else { return true }
            guard peek.canRequestExit else { return false }
            queuedArchivePreview = (id, profileID)
            peek.requestDismiss(.closeButton)
            return true
        }
        guard archivePreviewRequest == nil, peekUndoOpen == nil, activePeek == nil, let binding = nativeBinding,
              let route = peekBackdrop.archivePreviewRoute else { return false }
        let parent = route == .fromPage ? currentTabID.flatMap { browsers[$0]?.nativePage } : nil
        if let parent {
            guard selectedNativePage() === parent, PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))),
                  canHostPeek(binding, over: parent, overLibrary: true) else { return false }
        } else {
            guard route != .fromPage, windowAdmitsPeek(binding, overLibrary: true), tabPeeks.current == nil else { return false }
        }
        guard let lease = store.acquireArchivePreview(id: id, profileID: profileID) else { return false }
        guard lease.tabs.count == 1, let url = URL(string: lease.tabs[0].url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            store.releaseArchivePreview(lease); return false
        }
        let token = UUID()
        archivePreviewRequest = (parent?.identifier, lease, token)
        if let parent {
            guard parent.openPeek(url: url) else {
                archivePreviewRequest = nil; store.releaseArchivePreview(lease); return false
            }
        } else if case .overWindow(let host) = route {
            openHostedArchivePreview(url, lease: lease, host: host, token: token, binding: binding)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let request = self.archivePreviewRequest, request.token == token else { return }
            self.archivePreviewRequest = nil; self.store.releaseArchivePreview(request.lease)
        }
        return archivePreviewRequest?.token == token || archivePreviews.values.contains(lease)
    }

    var peekBackdrop: PeekBackdrop {
        let id = currentTabID
        return PeekBackdrop(currentTabID: id, tabIsOpen: id.map { store.state.containsTab($0, where: { $0.archivedAt == nil }) } ?? false,
                            hasLivePage: id.flatMap { browsers[$0]?.nativePage }.map { !$0.isClosed } ?? false,
                            showsStartPage: showsStartPage, activeSpaceID: activeSpaceID)
    }

    private func openHostedArchivePreview(_ url: URL, lease: ArchivePreviewLease, host: UUID, token: UUID,
                                          binding: PCNativeBrowserWindow) {
        openHostedPeekPage(url, profileID: lease.profileID, binding: binding) { owner, page, binding in
            owner.adoptHostedArchivePreview(page, host: host, token: token, binding: binding)
        }
    }

    private func openHostedPeekPage(_ url: URL, profileID: UUID, binding: PCNativeBrowserWindow,
                                    adopt: @escaping @MainActor (BrowserWindowController, PCNativePage?, PCNativeBrowserWindow) -> Void) {
        let path = store.independentEngineProfilePath(for: profileID)
        binding.open(url, profilePath: path, container: parkedPages) { [weak self, weak binding] page, _ in
            MainActor.assumeIsolated {
                guard let self, let binding else { page?.requestClose { _ in }; return }
                adopt(self, page, binding)
            }
        }
    }

    func openNoteLinkInPeek(_ url: URL, click: NoteLinkClick, over host: UUID, profileID: UUID) -> Bool {
        let settings = store.state.settings
        guard click.route(for: url, automaticPeek: settings.automaticPeekEnabled, shiftPeek: settings.shiftPeekEnabled) == .peek,
              noteLinkPeekRequest == nil, archivePreviewRequest == nil, peekUndoOpen == nil, !promotingPeek,
              let binding = nativeBinding, noteLinkCanHostPeek(host, profileID: profileID, binding: binding) else { return false }
        let token = UUID()
        noteLinkPeekRequest = token
        openHostedPeekPage(url, profileID: profileID, binding: binding) { owner, page, binding in
            owner.adoptNoteLinkPeek(page, url: url, host: host, profileID: profileID, token: token, binding: binding)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.noteLinkPeekRequest == token else { return }
            self.noteLinkPeekRequest = nil
            self.openNoteLinkWithoutPeek(url, host: host, profileID: profileID)
        }
        return true
    }

    private func noteLinkCanHostPeek(_ host: UUID, profileID: UUID, binding: PCNativeBrowserWindow) -> Bool {
        nativeBinding === binding && activePeek == nil && tabPeeks.current == nil
            && peekHostID == host && peekBackdrop == .pagelessTab(tabID: host) && noteEditors[host] != nil
            && profileID == activeProfileID && store.state.tab(host, where: { $0.archivedAt == nil })?.profileID == profileID
            && ownership.canUse(host, owner: presentationID) && !peeks.values.contains { $0.parentTabID == host && !$0.page.isClosed }
            && windowAdmitsPeek(binding)
    }

    private func adoptNoteLinkPeek(_ page: PCNativePage?, url: URL, host: UUID, profileID: UUID, token: UUID,
                                   binding: PCNativeBrowserWindow) {
        guard noteLinkPeekRequest == token else { page?.requestClose { _ in }; return }
        noteLinkPeekRequest = nil
        guard let page, !page.isClosed, noteLinkCanHostPeek(host, profileID: profileID, binding: binding),
              PCNativeBrowserApplication.owner(of: page) === binding,
              page.profilePath == store.independentEngineProfilePath(for: profileID),
              let spaceID = store.state.tab(host)?.spaceID, ownership.canAdopt(page.identifier) else {
            page?.requestClose { _ in }
            openNoteLinkWithoutPeek(url, host: host, profileID: profileID)
            return
        }
        let peek = PeekController(page: page, parent: nil, parentTabID: host, sourceSpaceID: spaceID)
        guard ownership.claim(peek.identity, owner: presentationID, page: page.identifier) else {
            peek.finish(); page.requestClose { _ in }
            openNoteLinkWithoutPeek(url, host: host, profileID: profileID)
            return
        }
        peeks[page.identifier] = peek
        wirePeek(peek, binding: binding)
        tabSwitcher?.cancel(); sidebarPreviews?.dismiss()
        let entryFocus = PeekFocusReturn(source: pageHost)
        binding.pageWillDetach(page)
        presentAdoptedPeek(peek, shown: true, entryFocus: entryFocus)
    }

    private func openNoteLinkWithoutPeek(_ url: URL, host: UUID, profileID: UUID) {
        guard currentTabID == host, activeProfileID == profileID, noteEditors[host] != nil, activePeek == nil,
              !isClosing, !wholeWindowClose else { return }
        openInput(url.absoluteString)
    }

    private func adoptHostedArchivePreview(_ page: PCNativePage?, host: UUID, token: UUID, binding: PCNativeBrowserWindow) {
        guard let request = archivePreviewRequest, request.token == token, request.parent == nil else {
            page?.requestClose { _ in }; return
        }
        archivePreviewRequest = nil
        let lease = request.lease
        let parent = page.flatMap { adoptableHostPage(host, profilePath: $0.profilePath) }
        guard let page, !page.isClosed, nativeBinding === binding, activePeek == nil, tabPeeks.current == nil,
              peekHostID == host, peekBackdrop.archivePreviewRoute != nil, windowAdmitsPeek(binding, overLibrary: true),
              parent != nil || browsers[host]?.nativePage.map({ $0.isClosed }) ?? true,
              PCNativeBrowserApplication.owner(of: page) === binding, lease.profileID == activeProfileID,
              page.profilePath == store.independentEngineProfilePath(for: lease.profileID),
              store.archivePreviewIsValid(lease), ownership.canAdopt(page.identifier) else {
            store.releaseArchivePreview(lease); page?.requestClose { _ in }; return
        }
        let peek = PeekController(page: page, parent: parent, parentTabID: host, sourceSpaceID: activeSpaceID)
        guard ownership.claim(peek.identity, owner: presentationID, page: page.identifier) else {
            peek.finish(); store.releaseArchivePreview(lease); page.requestClose { _ in }; return
        }
        peeks[page.identifier] = peek
        archivePreviews[peek.identity] = lease
        wirePeek(peek, binding: binding)
        tabSwitcher?.cancel(); sidebarPreviews?.dismiss()
        let entryFocus = PeekFocusReturn(source: pageHost)
        binding.pageWillDetach(page)
        presentAdoptedPeek(peek, shown: true, entryFocus: entryFocus)
    }

    func adoptHostedPeekParent(over id: UUID) {
        guard let peek = peeks.values.first(where: { $0.parentTabID == id && $0.parentPage == nil && !$0.page.isClosed }),
              let page = adoptableHostPage(id, profilePath: peek.page.profilePath) else { return }
        peek.adoptParent(page)
    }

    private func adoptableHostPage(_ id: UUID, profilePath: String) -> PCNativePage? {
        guard let page = browsers[id]?.nativePage, !page.isClosed, let binding = nativeBinding,
              PCNativeBrowserApplication.owner(of: page) === binding, page.profilePath == profilePath,
              store.state.containsTab(id, where: { $0.archivedAt == nil }), ownership.canUse(id, owner: presentationID),
              !closingTabIDs.contains(id), !modelRetirementIDs.contains(id), !peekRetirementParents.contains(id),
              !transferringTabIDs.contains(id), tabPeeks.current?.parentTabID != id, !tabPeekHolds(page),
              !peeks.values.contains(where: { $0.parentPage === page }) else { return nil }
        return page
    }

    func preserveHostlessPeeks() {
        for peek in Array(peeks.values) where peek.parentPage == nil { adoptHostedPeekParent(over: peek.parentTabID) }
        guard peeks.values.contains(where: { hostlessPeekLost($0) }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose else { return }
            for peek in Array(self.peeks.values) where peek.view.isHidden && self.hostlessPeekLost(peek) {
                peek.closeWhileHidden()
            }
        }
    }

    private func hostlessPeekLost(_ peek: PeekController) -> Bool {
        peek.parentPage == nil && !peek.closePending && !peekHostLives(peek)
    }

    private func peekHostLives(_ peek: PeekController) -> Bool {
        let id = peek.parentTabID
        if store.state.spaces.contains(where: { $0.id == id }) { return activeSpaceID != id || currentTabID == nil }
        return store.state.containsTab(id, where: { $0.archivedAt == nil }) && ownership.canUse(id, owner: presentationID)
    }

    func peekProfileID(_ peek: PeekController) -> UUID? {
        browserProfiles[peek.parentTabID] ?? (peek.parentPage == nil
            ? archivePreviews[peek.identity]?.profileID ?? store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil })?.profileID
            : nil)
    }

    func revealPeekHost(_ peek: PeekController) -> Bool {
        if store.state.tab(peek.parentTabID) != nil { return selectTab(peek.parentTabID) }
        guard peek.parentPage == nil, store.state.spaces.contains(where: { $0.id == peek.parentTabID }) else { return false }
        return selectSpaceFromUser(peek.parentTabID) && peekHostID == peek.parentTabID
    }

    private func focusPeekBackdrop() {
        if currentTabID != nil { focusSelectedLocalContent() }
        else if libraryView == nil, showsStartPage { residentCommandBar?.focusResident() }
    }

    func adoptPeek(_ page: PCNativePage, binding: PCNativeBrowserWindow) -> NSView? {
        guard let parent = page.peekParent else { return nil }
        var undo = peekUndoOpen.flatMap { $0.parent == parent.identifier ? $0.operation : nil }
        if let pending = undo, !(page.responds(to: #selector(getter: PCNativePage.isReopenedPeek))
            ? page.isReopenedPeek : page.url?.absoluteString == pending.record.url.absoluteString) {
            undo = nil; peekUndoOpen = nil
        }
        defer { if undo != nil { peekUndoOpen = nil } }
        let request = archivePreviewRequest.flatMap { $0.parent == parent.identifier ? $0 : nil }
        let admitted = nativeBrowser(binding, canPresentPeekFrom: parent)
        if request != nil { archivePreviewRequest = nil }
        let archive = request.flatMap { request in undo == nil
            && page.responds(to: #selector(getter: PCNativePage.isReopenedPeek)) && page.isReopenedPeek ? request.lease : nil }
        if let request, archive == nil { store.releaseArchivePreview(request.lease) }
        var previewAdopted = false
        defer { if let archive, !previewAdopted { store.releaseArchivePreview(archive) } }
        guard admitted, request == nil || archive != nil,
              let id = browsers.first(where: { $0.value.nativePage === parent })?.key,
              let profile = browserProfiles[id],
              let parentTab = store.state.tab(id),
              page.profilePath == parent.profilePath,
              parent.profilePath == store.independentEngineProfilePath(for: profile),
              archive.map({ $0.profileID == profile && store.archivePreviewIsValid($0) }) ?? true,
              ownership.canAdopt(page.identifier) else { return nil }
        let peek = PeekController(page: page, parent: parent, parentTabID: id, sourceSpaceID: parentTab.spaceID)
        guard ownership.claim(peek.identity, owner: presentationID, page: page.identifier) else { peek.finish(); return nil }
        peeks[page.identifier] = peek
        if let archive { archivePreviews[peek.identity] = archive; previewAdopted = true }
        undo?.openedPeek = peek.identity
        wirePeek(peek, binding: binding)
        let shown = activePeek === peek
        if shown { tabSwitcher?.cancel(); sidebarPreviews?.dismiss(); if archive == nil { closeLibrary(restoreFocus: false) } }
        else if undo != nil { undoHiddenPeek = peek.identity }
        let entryFocus = PeekFocusReturn(source: parent.nativeView)
        presentAdoptedPeek(peek, shown: shown, entryFocus: entryFocus)
        return peek.browser
    }

    private func presentAdoptedPeek(_ peek: PeekController, shown: Bool, entryFocus: PeekFocusReturn?) {
        let page = peek.page
        peekLayer.addSubview(peek.view, positioned: .above, relativeTo: nil)
        placePeek(peek); peek.view.layoutSubtreeIfNeeded()
        if !shown { peek.setVisible(false) }
        DispatchQueue.main.async { [weak self, weak peek] in
            guard let self, let peek, self.peeks[page.identifier] === peek, !page.isClosed else { return }
            self.layoutPeeks()
            if self.activePeek === peek { peek.view.animatePresentation() }
            self.nativeBinding?.synchronizeSelectionAndLayout()
            if let window = self.window {
                entryFocus?.perform(in: window, ownerIsAvailable: {
                    self.activePeek === peek && peek.canInteract?() == true
                        && PCNativeBrowserApplication.canUseWindowUndo(in: window)
                }) { _ in peek.focus() }
            }
        }
    }

    func wirePeek(_ peek: PeekController, binding: PCNativeBrowserWindow) {
        let page = peek.page, id = peek.parentTabID
        wirePeekPresentation(peek)
        peek.canInteract = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.peeks[page.identifier] === peek && self.activePeek === peek
                && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.closingTabIDs.contains(id) && !self.transferringTabIDs.contains(id)
                && !page.isClosed && PCNativeBrowserApplication.owner(of: page) === binding
                && peek.browser.window === self.window && binding.window === self.window
        }
        peek.canExpand = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.peekPromotionDestination(peek) != nil
        }
        peek.canSplit = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.activePeek === peek && self.selectedTabIDs.contains(id)
                && self.selectedTabIDs.count < 4 && self.nativeFullscreenTabID == nil
        }
        peek.onClose = { [weak self, weak peek] in
            guard let self, let peek, page.isClosed else { return }; self.removePeek(peek)
        }
        peek.onCloseRefused = { [weak self, weak peek] in
            guard let self, let peek else { return }
            if self.archivePreviews[peek.identity] != nil { self.queuedArchivePreview = nil }
            if let redo = self.peekRedo, redo.peek == peek.identity { self.peekRedo = nil; redo.done(nil) }
            if peek.parentPage.map({ $0.isClosed }) ?? !self.peekHostLives(peek) { self.promotePeek(peek, split: false, orphaned: true) }
        }
        peek.onPromote = { [weak self, weak peek] split in
            guard let self, let peek else { return }; self.promotePeek(peek, split: split)
        }
        peek.onUpdate = { [weak self] in self?.refreshLivePageChromeOrRender() }
        peek.onMediaChange = { [weak self] in self?.scheduleMediaRefresh() }
        peek.onContextImage = { [weak self, weak peek] image in
            guard let self, let peek else { return }; self.browserView(peek.browser, addContextImageToEasel: image)
        }
    }

    func layoutPeeks() {
        for peek in peeks.values {
            placePeek(peek)
            let visible = activePeek === peek
            peek.setVisible(visible)
            peek.view.layoutSubtreeIfNeeded()
        }
        reconcileTabPeek()
        if let shown = tabPeek?.shownController { _ = shown.refresh() }
        for card in leavingTabPeekCards { placePeek(card); card.view.layoutSubtreeIfNeeded() }
        syncPeekStepBack()
    }

    var leavingTabPeekCards: [PeekCard] { tabPeeks.leaving.compactMap(\.controller) }

    func notePeekSplitBlockers() {
        guard let peek = activePeek else { peekSplitBlockers = nil; return }
        let blockers = PeekSplitBlockers(windowClosing: windowClosePending || wholeWindowClose,
                                         libraryOpen: libraryView != nil, fullscreenTabID: nativeFullscreenTabID,
                                         transferringTabIDs: transferringTabIDs, selectedTabIDs: selectedTabIDs,
                                         grouped: activeSplitLayout != nil)
        guard blockers != peekSplitBlockers else { return }
        peekSplitBlockers = blockers
        _ = peek.refresh()
    }

    func placePeek(_ peek: PeekCard) {
        if peekLayer.frame != rootView.bounds { peekLayer.frame = rootView.bounds }
        peek.view.frame = peekLayer.bounds
        peek.view.pageFrame = pageHost.frame
        peek.view.stepsBack = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func wirePeekPresentation(_ peek: PeekCard) {
        peek.view.adoptWindowTheme(rootView)
        peek.onLeavingChange = { [weak self, weak peek] in
            guard let self, let peek else { return }
            self.followLeavingPeek(peek)
        }
        peek.view.onStep = { [weak self, weak peek] animated in
            guard let self, let peek, self.steppingPeek === peek else { return }
            self.syncPeekStepBack(animated: animated)
        }
        peek.onMotionPreference = { [weak self] in self?.layoutPeeks() }
    }

    private var steppingPeek: PeekCard? {
        if let peek = activePeek { return peek }
        guard let id = currentTabID else { return nil }
        return tabPeeks.leaving.compactMap(\.controller).last {
            $0.parentTabID == id && browsers[id]?.nativePage === $0.parentPage
        }
    }

    func syncPeekStepBack(animated: Bool = false) {
        let shown = steppingPeek.flatMap { $0.view.isHidden || $0.view.superview !== peekLayer ? nil : $0 }
        loadingIndicator.alphaValue = (shown?.view.stepProgress ?? 0) > 0 ? 0 : 1
        guard let peek = shown, peek.view.stepsBack, peek.view.stepProgress > 0, !isClosing, !wholeWindowClose else {
            peekStepBack.reset(); pageHost.peekStepScale = 1; return
        }
        let scale = PeekWindowLayout(bounds: peekLayer.bounds, page: pageHost.frame, stepsBack: true).scale
        pageHost.peekStepScale = scale
        if animated { peekStepBack.animateIn(scale: scale) }
        else if peekStepBack.progress != peek.view.stepProgress || peekStepBack.scale != scale {
            peekStepBack.set(peek.view.stepProgress, scale: scale)
        } else { peekStepBack.refresh() }
    }

    private func recordClosedPeek(_ peek: PeekController, url: URL) {
        let redo = peekRedo.flatMap { $0.peek == peek.identity ? $0 : nil }
        if redo != nil { peekRedo = nil }
        guard peeks[peek.page.identifier] === peek, !isPopupWindow,
              !isClosing, !wholeWindowClose,
              PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))), peek.parentPage != nil,
              let parent = store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil })
        else { redo?.done(nil); return }
        let record = ClosedPeekRecord(id: UUID(), url: url, parentTabID: parent.id, profileID: parent.profileID)
        if let history = peek.dismissedNavigationState { store.closedPageHistory.closed(record.id, state: history) }
        if !isPrivateBrowsing { closedItems.recordPeek(record, in: store.state) }
        if let redo { redo.done(record) } else { registerClosedPeekUndo(record) }
    }

    private func registerClosedPeekUndo(_ record: ClosedPeekRecord) {
        guard windowUndoOwnerAvailable, record.isValid(in: store.state) else { return }
        let operation = folderUndo.appendClosedPeek(record, state: { [weak self] in self?.store.state }, canOpen: { [weak self] operation in
            guard let self, self.windowUndoContextAvailable, self.peekUndoOpen == nil, self.archivePreviewRequest == nil,
                  let binding = self.nativeBinding,
                  PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))) else { return false }
            let parent = operation.record.parentTabID
            switch PageReparenting.rowAction(closing: false, busy: false, usableHere: self.switcherCanUse(parent),
                                             heldElsewhere: self.peekParentCanMoveHere(parent)) {
            case .here?: break
            case .moveHere?: return self.windowAdmitsPeek(binding)
            default: return false
            }
            guard let page = self.closedPeekParentPage(operation.record) else {
                self.pruneAwaitedPeeks()
                return self.peekUndoAwaitingParent[parent] == nil
                    && self.browsers[parent] == nil && self.windowAdmitsPeek(binding)
            }
            return self.canHostPeek(binding, over: page)
        }, open: { [weak self] operation, done in
            guard let self, self.windowUndoContextAvailable, self.peekUndoOpen == nil else { done(false); return }
            let parent = operation.record.parentTabID
            guard !self.switcherCanUse(parent), self.peekParentCanMoveHere(parent) else {
                done(self.openClosedPeekUndo(operation)); return
            }
            self.movePeekParentHere(parent, then: { [weak self] in
                done(self?.openClosedPeekUndo(operation, arrived: true) ?? false)
            }, failed: { done(false) })
        }, isOpen: { [weak self] operation in
            guard let self else { return false }
            self.pruneAwaitedPeeks()
            return self.peekUndoOpen?.operation === operation || self.peekUndoAwaitingParent.values.contains { $0 === operation }
                || self.peek(operation.openedPeek) != nil
        }, canClose: { [weak self] operation in
            guard let self, self.windowUndoContextAvailable, self.peekRedo == nil else { return false }
            if self.peekUndoAwaitingParent.values.contains(where: { $0 === operation }) { return true }
            guard let peek = self.peek(operation.openedPeek), !peek.closePending, !peek.page.isClosed else { return false }
            return self.activePeek === peek ? peek.canPrepareExit : peek.view.isHidden
        }, close: { [weak self] operation, done in
            guard let self, self.windowUndoContextAvailable, self.peekRedo == nil else { done(nil); return }
            if let parent = self.peekUndoAwaitingParent.first(where: { $0.value === operation })?.key {
                self.peekUndoAwaitingParent.removeValue(forKey: parent); self.awaitedPeekRetries.remove(parent)
                let previous = operation.record
                let record = ClosedPeekRecord(id: UUID(), url: previous.url, parentTabID: previous.parentTabID,
                                              profileID: previous.profileID)
                if let history = self.store.closedPageHistory.take(previous.id) { self.store.closedPageHistory.closed(record.id, state: history) }
                if !self.isPrivateBrowsing { self.closedItems.recordPeek(record, in: self.store.state) }
                done(record)
                return
            }
            guard let peek = self.peek(operation.openedPeek), !peek.closePending else { done(nil); return }
            self.peekRedo = (peek.identity, done)
            if self.activePeek === peek { peek.requestDismiss(.closeShortcut) } else { peek.closeWhileHidden() }
            if !peek.closePending, let redo = self.peekRedo, redo.peek == peek.identity {
                self.peekRedo = nil; redo.done(nil)
            }
        }) { _ in }
        peekUndoOperations.add(operation)
    }

    private func openClosedPeekUndo(_ operation: ClosedPeekUndoOperation, arrived: Bool = false) -> Bool {
        let parent = operation.record.parentTabID
        guard windowUndoContextAvailable, peekUndoOpen == nil, switcherCanUse(parent) else { return false }
        if let page = closedPeekParentPage(operation.record), !arrived || !loadingTabs.contains(parent) {
            guard let binding = nativeBinding, canHostPeek(binding, over: page), openUndonePeek(operation, over: page) else { return false }
        } else {
            pruneAwaitedPeeks()
            guard peekUndoAwaitingParent[parent] == nil, arrived || browsers[parent] == nil else { return false }
            peekUndoAwaitingParent[parent] = operation; awaitedPeekRetries.remove(parent)
        }
        _ = closedItems.consume(stepID: operation.record.id)
        return true
    }

    func peekParentCanMoveHere(_ parent: UUID) -> Bool {
        guard canMovePageHere(parent) else { return false }
        switch tabHolder?(parent, self) ?? .none {
        case .content(let holder): return !holder.peeks.values.contains { $0.parentTabID == parent && !$0.page.isClosed }
        case .emptyClaim: return true
        case .none: return false
        }
    }

    @discardableResult
    func movePeekParentHere(_ parent: UUID, then open: @escaping @MainActor () -> Void, failed: @escaping () -> Void = {}) -> Bool {
        var settled = false
        let fail = { if !settled { settled = true; failed() } }
        let arrival = PendingArrival(abandoned: fail)
        let started = movePagesHere([parent]) { [weak self] in
            arrival.ran = true
            guard let self, self.selectTab(parent) else { fail(); return false }
            settled = true
            DispatchQueue.main.async { open() }
            return true
        }
        if !started { arrival.ran = true; fail() }
        return started
    }

    func closedPeekParentPage(_ record: ClosedPeekRecord) -> PCNativePage? {
        guard let page = browsers[record.parentTabID]?.nativePage, !page.isClosed,
              page.profilePath == store.independentEngineProfilePath(for: record.profileID),
              page.responds(to: #selector(PCNativePage.openPeek(url:))) else { return nil }
        return page
    }

    func peek(_ identity: UUID?) -> PeekController? {
        identity.flatMap { identity in peeks.values.first { $0.identity == identity } }
    }

    private func openUndonePeek(_ operation: ClosedPeekUndoOperation, over page: PCNativePage) -> Bool {
        guard peekUndoOpen == nil, archivePreviewRequest == nil else { return false }
        let token = UUID()
        peekUndoOpen = (page.identifier, operation, token)
        guard openClosedPeek(operation.record, over: page) else { peekUndoOpen = nil; return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.peekUndoOpen?.token == token else { return }
            self.peekUndoOpen = nil
        }
        return true
    }

    func openClosedPeek(_ record: ClosedPeekRecord, over page: PCNativePage) -> Bool {
        guard let history = store.closedPageHistory.take(record.id) as? NSObject else { return page.openPeek(url: record.url) }
        let opened = page.responds(to: #selector(PCNativePage.openPeek(url:navigationState:)))
            ? page.openPeek(url: record.url, navigationState: history) : page.openPeek(url: record.url)
        if !opened { store.closedPageHistory.closed(record.id, state: history) }
        return opened
    }

    func openAwaitedPeek(over parentTabID: UUID) {
        pruneAwaitedPeeks()
        guard let operation = peekUndoAwaitingParent[parentTabID], selectedTabIDs.contains(parentTabID),
              let page = closedPeekParentPage(operation.record), browsers[parentTabID]?.url != nil,
              !loadingTabs.contains(parentTabID) else { return }
        if openUndonePeek(operation, over: page) {
            peekUndoAwaitingParent.removeValue(forKey: parentTabID); awaitedPeekRetries.remove(parentTabID)
        } else {
            awaitedPeekRetries.insert(parentTabID)
            if peekUndoOpen != nil { peekUndoSlotWaiters.refused(parentTabID) }
        }
    }

    private func pruneAwaitedPeeks() {
        for (parent, operation) in peekUndoAwaitingParent
        where !operation.record.isValid(in: store.state) || !ownership.canUse(parent, owner: presentationID) {
            peekUndoAwaitingParent.removeValue(forKey: parent); awaitedPeekRetries.remove(parent)
        }
    }

    func removePeek(_ peek: PeekController) {
        guard peeks[peek.page.identifier] === peek else { return }
        let archive = archivePreviews.removeValue(forKey: peek.identity)
        if let archive { store.releaseArchivePreview(archive) }
        else if archivePreviewRemnants.remove(peek.identity) == nil, peek.page.isClosed, let url = peek.dismissedURL {
            recordClosedPeek(peek, url: url)
        }
        if let redo = peekRedo, redo.peek == peek.identity { peekRedo = nil; redo.done(nil) }
        if undoHiddenPeek == peek.identity { undoHiddenPeek = nil }
        let focusReturn = peek.takeFocusReturn()
        let binding = nativeBinding
        peeks.removeValue(forKey: peek.page.identifier)
        ownership.release(peek.identity, owner: presentationID)
        inputRevisions.removeValue(forKey: peek.identity); zoomLevels.removeValue(forKey: peek.identity)
        peek.finish()
        if !isClosing && !wholeWindowClose {
            layoutPeeks(); updateNavigation(); requestNativeSelection()
            if let window, let binding {
                focusReturn?.perform(in: window, ownerIsAvailable: {
                    self.activePeek == nil && self.parentCanTakeFocus(from: peek, binding: binding, window: window)
                }) { _ in if let parent = peek.parentPage { _ = binding.requestFocus(for: parent) } else { self.focusPeekBackdrop() } }
            }
            if archive != nil, let next = queuedArchivePreview {
                queuedArchivePreview = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.libraryView?.kind == .archive, self.activeProfileID == next.profileID else { return }
                    self.previewArchivedItem(next.id, profileID: next.profileID)
                }
            }
        }
    }

    private func parentCanTakeFocus(from peek: PeekCard, binding: PCNativeBrowserWindow, window: NSWindow) -> Bool {
        peekHostID == peek.parentTabID
            && browsers[peek.parentTabID]?.nativePage === peek.parentPage
            && nativeBinding === binding && commandBar == nil
            && !closingTabIDs.contains(peek.parentTabID)
            && !modelRetirementIDs.contains(peek.parentTabID)
            && !peekRetirementParents.contains(peek.parentTabID)
            && !store.retiringTabIDs.contains(peek.parentTabID)
            && !transferringTabIDs.contains(peek.parentTabID)
            && !isClosing && !wholeWindowClose && !windowClosePending
            && PCNativeBrowserApplication.canUseWindowUndo(in: window)
    }

    private func followLeavingPeek(_ peek: PeekCard) {
        guard activePeek === peek else { return }
        guard !applyingNativeSelection, !rendering else {
            DispatchQueue.main.async { [weak self, weak peek] in
                guard let self, let peek else { return }
                self.followLeavingPeek(peek)
            }
            return
        }
        requestNativeSelection()
        if peek.isLeaving { handPeekFocusToParent(peek) }
    }

    private func handPeekFocusToParent(_ peek: PeekCard) {
        guard let window, let binding = nativeBinding else { return }
        peek.lendFocus(in: window) {
            guard let parent = peek.parentPage else { return false }
            return self.activePeek === peek && self.selectedNativePage() === parent
                && self.parentCanTakeFocus(from: peek, binding: binding, window: window)
                && binding.requestFocus(for: parent)
        }
    }

    func noteRetiringPeekParents(from old: Set<UUID>) {
        let changed = old.symmetricDifference(peekRetirementParents)
        guard !changed.isEmpty else { return }
        notePeekOwnersClosing { changed.contains($0.parentTabID) }
    }

    func notePeekOwnersClosing(where affected: (PeekController) -> Bool = { _ in true }) {
        for peek in Array(peeks.values) where affected(peek) {
            peek.parentClosingChanged(wholeWindowClose || peekRetirementParents.contains(peek.parentTabID))
        }
    }

    private func peekPromotionDestination(_ peek: PeekCard) -> BrowserSpace? {
        guard activePeek === peek, peek.canInteract?() == true,
              let profileID = store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil })?.profileID
                ?? (peek.parentPage == nil ? archivePreviews[peek.identity]?.profileID : nil),
              let space = store.state.spaces.first(where: { $0.id == activeSpaceID }),
              space.profileID == profileID, space.profileID == activeProfileID else { return nil }
        if let peek = peek as? PeekController {
            guard peek.page.profilePath == store.independentEngineProfilePath(for: space.profileID) else { return nil }
        } else if peek.canExpand?() != true {
            return nil
        }
        return space
    }

    func preparePeekOpenMenuItem(_ item: NSMenuItem, preservingTarget: Bool) -> Bool {
        if preservingTarget, let command = item.representedObject as? PeekOpenCommand {
            return command.isAvailable
        }
        item.representedObject = nil; item.isHidden = true; item.image = nil
        item.title = "Open Peek in Current Space"
        guard let original = window, let peek = activePeek,
              let space = peekPromotionDestination(peek) else { return false }
        let command = PeekOpenCommand(window: original, targetIsAvailable: { [weak self, weak original, weak peek] in
            guard let self, let original, let peek, self.window === original else { return false }
            return self.ownsSpaceCommandFocus && self.commandBar == nil && peek.canRequestExit
                && self.peekPromotionDestination(peek)?.id == space.id
        }, execute: { [weak self, weak peek] in
            guard let self, let peek else { return }
            self.promotePeek(peek, split: false)
        })
        guard command.isAvailable else { return false }
        item.representedObject = command; item.isHidden = false
        item.title = "Open in " + space.name
        let icon = (space.customIcon?.image(size: 12)
            ?? NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil))?.copy() as? NSImage
        icon?.size = NSSize(width: 12, height: 12)
        item.showImage(icon)
        return true
    }

    func promotePeek(_ peek: PeekCard, split: Bool, orphaned: Bool = false) {
        if peek.returnsPage { if tabPeeks.current?.shownController === peek, !orphaned { promoteTabPeek(split: split) }; return }
        guard let peek = peek as? PeekController, peeks[peek.page.identifier] === peek, !peek.page.isClosed,
              !peek.closePending || (orphaned && peek.waitsForParent),
              !isClosing, !wholeWindowClose, !promotingPeek,
              !split || peek.canSplit?() == true,
              let binding = nativeBinding else { return }
        promotingPeek = true
        defer { promotingPeek = false }
        let oldSelection = selectedTabIDs
        let focusReturn = orphaned ? nil : PeekFocusReturn(source: peek.view)
        let creation: TabCreationProvenance?
        let destinationID: UUID
        if orphaned {
            creation = nil
            destinationID = peek.sourceSpaceID
        } else if peek.parentPage == nil {
            guard let destination = peekPromotionDestination(peek),
                  PCNativeBrowserApplication.owner(of: peek.page) === binding else { return }
            if archivePreviews[peek.identity] != nil {
                creation = nil
            } else {
                guard let host = store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil }),
                      peek.page.profilePath == store.independentEngineProfilePath(for: host.profileID) else { return }
                creation = TabCreationProvenance(referrerID: host.id, activeTabID: nil, profileID: host.profileID, state: store.state)
            }
            destinationID = destination.id
        } else {
            guard let destination = peekPromotionDestination(peek),
                  let parent = store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil }), browsers[parent.id]?.nativePage === peek.parentPage,
                  let parentPage = peek.parentPage, !parentPage.isClosed,
                  PCNativeBrowserApplication.owner(of: parentPage) === binding,
                  PCNativeBrowserApplication.owner(of: peek.page) === binding,
                  parentPage.profilePath == peek.page.profilePath,
                  peek.page.profilePath == store.independentEngineProfilePath(for: parent.profileID)
            else { return }
            destinationID = destination.id
            creation = TabCreationProvenance(referrerID: parent.id, activeTabID: nil,
                profileID: parent.profileID, state: store.state)
        }
        let archive = orphaned ? nil : archivePreviews.removeValue(forKey: peek.identity)
        if orphaned, let lease = archivePreviews.removeValue(forKey: peek.identity) { store.releaseArchivePreview(lease) }
        let restored = archive.map { store.restoreArchivePreview($0, destination: .putBack(currentSpaceID: destinationID, requestedSpaceID: nil)) }
        if let archive, restored?.count != 1 {
            if restored?.isEmpty == true, store.archivePreviewIsValid(archive) { archivePreviews[peek.identity] = archive }
            else { store.releaseArchivePreview(archive) }
            return
        }
        guard let id = restored?.first ?? store.adoptNativePage(url: peek.browser.url, title: peek.browser.title,
              profilePath: peek.page.profilePath, preferredSpaceID: destinationID, select: false,
              creation: creation),
              let tab = store.state.tab(id) else { return }
        binding.pageWillDetach(peek.page)
        let pane = makePane(tab)
        let view = peek.browser
        pane.browser = view; pane.showBrowser(); parkedPages.addSubview(pane)
        guard binding.pageDidAttach(peek.page, container: view) else {
            pane.browser = nil; pane.removeFromSuperview()
            peek.view.content.addSubview(view); view.frame = peek.view.content.bounds
            _ = binding.pageDidAttach(peek.page, container: view)
            if archive == nil { store.removeTab(id) } else { abandonRestoredPreview(peek) }
            return
        }
        ownership.release(peek.identity, owner: presentationID)
        guard ownership.claim(id, owner: presentationID, page: peek.page.identifier) else {
            binding.pageWillDetach(peek.page)
            pane.browser = nil; pane.removeFromSuperview()
            peek.view.content.addSubview(view); view.frame = peek.view.content.bounds
            _ = binding.pageDidAttach(peek.page, container: view)
            _ = ownership.claim(peek.identity, owner: presentationID, page: peek.page.identifier)
            if archive == nil { store.removeTab(id) } else { abandonRestoredPreview(peek) }
            return
        }
        browsers[id] = view; browserProfiles[id] = tab.profileID; liveTabModels[id] = tab
        requestedURLs[id] = tab.url; panes[id] = pane
        peeks.removeValue(forKey: peek.page.identifier)
        peek.finish(); view.delegate = self
        attachedPageIDs.insert(peek.page.identifier)
        zoomLevels[id] = zoomLevels.removeValue(forKey: peek.identity)
        inputRevisions.removeValue(forKey: peek.identity)
        if !orphaned { presentation.recordPeekPromotion(id, state: store.state) }
        let removal = (!split && !orphaned)
            ? presentationSetMediaRemoval(capturing: oldSelection, remaining: { Set(self.selectedTabIDs) }) {
                self.selectedTabIDs == [id]
            }
            : nil
        presentation.adopt(id, state: store.state, foreground: !orphaned)
        if split {
            prepareStoreContext(); store.setSplit(oldSelection + [id])
            presentation.captureCommand(store.state) { ownership.canUse($0, owner: presentationID) }
        }
        if !orphaned { focusedTabID = id }
        if archive != nil { closeLibrary(restoreFocus: false) }
        promotingPeek = false
        render(store.state)
        removal?()
        requestNativeSelection()
        if let window {
            focusReturn?.perform(in: window, ownerIsAvailable: {
                self.nativeBinding === binding && self.currentBrowser?.nativePage === peek.page
                    && self.activePeek == nil && self.commandBar == nil
                    && !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                    && !self.store.retiringTabIDs.contains(id) && !self.transferringTabIDs.contains(id)
                    && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                    && PCNativeBrowserApplication.canUseWindowUndo(in: window)
            }) { _ in _ = binding.requestFocus(for: peek.page) }
        }
    }

    private func abandonRestoredPreview(_ peek: PeekController) {
        archivePreviewRemnants.insert(peek.identity)
        promotingPeek = false
        render(store.state); layoutPeeks()
        if peek.view.isHidden { peek.closeWhileHidden() } else { peek.requestDismiss(.closeButton) }
    }

    func closePageAndPeeks(_ id: UUID, page: PCNativePage, updateSavedTab: Bool) {
        guard !closingTabIDs.contains(id), !wholeWindowClose, !isClosing,
              !transferringTabIDs.contains(id) else { return }
        let original = liveTabModels[id], expected = store.state.tab(id)
        let children = peekPages(forTabID: id)
        peekRetirementParents.insert(id)
        closingTabIDs.insert(id)
        if !updateSavedTab { modelRetirementIDs.insert(id) }
        PCNativeBrowserApplication.requestClosePages([page] + children, shouldCommit: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return false }
                return !self.wholeWindowClose && !self.isClosing && self.browsers[id]?.nativePage === page
                    && children.allSatisfy { self.peeks[$0.identifier]?.parentTabID == id }
            }
        }, completion: { [weak self] allowed in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.peekRetirementParents.remove(id)
                self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
                if allowed { self.releaseClosedTab(id, updateSavedTab: updateSavedTab) }
                else if page.isClosed {
                    for child in children {
                        if let peek = self.peeks[child.identifier], !child.isClosed {
                            self.promotePeek(peek, split: false, orphaned: true)
                        }
                    }
                } else if !updateSavedTab, self.browsers[id]?.nativePage === page, let original {
                    _ = self.store.restoreLiveTab(original, replacing: expected)
                }
                self.render(self.store.state); self.requestNativeSelection()
            }
        })
    }

    func activePeek(showing page: PCNativePage) -> PeekController? {
        guard let peek = activePagePeek, peek.page === page else { return nil }
        return peek
    }

    var historySwipePalette: ThemeChromePalette { rootView.palette }
    var historySwipePages: [PCNativePage] {
        if let card = activePeek, !(card is PeekController) {
            guard !card.view.isHidden, let id = peekedDocumentTabID,
                  let page = embeddedPagePool(forTabID: id)?.selectedPage else { return [] }
            return [page]
        }
        let peek = activePagePeek
        let panes = renderedPaneIDs.map { id in
            let tab = store.state.tab(id)
            let browser = tab == nil ? nil : browsers[id]
            return HistorySwipeTargets.Pane(easelPage: embeddedPagePool(forTabID: id)?.selectedPage,
                                            page: browser?.nativePage,
                                            isInternal: tab.map { InternalPage.isInternal($0.url) } ?? true,
                                            isHidden: browser?.isHiddenOrHasHiddenAncestor ?? true)
        }
        return HistorySwipeTargets.pages(peek: peek?.page, peekShown: peek?.view.isHidden == false, panes: panes)
    }
}
