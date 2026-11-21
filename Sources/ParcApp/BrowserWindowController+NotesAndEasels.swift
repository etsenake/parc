import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func openLocalNoteAddress(_ input: String, inPane tabID: UUID? = nil) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if InternalPage.isRetiredNoteAddress(value) {
            showNoteError(NoteTabError.retiredAddress)
            return true
        }
        if let easel = InternalPage(urlString: value)?.easelID {
            guard !isPrivateBrowsing, !isPopupWindow else { return false }
            openEaselAddress(easel, inPane: tabID)
            if let target = EaselObjectAddress.target(of: value) { revealEaselObject(target.object, in: target.easel) }
            if let target = EaselPageAddress.target(of: value) { revealEaselPage(target.page, in: target.easel) }
            return true
        }
        guard let file = InternalPage.noteFile(value) else { return false }
        let target = URL(string: value).flatMap { InternalPage.noteFile($0) == nil ? nil : $0 } ?? file
        if isPrivateBrowsing || isPopupWindow {
            onOpenNoteInRegularWindow?(target)
        } else {
            openNote(url: target, inPane: tabID)
        }
        return true
    }
    @discardableResult
    func openNote(url: URL, inSplit: Bool = false) -> Bool {
        let result = presentNote(url: url, inSplit: inSplit)
        if let id = result.tabID, let anchor = url.fragment, !anchor.isEmpty { revealNoteAnchor(anchor, inTab: id) }
        return result.handled
    }
    func revealNoteAnchor(_ anchor: String, inTab id: UUID) {
        if let note = noteEditors[id], note.editor.isViewLoaded {
            pendingNoteAnchors.removeValue(forKey: id)
            note.editor.reveal(anchor: anchor)
        } else {
            pendingNoteAnchors[id] = anchor
        }
    }
    private func presentNote(url: URL, inSplit: Bool = false) -> (handled: Bool, tabID: UUID?) {
        guard let file = InternalPage.noteFile(url) else { showNoteError(NoteFileError.notANote); return (true, nil) }
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return (false, nil) }
        guard NoteFilePaths.isOpenableFile(file) else {
            showNoteError(NoteFilePaths.itemExists(file) ? NoteFileError.notANote : NoteFileError.missing)
            return (true, nil)
        }
        closeLibrary(restoreFocus: false)
        let title = NoteFileSession.session(for: file)?.title ?? file.deletingPathExtension().lastPathComponent
        var opened: UUID?
        performWindowCommand { opened = store.openNote(url: file, title: title, inSplit: inSplit) }
        focusSelectedLocalContent()
        return (opened != nil, opened)
    }
    func openDroppedNoteFiles(_ files: [URL], placement: SidebarNotePlacement? = nil) -> Bool {
        guard !files.isEmpty else { return false }
        if isPrivateBrowsing || isPopupWindow {
            guard let handoff = onOpenNoteInRegularWindow else { return false }
            files.forEach(handoff)
            return true
        }
        guard canCreateNote else { return false }
        let profileID = activeProfileID
        let open = Set(store.state.tabs.lazy.filter { $0.archivedAt == nil && $0.profileID == profileID }.map(\.id))
        var handled = false
        var arrivals: [UUID] = []
        for file in files {
            let result = presentNote(url: file)
            handled = result.handled || handled
            if let id = result.tabID, !open.contains(id), !arrivals.contains(id) { arrivals.append(id) }
        }
        if let placement, !arrivals.isEmpty { placeDroppedNotes(arrivals, at: placement) }
        return handled
    }
    private func placeDroppedNotes(_ ids: [UUID], at placement: SidebarNotePlacement) {
        let items = ids.map(SidebarItemReference.tab)
        guard placement.destination.spaceID == activeSpaceID, !isClosing,
              placement.before.map({ !items.contains($0) }) ?? true,
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID,
                                                      includesFavorites: true) else { return }
        do {
            try store.moveSidebarItems(items, to: placement.destination, before: placement.before, expected: expected)
        } catch {
            showError(error)
        }
    }
    func createNote(inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        do {
            let file = try NoteFolderPreferences.library(for: activeProfileID).createNote()
            openNote(url: file, inSplit: inSplit)
        } catch { showNoteError(error) }
    }
    func showNotesLibrary(folder: URL) {
        showLibrary(.documents)
        guard let libraryView, libraryView.profileID == activeProfileID else { return }
        libraryView.showDocuments(in: folder)
    }
    func revealInDocumentsLibrary(_ target: DocumentsLibraryReveal.Target) {
        showLibrary(.documents)
        guard let libraryView, libraryView.profileID == activeProfileID else { return }
        libraryView.revealDocument(target)
    }
    var canShowNotesFolder: Bool { canCreateNote }
    func showNotesFolder() {
        guard canShowNotesFolder else { return }
        let folder = NoteFolderPreferences.folder(for: activeProfileID)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch { showNoteError(error) }
    }
    func noteEditorsForRetirement(in ids: Set<UUID>) -> [UUID: NotePageViewController] {
        Dictionary(uniqueKeysWithValues: noteEditors.filter { ids.contains($0.key) }.map {
            ($0.key, $0.value.editor)
        })
    }
    func prepareNotesToClose(_ ids: Set<UUID>? = nil) -> Bool {
        var accepted = true
        for (id, note) in noteEditors where ids == nil || ids!.contains(id) {
            if !note.editor.prepareToClose() { accepted = false }
        }
        return accepted
    }
    func retireNoteEditor(_ id: UUID) {
        pendingNoteAnchors.removeValue(forKey: id)
        guard let note = noteEditors.removeValue(forKey: id) else { return }
        if note.editor.isViewLoaded { note.editor.view.removeFromSuperview() }
    }
    func showError(_ error: Error) {
        if window != nil { ParcDialog.present(error) }
    }
    func showNoteError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(error: error), queued: true)
    }
    func showNote(_ tab: BrowserTab, url: URL, in pane: BrowserPane) {
        guard !isPrivateBrowsing, !store.isProfileRemovalPending(tab.profileID) else { pane.showError("Notes are unavailable in this Space."); return }
        if let cached = noteEditors[tab.id], cached.profileID == tab.profileID,
           InternalPage.note(url) == .note(cached.url) || InternalPage.note(url) == InternalPage(urlString: cached.originalTab.url) {
            pane.showNote(cached.editor)
            configureNoteEmbeds(tab, editor: cached.editor)
            if let anchor = pendingNoteAnchors.removeValue(forKey: tab.id) { cached.editor.reveal(anchor: anchor) }
            return
        }
        let destination = tab.profileID.uuidString + ":" + InternalPage.note(url).urlString
        if let failure = noteFailures[tab.id], failure.destination == destination {
            pendingNoteAnchors.removeValue(forKey: tab.id)
            pane.showError(failure.message); return
        }
        do {
            let editor = NotePageViewController(file: try NoteFileSession.open(url))
            retireNoteEditor(tab.id)
            noteEditors[tab.id] = NotePane(profileID: tab.profileID, editor: editor, originalTab: tab)
            noteFailures.removeValue(forKey: tab.id)
            configureNoteOwner(tab, editor: editor)
            pane.showNote(editor)
            configureNoteEmbeds(tab, editor: editor)
            if let anchor = pendingNoteAnchors.removeValue(forKey: tab.id) ?? URL(string: tab.url)?.fragment, !anchor.isEmpty { editor.reveal(anchor: anchor) }
            if tab.title != editor.file.title || InternalPage.note(editor.file.url) != .note(url) {
                DispatchQueue.main.async { [weak self, weak editor] in
                    guard let self, let editor, self.noteEditors[tab.id]?.editor === editor else { return }
                    self.store.updateNoteFile(from: url, to: editor.file.url, title: editor.file.title)
                }
            }
        } catch {
            pendingNoteAnchors.removeValue(forKey: tab.id)
            noteFailures[tab.id] = (destination, error.localizedDescription)
            pane.showError(error.localizedDescription)
        }
    }

    func configureNoteOwner(_ tab: BrowserTab, editor: NotePageViewController) {
        let tabID = tab.id, profileID = tab.profileID
        NoteBacklinkIndex.shared.include(NoteFolderPreferences.library(for: profileID))
        if !isPrivateBrowsing, let easels = try? EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profileID)) {
            NoteBacklinkIndex.shared.include(easels)
        }
        var current = editor.file.url
        editor.onTitleChange = { [weak self, weak editor] title in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor else { return }
            self.store.updateNoteFile(from: editor.file.url, to: editor.file.url, title: title)
        }
        editor.onURLChange = { [weak self, weak editor] url in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor else { return }
            let previous = current
            current = url
            self.store.updateNoteFile(from: previous, to: url, title: editor.file.title)
        }
        editor.onOpenURL = { [weak self, weak editor] url in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor,
                  self.documentTakesInput(tabID), self.activeProfileID == profileID, !self.isClosing else { return }
            self.openInput(url.absoluteString)
        }
        editor.onFollowURL = { [weak self, weak editor] url, click in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor,
                  self.documentTakesInput(tabID), self.activeProfileID == profileID, !self.isClosing else { return }
            if self.openNoteLinkInPeek(url, click: click, over: tabID, profileID: profileID) { return }
            self.openInput(url.absoluteString)
        }
        editor.allowsShiftClickPeek = { [weak self] in
            guard let self, !self.isPopupWindow else { return false }
            return self.store.state.settings.shiftPeekEnabled
        }
        editor.onOpenNote = { [weak self, weak editor] url in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor,
                  self.documentTakesInput(tabID), self.activeProfileID == profileID, !self.isClosing else { return }
            self.openNote(url: url)
        }
        editor.onToast = { [weak self, weak editor] content in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor, !self.isClosing else { return }
            self.showToast(content, at: .window)
        }
        editor.notesFolder = { NoteFolderPreferences.folder(for: profileID) }
        editor.onOpenFolder = { [weak self, weak editor] folder in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor,
                  self.activeProfileID == profileID, !self.isClosing else { return }
            self.showNotesLibrary(folder: folder)
        }
        if !store.isEphemeral {
            editor.onShowInLibrary = { [weak self, weak editor] url in
                guard let self, let editor, self.noteEditors[tabID]?.editor === editor, self.documentTakesInput(tabID),
                      self.activeProfileID == profileID, !self.isClosing, !self.wholeWindowClose else { return }
                self.revealInDocumentsLibrary(.note(url))
            }
        }
        editor.onTrashed = { [weak self, weak editor] url in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor else { return }
            self.retireTrashedNote(url, profileID: profileID)
        }
        editor.downloadFolder = { [weak self] in await self?.downloadFolder(profileID: profileID) }
        configureNoteEmbeds(tab, editor: editor)
    }

    func noteContentDropTarget(for info: NSDraggingInfo, over overlay: NSView) -> SplitContentDropTarget? {
        guard let window = overlay.window, !isPrivateBrowsing else { return nil }
        for note in noteEditors.values where note.editor.isViewLoaded {
            guard let target = note.editor.view as? SplitContentDropTarget, target.window === window,
                  !target.isHiddenOrHasHiddenAncestor,
                  target.visibleRect.contains(target.convert(info.draggingLocation, from: nil)),
                  target.acceptsSplitContentDrop(info) else { continue }
            return target
        }
        return nil
    }

    func embeddedPagePool(forTabID id: UUID) -> EmbeddedPagePool? {
        if let easel = easelEditors[id] { return easel.editor.pageObjects }
        return noteEditors[id].flatMap { NoteEmbeddedPages.pool(for: $0.editor) }
    }

    var embeddedPagePools: [UUID: EmbeddedPagePool] {
        var pools: [UUID: EmbeddedPagePool] = [:]
        for (id, easel) in easelEditors { if let objects = easel.editor.pageObjects { pools[id] = objects } }
        for (id, note) in noteEditors where pools[id] == nil { if let pool = NoteEmbeddedPages.pool(for: note.editor) { pools[id] = pool } }
        return pools
    }

    @discardableResult
    func configureNoteEmbeds(_ tab: BrowserTab, editor: NotePageViewController,
                             windowTransfer: EmbeddedPagePool.WindowTransfer? = nil) -> Bool {
        configureNoteEasels(tab, editor: editor)
        guard let binding = nativeBinding, !isPrivateBrowsing, !isPopupWindow else { return windowTransfer == nil }
        let tabID = tab.id, profileID = tab.profileID
        return NoteEmbeddedPages.configure(editor, binding: binding,
            profilePath: store.independentEngineProfilePath(for: profileID),
            validOwner: { [weak self, weak editor, weak binding] in
                guard let self, let editor, let binding,
                      self.noteEditors[tabID]?.editor === editor, self.noteEditors[tabID]?.profileID == profileID,
                      binding === self.nativeBinding, editor.isViewLoaded, editor.view.window === self.window,
                      let actual = self.store.state.tab(tabID, where: { $0.archivedAt == nil }),
                      actual.profileID == profileID, InternalPage(urlString: actual.url)?.noteURL != nil,
                      !self.store.isProfileRemovalPending(profileID),
                      !self.transferringTabIDs.contains(tabID) else { return false }
                return !self.isClosing && !self.wholeWindowClose && !self.windowCloseApproved
            }, activeOwner: { [weak self] in
                guard let self else { return false }
                return !self.transferringTabIDs.contains(tabID) && self.documentTakesInput(tabID)
                    && self.libraryView == nil && self.commandBar == nil && !self.windowClosePending && !self.isClosing
            }, selectionChanged: { [weak self] in
                guard let self, !self.isClosing else { return }
                self.nativeBinding?.synchronizeSelectionAndLayout()
                self.refreshCaptureIndicators(); self.refreshNavigationControls()
                self.windowKeyViews.relink()
            }, metadataChanged: { [weak self] in self?.refreshLivePageChromeOrRender() },
            contextImage: { [weak self] view, image in self?.browserView(view, addContextImageToEasel: image) },
            open: { [weak self, weak editor] url in
                guard let self, let editor, self.noteEditors[tabID]?.editor === editor,
                      self.activeProfileID == profileID, !self.isClosing, !self.wholeWindowClose else { return }
                self.openInput(url.absoluteString)
            }, windowTransfer: windowTransfer)
    }

    func configureNoteEasels(_ tab: BrowserTab, editor controller: NotePageViewController) {
        guard !isPrivateBrowsing, controller.isViewLoaded, let editor = controller.editor else { return }
        let tabID = tab.id, profileID = tab.profileID
        NoteEaselHost.configure(editor, directory: store.easelsDirectory(for: profileID), open: { [weak self, weak controller] id, title in
            guard let self, let controller, self.noteEditors[tabID]?.editor === controller,
                  self.activeProfileID == profileID, !self.isClosing, !self.wholeWindowClose else { return }
            self.openEasel(id: id, title: title)
        }, elsewhere: { [weak self] id in
            guard let self else { return false }
            let name = id.uuidString.lowercased() + ".json"
            return self.store.state.profiles.contains { profile in
                profile.id != profileID && FileManager.default.fileExists(atPath: self.store.easelsDirectory(for: profile.id)
                    .appendingPathComponent("documents", isDirectory: true).appendingPathComponent(name).path)
            }
        }, keyLoopChanged: { [weak self] in self?.windowKeyViews.relink() })
    }

    func notePagesCanSleep(_ note: NotePane, lastShown: Date) -> Bool {
        guard let pool = NoteEmbeddedPages.pool(for: note.editor) else { return false }
        let candidate = EmbeddedPageSleepPolicy.Candidate(lastShown: lastShown, shown: false, closing: false, transferring: false,
            editing: !note.editor.canAcceptExternalDrop, pendingCreation: pool.hasPendingCreation,
            pages: pool.ownedViews.values.map { view -> EmbeddedPageSleepPolicy.Protection in
                switch view.automaticArchiveProtectionState {
                case .eligible: return .eligible
                case .protected: return .protected
                default: return .unknown
                }
            })
        return EmbeddedPageSleepPolicy.shouldSleep(candidate, now: Date())
    }

    func releaseIdleNotePages(_ id: UUID, cached: NotePane) {
        guard !closingTabIDs.contains(id), let pool = NoteEmbeddedPages.pool(for: cached.editor) else { return }
        let pages = pool.pages, expected = store.state.tab(id)
        closingTabIDs.insert(id)
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: { [weak self, weak pool] in
            MainActor.assumeIsolated {
                guard let self, let pool, let current = self.noteEditors[id], current.editor === cached.editor,
                      NoteEmbeddedPages.pool(for: current.editor) === pool else { return false }
                let shown = self.renderedPaneIDs.contains(id) || self.selectedTabIDs.contains(id) || self.pendingNativeSelection?.tabID == id
                    || self.tabPeeks.current?.tabID == id
                return !self.isClosing && !self.wholeWindowClose && !shown && !self.transferringTabIDs.contains(id)
                    && self.store.state.tab(id) == expected
                    && self.notePagesCanSleep(current, lastShown: expected?.lastAccessed ?? .distantFuture)
            }
        }, completion: { [weak self, weak pool] allowed in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closingTabIDs.remove(id)
                if allowed, let pool, NoteEmbeddedPages.pool(for: cached.editor) === pool { NoteEmbeddedPages.retire(cached.editor) }
            }
        })
    }

    func retireNoteAfterModelChange(_ id: UUID, cached: NotePane) {
        guard !closingTabIDs.contains(id), let pool = NoteEmbeddedPages.pool(for: cached.editor) else { return }
        let pages = pool.pages, expected = store.state.tab(id)
        closingTabIDs.insert(id); modelRetirementIDs.insert(id)
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: { [weak self, weak pool] in
            MainActor.assumeIsolated {
                guard let self, let pool else { return false }
                return !self.isClosing && self.noteEditors[id]?.editor === cached.editor
                    && NoteEmbeddedPages.pool(for: cached.editor) === pool && self.store.state.tab(id) == expected
            }
        }, completion: { [weak self] allowed in
            MainActor.assumeIsolated {
                guard let self, self.noteEditors[id]?.editor === cached.editor else { return }
                self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
                if allowed, cached.editor.prepareToClose() {
                    NoteEmbeddedPages.retire(cached.editor)
                    self.retireNoteEditor(id)
                } else { _ = self.store.restoreLiveTab(cached.originalTab, replacing: expected) }
                self.render(self.store.state); self.requestNativeSelection()
            }
        })
    }

    func downloadFolder(profileID: UUID) async -> URL? {
        guard !store.isProfileRemovalPending(profileID) else { return nil }
        let path = store.independentEngineProfilePath(for: profileID)
        guard let preferences = try? await PCNativeBrowserApplication.downloadPreferences(profilePath: path),
              preferences.profilePath == path else { return nil }
        return preferences.directoryURL
    }

    func retireTrashedNote(_ url: URL, profileID: UUID) {
        guard let file = InternalPage.noteFile(url) else { return }
        NoteReminderCenter.shared.forget(document: file)
        store.deleteLocalDocument(.note(file), profileID: profileID, ownerValid: { [weak self] in
            guard let self else { return false }
            return !self.isClosing && !self.wholeWindowClose
        }, deleteDocument: {}, completion: { [weak self] error in
            guard let self, let error, (error as? CocoaError)?.code != .userCancelled else { return }
            self.showNoteError(error)
        })
    }

    var currentNoteEditor: NotePageViewController? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, libraryView == nil,
              let id = documentInputTabID, !transferringTabIDs.contains(id),
              let note = noteEditors[id], note.profileID == activeProfileID, note.editor.isViewLoaded else { return nil }
        return note.editor
    }

    var canPrintCurrentPage: Bool {
        if currentNoteEditor != nil { return window?.attachedSheet == nil }
        if let easel = currentEaselEditor { return window?.attachedSheet == nil && easel.canExportImage }
        return canPerformPageTool(.print)
    }

    func printCurrentPage() {
        if let note = currentNoteEditor {
            guard window?.attachedSheet == nil else { return }
            note.printPage()
        } else if let easel = currentEaselEditor {
            guard window?.attachedSheet == nil else { return }
            easel.printEasel()
        } else {
            performPageTool(.print)
        }
    }

    func createEasel(inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: activeProfileID))
            let session = try easels.create()
            openEasel(id: session.document.id, title: session.document.title, inSplit: inSplit)
        } catch { showEaselError(error) }
    }

    func openEasel(id: UUID, title: String, inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : !isPrivateBrowsing else { return }
        if inSplit { closeLibrary(restoreFocus: false) }
        performWindowCommand { _ = store.openEasel(id: id, title: title, inSplit: inSplit) }
        if inSplit { focusSelectedLocalContent() }
    }

    private func openEaselAddress(_ id: UUID, inPane tabID: UUID?) {
        guard canCreateNote else { return }
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: activeProfileID))
            try easels.validateReference(id)
            let session = try easels.load(id)
            guard !session.isDeleted, !session.isClosed else { NSSound.beep(); return }
            openEasel(id: id, title: session.document.title, inPane: tabID)
        } catch { showEaselError(error) }
    }

    func showEaselError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(title: "Couldn’t open Easels", message: error.localizedDescription), queued: true)
    }
    func createEaselFromPlusMenu() {
        guard canCreateNote else { return }
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: activeEaselsDirectory)
            let session = try easels.create()
            openEasel(id: session.document.id, title: session.document.title)
        } catch { showNoteError(error) }
    }

    func captureRenderingMetrics() {
        guard !isPrivateBrowsing, ProcessInfo.processInfo.arguments.contains("--parc-diagnostics"), let browser = currentBrowser else { return }
        let origin = browser.url.flatMap { url -> String? in
            guard let scheme = url.scheme, let host = url.host else { return nil }
            return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        }
        let directory = store.directory.appendingPathComponent("diagnostics", isDirectory: true)
        browser.captureRenderingMetrics { metrics, error in
            do {
                if let error { throw error }
                guard let metrics else { return }
                var record = metrics
                record["capturedAt"] = ISO8601DateFormatter().string(from: Date())
                record["pageOrigin"] = origin ?? "local"
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let output = directory.appendingPathComponent(UUID().uuidString + ".json")
                try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
                FileHandle.standardError.write(Data(("Parc rendering metrics: " + output.path + "\n").utf8))
            } catch {
                FileHandle.standardError.write(Data(("Parc rendering metrics failed: " + error.localizedDescription + "\n").utf8))
            }
        }
    }
}

enum NoteTabError: LocalizedError {
    case retiredAddress, changed
    var errorDescription: String? {
        switch self {
        case .retiredAddress: return "This note uses Parc’s old format, so it can’t open anymore. New notes save as Markdown files."
        case .changed: return "This changed in another window. Give it another try."
        }
    }
}

@MainActor
enum NotePaneRetention {
    private static var holders: [ObjectIdentifier: Int] = [:]
    static func reconcile(old: [UUID: BrowserWindowController.NotePane], new: [UUID: BrowserWindowController.NotePane]) {
        let before = Set(old.values.map { ObjectIdentifier($0.editor) })
        let after = Set(new.values.map { ObjectIdentifier($0.editor) })
        guard before != after else { return }
        var seen = Set<ObjectIdentifier>()
        for pane in new.values {
            let key = ObjectIdentifier(pane.editor)
            guard !before.contains(key), seen.insert(key).inserted else { continue }
            holders[key, default: 0] += 1
            if holders[key] == 1 { pane.editor.file.retain() }
        }
        seen = []
        for pane in old.values {
            let key = ObjectIdentifier(pane.editor)
            guard !after.contains(key), seen.insert(key).inserted, let count = holders[key] else { continue }
            if count > 1 { holders[key] = count - 1; continue }
            holders.removeValue(forKey: key)
            NoteEmbeddedPages.retire(pane.editor)
            if pane.editor.isViewLoaded, let editor = pane.editor.editor { NoteEaselHost.retire(editor) }
            pane.editor.teardown()
            pane.editor.file.release()
        }
    }
}
