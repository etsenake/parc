import AppKit
import Quartz
import UniformTypeIdentifiers

enum NoteMediaActionError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

@MainActor
enum NoteMediaActions {
    static func chooseFile(for kind: NoteBlockKind, in window: NSWindow?, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = NoteMediaFileType.contentTypes(for: kind)
        panel.prompt = kind == .file ? "Attach" : "Add"
        panel.message = message(for: kind)
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
    }

    static func message(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "Pick an image for your note."
        case .video: return "Pick a video for your note."
        case .audio: return "Pick a sound for your note."
        default: return "Pick a file to tuck into your note."
        }
    }

    static func importAsset(_ url: URL, into environment: NoteEnvironment) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try environment.importAsset(from: url)
    }

    static func saveCopy(of source: NoteMediaSource, suggestedName: String, in window: NSWindow?,
                         completion: @escaping (Error?) -> Void) {
        guard let origin = source.url else { completion(NoteMediaActionError.unavailable("There's nothing to save yet.")); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.isEmpty ? origin.lastPathComponent : suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(filenameExtension: (panel.nameFieldStringValue as NSString).pathExtension) {
            panel.allowedContentTypes = [type]
            panel.allowsOtherFileTypes = true
        }
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            if origin.isFileURL {
                completion(copy(origin, to: destination))
            } else {
                download(origin, to: destination, completion: completion)
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
    }

    static func copy(_ origin: URL, to destination: URL) -> Error? {
        guard origin.standardizedFileURL != destination.standardizedFileURL else { return nil }
        do {
            let manager = FileManager.default
            let staging = manager.temporaryDirectory.appendingPathComponent("parc-note-copy-" + UUID().uuidString)
            try manager.copyItem(at: origin, to: staging)
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }
            return nil
        } catch {
            return error
        }
    }

    static func download(_ origin: URL, to destination: URL, completion: @escaping (Error?) -> Void) {
        let task = URLSession.shared.downloadTask(with: origin) { location, response, error in
            var failure = error
            if failure == nil, let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failure = NoteMediaActionError.unavailable("The site said no (\(http.statusCode)).")
            }
            if failure == nil, let location {
                let manager = FileManager.default
                do {
                    if manager.fileExists(atPath: destination.path) {
                        _ = try manager.replaceItemAt(destination, withItemAt: location)
                    } else {
                        try manager.moveItem(at: location, to: destination)
                    }
                } catch {
                    failure = error
                }
            }
            let reported = failure.map { $0.localizedDescription }
            DispatchQueue.main.async {
                completion(reported.map { NoteMediaActionError.unavailable($0) })
            }
        }
        task.resume()
    }

    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func temporaryCopy(of data: Data, named name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ParcNotePreviews", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = name.replacingOccurrences(of: "/", with: "-")
            let target = folder.appendingPathComponent(safe.isEmpty ? "Preview" : safe)
            try data.write(to: target, options: .atomic)
            return target
        } catch {
            return nil
        }
    }

    static func previewURL(for source: NoteMediaSource, completion: @escaping (URL?) -> Void) {
        switch source {
        case .local(let url): completion(FileManager.default.fileExists(atPath: url.path) ? url : nil)
        case .remote(let url):
            NoteMediaImageLoader.shared.data(for: url) { result in
                guard case .success(let data) = result else { completion(nil); return }
                completion(temporaryCopy(of: data, named: source.fileName))
            }
        case .empty, .unresolved: completion(nil)
        }
    }
}

@MainActor
final class NoteMediaQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = NoteMediaQuickLook()
    private(set) var items: [URL] = []
    private weak var sourceView: NSView?
    private var sourceRect: NSRect = .zero

    func prepare(_ url: URL, from view: NSView, rect: NSRect) {
        items = [url]
        sourceView = view
        sourceRect = rect
    }

    func show(from view: NSView) {
        guard view.window != nil, !items.isEmpty else { return }
        let panel: QLPreviewPanel = QLPreviewPanel.shared()
        if panel.isVisible {
            panel.reloadData()
            panel.currentPreviewItemIndex = 0
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func toggle(from view: NSView) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            show(from: view)
        }
    }

    func attach(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func detach(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { items.indices.contains(index) ? items[index] as NSURL : nil }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        MainActor.assumeIsolated {
            guard let view = sourceView, let window = view.window else { return .zero }
            return window.convertToScreen(view.convert(sourceRect, to: nil))
        }
    }
}
