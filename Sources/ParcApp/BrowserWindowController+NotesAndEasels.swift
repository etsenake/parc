import AppKit
import Combine

extension BrowserWindowController {
    func openLocalNoteAddress(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "parc",
              parts.host?.lowercased() == "note" else { return false }
        guard canCreateNote else { return true }
        do {
            guard let id = InternalPage(urlString: value)?.noteID else { throw NoteError.invalid }
            let note = try NoteStore.sharedStore(directory: store.notesDirectory(for: activeProfileID)).load(id)
            openNote(id: id, title: note.displayTitle)
        } catch { showNoteError(error) }
        return true
    }
    func openNote(id: UUID, title: String, inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        closeLibrary(restoreFocus: false)
        performWindowCommand { _ = store.openNote(id: id, title: title, inSplit: inSplit) }
        focusSelectedLocalContent()
    }
    func noteEditorsForRetirement(in ids: Set<UUID>) -> [UUID: NoteEditorViewController] {
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
    func showError(_ error: Error) {
        if window != nil { ParcDialog.present(error) }
    }
    func showNoteError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(error: error), queued: true)
    }
    func showNote(_ tab: BrowserTab, id: UUID, in pane: BrowserPane) {
        guard !isPrivateBrowsing, !store.isProfileRemovalPending(tab.profileID) else { pane.showError("Notes are unavailable in this Space."); return }
        if let cached = noteEditors[tab.id], cached.documentID == id, cached.profileID == tab.profileID {
            pane.showNativeContent(cached.editor.view); return
        }
        do {
            let editor = try NoteEditorViewController(directory: store.notesDirectory(for: tab.profileID), documentID: id)
            configureNoteOwner(tab, id: id, editor: editor)
            noteEditors[tab.id] = NotePane(documentID: id, profileID: tab.profileID, editor: editor, originalTab: tab)
            pane.showNativeContent(editor.view)
        } catch { pane.showNativeContent(NoteLoadErrorView(error: error)) }
    }

    func configureNoteOwner(_ tab: BrowserTab, id: UUID, editor: NoteEditorViewController) {
            editor.onTitleChange = { [weak self] title in self?.store.updateNoteTitle(id: id, profileID: tab.profileID, title: title) }
            editor.onOpenURL = { [weak self, weak editor] url in
                guard let self, let editor, self.noteEditors[tab.id]?.editor === editor,
                      self.currentTabID == tab.id, self.activeProfileID == tab.profileID, !self.isClosing else { return }
                self.openInput(url.absoluteString)
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
