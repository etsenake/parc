import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

struct EaselPreparedMedia {
    var url: URL
    var name: String?
    var source: EaselMediaImportPlan.Source
    var data: Data
    var type: EaselAssetType
    var fileExtension: String?
    var natural: (width: Double, height: Double)?
    var poster: CGImage?
}

extension EaselCanvasView {
    func importMediaFiles(_ urls: [URL], at point: NSPoint? = nil) throws {
        guard !urls.isEmpty else { return }
        if fixedCanvasSize != nil {
            for url in urls { try insertMediaFile(url) }
            return
        }
        var prepared: [EaselPreparedMedia] = []
        var firstError: Error?
        for url in urls {
            do { prepared.append(try prepareMedia(url)) } catch { firstError = firstError ?? error }
        }
        guard !prepared.isEmpty else {
            if let firstError { throw firstError }
            return
        }
        if let firstError { onError?(firstError) }
        if prepared.contains(where: { $0.source.needsFacts }) {
            let owner = window, document = session.document.id
            Task { @MainActor [weak self] in
                var ready: [EaselPreparedMedia] = []
                var failure: Error?
                for var entry in prepared {
                    do {
                        try await Self.loadFacts(&entry)
                        ready.append(entry)
                    } catch {
                        failure = failure ?? error
                    }
                }
                guard let self, self.window === owner, !self.session.isClosed, !self.session.isDeleted,
                      self.session.document.id == document else { return }
                if let failure { self.onError?(failure) }
                guard !ready.isEmpty else { return }
                do { try self.commitMedia(ready, at: point) } catch { self.onError?(error) }
            }
            return
        }
        try commitMedia(prepared, at: point)
    }

    @discardableResult
    func insertMediaLink(_ url: URL, kind: EaselItemKind, at point: NSPoint? = nil) -> UUID? {
        guard fixedCanvasSize == nil, EaselMediaImportPlan.isLinkable(url, kind: kind) else {
            onError?(EaselStoreError.invalidDocument("enter a complete http or https link"))
            return nil
        }
        cancelPointerInteraction()
        guard finishEditing() else { return nil }
        if drawing { drawing = false }
        let size = EaselMediaPlacement.filledSize(for: kind)
        let centre = point ?? NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        guard let frame = EaselMediaPlacement.row(of: [size], centredAt: EaselPoint(x: Double(centre.x), y: Double(centre.y))).first else { return nil }
        var item = EaselItem(kind: kind, frame: frame, zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1)
        item.url = url.absoluteString
        item.fileName = EaselMediaImportPlan.linkFileName(url)
        do {
            try session.perform(EaselMediaPlacement.addName(for: kind)) { $0.items.append(item) }
        } catch {
            onError?(error)
            return nil
        }
        selection = [item.id]
        return item.id
    }

    func prepareMedia(_ url: URL, as kind: EaselItemKind? = nil) throws -> EaselPreparedMedia {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw EaselStoreError.invalidFile }
        let movie = values.contentType?.conforms(to: .movie) == true
        let image = values.contentType?.conforms(to: .image) == true
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let asFile = kind == .file
        let probable = asFile ? .file : EaselMediaImportPlan.classify(sniffed: nil, fileExtension: ext, isImage: image, isMovie: movie, byteCount: size)
        guard let probable else { throw EaselStoreError.invalidFile }
        guard size <= EaselStore.maximumAssetBytes else { throw EaselMediaImportPlan.tooLargeError(for: probable) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let classified = asFile ? .file : EaselMediaImportPlan.classify(sniffed: EaselAssetType.sniff(data), fileExtension: ext, isImage: image,
                                                                         isMovie: movie, byteCount: data.count)
        guard let source = classified else { throw EaselStoreError.invalidFile }
        let name = EaselMediaImportPlan.cleanFileName(url.lastPathComponent)
        var entry = EaselPreparedMedia(url: url, name: name, source: source, data: data, type: .file, fileExtension: nil)
        switch source {
        case .image:
            let asset = try preparedImageAsset(data)
            entry.data = asset.data
            entry.type = asset.type
            entry.natural = (Double(asset.pixelSize.width), Double(asset.pixelSize.height))
        case .video(let type):
            entry.type = type
        case .audio(let type):
            entry.type = type
        case .pdf:
            guard let page = PDFDocument(data: data)?.page(at: 0) else { throw EaselStoreError.invalidPDF }
            let bounds = page.bounds(for: .cropBox)
            guard let natural = EaselMediaImportPlan.pageSize(width: Double(bounds.width), height: Double(bounds.height), rotation: page.rotation) else {
                throw EaselStoreError.invalidPDF
            }
            entry.type = .pdf
            entry.natural = natural
        case .file:
            entry.type = .file
            entry.fileExtension = EaselAssetType.safeExtension(ext)
        }
        return entry
    }

    static func loadFacts(_ entry: inout EaselPreparedMedia) async throws {
        switch entry.source {
        case .video:
            guard entry.type.isVideo, EaselAssetType.sniff(entry.data)?.isVideo == true else { throw EaselStoreError.invalidVideo }
            let facts = try await EaselVideoFacts.load(entry.url)
            entry.natural = (Double(facts.size.width), Double(facts.size.height))
            entry.poster = facts.poster
        case .audio:
            let asset = AVURLAsset(url: entry.url)
            guard (try? await asset.load(.isPlayable)) == true else { throw EaselStoreError.invalidAudio }
        default:
            break
        }
    }

    private func commitMedia(_ entries: [EaselPreparedMedia], at point: NSPoint?) throws {
        cancelPointerInteraction()
        guard finishEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        if drawing { drawing = false }
        var imported: [String] = []
        var items: [EaselItem] = []
        let sizes = entries.map { EaselMediaPlacement.filledSize(for: $0.source.itemKind, natural: $0.natural) }
        let centre = point ?? NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        let frames = EaselMediaImportPlan.layout(sizes, centre: EaselPoint(x: Double(centre.x), y: Double(centre.y)))
        let top = (session.document.items.map(\.zIndex).max() ?? 0) + 1
        do {
            for (index, entry) in entries.enumerated() {
                guard frames.indices.contains(index) else { break }
                let assetID = try session.importAsset(entry.data, type: entry.type, fileExtension: entry.fileExtension)
                imported.append(assetID)
                var item = EaselItem(kind: entry.source.itemKind, frame: frames[index], zIndex: top + index, assetID: assetID)
                if entry.source.itemKind.takesFileName { item.fileName = entry.name }
                if let poster = entry.poster, let png = NSBitmapImageRep(cgImage: poster).representation(using: .png, properties: [:]),
                   let posterID = try? session.importAsset(png, type: .png) {
                    imported.append(posterID)
                    item.poster = posterID
                }
                items.append(item)
            }
            let name = items.count == 1 ? EaselMediaPlacement.addName(for: items[0].kind) : "Add media"
            try session.perform(name) { $0.items.append(contentsOf: items) }
        } catch {
            session.discardUnusedAssets(imported)
            throw error
        }
        selection = Set(items.map(\.id))
    }
}
