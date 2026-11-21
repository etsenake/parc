import AppKit
import PDFKit
import UniformTypeIdentifiers

extension EaselEditorViewController {
    func toggleLock() {
        guard canvas.finishEditing(removingEmpty: false) else { return }
        let lock = !session.document.isLocked
        do {
            try session.perform(lock ? "Lock Easel" : "Unlock Easel") { $0.locked = lock ? true : nil }
        } catch {
            show(error)
        }
    }

    func setDefaultFamily(_ family: EaselTextStyle.Family) {
        guard !session.document.isLocked, session.document.resolvedDefaultFamily != family else { return }
        do {
            try session.perform("Default text") { $0.defaultFamily = family == .clean ? nil : family }
        } catch {
            show(error)
        }
    }

    func installSendProvider() {
        canvas.sendProvider = EaselSendProvider(destinations: { [weak self] in
            guard let self else { return [] }
            let current = self.session.document.id
            return ((try? self.easelStore.list()) ?? []).filter { $0.id != current }.map { EaselSendDestination(id: $0.id, title: $0.title) }
        }, session: { [weak self] id in try? self?.easelStore.load(id) }, create: { [weak self] in
            try? self?.easelStore.create(title: "Untitled Easel")
        }, sent: { [weak self] title, count, copied in
            let noun = count == 1 ? "object" : "objects"
            self?.showExportToast(.standard((copied ? "Copied " : "Sent ") + "\(count) \(noun) to \(title)"))
        })
    }

    func applyLock(_ locked: Bool) {
        palette?.isViewOnly = locked
        titleField.isEditable = !locked
        canvas.documentLockDidChange()
    }

    func printEasel() {
        guard canExportImage, let window = view.window else { return }
        withExportPages(in: window) { [weak self] pages in
            guard let self, window.attachedSheet == nil else { return }
            guard let data = self.canvas.exportPagesPDF(title: self.session.document.title, pages: pages),
                  let document = PDFDocument(data: data),
                  let info = NSPrintInfo.shared.copy() as? NSPrintInfo,
                  let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
                return EaselImageExport.showFailure(in: window)
            }
            operation.jobTitle = self.session.document.title
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    func copyMarkdown() {
        let text = EaselMarkdown.markdown(session.document)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        showExportToast(.standard("Copied Markdown"))
    }

    func exportMarkdown(in window: NSWindow) {
        let panel = NSSavePanel()
        panel.title = "Export Easel"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(session.document.title, fileExtension: "md")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated { self?.writeMarkdown(to: destination, in: window) }
        }
    }

    private func writeMarkdown(to destination: URL, in window: NSWindow) {
        let document = session.document
        let folderName = destination.deletingPathExtension().lastPathComponent + " Files"
        var assets: [UUID: String] = [:]
        for item in document.items where item.kind.isMedia {
            if let id = item.assetID { assets[item.id] = id }
        }
        var options = EaselMarkdown.Options()
        options.assetPath = { item in
            guard assets[item.id] != nil else { return nil }
            return (folderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderName) + "/" + (assets[item.id] ?? "")
        }
        let text = EaselMarkdown.markdown(document, options: options)
        do {
            if !assets.isEmpty {
                let folder = destination.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for id in Set(assets.values) {
                    try session.assetData(id).write(to: folder.appendingPathComponent(id), options: .atomic)
                }
            }
            try Data(text.utf8).write(to: destination, options: .atomic)
            showExportToast(.standard("Exported \(destination.lastPathComponent)"))
        } catch {
            EaselImageExport.showFailure(in: window)
        }
    }
}
