import AppKit
import ParcCore
import UniformTypeIdentifiers
import ParcKit
import ParcNotes

@MainActor
extension EaselEditorViewController {
    private var windowController: EaselWindowActions? { view.window?.windowController as? EaselWindowActions }

    package func showExportToast(_ content: ParcToastContent) {
        windowController?.showDocumentToast(content)
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
        guard canExportImage, let window = view.window, canvas.finishEditing() else { return }
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
        guard canExportImage, let window = view.window, canvas.finishEditing() else { return }
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
