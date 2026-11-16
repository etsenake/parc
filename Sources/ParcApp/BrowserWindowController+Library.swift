import AppKit
import Combine

extension BrowserWindowController {
    func performLibraryFlyout(_ action: LibraryFlyoutAction) -> Bool {
        switch action {
        case let .download(item, command): return performLibraryDownload(item, action: command)
        case let .file(file, command): return performLibraryFlyoutFile(file, action: command)
        case .showCapture: showLibrary(.captures); return libraryView?.kind == .captures
        case .copyCapture(let capture):
            guard !isPrivateBrowsing, capture.profileID == activeProfileID else { return false }
            let library = CaptureLibraryStore.shared(directory: store.capturesDirectory(for: capture.profileID), profileID: capture.profileID)
            guard library.contains(capture) else { return false }
            Task { @MainActor in
                guard let data = try? await library.data(for: capture), library.contains(capture) else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .png)
            }
            return true
        case .openCaptureSource(let capture):
            guard !isPrivateBrowsing, capture.profileID == activeProfileID else { return false }
            openLibraryURLs([capture.sourceURL], profileID: capture.profileID); return true
        case .copyCaptureSource(let capture):
            NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(capture.sourceURL, forType: .string)
        case let .share(item, share): return shareLibraryFlyoutItem(item, share)
        case .deleteCapture(let capture): return deleteLibraryFlyoutCapture(capture)
        }
    }
    private func performLibraryFlyoutFile(_ file: LibraryFlyoutFile, action: LibraryFlyoutFileAction) -> Bool {
        guard window?.attachedSheet == nil, FileManager.default.fileExists(atPath: file.url.path) else { return false }
        switch action {
        case .open: return NSWorkspace.shared.open(file.url)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([file.url]); return true
        case .copyFile:
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([file.url as NSURL])
        }
    }
    private func libraryFlyoutCaptureStore(_ capture: SavedCapture) -> CaptureLibraryStore? {
        guard !isPrivateBrowsing, !isClosing, !wholeWindowClose, capture.profileID == activeProfileID else { return nil }
        let library = CaptureLibraryStore.shared(directory: store.capturesDirectory(for: capture.profileID), profileID: capture.profileID)
        return library.contains(capture) ? library : nil
    }
    private func shareLibraryFlyoutItem(_ item: LibraryFlyoutItem, _ share: LibraryFlyoutShare) -> Bool {
        guard let parent = window, parent.attachedSheet == nil else { return false }
        switch item {
        case .download(let download):
            guard let url = libraryDownloadFileURL(download) else { return false }
            Task.detached(priority: .userInitiated) { [weak self] in
                let bytes = LibraryFlyoutSharing.isImage(url) ? (try? Data(contentsOf: url)) : nil
                await MainActor.run { [weak self] in
                    guard let self, self.window === parent, self.libraryDownloadFileURL(download) == url else { return }
                    let items = LibraryFlyoutSharing.items(share, image: bytes.flatMap(NSImage.init(data:)), url: url, text: nil)
                    LibraryFlyoutSharing.perform(share, items: items)
                }
            }
            return true
        case .file(let file):
            guard FileManager.default.fileExists(atPath: file.url.path) else { return false }
            let url = file.url
            Task.detached(priority: .userInitiated) { [weak self] in
                let bytes = LibraryFlyoutSharing.isImage(url) ? (try? Data(contentsOf: url)) : nil
                await MainActor.run { [weak self] in
                    guard let self, self.window === parent else { return }
                    let items = LibraryFlyoutSharing.items(share, image: bytes.flatMap(NSImage.init(data:)), url: url, text: nil)
                    LibraryFlyoutSharing.perform(share, items: items)
                }
            }
            return true
        case .capture(let capture):
            guard let library = libraryFlyoutCaptureStore(capture) else { return false }
            Task { @MainActor [weak self] in
                guard let data = try? await library.data(for: capture), let self, self.window === parent,
                      self.libraryFlyoutCaptureStore(capture) === library else { return }
                let items = LibraryFlyoutSharing.items(share, image: NSImage(data: data), url: nil,
                                                       text: share == .message ? capture.sourceURL : nil)
                LibraryFlyoutSharing.perform(share, items: items)
            }
            return true
        }
    }
    private func deleteLibraryFlyoutCapture(_ capture: SavedCapture) -> Bool {
        guard let parent = window, parent.attachedSheet == nil, libraryFlyoutCaptureStore(capture) != nil else { return false }
        return LibraryFlyoutCaptureDeletion.confirm(in: parent) { [weak self, weak parent] approved in
            MainActor.assumeIsolated {
                guard approved, let self, let parent, self.window === parent,
                      let library = self.libraryFlyoutCaptureStore(capture),
                      let reservation = library.reserveDeletion(owner: self.store, item: capture) else { return }
                Task { @MainActor [weak self, weak parent] in
                    do { try await reservation.perform { try await library.delete(capture) } }
                    catch {
                        guard let self, let parent, self.window === parent, parent.attachedSheet == nil else { return }
                        ParcDialog.inform(in: parent, .init(error: error))
                    }
                }
            }
        }
    }
    func updateLibraryEntryExpansion() {
        sidebar.libraryEntryExpansionAllowed = libraryView == nil && tabSwitcher == nil && commandBar == nil
    }
    func recordLibraryPage(_ kind: LibraryView.Kind) {
        guard !isPrivateBrowsing else { return }
        LibraryEntryPreferences.shared.lastSelectedPage = Self.libraryPage(kind)
    }
    static func libraryPage(_ kind: LibraryView.Kind) -> LibraryEntryPage {
        switch kind {
        case .downloads: return .downloads
        case .captures: return .captures
        case .documents: return .documents
        case .archive: return .archive
        case .spaces: return .spaces
        }
    }
    static func libraryKind(_ page: LibraryEntryPage) -> LibraryView.Kind {
        switch page {
        case .downloads: return .downloads
        case .captures: return .captures
        case .documents: return .documents
        case .archive: return .archive
        case .spaces: return .spaces
        }
    }

    func closeLibrary(restoreFocus: Bool = true) {
        if libraryView?.kind == .spaces {
            libraryView?.spaceManager.cancelEditing()
            spaceIconPicker?.cancel(); themePopover?.performClose(nil)
        }
        if libraryView != nil { sidebar.libraryDidClose() }
        libraryMotion.cancel()
        libraryView?.removeFromSuperview(); libraryView = nil; libraryContentWidth = 0
        layoutChrome()
        refreshPendingPaneSidebar()
        if restoreFocus, let window, window.isKeyWindow, window.attachedSheet == nil {
            if let currentBrowser { window.makeFirstResponder(currentBrowser) }
            else if showsStartPage, let bar = residentCommandBar { bar.focusResident() }
            else { focusSelectedLocalContent() }
        }
    }
    func setLibraryContentWidth(_ width: CGFloat) {
        guard libraryContentWidth != width else { return }
        libraryContentWidth = width
        guard let libraryView, SidebarMotionController.animatesLibraryWidth(in: window, layoutRoot: rootView) else {
            libraryMotion.cancel(); layoutChrome(); return
        }
        sidebarChromePass = .geometry
        libraryMotion.animate(layoutRoot: rootView,
                              views: [libraryView, pageHost, pageShadow, extensionSidePanel, findHost, loadingIndicator],
                              style: .libraryWidth) {
            layoutChrome()
        } completion: { [weak self] in
            guard let self, !self.isClosing, self.libraryView != nil else { return }
            self.pageHost.needsLayout = true
            self.extensionSidePanel.needsLayout = true
            self.layoutChrome()
        }
        sidebarChromePass = .full
    }
    func settleLibraryMotion() {
        guard libraryMotion.isAnimating else { return }
        libraryMotion.cancel(); pageHost.needsLayout = true; extensionSidePanel.needsLayout = true
    }

    func openLibraryURLs(_ inputs: [String], profileID: UUID) {
        guard activeProfileID == profileID else { return }
        let urls = inputs.compactMap(URL.init(string:))
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            for url in urls {
                let id = store.openResolvedURL(url, creation: creation)
                presentation.recordCreation(id, state: store.state)
            }
        }
    }

    func restoreArchivedTabs(_ ids: [UUID], profileID: UUID, destination: ArchiveRestoreDestination) {
        guard activeProfileID == profileID else { return }
        let items = store.archivedItems(profileID: profileID).filter { ids.contains($0.id) }
        let allIDs = items.flatMap { $0.tabs.map(\.id) }
        guard !allIDs.isEmpty, allIDs.allSatisfy({ !store.retiringTabIDs.contains($0) }) else { return }
        guard allIDs.allSatisfy({ ownership.canUse($0, owner: presentationID) }) else { refuseTabMove(); return }
        var restored: [UUID] = []
        performWindowCommand {
            for item in items {
                restored += store.restoreArchivedTab(item.id, profileID: profileID, destination: destination)
            }
        }
        guard let first = restored.first, let tab = store.state.tab(first),
              let space = store.state.spaces.first(where: { $0.id == tab.spaceID }) else { return }
        showToast(.tabRestored(to: space.name, selected: selectedTabIDs.contains(first)), at: .window, onTap: { [weak self] in
            guard let self, self.activeProfileID == profileID,
                  let tab = self.store.state.tab(first, where: { $0.archivedAt == nil }) else { return }
            if tab.spaceID != self.activeSpaceID, !self.selectSpaceFromUser(tab.spaceID, profileID: profileID) { return }
            self.closeLibrary(restoreFocus: false)
            _ = self.selectTab(first)
        })
    }

    func splitHomePlan(_ homes: [BrowserTab]) -> (ids: [UUID: UUID], documents: [UUID: SidebarDocumentReference])? {
        SplitMembership.homePlan(homes) { [resolveSidebarCopyDestinations] typed in resolveSidebarCopyDestinations?(typed)?.documents }
    }

    func openSplitHomes(_ ids: [UUID: UUID], profileID: UUID, originatingSpaceID: UUID) {
        guard let window else { return }
        for homeID in ids.values {
            guard let home = store.state.tab(homeID) else { continue }
            openDuplicatedChildren([homeID], spaceID: home.spaceID, profileID: profileID,
                window: window, originatingSpaceID: originatingSpaceID)
        }
    }
}
