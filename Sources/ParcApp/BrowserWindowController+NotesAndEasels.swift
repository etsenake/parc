import AppKit
import Combine

extension BrowserWindowController {
    func openLocalNoteAddress(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if InternalPage.isRetiredNoteAddress(value) {
            showNoteError(NoteTabError.retiredAddress)
            return true
        }
        guard let file = InternalPage.noteFile(value) else { return false }
        if isPrivateBrowsing || isPopupWindow {
            onOpenNoteInRegularWindow?(file)
        } else {
            openNote(url: file)
        }
        return true
    }
    @discardableResult
    func openNote(url: URL, inSplit: Bool = false) -> Bool {
        guard let file = InternalPage.noteFile(url) else { showNoteError(NoteFileError.notANote); return true }
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return false }
        guard FileManager.default.fileExists(atPath: file.path) else { showNoteError(NoteFileError.missing); return true }
        closeLibrary(restoreFocus: false)
        let title = NoteFileSession.session(for: file)?.title ?? file.deletingPathExtension().lastPathComponent
        var opened: UUID?
        performWindowCommand { opened = store.openNote(url: file, title: title, inSplit: inSplit) }
        focusSelectedLocalContent()
        return opened != nil
    }
    func createNote(inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        do {
            let file = try NoteFolderPreferences.library(for: activeProfileID).createNote()
            openNote(url: file, inSplit: inSplit)
        } catch { showNoteError(error) }
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
            pane.showNote(cached.editor); return
        }
        let destination = tab.profileID.uuidString + ":" + InternalPage.note(url).urlString
        if let failure = noteFailures[tab.id], failure.destination == destination { pane.showError(failure.message); return }
        do {
            let editor = NotePageViewController(file: try NoteFileSession.open(url))
            retireNoteEditor(tab.id)
            noteEditors[tab.id] = NotePane(profileID: tab.profileID, editor: editor, originalTab: tab)
            noteFailures.removeValue(forKey: tab.id)
            configureNoteOwner(tab, editor: editor)
            pane.showNote(editor)
            if tab.title != editor.file.title || InternalPage.note(editor.file.url) != .note(url) {
                DispatchQueue.main.async { [weak self, weak editor] in
                    guard let self, let editor, self.noteEditors[tab.id]?.editor === editor else { return }
                    self.store.updateNoteFile(from: url, to: editor.file.url, title: editor.file.title)
                }
            }
        } catch {
            noteFailures[tab.id] = (destination, error.localizedDescription)
            pane.showError(error.localizedDescription)
        }
    }

    func configureNoteOwner(_ tab: BrowserTab, editor: NotePageViewController) {
        let tabID = tab.id, profileID = tab.profileID
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
                  self.currentTabID == tabID, self.activeProfileID == profileID, !self.isClosing else { return }
            self.openInput(url.absoluteString)
        }
        editor.onOpenNote = { [weak self, weak editor] url in
            guard let self, let editor, self.noteEditors[tabID]?.editor === editor,
                  self.currentTabID == tabID, self.activeProfileID == profileID, !self.isClosing else { return }
            self.openNote(url: url)
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
        case .retiredAddress: return "This old note can’t open anymore. Notes live in files in your Notes folder now."
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
            pane.editor.file.release()
        }
    }
}
