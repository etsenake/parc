import AppKit
import ParcCore
import ParcKit
import ParcEasels

@MainActor
extension BrowserWindowController {
    func configureEaselPageMenu(_ editor: EaselEditorViewController, tab: BrowserTab, documentID: UUID) {
        let profileID = tab.profileID
        let current: () -> Bool = { [weak self, weak editor] in
            guard let self, let editor else { return false }
            return self.currentEaselEditor === editor && self.easelEditors[tab.id]?.documentID == documentID
                && self.activeProfileID == profileID && !self.isClosing && !self.wholeWindowClose
        }
        editor.pageMenu.actions = .init(showInLibrary: { [weak self] in
            guard let self, current() else { return }
            self.revealInDocumentsLibrary(.easel(documentID))
        }, duplicate: { [weak self] in
            guard let self, current() else { return }
            self.duplicateEasel(documentID, profileID: profileID)
        }, delete: { [weak self] in
            guard let self, current() else { return }
            self.confirmDeleteEasel(documentID, profileID: profileID, current: current)
        })
    }

    func duplicateEasel(_ documentID: UUID, profileID: UUID) {
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profileID))
            let original = try easels.load(documentID).document
            let copy = try easels.create(title: original.title + " copy")
            try copy.perform("Duplicate Easel") { document in
                document.pages = original.pages
                document.defaultFamily = original.defaultFamily
                document.icon = original.icon
                document.items = EaselArrange.copies(of: EaselArrange.paintOrder(original), offset: EaselPoint(x: 0, y: 0),
                                                     firstZIndex: 0, keepingGroups: Set(original.items.compactMap(\.groupID)))
            }
            openEasel(id: copy.document.id, title: copy.document.title)
        } catch { showEaselError(error) }
    }

    func confirmDeleteEasel(_ documentID: UUID, profileID: UUID, current: @escaping () -> Bool) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.confirm(in: window, title: "Are you sure you want to delete this Easel?",
                           message: "Doing so will delete the Easel permanently.",
                           confirm: "Delete", destructive: true) { [weak self] (approved: Bool) in
            guard let self, approved, current() else { return }
            do {
                let easels = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID))
                let snapshot = try easels.load(documentID).document
                self.store.deleteLocalDocument(.easel(documentID), profileID: profileID, ownerValid: { [weak self] in
                    guard let self, !self.isClosing, !self.wholeWindowClose else { return false }
                    return (try? easels.load(documentID).document) == snapshot
                }, deleteDocument: {
                    try easels.delete(documentID)
                }, completion: { [weak self] error in
                    guard let self, let error, (error as? CocoaError)?.code != .userCancelled else { return }
                    self.showEaselError(error)
                })
            } catch { self.showEaselError(error) }
        }
    }
}

extension BrowserWindowController {
    @objc func showEaselTableNotice(_ sender: Any?) {
        guard let notice = sender as? EaselTableNotice else { return }
        showToast(.standard(notice.label, subLabel: notice.detail))
    }
}
