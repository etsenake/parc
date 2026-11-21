import AppKit

extension EaselCanvasView {
    private func fillTarget(_ id: UUID) -> EaselItem? {
        guard let item = session.document.items.first(where: { $0.id == id }), item.kind.isMedia, !item.isLocked,
              !session.isClosed, !session.isDeleted else { return nil }
        return item
    }

    private static func mismatch(_ kind: EaselItemKind) -> EaselStoreError {
        switch kind {
        case .video: return .invalidVideo
        case .audio: return .invalidAudio
        case .pdf: return .invalidPDF
        case .file: return .invalidFile
        default: return .invalidImage
        }
    }

    func fillMedia(_ id: UUID, fileURL url: URL) {
        guard let current = fillTarget(id) else { return }
        do {
            var entry = try prepareMedia(url, as: current.kind == .file ? .file : nil)
            guard entry.source.itemKind == current.kind else { throw Self.mismatch(current.kind) }
            guard entry.source.needsFacts else { try commitFill(id, entry); return }
            noteHostedFill(id, pending: true)
            let owner = window, document = session.document.id
            Task { @MainActor [weak self] in
                do {
                    try await Self.loadFacts(&entry)
                    guard let self else { return }
                    self.noteHostedFill(id, pending: false)
                    guard self.window === owner, self.session.document.id == document else { return }
                    try self.commitFill(id, entry)
                } catch {
                    self?.noteHostedFill(id, pending: false)
                    self?.onError?(error)
                }
            }
        } catch { onError?(error) }
    }

    func fillPlaceholder(fromDrop sender: NSDraggingInfo) -> Bool? {
        let point = convert(sender.draggingLocation, from: nil)
        guard fixedCanvasSize == nil, let item = items.last(where: { item in
            item.isEmptyPlaceholder && item.kind.isMedia && !item.isLocked
                && NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height).contains(point)
        }) else { return nil }
        let board = sender.draggingPasteboard
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first {
            fillMedia(item.id, fileURL: url)
            return true
        }
        if item.kind == .image, let data = board.data(forType: Self.gifPasteboardType) ?? board.data(forType: .png) ?? board.data(forType: .tiff) {
            do { try fillImage(item.id, data: data) } catch { onError?(error) }
            return true
        }
        if let link = (board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first,
           let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            if !hostedObjects.contains(where: { $0.fillHosted(item.id, link: link) }) { fillMediaLink(item.id, url: link) }
            return true
        }
        return nil
    }

    func fillMedia(_ id: UUID, data: Data, fileExtension: String, fileName: String?) {
        do {
            fillMedia(id, fileURL: try Self.stagedFile(data, fileExtension: fileExtension, fileName: fileName))
        } catch { onError?(error) }
    }

    func fillImage(_ id: UUID, data: Data, credit: EaselMediaCredit? = nil, altText: String? = nil) throws {
        guard let current = fillTarget(id), current.kind == .image else { throw EaselStoreError.invalidImage }
        let asset = try preparedImageAsset(data)
        var entry = EaselPreparedMedia(url: URL(fileURLWithPath: "/"), name: nil, source: .image, data: asset.data, type: asset.type,
                                       fileExtension: nil)
        entry.natural = (Double(asset.pixelSize.width), Double(asset.pixelSize.height))
        try commitFill(id, entry, credit: credit, altText: altText)
    }

    func fillMediaLink(_ id: UUID, url: URL) {
        guard let current = fillTarget(id) else { return }
        if EaselMediaImportPlan.isLinkable(url, kind: current.kind) {
            var next = current
            next.url = url.absoluteString
            next.assetID = nil
            next.poster = nil
            next.fileName = EaselMediaImportPlan.linkFileName(url)
            if current.isEmptyPlaceholder {
                let size = EaselMediaPlacement.filledSize(for: current.kind)
                next.frame = EaselMediaPlacement.resized(current.frame, width: size.width, height: size.height)
            }
            replaceMediaItem(current, with: next, name: current.isEmptyPlaceholder ? EaselMediaPlacement.addName(for: current.kind)
                                                                                     : "Embed " + EaselMediaPlacement.displayName(for: current.kind).lowercased())
            return
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            onError?(EaselStoreError.invalidDocument("enter a complete http or https link"))
            return
        }
        noteHostedFill(id, pending: true)
        let owner = window
        Task { @MainActor [weak self] in
            do {
                let data = try await Self.download(url)
                guard let self else { return }
                self.noteHostedFill(id, pending: false)
                guard self.window === owner else { return }
                if current.kind == .image {
                    try self.fillImage(id, data: data)
                } else {
                    let name = EaselMediaImportPlan.linkFileName(url)
                    self.fillMedia(id, data: data, fileExtension: url.pathExtension, fileName: name)
                }
            } catch {
                self?.noteHostedFill(id, pending: false)
                self?.onError?(error)
            }
        }
    }

    func turnMediaIntoEmbed(_ id: UUID, url: URL) {
        guard let current = fillTarget(id), current.kind != .image || current.isEmptyPlaceholder else { return }
        var next = EaselItem(kind: .browser, frame: current.frame, zIndex: current.zIndex, text: url.host ?? "", url: url.absoluteString)
        next.id = current.id
        next.groupID = current.groupID
        next.page = current.page
        next.attachedTo = current.attachedTo
        let size = EaselMediaPlacement.filledSize(for: .browser)
        next.frame = EaselMediaPlacement.resized(current.frame, width: size.width, height: size.height)
        replaceMediaItem(current, with: next, name: "Embed")
    }

    func setMediaAltText(_ id: UUID, text: String) {
        guard let current = fillTarget(id), current.kind == .video || current.kind == .image else { return }
        let cleaned = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var limited = cleaned
        while limited.utf8.count > 4096 { limited.removeLast() }
        var next = current
        next.altText = limited.isEmpty ? nil : limited
        guard next != current else { return }
        replaceMediaItem(current, with: next, name: "Alt Text")
    }

    private func replaceMediaItem(_ current: EaselItem, with next: EaselItem, name: String) {
        cancelPointerInteraction()
        guard finishEditing() else { return }
        let changed = commit(name) { document in
            guard let index = document.items.firstIndex(where: { $0.id == current.id }), document.items[index] == current else {
                throw EaselStoreError.invalidDocument("the object changed while it was being filled")
            }
            document.items[index] = next
        }
        guard changed else { return }
        selection = [current.id]
        invalidateIncrementalDisplay(layout: true)
    }

    private func commitFill(_ id: UUID, _ entry: EaselPreparedMedia, credit: EaselMediaCredit? = nil, altText: String? = nil) throws {
        guard let current = fillTarget(id), current.kind == entry.source.itemKind else { throw Self.mismatch(entry.source.itemKind) }
        cancelPointerInteraction()
        guard finishEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        var imported: [String] = []
        do {
            let assetID = try session.importAsset(entry.data, type: entry.type, fileExtension: entry.fileExtension)
            imported.append(assetID)
            var next = current
            if current.kind == .image, !current.isEmptyPlaceholder, let natural = entry.natural {
                next = EaselImageFraming.replacing(current, natural: CGSize(width: natural.width, height: natural.height))
            }
            next.assetID = assetID
            next.url = nil
            next.poster = nil
            if current.kind.takesFileName { next.fileName = entry.name }
            if current.kind == .image {
                next.credit = credit
                if let altText, credit != nil || (current.altText ?? "").isEmpty { next.altText = altText }
                if credit == nil, current.credit != nil { next.altText = nil }
            }
            if let poster = entry.poster, let png = NSBitmapImageRep(cgImage: poster).representation(using: .png, properties: [:]),
               let posterID = try? session.importAsset(png, type: .png) {
                imported.append(posterID)
                next.poster = posterID
            }
            if current.isEmptyPlaceholder {
                let size = EaselMediaPlacement.filledSize(for: current.kind, natural: entry.natural)
                next.frame = EaselMediaPlacement.resized(current.frame, width: size.width, height: size.height)
            } else if current.kind == .video || current.kind == .pdf, let natural = entry.natural, natural.width > 0 {
                next.frame = EaselMediaPlacement.resized(current.frame, width: current.frame.width,
                                                         height: current.frame.width * natural.height / natural.width)
            }
            let name = current.isEmptyPlaceholder ? EaselMediaPlacement.addName(for: current.kind)
                : "Replace " + EaselMediaPlacement.displayName(for: current.kind).lowercased()
            try session.perform(name) { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }), document.items[index] == current else {
                    throw EaselStoreError.invalidDocument("the object changed while it was being filled")
                }
                document.items[index] = next
            }
        } catch {
            session.discardUnusedAssets(imported)
            throw error
        }
        selection = [id]
        invalidateIncrementalDisplay(layout: true)
        if current.kind == .image { refreshImagePlayback() }
    }

    static func stagedFile(_ data: Data, fileExtension: String, fileName: String?) throws -> URL {
        guard data.count <= EaselStore.maximumAssetBytes else { throw EaselStoreError.tooLarge }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Parc Easel Media", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = EaselAssetType.safeExtension(fileExtension)
        var name = fileName.flatMap(EaselMediaImportPlan.cleanFileName)?.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? "Media"
        if let ext, (name as NSString).pathExtension.lowercased() != ext { name += "." + ext }
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw EaselStoreError.invalidFile }
        guard !data.isEmpty else { throw EaselStoreError.invalidFile }
        guard data.count <= EaselStore.maximumAssetBytes else { throw EaselStoreError.tooLarge }
        return data
    }
}
