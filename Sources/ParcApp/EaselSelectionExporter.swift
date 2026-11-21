import AppKit
import UniformTypeIdentifiers

@MainActor
extension EaselEditorViewController {
    func exportSelection(_ ids: Set<UUID>, as format: EaselSelectionExportFormat) {
        guard canExportImage, let window = view.window else { return }
        let document = session.document
        if format == .stickies {
            exportStickies(EaselSelectionExport.stickies(in: document, within: ids))
            return
        }
        guard !EaselSelectionExport.scope(ids, in: document).isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export Selection"
        panel.allowedContentTypes = format.contentTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(document.title, fileExtension: format.fileExtension)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated { self?.writeSelection(ids, as: format, to: destination, in: window) }
        }
    }

    func exportStickies(_ stickies: [EaselItem]) {
        guard canExportImage, let window = view.window else { return }
        guard !stickies.isEmpty else { showExportToast(.standard("No stickies to export")); return }
        let csv = "\u{FEFF}" + EaselSelectionExport.stickyCSV(stickies)
        let panel = NSSavePanel()
        panel.title = "Export Stickies"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(session.document.title, fileExtension: "csv")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try Data(csv.utf8).write(to: destination, options: .atomic)
                    let count = stickies.count
                    self?.showExportToast(.standard("Exported \(count) stick\(count == 1 ? "y" : "ies")", subLabel: destination.lastPathComponent))
                } catch {
                    EaselImageExport.showFailure(in: window)
                }
            }
        }
    }

    private func writeSelection(_ ids: Set<UUID>, as format: EaselSelectionExportFormat, to destination: URL, in window: NSWindow) {
        withExportPages(in: window) { [weak self] pages in
            guard let self else { return }
            let document = self.session.document
            let scope = EaselSelectionExport.scope(ids, in: document)
            do {
                guard !scope.isEmpty else { throw CocoaError(.fileWriteUnknown) }
                switch format {
                case .image:
                    let scale = EaselImageExport.pixelDensity()
                    guard let image = self.canvas.renderObjectsImage(scope, backingScale: scale, pages: pages) else { throw CocoaError(.fileWriteUnknown) }
                    try EaselImageExport.write(image, scale: scale, to: destination)
                case .pdf:
                    guard let data = self.canvas.exportPDF(title: document.title, pages: pages, only: scope) else { throw CocoaError(.fileWriteUnknown) }
                    try data.write(to: destination, options: .atomic)
                case .html:
                    let subset = EaselSelectionExport.document(document, keeping: scope)
                    let art = EaselDocumentExport.art(session: self.session, canvas: self.canvas, pages: pages)
                    let html = EaselVectorExport.htmlDocument(subset, art: art, palette: EaselDocumentExport.palette)
                    try Data(html.utf8).write(to: destination, options: .atomic)
                case .stickies:
                    return
                }
                self.showExportToast(.standard("Exported \(destination.lastPathComponent)"))
            } catch {
                EaselImageExport.showFailure(in: window)
            }
        }
    }
}
