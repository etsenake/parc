import AppKit
import Combine

extension BrowserWindowController {
    func canHostPeek(_ browser: PCNativeBrowserWindow, over page: PCNativePage, overLibrary: Bool = false,
                     ignoringCommandBar: Bool = false) -> Bool {
        windowAdmitsPeek(browser, overLibrary: overLibrary, ignoringCommandBar: ignoringCommandBar) && !page.isClosed
            && PCNativeBrowserApplication.owner(of: page) === browser
            && !peeks.values.contains { $0.parentPage === page } && tabPeeks.current == nil
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
              let current = currentTabID, store.state.containsTab(current, where: { $0.archivedAt == nil }),
              let parent = browsers[current]?.nativePage, selectedNativePage() === parent,
              PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))),
              canHostPeek(binding, over: parent, overLibrary: true),
              let lease = store.acquireArchivePreview(id: id, profileID: profileID) else { return false }
        guard lease.tabs.count == 1, let url = URL(string: lease.tabs[0].url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            store.releaseArchivePreview(lease); return false
        }
        let token = UUID()
        archivePreviewRequest = (parent.identifier, lease, token)
        guard parent.openPeek(url: url) else {
            archivePreviewRequest = nil; store.releaseArchivePreview(lease); return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let request = self.archivePreviewRequest, request.token == token else { return }
            self.archivePreviewRequest = nil; self.store.releaseArchivePreview(request.lease)
        }
        return true
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
        return peek.browser
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
            if peek.parentPage.isClosed { self.promotePeek(peek, split: false, orphaned: true) }
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
        syncPeekStepBack()
    }

    func placePeek(_ peek: PeekController) {
        if peekLayer.frame != rootView.bounds { peekLayer.frame = rootView.bounds }
        peek.view.frame = peekLayer.bounds
        peek.view.pageFrame = pageHost.frame
        peek.view.stepsBack = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func wirePeekPresentation(_ peek: PeekController) {
        peek.view.adoptWindowTheme(rootView)
        peek.onLeavingChange = { [weak self, weak peek] in
            guard let self, let peek, self.activePeek === peek else { return }
            self.requestNativeSelection()
            if peek.isLeaving { self.handPeekFocusToParent(peek) }
        }
        peek.view.onStep = { [weak self, weak peek] animated in
            guard let self, let peek, self.activePeek === peek else { return }
            self.syncPeekStepBack(animated: animated)
        }
        peek.onMotionPreference = { [weak self] in self?.layoutPeeks() }
    }

    func syncPeekStepBack(animated: Bool = false) {
        let shown = activePeek.flatMap { $0.view.isHidden || $0.view.superview !== peekLayer ? nil : $0 }
        loadingIndicator.alphaValue = shown == nil ? 1 : 0
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
              PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))),
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
    func movePeekParentHere(_ parent: UUID, then open: @escaping () -> Void, failed: @escaping () -> Void = {}) -> Bool {
        var settled = false
        let fail = { if !settled { settled = true; failed() } }
        let arrival = PendingArrival(abandoned: fail)
        let started = movePagesHere([parent]) { [weak self] in
            arrival.ran = true
            guard let self, self.selectTab(parent) else { fail(); return false }
            settled = true
            DispatchQueue.main.async(execute: open)
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
                }) { _ in _ = binding.requestFocus(for: peek.parentPage) }
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

    private func parentCanTakeFocus(from peek: PeekController, binding: PCNativeBrowserWindow, window: NSWindow) -> Bool {
        currentTabID == peek.parentTabID
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

    private func handPeekFocusToParent(_ peek: PeekController) {
        guard let window, let binding = nativeBinding else { return }
        peek.lendFocus(in: window) {
            self.activePeek === peek && self.selectedNativePage() === peek.parentPage
                && self.parentCanTakeFocus(from: peek, binding: binding, window: window)
                && binding.requestFocus(for: peek.parentPage)
        }
    }

    func noteRetiringPeekParents(from old: Set<UUID>) {
        let changed = old.symmetricDifference(peekRetirementParents)
        guard !changed.isEmpty else { return }
        for peek in Array(peeks.values) where changed.contains(peek.parentTabID) {
            peek.parentClosingChanged(peekRetirementParents.contains(peek.parentTabID))
        }
    }

    private func peekPromotionDestination(_ peek: PeekController) -> BrowserSpace? {
        guard activePeek === peek, peek.canInteract?() == true,
              let parent = store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil }),
              let space = store.state.spaces.first(where: { $0.id == activeSpaceID }),
              space.profileID == parent.profileID, space.profileID == activeProfileID,
              peek.page.profilePath == store.independentEngineProfilePath(for: space.profileID) else { return nil }
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

    func promotePeek(_ peek: PeekController, split: Bool, orphaned: Bool = false) {
        if peek.returnsPage { if tabPeeks.current?.shownController === peek, !orphaned { promoteTabPeek(split: split) }; return }
        guard peeks[peek.page.identifier] === peek, !peek.page.isClosed,
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
        } else {
            guard let destination = peekPromotionDestination(peek),
                  let parent = store.state.tab(peek.parentTabID, where: { $0.archivedAt == nil }), browsers[parent.id]?.nativePage === peek.parentPage,
                  !peek.parentPage.isClosed,
                  PCNativeBrowserApplication.owner(of: peek.parentPage) === binding,
                  PCNativeBrowserApplication.owner(of: peek.page) === binding,
                  peek.parentPage.profilePath == peek.page.profilePath,
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
        guard let peek = activePeek, peek.page === page else { return nil }
        return peek
    }

    var historySwipePalette: ThemeChromePalette { rootView.palette }
    var historySwipePages: [PCNativePage] {
        let peek = activePeek
        let panes = renderedPaneIDs.map { id in
            let tab = store.state.tab(id)
            let browser = tab == nil ? nil : browsers[id]
            return HistorySwipeTargets.Pane(easelPage: easelEditors[id]?.editor.pageObjects?.selectedPage,
                                            page: browser?.nativePage,
                                            isInternal: tab.map { InternalPage.isInternal($0.url) } ?? true,
                                            isHidden: browser?.isHiddenOrHasHiddenAncestor ?? true)
        }
        return HistorySwipeTargets.pages(peek: peek?.page, peekShown: peek?.view.isHidden == false, panes: panes)
    }
}
