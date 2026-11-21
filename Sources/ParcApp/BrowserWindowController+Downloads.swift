import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    private func privateDownloadContext(_ item: BrowserDownload) -> PCNativePrivateDownloadContext? {
        guard let id = item.privateContextID, let profile = item.profileID else { return nil }
        return PCNativeBrowserApplication.privateDownloadContexts().first {
            $0.identifier == id && $0.isValid && $0.profilePath == downloadStore.independentEngineProfilePath(for: profile)
        }
    }

    func showDownloads() { showLibrary(.downloads) }
    func startLibraryFlyoutFileQuery() {
        guard libraryFlyoutFileMonitor == nil else { return }
        libraryFlyoutFileActivation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshLibraryFlyoutFiles() } }
        libraryFlyoutFileMonitor = LibraryFlyoutFolderMonitor { [weak self] in self?.refreshLibraryFlyoutFiles() }
        refreshLibraryFlyoutFiles()
    }
    func stopLibraryFlyoutFileQuery() {
        libraryFlyoutFileGeneration &+= 1
        libraryFlyoutFileMonitor?.cancel(); libraryFlyoutFileMonitor = nil
        if let libraryFlyoutFileActivation {
            NotificationCenter.default.removeObserver(libraryFlyoutFileActivation)
            self.libraryFlyoutFileActivation = nil
        }
        sidebar.updateLibraryFlyoutFiles([])
    }
    private func refreshLibraryFlyoutFiles() {
        libraryFlyoutFileGeneration &+= 1
        let generation = libraryFlyoutFileGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let folders = LibraryFlyoutFiles.defaultFolders()
            let files = LibraryFlyoutFiles.scan(folders: folders)
            DispatchQueue.main.async {
                guard let self, generation == self.libraryFlyoutFileGeneration, !self.isClosing, !self.wholeWindowClose else { return }
                self.libraryFlyoutFileMonitor?.watch(folders.map(\.1))
                self.sidebar.updateLibraryFlyoutFiles(files)
            }
        }
    }
    func refreshDownloadProfiles() {
        let catalog = downloadStore
        for profile in catalog.state.profiles where !loadingDownloadProfiles.contains(profile.id) && !catalog.isProfileRemovalPending(profile.id) {
            loadingDownloadProfiles.insert(profile.id); downloadProfileErrors[profile.id] = nil
            PCNativeBrowserApplication.refreshDownloads(profilePath: catalog.independentEngineProfilePath(for: profile.id)) { [weak self, weak catalog] identifiers, error in
                MainActor.assumeIsolated {
                    guard let self, let catalog, self.downloadStore === catalog else { return }
                    self.loadingDownloadProfiles.remove(profile.id)
                    if catalog.state.profiles.contains(where: { $0.id == profile.id }) {
                        if error == nil, let identifiers { catalog.reconcileDownloads(profileID: profile.id, nativeIDs: Set(identifiers)) }
                        let spaceName = catalog.state.spaces.first { $0.profileID == profile.id }?.name
                        self.downloadProfileErrors[profile.id] = error.map { error in
                            spaceName.map { $0 + ": " + error.localizedDescription } ?? error.localizedDescription
                        }
                    }
                    self.updateDownloadLoading()
                }
            }
        }
        for context in PCNativeBrowserApplication.privateDownloadContexts() where context.isValid && !loadingPrivateDownloadContexts.contains(context.identifier) {
            let id = context.identifier
            loadingPrivateDownloadContexts.insert(id); privateDownloadErrors[id] = nil
            context.refresh { [weak self, weak catalog, weak context] identifiers, error in
                MainActor.assumeIsolated {
                    guard let self, let catalog, self.downloadStore === catalog else { return }
                    self.loadingPrivateDownloadContexts.remove(id)
                    if let context, context.isValid {
                        if error == nil, let identifiers { catalog.reconcileTransientDownloads(contextID: id, nativeIDs: Set(identifiers)) }
                        self.privateDownloadErrors[id] = error?.localizedDescription
                    } else { catalog.retireTransientDownloads(contextID: id); self.privateDownloadErrors[id] = nil }
                    self.updateDownloadLoading()
                }
            }
        }
        updateDownloadLoading()
    }
    private func updateDownloadLoading() {
        let profiles = Set(downloadStore.state.profiles.map(\.id))
        let liveContexts = Set(PCNativeBrowserApplication.privateDownloadContexts().filter(\.isValid).map(\.identifier))
        privateDownloadErrors = privateDownloadErrors.filter { liveContexts.contains($0.key) }
        let message = (Array(downloadProfileErrors.filter { profiles.contains($0.key) }.values) + Array(privateDownloadErrors.values)).sorted().joined(separator: " · ")
        if libraryView?.kind == .downloads {
            for item in downloadStore.downloadItems where recyclingDownloads[item.id] == DownloadLibraryIdentity(item) {
                libraryView?.setDownloadOperation(item, message: "Moving to Trash…")
            }
        }
        libraryView?.setDownloadsLoading(count: loadingDownloadProfiles.intersection(profiles).count + loadingPrivateDownloadContexts.intersection(liveContexts).count,
                                         message: message.isEmpty ? nil : message)
    }
    private var downloadActivityProfiles: Set<UUID> {
        Set(downloadStore.state.profiles.filter { !downloadStore.isProfileRemovalPending($0.id) }.map(\.id))
    }
    private var downloadActivityEnabled: Bool {
        (!isPrivateBrowsing || nativeBinding?.privateDownloadsAvailable == true) && !isClosing && !wholeWindowClose && presentation.isReady
    }
    func refreshLibraryDownloadActivity() {
        libraryView?.updateDownloadActivity(downloadStore.downloadItems, profiles: downloadActivityProfiles,
                                            privateWindow: isPrivateBrowsing, enabled: downloadActivityEnabled)
    }
    func refreshDownloads() {
        sidebar.updateDownloadActivity(downloadStore.downloadItems, profiles: downloadActivityProfiles, enabled: downloadActivityEnabled)
        refreshLibraryDownloadActivity()
        sidebar.updateLibraryCaptures(isPrivateBrowsing || isClosing || wholeWindowClose ? nil
            : CaptureLibraryStore.shared(directory: store.capturesDirectory(for: activeProfileID), profileID: activeProfileID))
        if let downloadReview, let item = downloadReviewItem {
            if let current = currentDownloadReview(item) { downloadReview.update(current) }
            else { downloadReview.dismiss() }
        }
    }
    private func liveLibraryDownload(_ expected: BrowserDownload) -> BrowserDownload? {
        guard !isClosing, !wholeWindowClose, presentation.isReady,
              let identity = expected.nativeIdentity, !identity.isEmpty,
              let profile = expected.profileID, !downloadStore.isProfileRemovalPending(profile),
              downloadStore.state.profiles.contains(where: { $0.id == profile }),
              let current = downloadStore.downloadItems.first(where: { $0.id == expected.id }),
              current.profileID == profile, current.nativeID == expected.nativeID,
              current.nativeIdentity == identity, current.privateContextID == expected.privateContextID,
              current.privateContextID == nil || privateDownloadContext(current) != nil else { return nil }
        return current
    }
    func libraryDownloadFileURL(_ expected: BrowserDownload) -> URL? {
        guard window?.attachedSheet == nil,
              let item = liveLibraryDownload(expected), item.canCopyFile,
              let profile = item.profileID, let nativeID = item.nativeID,
              let identity = item.nativeIdentity, recyclingDownloads[item.id] == nil else { return nil }
        if item.privateContextID != nil { return privateDownloadContext(item)?.fileURL(identifier: nativeID, itemIdentity: identity) }
        return PCNativeBrowserApplication.downloadFileURL(identifier: nativeID,
            profilePath: downloadStore.independentEngineProfilePath(for: profile), itemIdentity: identity)
    }
    private func currentDownloadReview(_ expected: BrowserDownload) -> PCNativeDownloadReview? {
        guard let item = liveLibraryDownload(expected), item.canReview,
              let profile = item.profileID, let nativeID = item.nativeID else { return nil }
        if item.privateContextID != nil {
            guard let identity = item.nativeIdentity else { return nil }
            return privateDownloadContext(item)?.review(identifier: nativeID, itemIdentity: identity)
        }
        return PCNativeBrowserApplication.downloadReview(identifier: nativeID,
            profilePath: downloadStore.independentEngineProfilePath(for: profile))
    }
    private func reviewDownload(_ item: BrowserDownload) -> Bool {
        guard downloadReview == nil, let parent = window, parent.attachedSheet == nil,
              let profile = item.profileID, let snapshot = currentDownloadReview(item) else { return false }
        let path = downloadStore.independentEngineProfilePath(for: profile)
        let controller = DownloadReviewController(review: snapshot, theme: activeSpace.theme, incognito: rootView.incognito)
        downloadReview = controller; downloadReviewItem = item
        controller.onDecision = { [weak self, weak controller, weak parent] displayed, action, password, justification in
            guard let self, let controller, let parent, self.window === parent,
                  self.downloadReview === controller, controller.window?.sheetParent === parent,
                  displayed.profilePath == path, self.currentDownloadReview(item) != nil else { return false }
            if item.privateContextID != nil {
                return self.privateDownloadContext(item)?.performReview(action, for: displayed,
                    password: password, justification: justification) ?? false
            }
            return PCNativeBrowserApplication.performDownloadReviewAction(action, for: displayed,
                password: password, justification: justification)
        }
        controller.onOpenLink = { [weak self, weak controller, weak parent] displayed, index in
            guard let self, let controller, let parent, self.window === parent,
                  self.downloadReview === controller, controller.window?.sheetParent === parent,
                  displayed.profilePath == path, self.currentDownloadReview(item) != nil,
                  let nativeIndex = UInt(exactly: index),
                  let url = (item.privateContextID != nil ? self.privateDownloadContext(item)?.reviewLink(at: nativeIndex, for: displayed)
                    : PCNativeBrowserApplication.downloadReviewLink(at: nativeIndex, for: displayed)) else { return false }
            controller.dismiss()
            return self.onOpenDownloadSource?(item, url) ?? false
        }
        controller.onRefresh = { [weak self] in self?.currentDownloadReview(item) }
        controller.onClose = { [weak self, weak controller] in
            if self?.downloadReview === controller { self?.downloadReview = nil; self?.downloadReviewItem = nil }
        }
        controller.present(on: parent)
        return true
    }
    func openDownloadSourceURL(_ url: URL, profileID: UUID) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty,
              let window, window.attachedSheet == nil,
              ["http", "https", "parc", "chrome", "chrome-extension"].contains(url.scheme?.lowercased() ?? ""),
              let destination = (activeProfileID == profileID ? activeSpaceID :
                  store.state.spaces.first(where: { $0.profileID == profileID })?.id),
              (isPrivateBrowsing ? (nativeBinding?.privateDownloadsAvailable == true && activeProfileID == profileID && destination == activeSpaceID)
                 : selectSpaceFromUser(destination, profileID: profileID)), activeProfileID == profileID else { return false }
        closeLibrary(restoreFocus: false)
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.open(url.absoluteString, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
    private func performNativeDownloadAction(_ command: PCNativeDownloadAction, item: BrowserDownload) -> Bool {
        guard let current = liveLibraryDownload(item), let identifier = current.nativeID,
              let itemIdentity = current.nativeIdentity, let profile = current.profileID else { return false }
        if current.privateContextID != nil {
            return privateDownloadContext(current)?.perform(command, identifier: identifier, itemIdentity: itemIdentity) ?? false
        }
        return PCNativeBrowserApplication.performDownloadAction(command, identifier: identifier,
            profilePath: downloadStore.independentEngineProfilePath(for: profile), itemIdentity: itemIdentity)
    }
    func performLibraryDownload(_ expected: BrowserDownload, action: DownloadLibraryAction) -> Bool {
        guard let window, window.attachedSheet == nil, !isClosing, !wholeWindowClose,
              presentation.isReady, transferringTabIDs.isEmpty else { return false }
        if action == .copyLink || action == .openSource {
            guard let current = downloadStore.downloadItems.first(where: { $0.id == expected.id }),
                  current.profileID == expected.profileID, current.sourceURL == expected.sourceURL,
                  current.privateContextID == expected.privateContextID,
                  current.privateContextID == nil || privateDownloadContext(current) != nil,
                  expected.nativeIdentity == nil || current.nativeIdentity == expected.nativeIdentity,
                  let profile = current.profileID, downloadStore.state.profiles.contains(where: { $0.id == profile }),
                  !downloadStore.isProfileRemovalPending(profile), let source = current.sourceURL, let url = URL(string: source) else { return false }
            if action == .openSource { return onOpenDownloadSource?(current, url) ?? false }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(source, forType: .string) else { return false }
            showToast(.copiedCurrentURL(url), at: .window)
            return true
        }
        guard let item = liveLibraryDownload(expected), recyclingDownloads[item.id] == nil else { return false }
        if action == .review { return reviewDownload(item) }
        if action == .copyFile {
            guard let url = libraryDownloadFileURL(item) else { return false }
            NSPasteboard.general.clearContents(); return NSPasteboard.general.writeObjects([url as NSURL])
        }
        if action == .trash {
            guard item.canRemove, let url = libraryDownloadFileURL(item) else { return false }
            recyclingDownloads[item.id] = DownloadLibraryIdentity(item)
            libraryView?.setDownloadOperation(item, message: "Moving to Trash…")
            NSWorkspace.shared.recycle([url]) { [weak self] moved, error in
                let succeeded = error == nil && moved[url] != nil
                let message = error?.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.recyclingDownloads.removeValue(forKey: item.id)
                    self.libraryView?.setDownloadOperation(item, message: nil)
                    guard let current = self.liveLibraryDownload(item), current.path == item.path else { return }
                    if succeeded {
                        _ = self.performNativeDownloadAction(.remove, item: item)
                    } else if let owner = self.window, !self.isClosing, owner.attachedSheet == nil {
                        ParcDialog.inform(in: owner, .init(title: "Couldn’t move the download to Trash",
                            message: message ?? "The file was not moved. Its download record has been kept."))
                    }
                }
            }
            return true
        }
        let command: PCNativeDownloadAction
        switch action {
        case .open: command = .open
        case .reveal: command = .reveal
        case .toggleOpen: command = .toggleOpen
        case .pause: command = .pause
        case .resume: command = .resume
        case .cancel: command = .cancel
        case .retry: command = .retry
        case .remove: command = .remove
        case .review, .copyFile, .copyLink, .openSource, .trash: return false
        }
        return performNativeDownloadAction(command, item: item)
    }

    func id(for browser: PCBrowserView) -> UUID? { browsers.first { $0.value === browser }?.key }
    func browserView(_ view: PCBrowserView, openLinkInSplitView url: URL) {
        guard browserViewCanOpenLinkInSplitView(view), let id = id(for: view),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        let creation = TabCreationProvenance(referrerID: id, activeTabID: currentTabID,
                                             profileID: activeProfileID, state: store.state)
        if insertPreviewSplit(url: url, creation: creation, after: id) { return }
        if selectedTabIDs.count >= 4 { showToast(.cannotAddNewPane, at: .window) }
    }

    func browserViewCanOpenLinkInSplitView(_ view: PCBrowserView) -> Bool {
        canOpenLinkInSplitView(view, ignoringCommandBar: false)
    }

    func canOpenLinkInSplitView(_ view: PCBrowserView, ignoringCommandBar: Bool) -> Bool {
        guard let id = id(for: view), selectedTabIDs.contains(id), browserProfiles[id] == activeProfileID,
              let window, window.attachedSheet == nil, !isClosing,
              ignoringCommandBar || commandBar == nil else { return false }
        return splitCommandsAvailable && splitInsertion == nil && !isPopupWindow
            && nativeFullscreenTabID == nil && selectedTabIDs.allSatisfy({ switcherCanUse($0) })
    }

    func browserView(_ view: PCBrowserView, addContextImageToEasel image: PCNativeContextImage) {
        let embedded = view.nativePage.flatMap { embeddedPageOwner($0) }
        let held = activePeek.flatMap { $0.returnsPage && $0.browser === view ? $0.parentTabID : nil }
        let hosted = activePeek.flatMap { $0.parentPage == nil && $0.browser === view ? $0 : nil }
        guard !isPrivateBrowsing, let id = held ?? id(for: view) ?? peeks.values.first(where: { $0.browser === view })?.parentTabID ?? embedded?.0,
              let profileID = browserProfiles[id] ?? easelEditors[id]?.profileID ?? noteEditors[id]?.profileID ?? hosted.flatMap(peekProfileID),
              profileID == activeProfileID, selectedTabIDs.contains(id) || hosted != nil,
              let window, window.attachedSheet == nil, easelImageDestination == nil, !isClosing, image.isValid,
              let page = view.nativePage,
              page.profilePath == store.independentEngineProfilePath(for: profileID) else { return }
        do {
            let controller = try EaselImageDestinationController(image: image,
                directory: store.easelsDirectory(for: profileID),
                valid: { [weak self, weak view, weak page] in
                    guard let self, let view, let page else { return false }
                    return !self.isClosing && self.activeProfileID == profileID
                        && self.selectedNativePage() === page && view.nativePage === page
                        && ((self.browserProfiles[id] ?? self.easelEditors[id]?.profileID) == profileID && self.selectedTabIDs.contains(id)
                            || self.activePeek.map { $0.parentPage == nil && $0.browser === view } == true)
                        && !self.transferringTabIDs.contains(id) && image.isValid
                }, saved: { [weak self] documentID, title in
                    guard let self, self.activeProfileID == profileID, !self.isClosing else { return }
                    self.openEasel(id: documentID, title: title)
                }, finished: { [weak self] in self?.easelImageDestination = nil })
            easelImageDestination = controller
            controller.present(on: window)
        } catch {
            ParcDialog.inform(in: window, .init(error: error), queued: true)
        }
    }

    func browserViewDidChangeFavicon(_ view: PCBrowserView) {
        guard let id = id(for: view), !rendering, !isClosing, !wholeWindowClose else { return }
        sidebar.reloadFavicon(for: id)
        refreshFavoriteOverlays(from: presentedState)
    }
    func browserViewDidChangePageColor(_ view: PCBrowserView) {
        guard let id = id(for: view), let pane = panes[id], pane.browser === view, !isClosing, !wholeWindowClose else { return }
        pane.showPageBacking(of: view.nativePage)
        guard pane.livePage === view, !pane.browserToolbar.isHidden else { return }
        pane.browserToolbar.showPageColor(of: view.nativePage, failing: pane.showsFailure)
    }
    func browserViewDidPresentFrame(_ view: PCBrowserView) {
        guard let id = id(for: view), let pane = panes[id], pane.browser === view else { return }
        finishPageSwitch(switchHold.presented(pane))
    }
    func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?) {
        guard let id = id(for: view) else { return }
        adoptHostedPeekParent(over: id)
        guard !rendering, !isClosing, !wholeWindowClose else { return }
        refreshLivePageChromeOrRender()
    }
    private var publicationRefreshesChrome: Bool {
        RunLoop.current.currentMode == .default && !promotingPeek
            && transferringTabIDs.isEmpty && collectionTransfer == nil
    }
    func browserView(_ view: PCBrowserView, didChangeTitle title: String) {
        guard let id = id(for: view) else { _ = followCoveredPage(view, title: title); return }
        let revision = store.stateRevision
        store.updateTab(id, title: title)
        if store.stateRevision == revision || !publicationRefreshesChrome,
           !rendering, !isClosing, !wholeWindowClose { refreshLivePageChromeOrRender() }
    }
    func browserView(_ view: PCBrowserView, didChangeURL url: URL) {
        if selectedTabIDs.contains(where: { browsers[$0] === view }) { pageHost.cancelDrop() }
        if view === pendingCommandSplitBrowser { cancelPendingCommandSplit() }
        if followCoveredPage(view, url: url) { return }
        if let id = id(for: view) {
            requestedURLs[id] = url.absoluteString
            let revision = store.stateRevision
            store.updateTab(id, url: url.absoluteString)
            if store.stateRevision == revision || !publicationRefreshesChrome,
               !rendering, !isClosing, !wholeWindowClose { refreshLivePageChromeOrRender() }
            scheduleTabHistoryCapture(id)
            if id == currentTabID { refreshHandoffActivity() }
        }
    }
    func browserViewDidChangeMedia(_ view: PCBrowserView) {
        guard id(for: view) != nil else { return }
        scheduleMediaRefresh()
    }
}
