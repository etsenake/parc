import Foundation

extension SidebarImport {
    package struct Note: Equatable {
        package struct Image: Equatable {
            let data: Data
            let fileExtension: String
        }

        let id: String
        let title: String
        let page: NotePage
        var images: [String: Image] = [:]
        var droppedImages = 0

        package init(id: String, title: String, page: NotePage, images: [String: Image] = [:], droppedImages: Int = 0) {
            self.id = id
            self.title = title
            self.page = page
            self.images = images
            self.droppedImages = droppedImages
        }

        package var markdown: String { NoteMarkdown.serialize(page) }
    }
}

package enum ArcNotesImport {
    static let maximumFileSize = 32 * 1024 * 1024
    static let maximumTotalSize = 512 * 1024 * 1024
    static let maximumFiles = 10_000
    static let maximumBlocks = 100_000
    static let maximumDepth = 64
    static let maximumListLevel = 8
    static let imagePrefix = "arc-note-image-"

    package static func notes(in directory: URL, read: (URL) throws -> Data = { try Data(contentsOf: $0) }) -> [SidebarImport.Note] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        var result: [SidebarImport.Note] = [], seen = Set<String>(), total = 0
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(maximumFiles) {
            let kind = url.pathExtension.lowercased()
            guard ["json", "html", "htm"].contains(kind), let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, let size = values.fileSize, size <= maximumFileSize,
                  total + size <= maximumTotalSize, let data = try? read(url) else { continue }
            total += size
            let stem = url.deletingPathExtension().lastPathComponent
            let found = kind == "json" ? notes(json: data, name: stem) : html(data, name: stem).map { [$0] } ?? []
            for note in found where seen.insert(note.id).inserted { result.append(note) }
        }
        return result
    }

    package static func notes(json data: Data, name: String) -> [SidebarImport.Note] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let entries = object as? [Any] ?? [object]
        return entries.prefix(maximumFiles).compactMap { entry in
            (entry as? [String: Any]).flatMap { note($0, fallbackID: entries.count == 1 ? name : nil) }
        }
    }

    package static func html(_ data: Data, name: String) -> SidebarImport.Note? {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let title = htmlTitle(html) ?? name
        var builder = PageBuilder()
        builder.html(html, title: title)
        return builder.note(id: name, title: title)
    }

    static func note(_ entry: [String: Any], fallbackID: String?) -> SidebarImport.Note? {
        let document = unwrap(entry["arcDocument"]) as? [String: Any] ?? unwrap(entry["document"]) as? [String: Any] ?? entry
        guard let id = nonEmpty(document["id"] as? String) ?? nonEmpty(entry["id"] as? String) ?? fallbackID else { return nil }
        let title = text(document["title"]) ?? ""
        var builder = PageBuilder()
        if let html = document["html"] as? String {
            builder.html(html, title: title)
        } else if let scratchpad = scratchpad(document["data"] ?? document["scratchpad"]) {
            builder.scratchpad(scratchpad)
        } else if document["title"] == nil {
            return nil
        }
        return builder.note(id: id, title: title)
    }

    package static func markdown(text: String, properties: [Any]) -> String {
        var builder = PageBuilder()
        builder.richText(text, properties: properties)
        return builder.note(id: "", title: "").markdown
    }

    package static func markdown(scratchpad: [String: Any]) -> String {
        var builder = PageBuilder()
        builder.scratchpad(scratchpad)
        return builder.note(id: "", title: "").markdown
    }

    private static func scratchpad(_ value: Any?) -> [String: Any]? {
        guard let data = unwrap(value) as? [String: Any] else { return nil }
        if data["blocks"] != nil || data["rootBlocks"] != nil { return data }
        return unwrap(data["scratchpad"]) as? [String: Any]
    }

    static func unwrap(_ value: Any?) -> Any? {
        var current = value
        for _ in 0..<8 {
            guard let dictionary = current as? [String: Any], dictionary.count == 1, let inner = dictionary["_0"] else { break }
            current = inner
        }
        return current
    }

    static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    private static func text(_ value: Any?) -> String? {
        switch unwrap(value) {
        case let string as String: return string
        case let dictionary as [String: Any]: return (unwrap(dictionary["value"]) ?? unwrap(dictionary["text"])) as? String
        default: return nil
        }
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let close = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: close.upperBound..<html.endIndex) else { return nil }
        return nonEmpty(NoteHTMLEntities.decode(String(html[close.upperBound..<end.lowerBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    enum ImageSource: Equatable {
        case data(Data, String)
        case remote(String)
        case unreadable
    }

    enum LineKind: Equatable {
        case paragraph
        case heading(Int)
        case bulleted(Int)
        case numbered(Int)
        case todo(Bool, Int)
        case quote
        case code(String)

        var priority: Int {
            switch self {
            case .code: return 5
            case .heading: return 4
            case .todo: return 3
            case .bulleted, .numbered: return 2
            case .quote: return 1
            case .paragraph: return 0
            }
        }
    }

    enum Format: Equatable {
        case bold, italic, underline, strikethrough, code
        case link(String?)
        case heading(Int)
        case list(ordered: Bool, level: Int)
        case todo(checked: Bool, level: Int)
        case quote
        case codeBlock(String)
        case image(ImageSource)

        var level: Int? {
            switch self {
            case .list(_, let level), .todo(_, let level): return level
            default: return nil
            }
        }
    }

    static func format(_ raw: Any?) -> Format? {
        let value = unwrap(raw)
        if let name = value as? String { return named(name, payload: nil) }
        guard let dictionary = value as? [String: Any] else { return nil }
        if let name = dictionary["type"] as? String { return named(name, payload: dictionary) }
        guard dictionary.count == 1, let entry = dictionary.first else { return nil }
        return named(entry.key, payload: unwrap(entry.value))
    }

    private static func named(_ raw: String, payload: Any?) -> Format? {
        let name = raw.lowercased().filter { $0 != "_" && $0 != "-" && $0 != " " }
        let fields = payload as? [String: Any] ?? [:]
        let level = integer(fields["level"] ?? fields["indent"] ?? fields["depth"] ?? payload) ?? 0
        switch name {
        case "bold", "strong": return .bold
        case "italic", "italics", "emphasis": return .italic
        case "underline", "underlined": return .underline
        case "strikethrough", "strike": return .strikethrough
        case "code", "inlinecode", "monospace", "monospaced": return .code
        case "h1", "heading1", "title": return .heading(1)
        case "h2", "heading2", "subtitle": return .heading(2)
        case "h3", "heading3": return .heading(3)
        case "h4", "heading4": return .heading(4)
        case "h5", "heading5": return .heading(5)
        case "h6", "heading6": return .heading(6)
        case "heading", "header": return .heading(min(6, max(1, integer(fields["level"] ?? payload) ?? 1)))
        case "hyperlink", "link", "formattedhyperlink", "url": return .link(url(payload))
        case "unorderedlist", "bulletlist", "bulletedlist", "bullet", "bullets": return .list(ordered: false, level: level)
        case "orderedlist", "numberedlist", "numbered", "numbers": return .list(ordered: true, level: level)
        case "checklist", "checkbox", "todo", "todolist", "tasklist", "task", "checklistitem":
            return .todo(checked: checked(payload), level: level)
        case "checked", "done", "completed": return .todo(checked: true, level: level)
        case "unchecked": return .todo(checked: false, level: level)
        case "quote", "blockquote", "quotation": return .quote
        case "codeblock", "preformatted", "pre":
            return .codeBlock((fields["language"] as? String ?? fields["lang"] as? String ?? "").trimmingCharacters(in: .whitespaces))
        case "image", "attachment", "inlineimage", "picture": return .image(imageSource(payload))
        default: return nil
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = unwrap(value) as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite else { return nil }
        return Int(max(-1_000, min(1_000, double)))
    }

    private static func checked(_ payload: Any?) -> Bool {
        if let flag = unwrap(payload) as? Bool { return flag }
        guard let fields = unwrap(payload) as? [String: Any] else { return false }
        for key in ["checked", "isChecked", "done", "isDone", "completed", "isCompleted", "state"] {
            if let flag = unwrap(fields[key]) as? Bool { return flag }
            if let state = unwrap(fields[key]) as? String { return ["checked", "done", "completed", "on"].contains(state.lowercased()) }
            if let state = unwrap(fields[key]) as? [String: Any], state.count == 1, let name = state.keys.first {
                return ["checked", "done", "completed", "on"].contains(name.lowercased())
            }
        }
        return false
    }

    private static func url(_ payload: Any?) -> String? {
        switch unwrap(payload) {
        case let string as String: return nonEmpty(string)
        case let fields as [String: Any]:
            for key in ["url", "href", "link", "relative", "absoluteString", "_0"] {
                if let found = url(fields[key]) { return found }
            }
            return nil
        default: return nil
        }
    }

    static func imageSource(_ payload: Any?, depth: Int = 0) -> ImageSource {
        guard depth < 6 else { return .unreadable }
        switch unwrap(payload) {
        case let string as String: return source(string) ?? .unreadable
        case let fields as [String: Any]:
            let preferred = ["data", "base64", "png", "jpeg", "imageData", "url", "src", "source"]
            for key in preferred.filter({ fields[$0] != nil }) + fields.keys.sorted().filter({ !preferred.contains($0) }) {
                let found = imageSource(fields[key], depth: depth + 1)
                if found != .unreadable { return found }
            }
            return .unreadable
        case let list as [Any]:
            for value in list.prefix(8) {
                let found = imageSource(value, depth: depth + 1)
                if found != .unreadable { return found }
            }
            return .unreadable
        default: return .unreadable
        }
    }

    private static func source(_ raw: String) -> ImageSource? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("data:") { return dataURL(trimmed).map { .data($0.data, $0.fileExtension) } }
        if lowered.hasPrefix("https://") || lowered.hasPrefix("http://") { return URL(string: trimmed) == nil ? nil : .remote(trimmed) }
        guard trimmed.utf8.count > 16, trimmed.utf8.count <= maximumFileSize * 4 / 3 + 4,
              let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              data.count <= maximumFileSize, let kind = sniff(data) else { return nil }
        return .data(data, kind)
    }

    static func dataURL(_ value: String) -> (data: Data, fileExtension: String)? {
        guard value.utf8.count <= maximumFileSize * 4 / 3 + 256, let comma = value.firstIndex(of: ",") else { return nil }
        let header = value[value.index(value.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(value[value.index(after: comma)...])
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let data = parts.contains("base64") ? Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            : payload.removingPercentEncoding.map { Data($0.utf8) }
        guard let data, !data.isEmpty, data.count <= maximumFileSize else { return nil }
        let types = ["image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/gif": "gif", "image/webp": "webp",
                     "image/heic": "heic", "image/heif": "heif", "image/svg+xml": "svg", "image/tiff": "tiff",
                     "image/bmp": "bmp", "image/avif": "avif"]
        guard let kind = parts.first.flatMap({ types[$0] }) ?? sniff(data) else { return nil }
        return (data, kind)
    }

    static func sniff(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.starts(with: prefix) }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts(Array("GIF8".utf8)) { return "gif" }
        if starts(Array("RIFF".utf8)), bytes.count >= 12, Array(bytes[8..<12]) == Array("WEBP".utf8) { return "webp" }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            if brand.hasPrefix("avi") { return "avif" }
            if ["heic", "heix", "mif1", "msf1", "heim", "heis"].contains(brand) { return "heic" }
        }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if starts([0x42, 0x4D]) { return "bmp" }
        return nil
    }

    static func range(_ value: Any?, count: Int) -> Range<Int>? {
        var location: Int?, length: Int?
        switch unwrap(value) {
        case let fields as [String: Any]:
            if let lower = integer(fields["lowerBound"]), let upper = integer(fields["upperBound"]) {
                location = lower; length = upper - lower
            } else {
                location = integer(fields["location"]); length = integer(fields["length"])
            }
        case let list as [Any] where list.count == 2:
            location = integer(list[0]); length = integer(list[1])
        case let string as String:
            let parsed = NSRangeFromString(string)
            if string.contains(where: \.isNumber) { location = parsed.location; length = parsed.length }
        default: break
        }
        guard let location, let length, location >= 0, length >= 0, location <= count else { return nil }
        return location..<min(count, location + length)
    }

    struct PageBuilder {
        var blocks: [NoteBlock] = []
        var images: [String: SidebarImport.Note.Image] = [:]
        var dropped = 0
        private var blockCount = 0

        func note(id: String, title: String) -> SidebarImport.Note {
            SidebarImport.Note(id: id, title: title, page: NotePage(blocks: blocks), images: images, droppedImages: dropped)
        }

        mutating func html(_ html: String, title: String) {
            var found = NoteHTMLReader.blocks(from: html, baseURL: nil)
            if let first = found.first, first.kind == .heading,
               first.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines) == title.trimmingCharacters(in: .whitespacesAndNewlines) {
                found.removeFirst()
            }
            blocks += attaching(found)
        }

        private mutating func attaching(_ found: [NoteBlock]) -> [NoteBlock] {
            var result: [NoteBlock] = []
            for var block in found {
                block.children = attaching(block.children)
                if block.kind == .image, let source = block.props.source, source.lowercased().hasPrefix("data:") {
                    guard let decoded = ArcNotesImport.dataURL(source) else { dropped += 1; continue }
                    block.props.source = attachment(decoded.data, fileExtension: decoded.fileExtension)
                }
                result.append(block)
            }
            return result
        }

        private mutating func attachment(_ data: Data, fileExtension: String) -> String {
            let token = ArcNotesImport.imagePrefix + String(images.count) + "." + fileExtension
            images[token] = SidebarImport.Note.Image(data: data, fileExtension: fileExtension)
            return token
        }

        mutating func scratchpad(_ pad: [String: Any]) {
            var map: [String: [String: Any]] = [:], order: [String] = []
            func add(_ key: String?, _ value: Any?) {
                guard let block = ArcNotesImport.unwrap(value) as? [String: Any],
                      let id = key ?? block["id"] as? String, map[id] == nil, map.count < ArcNotesImport.maximumBlocks else { return }
                map[id] = block
                order.append(id)
            }
            switch ArcNotesImport.unwrap(pad["blocks"]) {
            case let dictionary as [String: Any]:
                for key in dictionary.keys.sorted() { add(key, dictionary[key]) }
            case let list as [Any]:
                if list.first is String {
                    for (key, value) in SidebarImport.arcPairs(list) { add(key as? String, value) }
                } else {
                    for value in list { add(nil, value) }
                }
            default: break
            }
            let roots = (pad["rootBlocks"] as? [Any] ?? []).compactMap { $0 as? String }.filter { map[$0] != nil }
            var visited = Set<String>()
            func render(_ id: String, depth: Int) {
                guard depth < ArcNotesImport.maximumDepth, visited.insert(id).inserted, let block = map[id] else { return }
                if let text = block["text"] as? String {
                    richText(text, properties: ArcNotesImport.unwrap(block["properties"]) as? [Any] ?? [])
                }
                for child in block["content"] as? [Any] ?? [] {
                    if let child = child as? String, map[child] != nil { render(child, depth: depth + 1) }
                }
            }
            for id in roots.isEmpty ? order : roots { render(id, depth: 0) }
        }

        mutating func richText(_ text: String, properties: [Any]) {
            let units = Array(text.utf16)
            var formats: [(range: Range<Int>, format: Format)] = []
            for property in properties.prefix(ArcNotesImport.maximumBlocks) {
                guard let fields = ArcNotesImport.unwrap(property) as? [String: Any] else { continue }
                let rich = ArcNotesImport.unwrap(fields["richText"]) as? [String: Any] ?? fields
                guard let range = ArcNotesImport.range(rich["range"], count: units.count),
                      let format = ArcNotesImport.format(rich["value"] ?? rich["format"] ?? rich["type"]) else { continue }
                formats.append((range, format))
            }
            let base = formats.compactMap({ $0.format.level }).min() ?? 0
            func depth(_ level: Int) -> Int { min(ArcNotesImport.maximumListLevel, max(0, level - base)) }
            var inline = [NoteMarks](repeating: .plain, count: units.count)
            var lines: [(range: Range<Int>, kind: LineKind)] = []
            var pictures: [Int: [ImageSource]] = [:]
            var covered = Set<Int>()
            for (range, format) in formats {
                switch format {
                case .bold: for index in range { inline[index].bold = true }
                case .italic: for index in range { inline[index].italic = true }
                case .underline: for index in range { inline[index].underline = true }
                case .strikethrough: for index in range { inline[index].strikethrough = true }
                case .code: for index in range { inline[index].code = true }
                case .link(let url):
                    guard let target = url ?? Self.bareLink(units[range]) else { continue }
                    for index in range { inline[index].link = target }
                case .heading(let level): lines.append((range, .heading(level)))
                case let .list(ordered, level): lines.append((range, ordered ? .numbered(depth(level)) : .bulleted(depth(level))))
                case let .todo(checked, level): lines.append((range, .todo(checked, depth(level))))
                case .quote: lines.append((range, .quote))
                case .codeBlock(let language): lines.append((range, .code(language)))
                case .image(let source):
                    pictures[range.lowerBound, default: []].append(source)
                    covered.formUnion(range)
                }
            }
            var spans: [Range<Int>] = []
            var start = 0
            for (index, unit) in units.enumerated() where unit == 0x0A {
                spans.append(start..<index)
                start = index + 1
            }
            if start < units.count || pictures[units.count] != nil { spans.append(start..<units.count) }

            var entries: [(block: NoteBlock, level: Int?)] = []
            var code: (language: String, lines: [String])?
            func flushCode() {
                guard let pending = code else { return }
                var props = NoteBlockProps()
                props.language = pending.language
                entries.append((NoteBlock(.code, text: NoteText(pending.lines.joined(separator: "\n")), props: props), nil))
                code = nil
            }
            func kind(_ probe: Range<Int>) -> LineKind {
                var best = LineKind.paragraph
                for line in lines where line.range.lowerBound < probe.upperBound && line.range.upperBound > probe.lowerBound
                    || (line.range.isEmpty && probe.contains(line.range.lowerBound)) {
                    if line.kind.priority > best.priority { best = line.kind }
                }
                return best
            }
            for span in spans {
                var end = span.upperBound
                while end > span.lowerBound, units[end - 1] == 0x0D { end -= 1 }
                let content = span.lowerBound..<end
                let lineKind = kind(span.lowerBound..<min(units.count, span.upperBound + 1))
                if case .code(let language) = lineKind {
                    if code?.language != language { flushCode(); code = (language, []) }
                    code?.lines.append(String(decoding: units[content].filter { $0 != 0xFFFC }, as: UTF16.self))
                    continue
                }
                flushCode()
                var pieces: [(String, NoteMarks)] = [], run: [UInt16] = [], runMarks = NoteMarks.plain
                func flushRun() {
                    if !run.isEmpty { pieces.append((String(decoding: run, as: UTF16.self), runMarks)) }
                    run = []
                }
                func flushText() {
                    flushRun()
                    let value = NoteText(pieces: pieces)
                    pieces = []
                    guard !value.string.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    entries.append(Self.block(lineKind, value))
                }
                func place(_ sources: [ImageSource]) {
                    for source in sources {
                        flushText()
                        if let block = picture(source) { entries.append((block, nil)) }
                    }
                }
                for index in content {
                    if let sources = pictures[index] { place(sources) }
                    let unit = units[index]
                    if unit == 0xFFFC {
                        if !covered.contains(index) { dropped += 1 }
                        continue
                    }
                    if inline[index] != runMarks { flushRun(); runMarks = inline[index] }
                    run.append(unit)
                }
                for index in content.upperBound...span.upperBound {
                    if let sources = pictures[index] { place(sources) }
                }
                flushText()
            }
            flushCode()
            blocks += Self.nest(entries[...])
        }

        private mutating func picture(_ source: ImageSource) -> NoteBlock? {
            var block = NoteBlock(.image)
            switch source {
            case let .data(data, fileExtension): block.props.source = attachment(data, fileExtension: fileExtension)
            case .remote(let url): block.props.source = url
            case .unreadable: dropped += 1; return nil
            }
            return block
        }

        private static func block(_ kind: LineKind, _ text: NoteText) -> (block: NoteBlock, level: Int?) {
            switch kind {
            case .paragraph, .code: return (.paragraph(text), nil)
            case .heading(let level): return (.heading(level, text), nil)
            case .bulleted(let level): return (NoteBlock(.bulletedItem, text: text), level)
            case .numbered(let level): return (NoteBlock(.numberedItem, text: text), level)
            case let .todo(checked, level):
                var props = NoteBlockProps()
                props.checked = checked
                return (NoteBlock(.todo, text: text, props: props), level)
            case .quote: return (NoteBlock(.quote, text: text), nil)
            }
        }

        private static func bareLink(_ units: ArraySlice<UInt16>) -> String? {
            let value = String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.lowercased().hasPrefix("www."), !value.contains(" ") { return "https://" + value }
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return nil }
            return value
        }

        static func nest(_ entries: ArraySlice<(block: NoteBlock, level: Int?)>) -> [NoteBlock] {
            var result: [NoteBlock] = []
            var index = entries.startIndex
            while index < entries.endIndex {
                var entry = entries[index]
                index += 1
                guard let level = entry.level else { result.append(entry.block); continue }
                var end = index
                while end < entries.endIndex, let deeper = entries[end].level, deeper > level { end += 1 }
                entry.block.children += nest(entries[index..<end])
                index = end
                result.append(entry.block)
            }
            return result
        }
    }
}

@MainActor
final class SidebarImportNoteWriter {
    typealias Item = SidebarImport.Item
    typealias Tab = SidebarImport.Tab

    private let provided: NoteFiles?
    private let date: Date
    private var written: [String: URL] = [:]
    private lazy var files: NoteFiles = provided ?? .shared

    init(files: NoteFiles?, date: Date) {
        provided = files
        self.date = date
    }

    func resolving(_ items: [Item], profileID: UUID) -> [Item] {
        var result: [Item] = []
        for item in items {
            switch item {
            case .tab(let tab):
                if tab.note == nil { result.append(item) } else if let resolved = resolved(tab, profileID: profileID) {
                    result.append(.tab(resolved))
                }
            case let .folder(title, icon, children, isExpanded):
                result.append(.folder(title: title, icon: icon, children: resolving(children, profileID: profileID),
                                      isExpanded: isExpanded))
            case let .split(title, icon, tabs, orientation, factors):
                guard tabs.contains(where: { $0.note != nil }) else { result.append(item); continue }
                let kept = resolvedTabs(tabs, profileID: profileID)
                if kept.count == tabs.count {
                    result.append(.split(title: title, icon: icon, tabs: kept, orientation: orientation, widthFactors: factors))
                } else if kept.count > 1 {
                    result.append(.split(title: title, icon: icon, tabs: kept, orientation: orientation,
                                         widthFactors: Array(repeating: 1 / Double(kept.count), count: kept.count)))
                } else {
                    result += kept.map(Item.tab)
                }
            case let .stackedSplit(title, icon, tabs, orientation, stacks):
                guard tabs.contains(where: { $0.note != nil }) else { result.append(item); continue }
                let kept = resolvedTabs(tabs, profileID: profileID)
                if kept.count == tabs.count {
                    result.append(.stackedSplit(title: title, icon: icon, tabs: kept, orientation: orientation, stacks: stacks))
                } else {
                    result += kept.map(Item.tab)
                }
            }
        }
        return result
    }

    func write(_ notes: [SidebarImport.Note], profileID: UUID) {
        for note in notes { _ = file(for: note, profileID: profileID) }
    }

    private func resolvedTabs(_ tabs: [Tab], profileID: UUID) -> [Tab] {
        var kept: [Tab] = []
        for tab in tabs {
            if tab.note == nil { kept.append(tab) } else if let resolved = resolved(tab, profileID: profileID) { kept.append(resolved) }
        }
        return kept
    }

    private func resolved(_ tab: Tab, profileID: UUID) -> Tab? {
        guard let note = tab.note, let url = file(for: note, profileID: profileID) else { return nil }
        let title = InternalPage.noteTitle(url.deletingPathExtension().lastPathComponent, file: url)
        return Tab(title: title, url: InternalPage.note(url).urlString, isMuted: tab.isMuted, isUnread: tab.isUnread)
    }

    private func file(for note: SidebarImport.Note, profileID: UUID) -> URL? {
        let folder = NoteFilePaths.canonical(files.folders.folder(for: profileID))
        let key = folder.path + "\n" + note.id
        if let url = written[key] { return url }
        guard let url = existing(note, in: folder) ?? create(note, in: folder) else { return nil }
        written[key] = url
        return url
    }

    private func existing(_ note: SidebarImport.Note, in folder: URL) -> URL? {
        var base = NoteFileNaming.sanitizedTitle(note.title)
        if base.isEmpty { base = NoteFileNaming.untitled }
        let expected = Self.comparable(note.markdown)
        var misses = 0
        for candidate in NoteFileNaming.candidates(in: folder, base: base, pathExtension: "md").prefix(1_000) {
            guard NoteFilePaths.itemExists(candidate) else {
                misses += 1
                if misses > 20 { return nil }
                continue
            }
            misses = 0
            guard let size = (try? FileManager.default.attributesOfItem(atPath: candidate.path))?[.size] as? Int,
                  size <= ArcNotesImport.maximumFileSize * 2, let data = try? Data(contentsOf: candidate),
                  let text = String(data: data, encoding: .utf8) else { continue }
            if Self.comparable(text) == expected { return candidate }
        }
        return nil
    }

    private func create(_ note: SidebarImport.Note, in folder: URL) -> URL? {
        guard let url = try? files.createNote(in: folder, title: note.title) else { return nil }
        var page = note.page
        if let current = try? String(contentsOf: url, encoding: .utf8), !current.isEmpty {
            page.settings = NoteMarkdown.parse(current).settings
        }
        page.blocks = placing(note.images, in: page.blocks, note: url)
        do {
            try Data(NoteMarkdown.serialize(page).utf8).write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: url)
            files.filesRewritten([url])
            return nil
        }
        files.filesRewritten([url])
        return url
    }

    private func placing(_ images: [String: SidebarImport.Note.Image], in blocks: [NoteBlock], note: URL) -> [NoteBlock] {
        guard !images.isEmpty else { return blocks }
        var result: [NoteBlock] = []
        for var block in blocks {
            block.children = placing(images, in: block.children, note: note)
            if block.kind == .image, let source = block.props.source, let image = images[source] {
                guard let placement = try? NoteAttachments.placeData(image.data, fileExtension: image.fileExtension,
                                                                     suggestedName: nil, into: note, date: date) else { continue }
                block.props.source = placement.path
            }
            result.append(block)
        }
        return result
    }

    private static func comparable(_ markdown: String) -> String {
        func blank(_ blocks: [NoteBlock]) -> [NoteBlock] {
            blocks.map { block in
                var copy = block
                copy.children = blank(block.children)
                if copy.kind == .image { copy.props.source = "image.png" }
                return copy
            }
        }
        return NoteMarkdown.serialize(NotePage(blocks: blank(NoteMarkdown.parse(markdown).blocks)))
    }
}
