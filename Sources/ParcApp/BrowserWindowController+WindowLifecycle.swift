import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func scheduleMediaRefresh() {
        mediaRefresh.schedule { [weak self] in
            guard let self, !self.rendering, !self.isClosing, !self.wholeWindowClose else { return }
            self.refreshLivePageChromeOrRender()
        }
    }
    func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?) {
        if selectedTabIDs.contains(where: { browsers[$0] === view }) { pageHost.cancelDrop() }
        guard let id = id(for: view) else { return }
        refreshPagePresentation(id)
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) {
        guard let id = id(for: view), view.rendererCrash === crash,
              let expected = rendererPresentation(view) else { return }
        refreshPagePresentation(id)
        focusRendererFailure(id, expected)
    }
    func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack back: Bool, canGoForward forward: Bool) {
        reconcileFind()
        if loading, selectedTabIDs.contains(where: { browsers[$0] === view }) { pageHost.cancelDrop() }
        if loading, view === pendingCommandSplitBrowser { cancelPendingCommandSplit() }
        if let id = id(for: view) {
            if loading {
                loadingTabs.insert(id)
            } else {
                loadingTabs.remove(id); scheduleCookieFlush(); scheduleTabHistoryCapture(id)
            }
            refreshLivePageChromeOrRender()
            if !loading, !rendering, !isClosing, !wholeWindowClose { sidebar.reloadFavicon(for: id) }
            if pendingNativeSelection?.view === view { attachOwnedPages() }
            if !loading, peekUndoAwaitingParent[id] != nil, !awaitedPeekRetries.contains(id) {
                DispatchQueue.main.async { [weak self] in self?.openAwaitedPeek(over: id) }
            }
        }
    }
    func browserViewDidRequestClose(_ view: PCBrowserView) {
        if let covered = coveredTabID(for: view), view.nativePage?.isClosed == true { releaseCoveredPage(covered); return }
        guard let id = id(for: view), view.nativePage?.isClosed == true else { return }
        releaseClosedTab(id, updateSavedTab: !wholeWindowClose && !modelRetirementIDs.contains(id) && !transferringTabIDs.contains(id))
    }
    func browserView(_ view: PCBrowserView, didLearnSafariIdentityForSite site: String,
                     profilePath: String, offTheRecord: Bool) {
        FairPlayIdentityController.shared.didLearn(site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
    func browserView(_ view: PCBrowserView, didFailWithError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        if let id = id(for: view) {
            if view.rendererCrash == nil { failures[id] = error.localizedDescription }
            loadingTabs.remove(id)
            refreshPagePresentation(id)
            updateNavigation()
        }
    }
    func shutdownBrowsers() {
        guard !isClosing else { return }
        guard browsers.values.allSatisfy({ $0.nativePage == nil || $0.nativePage?.isClosed == true }),
              peeks.values.allSatisfy({ $0.page.isClosed }) else {
            NSLog("Parc refused window disposal with live native pages")
            return
        }
        isClosing = true
        store.placeholderImages.removeWindow(presentationID)
        placeholderCapturesPending.removeAll()
        stopLibraryFlyoutFileQuery()
        archiveActivityScheduling.cancel()
        for peek in peeks.values { peek.finish() }; peeks.removeAll()
        retireTabPeeks()
        archivePreviews.values.forEach(store.releaseArchivePreview); archivePreviews.removeAll()
        if let request = archivePreviewRequest { store.releaseArchivePreview(request.lease) }
        archivePreviewRequest = nil; queuedArchivePreview = nil; archivePreviewRemnants.removeAll()
        sidebarPreviews?.shutdown(); sidebarPreviews = nil
        settleSidebarMotion()
        libraryMotion.cancel()
        if let sidebarAccessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sidebarAccessibilityObserver)
            self.sidebarAccessibilityObserver = nil
        }
        pendingNativeSelection = nil
        dismissSiteControlCenter()
        themePopover?.performClose(nil)
        sidebarHover.invalidate()
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }; menuObservers.removeAll()
        commandBar?.dismiss()
        for view in browsers.values { view.delegate = nil; view.removeFromSuperview() }
        browsers.removeAll()
        ownership.releaseAll(owner: presentationID)
        subscription = nil
        developerModeSubscription = nil
        toolbarSubscription = nil
        windowDraggingSubscription = nil
        websiteThemeSubscription = nil
        for pane in panes.values { pane.windowGrabber.configure(owner: nil, revision: 0, isCurrent: nil, eligibility: nil) }
        for (id, pane) in easelEditors { pane.editor.retirePageOwner(); panes[id]?.clearNativeContent() }
        easelEditors.removeAll(); easelFailures.removeAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
    }
    func retireEmptyNativeWindow() {
        guard settings?.window?.isVisible != true,
              settings?.window?.attachedSheet == nil else { return }
        windowCloseApproved = true
        windowClosePending = false
        wholeWindowClose = true
        window?.close()
    }
    func prepareForApplicationClose() { wholeWindowClose = true }
    func cancelApplicationClose() {
        wholeWindowClose = false
        if restoreSettingsAfterCancelledTermination { settings?.restoreAfterCancelledOwnerClose() }
        restoreSettingsAfterCancelledTermination = false
        render(store.state)
    }
    func ownsSettings(_ candidate: SettingsWindow) -> Bool { settings === candidate }
    func prepareAuxiliaryWindowForOnboarding(completion: @escaping (Bool) -> Void) {
        guard isPrivateBrowsing || isPopupWindow, hasReadyPresentation, let window,
              window.attachedSheet == nil, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, let binding = nativeBinding else {
            completion(false); return
        }
        func pages() -> [PCNativePage] {
            Array(browsers.values.compactMap(\.nativePage)) + peeks.values.map(\.page)
                + easelEditors.values.flatMap { $0.editor.pageObjects?.pages ?? [] }
        }
        func hasStableOwners() -> Bool {
            collectionTransfer == nil && transferRecoveries.isEmpty && transferringTabIDs.isEmpty
                && resolvingTransfers.isEmpty && transferContainers.isEmpty
                && !hasPendingNativePage(in: Set(browsers.keys).union(easelEditors.keys))
        }
        guard hasStableOwners() else { completion(false); return }
        let originals = pages()
        let identities = Set(originals.map(ObjectIdentifier.init))
        guard identities.count == originals.count else { completion(false); return }
        windowClosePending = true
        func isCurrent() -> Bool {
            self.window === window && self.nativeBinding === binding && !isClosing && !wholeWindowClose
                && windowClosePending && hasStableOwners()
                && Set(pages().map(ObjectIdentifier.init)) == identities
                && originals.allSatisfy { !$0.isClosed && PCNativeBrowserApplication.owner(of: $0) === binding }
        }
        var consented = false
        PCNativeBrowserApplication.requestClosePages(originals, shouldCommit: {
            MainActor.assumeIsolated {
                consented = isCurrent()
                return false
            }
        }, completion: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { completion(false); return }
                let approved = consented && isCurrent()
                self.windowClosePending = false
                completion(approved)
            }
        })
    }
    func closeForOnboarding(completion: @escaping (Bool) -> Void) {
        guard hasReadyPresentation, let window, window.attachedSheet == nil,
              !isClosing, !wholeWindowClose, !windowClosePending,
              !windowCloseApproved, nativeBinding != nil else { completion(false); return }
        onboardingCloseRequested = true
        scriptingWindowCloseCompletions.append { [weak self] approved in
            if let self {
                for saved in self.onboardingCloseNotes ?? [] { saved.file.page.isReadOnly = saved.wasReadOnly }
                self.onboardingCloseNotes = nil
                self.onboardingCloseRequested = false
            }
            completion(approved)
        }
        window.performClose(nil)
        if !windowClosePending && !windowCloseApproved && !closeAfterEjecting && !pendingApprovedWindowClose {
            finishScriptingWindowClose(false)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return false }
        if windowCloseApproved, onboardingCloseNotes != nil { return true }
        guard !windowClosePending else { return false }
        func refuse() -> Bool { finishScriptingWindowClose(false); return false }
        guard prepareNotesToClose() else { return refuse() }
        if let transfer = collectionTransfer { transfer.retry(); return refuse() }
        if let retry = transferRecoveries.values.first { retry(); return refuse() }
        guard transferringTabIDs.isEmpty else { return refuse() }
        if windowCloseApproved {
            guard settings?.attemptClose() ?? true else {
                pendingApprovedWindowClose = true
                return false
            }
            pendingApprovedWindowClose = false
            return true
        }
        guard let binding = nativeBinding else { return refuse() }
        if ejectPageBeforeClose() { return false }
        let settingsWasVisible = settings?.window?.isVisible == true
        guard settings?.attemptClose() ?? true else {
            finishScriptingWindowClose(false)
            return false
        }
        if onboardingCloseRequested {
            guard prepareNotesToClose() else { return refuse() }
            var files: [ObjectIdentifier: NoteFileSession] = [:]
            for note in noteEditors.values { files[ObjectIdentifier(note.editor.file)] = note.editor.file }
            onboardingCloseNotes = files.values.map { file in
                let saved = (file: file, wasReadOnly: file.page.isReadOnly)
                file.page.isReadOnly = true
                return saved
            }
        }
        windowClosePending = true
        wholeWindowClose = true
        binding.requestClose { [weak self, weak sender] allowed in
            guard let self else { return }
            self.windowClosePending = false
            if allowed {
                self.windowCloseApproved = true
                sender?.performClose(nil)
            } else {
                self.wholeWindowClose = false
                self.render(self.store.state)
                if settingsWasVisible { self.settings?.restoreAfterCancelledOwnerClose() }
                self.finishScriptingWindowClose(false)
            }
        }
        return false
    }
    private func ejectPageBeforeClose() -> Bool {
        for id in heldContentIDs.sorted(by: { $0.uuidString < $1.uuidString })
        where !ejectionAttempts.contains(id) && canHandOverPage(id) {
            ejectionAttempts.insert(id)
            if onUntargetedReturn?(id, self, .ownerClosing) == .started { closeAfterEjecting = true; return true }
        }
        ejectionAttempts.removeAll()
        return false
    }
    func resumeCloseAfterEjecting() {
        guard closeAfterEjecting else { return }
        closeAfterEjecting = false
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, let window = self.window else { return }
            window.performClose(nil)
        }
    }
    func retryPendingSettingsClose() {
        guard !isClosing else { return }
        if pendingApprovedWindowClose { window?.performClose(nil) }
    }
    func windowWillClose(_ notification: Notification) { abandonFrameCrank(); archiveEducationSubscription?.cancel(); updateCompleteSubscription?.cancel(); updateReadySubscription?.cancel(); sidebar.resetAutoArchiveEducation(); sidebar.resetUpdateComplete(); sidebar.resetUpdateReady(); loadingIndicator.reset(); paneFrameObservers.values.forEach(NotificationCenter.default.removeObserver); paneFrameObservers.removeAll(); if isPrivateBrowsing { store.clearPrivateDownloads() }; if let session = spaceCreation { finishSpaceCreation(session) }; pageHost.cancelDrop(); favoriteRename?.cancel(); favoriteSplitRename?.cancel(); splitIconPicker?.cancel(); spaceIconPicker?.cancel(); sidebar.cancelSpaceNameEditing(); dismissSidebarMoveNotice(); sharedQuotes.invalidate(); noteEditors.removeAll(); closedItems = WindowClosedItems(); peekRedo = nil; peekUndoOpen = nil; peekUndoAwaitingParent.removeAll(); awaitedPeekRetries.removeAll(); undoHiddenPeek = nil; retiringPageHistory.removeAll(); folderUndo.removeAllActions(); nativeEditingUndo.removeAllActions(); finishScriptingWindowClose(true); pageCapture?.dismiss(restoreFocus: false); navigationHistory?.dismiss(); shortcutEssentials?.close(); tabSwitcher?.cancel(); libraryMotion.cancel(); libraryView?.removeFromSuperview(); libraryView = nil; libraryContentWidth = 0; easelImageDestination?.dismiss(); downloadReview?.dismiss(); downloadArrival.dismiss(force: true); dismissSiteControlCenter(); endAddressButtonHolds(); if let bar = residentCommandBar { residentCommandBar = nil; bar.dismiss(restoreFocus: false) }; shutdownBrowsers(); userActivity?.invalidate(); userActivity = nil; onClose?() }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === window { splitLinkGeneration &+= 1 }
        pageHost.cancelDrop()
        refreshDeveloperToolbars()
        cancelPendingCommandSplit()
        sidebar.updateSpaceAvailability()
        sidebarPreviews?.dismiss()
        refreshSidebarPointer()
    }
    func windowDidEndSheet(_ notification: Notification) {
        if !rendering, !isClosing { updateNavigation() }
        refreshSidebarPointer()
    }
}
