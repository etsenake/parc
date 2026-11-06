import AppKit
import UniformTypeIdentifiers

/// One export belongs to its original window/Profile and immutable documents.
/// Preparing the archive never occupies the UI thread or writes browser state.
@MainActor
final class NoteExportController {
    private weak var window: NSWindow?
    private let isValid: () -> Bool
    private let onFinish: () -> Void
    private let onError: (Error) -> Void
    private var worker: Task<NoteExportArchive, Error>?
    private var task: Task<Void, Never>?
    private var panel: NSSavePanel?
    private var finished = false

    init(window: NSWindow, isValid: @escaping () -> Bool,
         onFinish: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.window = window; self.isValid = isValid; self.onFinish = onFinish; self.onError = onError
    }

    func begin(_ documents: [NoteDocument]) {
        guard task == nil, !finished else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var exported: [NoteExportDocument] = []
                for document in documents {
                    try Task.checkCancellation()
                    guard self.isValid() else { self.finish(); return }
                    exported.append(try NoteHTMLExport.document(document))
                    await Task.yield()
                }
                let snapshot = exported
                let worker = Task.detached(priority: .userInitiated) { try NoteExportArchive.prepare(snapshot) }
                self.worker = worker
                let archive = try await worker.value
                self.worker = nil
                try Task.checkCancellation()
                guard !self.finished, self.isValid(), let window = self.window,
                      window.attachedSheet == nil else { self.finish(); return }
                let panel = NSSavePanel(); self.panel = panel
                panel.allowedContentTypes = [.zip]; panel.canCreateDirectories = true
                panel.nameFieldStringValue = archive.suggestedName
                panel.title = "Export Notes"
                panel.message = "Save this profile’s notes as HTML documents in a ZIP archive."
                panel.beginSheetModal(for: window) { [weak self] result in
                    guard let self, !self.finished else { return }
                    self.panel = nil
                    guard result == .OK, let destination = panel.url, self.isValid() else {
                        self.finish(); return
                    }
                    // The save dialog authorized this exact immutable archive
                    // and destination. Copy/atomic replacement is off-main too.
                    self.task = Task { [weak self] in
                        guard let self else { return }
                        let scoped = destination.startAccessingSecurityScopedResource()
                        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                        do {
                            try await Task.detached(priority: .userInitiated) { try archive.save(to: destination) }.value
                            self.finish()
                        } catch { self.fail(error) }
                    }
                }
            } catch is CancellationError { self.finish() }
            catch { self.fail(error) }
        }
    }

    func cancel() {
        guard !finished else { return }
        worker?.cancel(); task?.cancel()
        if let panel { window?.endSheet(panel, returnCode: .cancel) }
        finish()
    }
    private func finish() {
        guard !finished else { return }
        finished = true; panel = nil; worker = nil; task = nil; onFinish()
    }
    private func fail(_ error: Error) {
        let report = !finished && isValid()
        finish()
        if report { onError(error) }
    }
}
