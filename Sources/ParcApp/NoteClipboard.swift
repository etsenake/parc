import AppKit
import UniformTypeIdentifiers

enum NoteClipboard {
    static let blocksType = NSPasteboard.PasteboardType("app.parc.notes.blocks")
    static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")
    static let imageTypes: [(type: NSPasteboard.PasteboardType, fileExtension: String)] = [
        (.png, "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (NSPasteboard.PasteboardType(UTType.webP.identifier), "webp"),
        (.tiff, "tiff"),
    ]

    struct Archive: Codable, Equatable {
        var version = 1
        var blocks: [NoteBlock]
        var base: URL?
        var inline: Bool
    }

    struct Payload: Equatable {
        var archive: Archive
        var markdown: String?
        var plainText: String
        var html: String?
    }

    struct Reading: Equatable {
        var archive: Archive?
        var files: [URL] = []
        var image: Data?
        var imageExtension: String?
        var html: String?
        var string: String?
        var url: URL?
        var urlTitle: String?
    }

    enum Choice: Equatable {
        case blocks
        case files
        case image
        case html
        case url
        case markdown
        case plainText
        case nothing
    }

    static func payload(for blocks: [NoteBlock], inline: Bool, base: URL?, plainTextFile: Bool, html: String? = nil) -> Payload {
        let archive = Archive(blocks: blocks, base: base, inline: inline)
        if plainTextFile {
            return Payload(archive: archive, markdown: nil, plainText: NotePlainText.serialize(NotePage(blocks: blocks)), html: nil)
        }
        let single = blocks.count == 1 && blocks[0].children.isEmpty
        let inlineText = single && inline && blocks[0].kind.hasRichText
        let serialized = inlineText ? [NoteBlock.paragraph(blocks[0].text)] : blocks
        let markdown = trimmedTrailingNewlines(NoteMarkdown.serialize(NotePage(blocks: serialized)))
        let plain = single && inline && (blocks[0].kind.hasRichText || blocks[0].kind.hasPlainText) ? blocks[0].text.plainText : markdown
        return Payload(archive: archive, markdown: markdown, plainText: plain, html: html)
    }

    @MainActor @discardableResult
    static func write(_ payload: Payload, to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        if let data = encode(payload.archive) { item.setData(data, forType: blocksType) }
        if let markdown = payload.markdown { item.setString(markdown, forType: markdownType) }
        item.setString(payload.plainText, forType: .string)
        if let html = payload.html {
            item.setString(html, forType: .html)
            let provider = NoteRichTextProvider(html: html, base: payload.archive.base)
            item.setDataProvider(provider, forTypes: [.rtf])
            NoteRichTextProvider.retain(provider)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func encode(_ archive: Archive) -> Data? {
        try? JSONEncoder().encode(archive)
    }

    static func decode(_ data: Data) -> Archive? {
        guard let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1, !archive.blocks.isEmpty else { return nil }
        return archive
    }

    static func read(_ pasteboard: NSPasteboard) -> Reading {
        var reading = Reading()
        let types = Set(pasteboard.types ?? [])
        if types.contains(blocksType), let data = pasteboard.data(forType: blocksType) { reading.archive = decode(data) }
        if types.contains(.fileURL) {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            reading.files = urls.filter(\.isFileURL)
        }
        for candidate in imageTypes where types.contains(candidate.type) {
            if let data = pasteboard.data(forType: candidate.type), !data.isEmpty {
                reading.image = data
                reading.imageExtension = candidate.fileExtension
                break
            }
        }
        if types.contains(.html) { reading.html = pasteboard.string(forType: .html) }
        if types.contains(.string) { reading.string = pasteboard.string(forType: .string) }
        if reading.string == nil, types.contains(markdownType) { reading.string = pasteboard.string(forType: markdownType) }
        if types.contains(.URL), let link = NSURL(from: pasteboard) as URL?, !link.isFileURL { reading.url = link }
        if let titles = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")) as? [[String]],
           titles.count == 2, let title = titles[1].first, !title.isEmpty {
            reading.urlTitle = title
        }
        return reading
    }

    static func choose(_ reading: Reading, plainOnly: Bool, canReadHTML: Bool) -> Choice {
        if plainOnly {
            if let string = reading.string, !string.isEmpty { return .plainText }
            if reading.url != nil || !reading.files.isEmpty { return .plainText }
            return .nothing
        }
        if reading.archive != nil { return .blocks }
        if !reading.files.isEmpty { return .files }
        let text = reading.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let textIsLink = text.isEmpty || webURL(in: text) != nil
        if reading.image != nil, textIsLink, !htmlHasText(reading.html) { return .image }
        if canReadHTML, let html = reading.html, htmlHasText(html) || reading.string == nil { return .html }
        if !text.isEmpty {
            if webURL(in: text) != nil { return .url }
            return looksLikeMarkdown(text) ? .markdown : .plainText
        }
        if reading.url != nil { return .url }
        if reading.image != nil { return .image }
        return .nothing
    }

    static func plainString(_ reading: Reading) -> String? {
        if let string = reading.string, !string.isEmpty { return string }
        if let url = reading.url { return url.absoluteString }
        if !reading.files.isEmpty { return reading.files.map(\.path).joined(separator: "\n") }
        return nil
    }

    static func htmlHasText(_ html: String?) -> Bool {
        guard let html, !html.isEmpty else { return false }
        var stripped = html.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
        stripped = stripped.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: "&nbsp;", with: " ")
        return !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func webURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let candidate = trimmed.lowercased().hasPrefix("www.") ? "https://" + trimmed : trimmed
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host, host.contains(".") || host == "localhost" else { return nil }
            return url
        case "mailto": return url.absoluteString.count > 7 ? url : nil
        default: return nil
        }
    }

    private static let blockPatterns: [NSRegularExpression] = [
        "^#{1,6}[ \\t]+\\S",
        "^[ \\t]*[-*+][ \\t]+\\[[ xX]\\][ \\t]",
        "^[ \\t]*[-*+][ \\t]+\\S",
        "^[ \\t]*\\d{1,3}[.)][ \\t]+\\S",
        "^>[ \\t]?\\S",
        "^(```|~~~)",
        "^[ \\t]*\\|.*\\|[ \\t]*$",
        "^[ \\t]*(\\*[ \\t]*){3,}$|^[ \\t]*(-[ \\t]*){3,}$|^[ \\t]*(_[ \\t]*){3,}$",
        "^\\$\\$[ \\t]*$",
        "^:::",
    ].map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    private static let inlinePatterns: [NSRegularExpression] = [
        "(^|[^\\w*])\\*\\*[^\\s*](?:[^*\\n]*[^\\s*])?\\*\\*(?![\\w*])",
        "(^|[^\\w_])__[^\\s_](?:[^_\\n]*[^\\s_])?__(?![\\w_])",
        "(^|[^\\w*])\\*[^\\s*](?:[^*\\n]*[^\\s*])?\\*(?![\\w*])",
        "(^|[^\\w~])~~[^\\s~](?:[^~\\n]*[^\\s~])?~~(?![\\w~])",
        "(^|[^\\w`])`[^`\\n]+`(?![\\w`])",
        "!?\\[[^\\]\\n]+\\]\\([^)\\s]+(?:\\s+\"[^\"]*\")?\\)",
        "(^|[^\\w=])==[^\\s=](?:[^=\\n]*[^\\s=])?==(?![\\w=])",
        "<(u|span data-color=\"[a-z_]+\"|details|summary|aside|mark)>",
    ].map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    private static let tableSeparator = try! NSRegularExpression(pattern: "^[ \\t]*\\|?[ \\t]*:?-{3,}:?[ \\t]*(\\|[ \\t]*:?-{3,}:?[ \\t]*)+\\|?[ \\t]*$", options: [.anchorsMatchLines])

    static func looksLikeMarkdown(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard range.length > 0 else { return false }
        if tableSeparator.firstMatch(in: text, range: range) != nil { return true }
        let blockHits = blockPatterns.reduce(0) { $0 + $1.numberOfMatches(in: text, range: range) }
        let tableRows = blockPatterns[6].numberOfMatches(in: text, range: range)
        let structural = blockHits - tableRows
        if structural > 0 { return true }
        return inlinePatterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    static func plainBlocks(_ text: String) -> [NoteBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 { lines.removeLast() }
        var blocks: [NoteBlock] = []
        var previousEmpty = false
        for line in lines {
            let empty = line.trimmingCharacters(in: .whitespaces).isEmpty
            if empty && previousEmpty { continue }
            previousEmpty = empty
            blocks.append(.paragraph(NoteText(empty ? "" : line)))
        }
        return blocks
    }

    static func markdownBlocks(_ text: String) -> [NoteBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = NoteMarkdown.parse(normalized).blocks
        return blocks.isEmpty ? plainBlocks(text) : blocks
    }

    private static let embeddableHosts: [String] = [
        "youtube.com", "youtu.be", "vimeo.com", "loom.com", "twitter.com", "x.com", "figma.com", "codepen.io",
        "codesandbox.io", "spotify.com", "soundcloud.com", "maps.google.com", "google.com/maps", "gist.github.com",
        "docs.google.com", "drive.google.com", "miro.com", "typeform.com", "airtable.com", "replit.com",
        "excalidraw.com", "tiktok.com", "instagram.com", "music.apple.com", "podcasts.apple.com",
    ]

    static func isEmbeddable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path.lowercased()
        return embeddableHosts.contains { entry in
            if let slash = entry.firstIndex(of: "/") {
                let entryHost = String(entry[..<slash]), entryPath = String(entry[slash...])
                return (host == entryHost || host.hasSuffix("." + entryHost)) && path.hasPrefix(entryPath)
            }
            return host == entry || host.hasSuffix("." + entry)
        }
    }

    static func isNoteFile(_ url: URL) -> Bool {
        url.isFileURL && NoteFileKind(url: url) != nil
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }

    static func mediaKind(for url: URL) -> NoteBlockKind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .file
    }

    @MainActor
    static func blocks(forFiles urls: [URL], environment: NoteEnvironment) -> (blocks: [NoteBlock], failures: [Error]) {
        var blocks: [NoteBlock] = []
        var failures: [Error] = []
        for url in urls where url.isFileURL {
            if NoteFileKind(url: url) == .markdown {
                blocks.append(pageLink(to: url, environment: environment))
                continue
            }
            do {
                let source = try environment.importAsset(from: url)
                var props = NoteBlockProps()
                props.source = source
                let kind = mediaKind(for: url)
                if kind == .image { props.alt = url.deletingPathExtension().lastPathComponent }
                if kind == .file { props.caption = NoteText(url.lastPathComponent) }
                blocks.append(NoteBlock(kind, props: props))
            } catch {
                failures.append(error)
            }
        }
        return (blocks, failures)
    }

    @MainActor
    static func pageLink(to url: URL, environment: NoteEnvironment) -> NoteBlock {
        var props = NoteBlockProps()
        props.target = environment.linkTarget(for: url)
        return NoteBlock(.pageLink, text: NoteText(url.deletingPathExtension().lastPathComponent), props: props)
    }

    @MainActor
    static func imageBlock(data: Data, fileExtension: String, environment: NoteEnvironment) throws -> NoteBlock {
        var bytes = data
        var ext = fileExtension
        if ext == "tiff", let image = NSBitmapImageRep(data: data), let png = image.representation(using: .png, properties: [:]) {
            bytes = png
            ext = "png"
        }
        var props = NoteBlockProps()
        props.source = try environment.importAsset(data: bytes, fileExtension: ext, suggestedName: "Pasted Image")
        return NoteBlock(.image, props: props)
    }

    @MainActor
    static func rebase(_ archive: Archive, into environment: NoteEnvironment) -> [NoteBlock] {
        let destination = environment.documentURL?.deletingLastPathComponent().standardizedFileURL
        guard let base = archive.base?.standardizedFileURL, base != destination else { return archive.blocks }
        func absolute(_ source: String) -> URL? {
            guard !source.isEmpty, URL(string: source)?.scheme == nil, !source.hasPrefix("/"), !source.hasPrefix("#") else { return nil }
            let decoded = source.removingPercentEncoding ?? source
            return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
        }
        func relink(_ target: String) -> String {
            guard let url = absolute(target) else { return target }
            return environment.linkTarget(for: url)
        }
        func fix(_ text: NoteText) -> NoteText {
            var value = text
            for run in text.runs() {
                if let link = run.marks.link, absolute(link) != nil {
                    let next = relink(link)
                    value.updateMarks(in: run.range) { $0.link = next }
                }
                if case .page(let target, let title)? = run.marks.atom, absolute(target) != nil {
                    var marks = run.marks
                    marks.atom = .page(target: relink(target), title: title)
                    value.replace(run.range, with: NoteText(NoteAtom.character, marks: marks))
                }
            }
            return value
        }
        func walk(_ block: NoteBlock) -> NoteBlock {
            var copy = block
            copy.text = fix(block.text)
            copy.props.caption = fix(block.props.caption)
            if let source = block.props.source, let url = absolute(source) {
                if block.kind.isMedia, let imported = try? environment.importAsset(from: url) { copy.props.source = imported }
                else if !block.kind.isMedia { copy.props.source = relink(source) }
            }
            if let target = block.props.target, absolute(target) != nil { copy.props.target = relink(target) }
            if var table = block.props.table {
                table.rows = table.rows.map { $0.map(fix) }
                copy.props.table = table
            }
            copy.children = block.children.map(walk)
            return copy
        }
        return archive.blocks.map(walk)
    }

    private static func trimmedTrailingNewlines(_ value: String) -> String {
        var result = value
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}

final class NoteRichTextProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    @MainActor private static var live: [NoteRichTextProvider] = []
    private let html: String
    private let base: URL?

    init(html: String, base: URL?) {
        self.html = html
        self.base = base
    }

    @MainActor
    static func retain(_ provider: NoteRichTextProvider) {
        live.append(provider)
        if live.count > 4 { live.removeFirst(live.count - 4) }
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .rtf, let data = html.data(using: .utf8) else { return }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let base { options[.baseURL] = base }
        guard let rich = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
              let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) else { return }
        item.setData(rtf, forType: .rtf)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NoteRichTextProvider.live.removeAll { $0 === self } }
        }
    }
}
