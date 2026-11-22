import AppKit
import ParcCore
import ParcNotes

struct EaselPastedNoteMedia {
    enum Origin {
        case file(URL)
        case data(Data, fileExtension: String)
        case download(URL)
        case link(URL)
    }

    var kind: EaselItemKind
    var origin: Origin
    var name: String?
    var altText: String?
    var crop: EaselRect?
    var mask: EaselImageMask?
    var credit: EaselMediaCredit?
    var captured: EaselItem?

    static let maximumCount = 20

    static func plan(_ block: NoteBlock, base: URL?, trusted folder: URL?) -> EaselPastedNoteMedia? {
        guard block.kind.isMedia, block.children.isEmpty, let kind = itemKind(block.kind),
              let source = block.props.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty,
              let origin = origin(source, kind: kind, base: base, trusted: folder) else { return nil }
        let alt = block.props.alt?.trimmingCharacters(in: .whitespacesAndNewlines)
        var media = EaselPastedNoteMedia(kind: kind, origin: origin)
        media.name = kind.takesFileName ? [block.props.caption.plainText, alt ?? ""].first { !$0.isEmpty } : nil
        guard kind == .image || kind == .video else { return media }
        media.altText = alt?.isEmpty == false ? alt : nil
        guard kind == .image else { return media }
        if let capture = NoteCaptureLive.capture(of: block), capture.sourceAddress != nil, var captured = NoteCaptureLive.chromeItem(of: block) {
            captured.text = NoteCaptureText.title(for: capture, alt: alt)
            media.captured = captured
            return media
        }
        media.crop = block.props.crop.map { EaselRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        media.mask = block.props.mask.flatMap { EaselImageMask(rawValue: $0.rawValue) }
        media.credit = block.props.credit.map { EaselMediaCredit(name: $0.name, profileURL: $0.profileURL?.absoluteString) }
        return media
    }

    static func itemKind(_ kind: NoteBlockKind) -> EaselItemKind? {
        switch kind {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .file: return .file
        case .pdf: return .pdf
        default: return nil
        }
    }

    static func origin(_ source: String, kind: EaselItemKind, base: URL?, trusted folder: URL?) -> Origin? {
        if let decoded = NoteClipboard.decodeDataURL(source) { return .data(decoded.data, fileExtension: decoded.fileExtension) }
        if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
            return EaselMediaImportPlan.isLinkable(url, kind: kind) ? .link(url) : .download(url)
        }
        guard let base, let folder, !source.hasPrefix("/"), !source.hasPrefix("#") else { return nil }
        let file = URL(fileURLWithPath: source.removingPercentEncoding ?? source, relativeTo: base).standardizedFileURL
        return NoteClipboard.mayImportMedia(file, from: base, trusted: folder) ? .file(file) : nil
    }
}

extension EaselCanvasView {
    func pasteNoteBlocks(_ reading: NoteClipboard.Reading, choice: NoteClipboard.Choice, at point: NSPoint?) -> Bool {
        guard fixedCanvasSize == nil, !viewOnly, !session.isClosed else { return false }
        var blocks: [NoteBlock] = []
        var base: URL?
        switch choice {
        case .blocks:
            guard let archive = reading.archive else { return false }
            blocks = archive.blocks
            base = archive.base.flatMap { $0.isFileURL ? URL(fileURLWithPath: $0.standardizedFileURL.path, isDirectory: true) : nil }
        case .html:
            guard let html = reading.html else { return false }
            blocks = NoteHTMLReader.blocks(from: html, baseURL: nil)
        default:
            return false
        }
        let objects = blocks.filter { block in
            !(block.kind == .paragraph && block.children.isEmpty && block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        guard !objects.isEmpty, objects.count <= EaselPastedNoteMedia.maximumCount else { return false }
        if objects.count == 1, let only = objects.first, only.kind == .bookmark || only.kind == .embed {
            guard let raw = only.props.source, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            return pasteWebLink(url, at: point, as: only.kind == .embed ? .browser : .link, offersChoices: false)
        }
        let folder = base.flatMap(NoteClipboard.trustedMediaFolder)
        let planned = objects.compactMap { EaselPastedNoteMedia.plan($0, base: base, trusted: folder) }
        guard planned.count == objects.count else { return false }
        if planned.count == 1, let only = planned.first, case .link(let url) = only.origin {
            return insertMediaLink(url, kind: only.kind, at: point) != nil
        }
        guard !planned.contains(where: { if case .link = $0.origin { return true } else { return false } }) else { return false }
        let downloads = planned.contains { if case .download = $0.origin { return true } else { return false } }
        guard downloads else {
            var ready: [EaselPreparedMedia] = []
            var failure: Error?
            for media in planned {
                do { ready.append(try preparePastedMedia(media, file: try localFile(for: media))) } catch { failure = failure ?? error }
            }
            if let failure { onError?(failure) }
            guard !ready.isEmpty else { return failure != nil }
            do { try importPreparedMedia(ready, at: point) } catch { onError?(error) }
            return true
        }
        let owner = window, document = session.document.id
        Task { @MainActor [weak self] in
            var ready: [EaselPreparedMedia] = []
            var failure: Error?
            for media in planned {
                do {
                    let file: URL
                    if case .download(let url) = media.origin {
                        let data = try await Self.download(url, kind: media.kind)
                        file = try Self.stagedFile(data, fileExtension: url.pathExtension, fileName: media.name ?? EaselMediaImportPlan.linkFileName(url))
                    } else {
                        guard let self else { return }
                        file = try self.localFile(for: media)
                    }
                    guard let self else { return }
                    ready.append(try self.preparePastedMedia(media, file: file))
                } catch is CancellationError {
                    return
                } catch {
                    failure = failure ?? error
                }
            }
            guard let self, self.window === owner, !self.session.isClosed, !self.session.isDeleted,
                  self.session.document.id == document else { return }
            if let failure { self.onError?(failure) }
            guard !ready.isEmpty else { return }
            var commitFailure: Error?
            self.withObjectMotion(.appear) {
                do { try self.importPreparedMedia(ready, at: point) } catch { commitFailure = error }
            }
            if let commitFailure { self.onError?(commitFailure) }
        }
        return true
    }

    private func localFile(for media: EaselPastedNoteMedia) throws -> URL {
        switch media.origin {
        case .file(let url): return url
        case .data(let data, let fileExtension): return try Self.stagedFile(data, fileExtension: fileExtension, fileName: media.name)
        case .download, .link: throw EaselStoreError.invalidFile
        }
    }

    private func preparePastedMedia(_ media: EaselPastedNoteMedia, file: URL) throws -> EaselPreparedMedia {
        var entry = try prepareMedia(file, as: media.kind == .file ? .file : nil)
        if let name = media.name, entry.source.itemKind.takesFileName { entry.name = EaselMediaImportPlan.cleanFileName(name) ?? entry.name }
        entry.altText = media.altText
        entry.crop = media.crop
        entry.mask = media.mask
        entry.credit = media.credit
        entry.captured = media.captured
        return entry
    }
}
