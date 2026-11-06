import AppKit

/// One archived member's original local document editor in the initiating
/// physical window. The containing preview owns the archive lease, attachment,
/// callbacks and whole-set retirement; this object never restores a tab.
@MainActor
final class ArchivePreviewDocumentOwner {
    enum Editor {
        case note(NoteEditorViewController)
        case easel(EaselEditorViewController)
    }
    enum AdmissionError: Error { case staleOrUnsupported }

    let originalTab: BrowserTab
    let documentID: UUID
    let editor: Editor

    init(store: BrowserStore, originalTab: BrowserTab, leaseIsCurrent: () -> Bool) throws {
        guard !store.isEphemeral, originalTab.archivedAt != nil,
              !store.isProfileRemovalPending(originalTab.profileID),
              store.state.profiles.contains(where: { $0.id == originalTab.profileID }),
              store.state.tabs.contains(originalTab), leaseIsCurrent(),
              let page = InternalPage(urlString: originalTab.url) else { throw AdmissionError.staleOrUnsupported }
        self.originalTab = originalTab
        switch page {
        case .note(let id):
            documentID = id
            editor = .note(try NoteEditorViewController(directory: store.notesDirectory(for: originalTab.profileID), documentID: id))
        case .easel(let id):
            documentID = id
            editor = .easel(try EaselEditorViewController(directory: store.easelsDirectory(for: originalTab.profileID), documentID: id))
        }
        guard !store.isProfileRemovalPending(originalTab.profileID),
              store.state.profiles.contains(where: { $0.id == originalTab.profileID }),
              store.state.tabs.contains(originalTab), leaseIsCurrent() else { throw AdmissionError.staleOrUnsupported }
    }

    var view: NSView {
        switch editor {
        case .note(let editor): return editor.view
        case .easel(let editor): return editor.view
        }
    }
    var noteEditor: NoteEditorViewController? {
        if case .note(let editor) = editor { return editor }; return nil
    }
    var easelEditor: EaselEditorViewController? {
        if case .easel(let editor) = editor { return editor }; return nil
    }
    var embeddedPages: [PCNativePage] { easelEditor?.pageObjects?.pages ?? [] }
    var hasPendingPageCreation: Bool { easelEditor?.pageObjects?.hasPendingCreation == true }

    /// Recheck before and after asynchronous native close consent. An Easel's
    /// in-progress edit must also finish without discarding its draft.
    func prepareToClose() -> Bool {
        switch editor {
        case .note(let editor):
            guard editor.prepareToClose() else { return false }
            guard !editor.session.document.deleted else { return true }
            // The editor may not have loaded its view, while another alias
            // has a delayed save on the shared session.
            do { try editor.session.flushDelayedDiskSave(); return true }
            catch { return false }
        case .easel(let editor): return editor.prepareForPreviewClose()
        }
    }

    /// Call only after the shared close coordinator has closed every embedded
    /// page. A refused or still-pending close keeps the original owner intact.
    func retireAfterClose() -> Bool {
        guard !hasPendingPageCreation, embeddedPages.isEmpty, prepareToClose() else { return false }
        easelEditor?.retirePageOwner()
        return true
    }
}
