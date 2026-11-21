import AppKit
import UniformTypeIdentifiers

enum EaselSelectionExportFormat: String, CaseIterable {
    case image, pdf, html, stickies

    var title: String {
        switch self {
        case .image: return "Image…"
        case .pdf: return "PDF…"
        case .html: return "HTML File…"
        case .stickies: return "Stickies as CSV…"
        }
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .html: return "doc.text"
        case .stickies: return "list.bullet.rectangle"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .image: return [.png, .jpeg]
        case .pdf: return [.pdf]
        case .html: return [.html]
        case .stickies: return [.commaSeparatedText]
        }
    }

    var fileExtension: String {
        switch self {
        case .image: return "png"
        case .pdf: return "pdf"
        case .html: return "html"
        case .stickies: return "csv"
        }
    }
}

@MainActor
extension EaselCanvasView {
    func exportSelectionRows() -> [EaselMenuRow] {
        let document = session.document
        let scope = EaselSelectionExport.scope(selection, in: document)
        let hasStickies = !EaselSelectionExport.stickies(in: document, within: selection).isEmpty
        let enabled = onExportSelection != nil && !scope.isEmpty && window?.attachedSheet == nil
        return EaselSelectionExportFormat.allCases.compactMap { format in
            guard format != .stickies || hasStickies else { return nil }
            return EaselMenuRow(id: "export-selection-" + format.rawValue, title: format.title, symbol: format.symbol,
                                isEnabled: enabled, perform: guardedMenuAction { canvas in canvas.exportSelection(as: format) })
        }
    }

    func exportSelectionMenuRow() -> EaselMenuRow {
        let children = exportSelectionRows()
        return EaselMenuRow(id: "export-selection", title: "Export Selection", symbol: "square.and.arrow.up",
                            isEnabled: children.contains { $0.isEnabled }, children: children)
    }

    func exportSelection(as format: EaselSelectionExportFormat) {
        let ids = selection
        guard !ids.isEmpty, let onExportSelection, finishEditing() else { return }
        onExportSelection(ids, format)
    }

    @discardableResult
    func presentExportSelectionMenu() -> Bool {
        let objects = selectedObjects
        guard !objects.isEmpty, onExportSelection != nil, finishEditing(),
              let bounds = EaselArrange.union(objects.map(EaselArrange.visualFrame)) else { return false }
        let visible = visibleRect.insetBy(dx: 24, dy: 24)
        let x = min(max(bounds.x + bounds.width / 2, visible.minX), visible.maxX)
        let y = min(max(bounds.y + bounds.height, visible.minY), visible.maxY)
        presentMenu([exportSelectionRows()], anchor: NSRect(x: x, y: y, width: 1, height: 1), keyboard: true, label: "Export Selection")
        return true
    }
}

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
