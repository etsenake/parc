import AppKit
import UniformTypeIdentifiers

@MainActor
extension EaselEditorViewController {
    private var windowController: BrowserWindowController? { view.window?.windowController as? BrowserWindowController }

    func showExportToast(_ content: ParcToastContent) {
        windowController?.showToast(content)
    }

    var easelLink: URL? { URL(string: InternalPage.easel(session.document.id).urlString) }

    func copyLink() {
        guard let url = easelLink else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
        showExportToast(.copiedLinks([url]))
    }

    func copyImage() {
        guard canExportImage, let window = view.window else { return }
        withExportPages(in: window) { [weak self] pages in
            guard let self else { return }
            let scale = EaselImageExport.pixelDensity()
            guard let image = self.canvas.exportImage(backingScale: scale, pages: pages, hugsContent: true),
                  let png = EaselDocumentExport.png(image) else { return EaselImageExport.showFailure(in: window) }
            let board = NSPasteboard.general
            board.clearContents()
            board.setData(png, forType: .png)
            self.showExportToast(.copiedImage)
        }
    }

    func export(_ format: EaselPageMenu.ExportFormat) {
        guard canExportImage, let window = view.window else { return }
        if format == .image { exportImage(); return }
        if format == .stickies { exportStickies(EaselSelectionExport.stickies(in: session.document)); return }
        if format == .markdown { exportMarkdown(in: window); return }
        let panel = NSSavePanel()
        panel.title = "Export Easel"
        panel.allowedContentTypes = [format == .pdf ? .pdf : .html]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(session.document.title, fileExtension: format == .pdf ? "pdf" : "html")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated { self?.write(format, to: destination, in: window) }
        }
    }

    private func write(_ format: EaselPageMenu.ExportFormat, to destination: URL, in window: NSWindow) {
        withExportPages(in: window) { [weak self] pages in
            guard let self else { return }
            let data: Data?
            if format == .pdf {
                data = self.canvas.exportPagesPDF(title: self.session.document.title, pages: pages)
            } else {
                let art = EaselDocumentExport.art(session: self.session, canvas: self.canvas, pages: pages)
                data = Data(EaselVectorExport.htmlDocument(self.session.document, art: art, palette: EaselDocumentExport.palette).utf8)
            }
            do {
                guard let data else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: destination, options: .atomic)
                self.showExportToast(.standard("Exported \(destination.lastPathComponent)"))
            } catch {
                EaselImageExport.showFailure(in: window)
            }
        }
    }

    func withExportPages(in window: NSWindow, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) {
        let documentID = session.document.id
        _ = canvas.collectExportPages { [weak self, weak window] pages in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let window, self.view.window === window, !self.session.isClosed,
                          self.session.document.id == documentID else { return }
                    completion(pages)
                }
            }
        }
    }
}

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
