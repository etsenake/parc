import AppKit
import ParcCore
import UniformTypeIdentifiers

extension NoteClipboard {
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

    private static let embeddableHosts: [String] = [
        "youtube.com", "youtu.be", "vimeo.com", "loom.com", "twitter.com", "x.com", "figma.com", "codepen.io",
        "codesandbox.io", "spotify.com", "soundcloud.com", "maps.google.com", "google.com/maps", "gist.github.com",
        "docs.google.com", "drive.google.com", "miro.com", "typeform.com", "airtable.com", "replit.com",
        "excalidraw.com", "tiktok.com", "instagram.com", "music.apple.com", "podcasts.apple.com",
    ]

    static func mediaKind(forContentType contentType: String?) -> NoteBlockKind? {
        guard let type = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased(), !type.isEmpty else { return nil }
        if type == "application/pdf" { return .pdf }
        if type == "image/svg+xml" { return .image }
        if type.hasPrefix("image/") { return .image }
        if type.hasPrefix("video/") { return .video }
        if type.hasPrefix("audio/") { return .audio }
        return nil
    }

    package static func playsAsEmbed(_ url: URL, kind: NoteBlockKind) -> Bool {
        (kind == .video || kind == .audio) && isEmbeddable(url)
    }

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

    package static func linkedMediaKind(_ url: URL) -> NoteBlockKind? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        let kind = mediaKind(for: url)
        return kind == .file ? nil : kind
    }

    static func mediaKind(for url: URL) -> NoteBlockKind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .file }
        if type.conforms(to: .pdf) { return .pdf }
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
                var props = NoteBlockProps()
                props.source = try NoteMediaImport.source(importing: url, environment: environment)
                let kind = mediaKind(for: url)
                if kind == .image { props.alt = url.deletingPathExtension().lastPathComponent }
                if kind == .file { props.caption = NoteText(url.lastPathComponent) }
                if kind == .pdf { props.alt = url.lastPathComponent }
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
        var props = NoteBlockProps()
        props.source = try NoteMediaImport.source(importing: data, fileExtension: fileExtension, suggestedName: "Pasted Image", environment: environment)
        return NoteBlock(.image, props: props)
    }

    static func isMediaDataURL(_ source: String) -> Bool { mediaDataURLHeader(source) != nil }

    private static func mediaDataURLHeader(_ source: String) -> (mime: String, base64: Bool, comma: String.Index)? {
        guard source.prefix(5).lowercased() == "data:", let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[source.index(source.startIndex, offsetBy: 5)..<comma].lowercased()
        let parts = header.split(separator: ";").map(String.init)
        guard let mime = parts.first, mime.hasPrefix("image/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/") else { return nil }
        return (mime, parts.contains("base64"), comma)
    }

    package static func decodeDataURL(_ source: String) -> (data: Data, fileExtension: String)? {
        guard let header = mediaDataURLHeader(source) else { return nil }
        let mime = header.mime
        let payload = String(source[source.index(after: header.comma)...])
        let data: Data?
        if header.base64 {
            data = Data(base64Encoded: payload.filter { !$0.isWhitespace }, options: .ignoreUnknownCharacters)
        } else {
            data = payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        guard let data, !data.isEmpty else { return nil }
        let subtype = String(mime.split(separator: "/").last ?? "png")
        let known: [String: String] = ["jpeg": "jpg", "svg+xml": "svg", "x-icon": "ico", "vnd.microsoft.icon": "ico", "quicktime": "mov", "mpeg": "mp3"]
        return (data, known[subtype] ?? subtype)
    }

    @MainActor
    static func importInlineMedia(_ blocks: [NoteBlock], environment: NoteEnvironment) -> (blocks: [NoteBlock], failures: [Error]) {
        var failures: [Error] = []
        func walk(_ block: NoteBlock) -> NoteBlock {
            var copy = block
            if block.kind.isMedia, let source = block.props.source, isMediaDataURL(source) {
                do {
                    copy.props.source = try NoteMediaImport.source(importingDataURL: source,
                                                                   suggestedName: "Pasted " + (block.kind == .image ? "Image" : "File"),
                                                                   environment: environment)
                } catch {
                    failures.append(error)
                }
            }
            copy.children = block.children.map(walk)
            return copy
        }
        return (blocks.map(walk), failures)
    }

    package static func trustedMediaFolder(_ base: URL) -> URL? {
        guard base.isFileURL else { return nil }
        let folder = NoteFilePaths.canonical(URL(fileURLWithPath: base.standardizedFileURL.path, isDirectory: true))
        let components = folder.pathComponents
        guard components.count > 1, !components.dropFirst().contains(where: { $0.hasPrefix(".") }) else { return nil }
        let home = NoteFilePaths.canonical(FileManager.default.homeDirectoryForCurrentUser)
        if folder.path == home.path || NoteFilePaths.isSameFile(folder, home) || NoteFilePaths.contains(folder: folder, item: home) { return nil }
        if (try? folder.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true { return nil }
        return folder
    }

    package static func mayImportMedia(_ file: URL, from base: URL, trusted folder: URL) -> Bool {
        let root = URL(fileURLWithPath: base.standardizedFileURL.path, isDirectory: true).standardizedFileURL.pathComponents
        let path = file.standardizedFileURL.pathComponents
        guard path.count > root.count, Array(path.prefix(root.count)) == root,
              !path.dropFirst(root.count).contains(where: { $0.hasPrefix(".") }) else { return false }
        return NoteFilePaths.contains(folder: folder, item: file)
    }

    @MainActor
    static func rebase(_ archive: Archive, into environment: NoteEnvironment) -> [NoteBlock] {
        let destination = environment.documentURL?.deletingLastPathComponent().standardizedFileURL
        let base = archive.base.flatMap { written -> URL? in
            guard written.isFileURL else { return nil }
            let folder = URL(fileURLWithPath: written.standardizedFileURL.path, isDirectory: true).standardizedFileURL
            return folder == destination ? nil : folder
        }
        let imports = NoteMediaImport.imports(for: environment)
        let carries = archive.blocks.contains { carriesImport($0, imports: imports) }
        guard base != nil || carries else { return archive.blocks }
        let mediaFolder = base.flatMap(trustedMediaFolder)
        func absolute(_ source: String) -> URL? {
            guard let base, !source.isEmpty, URL(string: source)?.scheme == nil, !source.hasPrefix("/"), !source.hasPrefix("#") else { return nil }
            let decoded = source.removingPercentEncoding ?? source
            return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
        }
        func importedMedia(_ url: URL) -> String? {
            guard let base, let mediaFolder, mayImportMedia(url, from: base, trusted: mediaFolder) else { return nil }
            return try? NoteMediaImport.source(importing: url, environment: environment)
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
            if let source = block.props.source {
                if block.kind.isMedia, let carried = NoteMediaImport.carriedSource(source, environment: environment) {
                    copy.props.source = carried
                } else if let url = absolute(source) {
                    if block.kind.isMedia, let imported = importedMedia(url) { copy.props.source = imported }
                    else if !block.kind.isMedia { copy.props.source = relink(source) }
                }
            }
            if copy.props.source != block.props.source { copy.props.capture?.snapshot = nil }
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

    @MainActor
    private static func carriesImport(_ block: NoteBlock, imports: NoteAttachmentImports) -> Bool {
        if block.kind.isMedia, let source = block.props.source, let url = URL(string: source), url.isFileURL,
           imports.mayImport(url) { return true }
        return block.children.contains { carriesImport($0, imports: imports) }
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
        guard type == .rtf, let data = NoteOfflineHTML.scrub(html).data(using: .utf8) else { return }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let base, base.isFileURL { options[.baseURL] = base }
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

enum NoteOfflineHTML {
    private struct Attribute {
        var name: String
        var value: String?
        var raw: String
    }

    private struct Tag {
        var name: String
        var attributes: [Attribute]
        var selfClosing: Bool
        var end: Int

        func value(_ key: String) -> String? { attributes.first { $0.name == key }?.value }
    }

    private static let droppedWithContent: Set<String> = [
        "script", "iframe", "object", "applet", "frameset", "noembed", "noframes", "template", "portal", "fencedframe",
    ]
    private static let droppedTags: Set<String> = ["base", "link", "meta", "embed", "source", "track", "param", "frame", "bgsound", "keygen"]
    private static let pictureTags: Set<String> = ["img", "image"]
    private static let primarySources: Set<String> = ["src", "href", "xlink:href"]
    private static let resourceAttributes: Set<String> = [
        "src", "poster", "background", "lowsrc", "dynsrc", "data", "codebase", "archive", "longdesc", "profile", "manifest", "icon", "ping",
    ]
    private static let candidateAttributes: Set<String> = ["srcset", "imagesrcset"]
    private static let linkTags: Set<String> = ["a", "area"]
    private static let localSchemes: Set<String> = ["file", "data", "about", "cid"]
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "colon": ":", "sol": "/", "bsol": "\\", "period": ".",
        "tab": "\t", "newline": "\n", "nbsp": " ", "num": "#", "quest": "?", "lpar": "(", "rpar": ")",
    ]

    static func scrub(_ html: String) -> String {
        let input = Array(html.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        func append(_ text: String) { output.append(contentsOf: text.unicodeScalars) }
        while index < input.count {
            guard input[index] == "<" else {
                let next = input[index...].firstIndex(of: "<") ?? input.count
                output.append(contentsOf: input[index..<next])
                index = next
                continue
            }
            if starts(input, at: index, with: "<!--") {
                index = find(input, "-->", from: index + 4).map { $0 + 3 } ?? input.count
                continue
            }
            guard index + 1 < input.count else { append("&lt;"); index += 1; continue }
            let next = input[index + 1]
            if next == "!" || next == "?" || next == "/" {
                let end = (input[(index + 1)...].firstIndex(of: ">") ?? input.count - 1) + 1
                output.append(contentsOf: input[index..<end])
                index = end
                continue
            }
            guard next.isASCII, next.properties.isAlphabetic, let tag = parseTag(input, at: index) else {
                if next.isASCII, next.properties.isAlphabetic { break }
                append("&lt;")
                index += 1
                continue
            }
            let start = index
            index = tag.end
            if droppedWithContent.contains(tag.name) {
                if !tag.selfClosing { index = closingTag(input, tag.name, from: index).map { tagEnd(input, from: $0) } ?? input.count }
                continue
            }
            if droppedTags.contains(tag.name) { continue }
            let picture = pictureTags.contains(tag.name) || (tag.name == "input" && tag.value("type")?.lowercased() == "image")
            if picture, tag.attributes.contains(where: { primarySources.contains($0.name) && refersRemotely($0, in: tag.name) }) {
                append(escapedText(tag.value("alt") ?? ""))
                continue
            }
            append(render(tag, raw: String(String.UnicodeScalarView(input[start..<tag.end]))))
            if tag.name == "style", !tag.selfClosing {
                let close = closingTag(input, "style", from: index) ?? input.count
                append(offlineCSS(String(String.UnicodeScalarView(input[index..<close]))))
                index = close
            }
        }
        return String(output)
    }

    static func offlineCSS(_ css: String) -> String {
        if css.contains("\\") {
            let decoded = cssUnescaped(css).lowercased()
            if ["url(", "@import", "image(", "image-set(", "src("].contains(where: decoded.contains) { return "" }
        }
        var result = css.replacingOccurrences(of: "@import[^;]*;?", with: "", options: [.regularExpression, .caseInsensitive])
        result = replacing(#"url\(\s*("[^"]*"|'[^']*'|[^)]*?)\s*\)"#, in: result) { match in
            let target = match.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return isRemote(target) ? "none" : nil
        }
        result = replacing(#"(?:-webkit-)?image-set\((?:[^()]|\([^()]*\))*\)"#, in: result) { match in
            let strings = match.split(whereSeparator: { $0 == "\"" || $0 == "'" }).enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
            return strings.contains(where: isRemote) ? "none" : nil
        }
        return result
    }

    static func isRemote(_ raw: String) -> Bool {
        let decoded = decodeEntities(raw)
        let compact = String(String.UnicodeScalarView(decoded.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F && !$0.properties.isWhitespace }))
        if compact.isEmpty { return false }
        if compact.hasPrefix("//") || compact.hasPrefix("\\") || compact.hasPrefix("/\\") || compact.hasPrefix("\\/") { return true }
        let head = compact.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if head.contains("&") || head.contains("\\") { return true }
        guard let colon = head.firstIndex(of: ":") else { return false }
        return !localSchemes.contains(head[..<colon].lowercased())
    }

    private static func refersRemotely(_ attribute: Attribute, in tag: String) -> Bool {
        guard let value = attribute.value else { return false }
        if candidateAttributes.contains(attribute.name) {
            return value.split(separator: ",").contains { candidate in
                isRemote(String(candidate.split(whereSeparator: \.isWhitespace).first ?? ""))
            }
        }
        let resource = resourceAttributes.contains(attribute.name)
            || ((attribute.name == "href" || attribute.name == "xlink:href") && !linkTags.contains(tag))
        return resource && isRemote(value)
    }

    private static func render(_ tag: Tag, raw: String) -> String {
        var changed = false
        var parts: [String] = []
        for attribute in tag.attributes {
            if refersRemotely(attribute, in: tag.name) {
                changed = true
                continue
            }
            if attribute.name == "style", let value = attribute.value {
                let decoded = decodeEntities(value)
                let cleaned = offlineCSS(decoded)
                if cleaned != decoded {
                    changed = true
                    parts.append("style=\"" + cleaned.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;") + "\"")
                    continue
                }
            }
            parts.append(attribute.raw)
        }
        guard changed else { return raw }
        return "<" + tag.name + parts.map { " " + $0 }.joined() + (tag.selfClosing ? " />" : ">")
    }

    private static func escapedText(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func parseTag(_ input: [Unicode.Scalar], at start: Int) -> Tag? {
        var index = start + 1
        var name = ""
        while index < input.count, isNameScalar(input[index]) { name.unicodeScalars.append(input[index]); index += 1 }
        var attributes: [Attribute] = []
        var selfClosing = false
        while index < input.count {
            let scalar = input[index]
            if scalar == ">" { return Tag(name: name.lowercased(), attributes: attributes, selfClosing: selfClosing, end: index + 1) }
            if scalar.properties.isWhitespace { index += 1; continue }
            if scalar == "/" { selfClosing = true; index += 1; continue }
            selfClosing = false
            let attributeStart = index
            var attributeName = ""
            while index < input.count, !input[index].properties.isWhitespace, input[index] != "=", input[index] != ">", input[index] != "/" {
                attributeName.unicodeScalars.append(input[index])
                index += 1
            }
            var probe = index
            while probe < input.count, input[probe].properties.isWhitespace { probe += 1 }
            var value: String?
            if probe < input.count, input[probe] == "=" {
                probe += 1
                while probe < input.count, input[probe].properties.isWhitespace { probe += 1 }
                guard probe < input.count else { return nil }
                if input[probe] == "\"" || input[probe] == "'" {
                    let quote = input[probe]
                    guard let close = input[(probe + 1)...].firstIndex(of: quote) else { return nil }
                    value = String(String.UnicodeScalarView(input[(probe + 1)..<close]))
                    index = close + 1
                } else {
                    var end = probe
                    while end < input.count, !input[end].properties.isWhitespace, input[end] != ">" { end += 1 }
                    value = String(String.UnicodeScalarView(input[probe..<end]))
                    index = end
                }
            }
            if attributeName.isEmpty { index = max(index, attributeStart + 1); continue }
            attributes.append(Attribute(name: attributeName.lowercased(), value: value,
                                        raw: String(String.UnicodeScalarView(input[attributeStart..<index]))))
        }
        return nil
    }

    private static func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "-" || scalar == ":" || scalar == "_")
    }

    private static func starts(_ input: [Unicode.Scalar], at index: Int, with prefix: String) -> Bool {
        let scalars = Array(prefix.unicodeScalars)
        guard index + scalars.count <= input.count else { return false }
        return zip(input[index..<(index + scalars.count)], scalars).allSatisfy { lowered($0) == lowered($1) }
    }

    private static func lowered(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32) ?? scalar : scalar
    }

    private static func find(_ input: [Unicode.Scalar], _ needle: String, from start: Int) -> Int? {
        var index = start
        while index < input.count {
            if starts(input, at: index, with: needle) { return index }
            index += 1
        }
        return nil
    }

    private static func closingTag(_ input: [Unicode.Scalar], _ name: String, from start: Int) -> Int? {
        var index = start
        while let found = find(input, "</" + name, from: index) {
            let after = found + 2 + name.unicodeScalars.count
            if after >= input.count || !isNameScalar(input[after]) { return found }
            index = after
        }
        return nil
    }

    private static func tagEnd(_ input: [Unicode.Scalar], from start: Int) -> Int {
        (input[start...].firstIndex(of: ">") ?? input.count - 1) + 1
    }

    private static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        let pattern = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);?")
        var result = ""
        let text = value as NSString
        var cursor = 0
        for match in pattern.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            result += text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let body = text.substring(with: match.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[body.lowercased()]
            }
            result += replacement ?? text.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        return result + text.substring(from: cursor)
    }

    private static func cssUnescaped(_ css: String) -> String {
        var output = String.UnicodeScalarView()
        let input = Array(css.unicodeScalars)
        var index = 0
        while index < input.count {
            guard input[index] == "\\", index + 1 < input.count else { output.append(input[index]); index += 1; continue }
            var hex = ""
            var probe = index + 1
            while probe < input.count, hex.count < 6, input[probe].properties.isASCIIHexDigit { hex.unicodeScalars.append(input[probe]); probe += 1 }
            if hex.isEmpty {
                output.append(input[index + 1])
                index += 2
                continue
            }
            if probe < input.count, input[probe].properties.isWhitespace { probe += 1 }
            if let scalar = UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init) { output.append(scalar) }
            index = probe
        }
        return String(output)
    }

    private static func replacing(_ pattern: String, in text: String, _ transform: (String) -> String?) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let mutable = NSMutableString(string: text)
        for match in expression.matches(in: text, range: NSRange(location: 0, length: mutable.length)).reversed() {
            let inner = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range
            if let replacement = transform(mutable.substring(with: inner)) {
                mutable.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return mutable as String
    }
}

@MainActor
package enum NoteLinkKindProbe {
    private static var known: [URL: NoteBlockKind?] = [:]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    package static func kind(of url: URL, completion: @escaping (NoteBlockKind?) -> Void) {
        if let cached = known[url] { completion(cached); return }
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        request(head) { kind, answered in
            if answered { finish(url, kind, completion); return }
            var ranged = URLRequest(url: url)
            ranged.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            request(ranged) { kind, _ in finish(url, kind, completion) }
        }
    }

    private static func request(_ request: URLRequest, completion: @escaping @MainActor (NoteBlockKind?, Bool) -> Void) {
        session.dataTask(with: request) { _, response, _ in
            let http = response as? HTTPURLResponse
            let answered = http.map { (200..<300).contains($0.statusCode) } ?? false
            let kind = answered ? NoteClipboard.mediaKind(forContentType: http?.value(forHTTPHeaderField: "Content-Type")) : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(kind, answered) } }
        }.resume()
    }

    private static func finish(_ url: URL, _ kind: NoteBlockKind?, _ completion: (NoteBlockKind?) -> Void) {
        known[url] = kind
        completion(kind)
    }
}
