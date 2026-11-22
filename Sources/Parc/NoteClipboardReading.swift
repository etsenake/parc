import AppKit
import UniformTypeIdentifiers
import ParcCore

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

    static func encode(_ archive: Archive) -> Data? {
        try? JSONEncoder().encode(archive)
    }

    static func decode(_ data: Data) -> Archive? {
        guard let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1, !archive.blocks.isEmpty else { return nil }
        return archive
    }

    static let draggedImageHTMLType = NSPasteboard.PasteboardType("org.chromium.image-html")

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
        if reading.html == nil, types.contains(draggedImageHTMLType) { reading.html = pasteboard.string(forType: draggedImageHTMLType) }
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
        let textLink = webURL(in: text) ?? easelURL(in: text)
        if reading.image != nil, text.isEmpty || textLink != nil, !htmlHasText(reading.html) { return .image }
        if textLink != nil { return .url }
        if canReadHTML, let html = reading.html, htmlHasText(html) || reading.string == nil { return .html }
        if !text.isEmpty { return looksLikeMarkdown(text) ? .markdown : .plainText }
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

    static func easelURL(in text: String) -> URL? {
        NoteEaselAddress.id(from: text).map(NoteEaselAddress.url)
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
}
