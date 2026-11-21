import AppKit
import UniformTypeIdentifiers

@MainActor
enum EaselSelectionExporter {
    static func export(_ ids: Set<UUID>, as format: EaselSelectionExportFormat, canvas: EaselCanvasView, session: EaselSession,
                       in window: NSWindow, toast: @escaping (ParcToastContent) -> Void) {
        let document = session.document
        if format == .stickies {
            exportStickies(EaselSelectionExport.stickies(in: document, within: ids), title: document.title, in: window, toast: toast)
            return
        }
        guard !EaselSelectionExport.scope(ids, in: document).isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export Selection"
        panel.allowedContentTypes = format.contentTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(document.title, fileExtension: format.fileExtension)
        panel.beginSheetModal(for: window) { [weak canvas, weak session] response in
            guard response == .OK, let destination = panel.url, let canvas, let session else { return }
            MainActor.assumeIsolated {
                write(ids, as: format, canvas: canvas, session: session, to: destination, in: window, toast: toast)
            }
        }
    }

    static func exportStickies(_ stickies: [EaselItem], title: String, in window: NSWindow, toast: @escaping (ParcToastContent) -> Void) {
        guard !stickies.isEmpty else { toast(.standard("No stickies to export")); return }
        let csv = "\u{FEFF}" + EaselSelectionExport.stickyCSV(stickies)
        let panel = NSSavePanel()
        panel.title = "Export Stickies"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(title, fileExtension: "csv")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try Data(csv.utf8).write(to: destination, options: .atomic)
                    let count = stickies.count
                    toast(.standard("Exported \(count) stick\(count == 1 ? "y" : "ies")", subLabel: destination.lastPathComponent))
                } catch {
                    EaselImageExport.showFailure(in: window)
                }
            }
        }
    }

    private static func write(_ ids: Set<UUID>, as format: EaselSelectionExportFormat, canvas: EaselCanvasView, session: EaselSession,
                              to destination: URL, in window: NSWindow, toast: @escaping (ParcToastContent) -> Void) {
        let documentID = session.document.id
        _ = canvas.collectExportPages { [weak canvas, weak session, weak window] pages in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let canvas, let session, let window, canvas.window === window, !session.isClosed,
                          session.document.id == documentID else { return }
                    let document = session.document
                    let scope = EaselSelectionExport.scope(ids, in: document)
                    do {
                        guard !scope.isEmpty else { throw CocoaError(.fileWriteUnknown) }
                        switch format {
                        case .image:
                            let scale = EaselImageExport.pixelDensity()
                            guard let image = canvas.renderObjectsImage(scope, backingScale: scale, pages: pages) else { throw CocoaError(.fileWriteUnknown) }
                            try EaselImageExport.write(image, scale: scale, to: destination)
                        case .pdf:
                            guard let data = canvas.exportPDF(title: document.title, pages: pages, only: scope) else { throw CocoaError(.fileWriteUnknown) }
                            try data.write(to: destination, options: .atomic)
                        case .html:
                            let subset = EaselSelectionExport.document(document, keeping: scope)
                            let art = EaselDocumentExport.art(session: session, canvas: canvas, pages: pages)
                            let html = EaselVectorExport.htmlDocument(subset, art: art, palette: EaselDocumentExport.palette)
                            try Data(html.utf8).write(to: destination, options: .atomic)
                        case .stickies:
                            return
                        }
                        toast(.standard("Exported \(destination.lastPathComponent)"))
                    } catch {
                        EaselImageExport.showFailure(in: window)
                    }
                }
            }
        }
    }
}

@MainActor
extension EaselEditorViewController {
    func exportSelection(_ ids: Set<UUID>, as format: EaselSelectionExportFormat) {
        guard canExportImage, let window = view.window else { return }
        EaselSelectionExporter.export(ids, as: format, canvas: canvas, session: session, in: window) { [weak self] in self?.showExportToast($0) }
    }

    func exportStickies(_ stickies: [EaselItem]) {
        guard canExportImage, let window = view.window else { return }
        EaselSelectionExporter.exportStickies(stickies, title: session.document.title, in: window) { [weak self] in self?.showExportToast($0) }
    }
}
