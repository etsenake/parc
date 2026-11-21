import Foundation

package enum EaselMarkdown {
    package struct Options {
        package var assetPath: (EaselItem) -> String? = { _ in nil }
        package init(assetPath: @escaping (EaselItem) -> String? = { _ in nil }) {
            self.assetPath = assetPath
        }
    }

    package static let boldTrait: UInt32 = 1 << 1
    package static let italicTrait: UInt32 = 1 << 0
    package static let monospaceTrait: UInt32 = 1 << 10
    package static let quoteMarker = "\u{258E}"

    package static func markdown(_ document: EaselDocument, options: Options = Options()) -> String {
        let body = NoteMarkdown.serialize(page(document, options: options), purpose: .export)
        return NotePageExport.markdownForCopy(body: body, title: document.title)
    }

    package static func page(_ document: EaselDocument, options: Options = Options()) -> NotePage {
        let pages = EaselPages.contentPages(document)
        var blocks: [NoteBlock] = []
        if pages.count > 1 {
            for page in pages {
                blocks.append(.heading(2, NoteText(page.name)))
                blocks += pageBlocks(EaselPages.items(on: page.id, in: document), headingLevel: 3, options: options)
            }
        } else {
            blocks = pageBlocks(EaselFinder.visibleItems(in: document), headingLevel: 2, options: options)
        }
        return NotePage(blocks: blocks)
    }

    package static func blocks(text: String, richText: EaselRichText?) -> [NoteBlock] {
        var item = EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 1, height: 1))
        item.text = text
        item.richText = richText
        return nest(paragraphs(of: item))
    }

    package static func blocks(for items: [EaselItem], options: Options = Options()) -> [NoteBlock] {
        pageBlocks(items, headingLevel: 2, options: options)
    }

    package static func pageBlocks(_ items: [EaselItem], headingLevel: Int, options: Options) -> [NoteBlock] {
        let hidden = EaselBoardObjects.hiddenIDs(in: items)
        let visible = hidden.isEmpty ? items : items.filter { !hidden.contains($0.id) }
        let sections = visible.filter { $0.kind == .section }
        func container(of item: EaselItem) -> UUID? {
            guard item.kind != .section else { return nil }
            let centerX = item.frame.x + item.frame.width / 2, centerY = item.frame.y + item.frame.height / 2
            return sections
                .filter { centerX >= $0.frame.x && centerX <= $0.frame.x + $0.frame.width
                    && centerY >= $0.frame.y && centerY <= $0.frame.y + $0.frame.height }
                .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id
        }
        var inside: [UUID: [EaselItem]] = [:]
        var flow: [EaselItem] = []
        for item in EaselFinder.readingOrder(visible) {
            if let section = container(of: item) { inside[section, default: []].append(item) } else { flow.append(item) }
        }
        var entries: [(block: NoteBlock, depth: Int)] = []
        for item in flow {
            if item.kind == .section {
                if let title = sectionTitle(item) { entries.append((.heading(headingLevel, NoteText(title)), 0)) }
                for member in inside[item.id] ?? [] { entries += blocks(for: member, options: options) }
            } else {
                entries += blocks(for: item, options: options)
            }
        }
        return nest(entries)
    }

    package static func sectionTitle(_ item: EaselItem) -> String? {
        let title = item.text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    package static func nest(_ entries: [(block: NoteBlock, depth: Int)]) -> [NoteBlock] {
        var index = 0
        func take(depth: Int) -> [NoteBlock] {
            var result: [NoteBlock] = []
            while index < entries.count, entries[index].depth >= depth {
                var block = entries[index].block
                let own = entries[index].depth
                index += 1
                if index < entries.count, entries[index].depth > own { block.children = take(depth: own + 1) }
                result.append(block)
            }
            return result
        }
        return take(depth: 0)
    }

    package static func blocks(for item: EaselItem, options: Options) -> [(block: NoteBlock, depth: Int)] {
        let flat: (NoteBlock) -> [(block: NoteBlock, depth: Int)] = { [($0, 0)] }
        switch item.kind {
        case .text, .rectangle, .circle, .arrow:
            return paragraphs(of: item)
        case .sticky:
            let text = noteText(of: item, range: 0..<(item.text as NSString).length)
            guard !text.isEmpty else { return [] }
            return flat(NoteBlock(.bulletedItem, text: lineBroken(text)))
        case .section:
            return sectionTitle(item).map { flat(.heading(2, NoteText($0))) } ?? []
        case .table:
            guard let table = item.table else { return [] }
            return flat(NoteBlock(.table, props: tableProps(table)))
        case .code:
            var props = NoteBlockProps()
            props.language = item.language ?? ""
            return flat(NoteBlock(.code, text: NoteText(item.text), props: props))
        case .link, .webCard, .browser:
            guard let raw = item.url else { return item.text.isEmpty ? [] : flat(.paragraph(NoteText(item.text))) }
            let title = item.text.isEmpty ? (item.preview?.title ?? displayName(raw)) : item.text
            return flat(.paragraph(linked(title.isEmpty ? displayName(raw) : title, raw)))
        case .image, .video, .audio, .file, .pdf:
            return media(item, options: options)
        case .equation:
            return item.text.isEmpty ? [] : flat(NoteBlock(.equation, text: NoteText(item.text)))
        case .stamp, .freehand:
            return []
        }
    }

    package static func blockKind(_ kind: EaselItemKind) -> NoteBlockKind {
        switch kind {
        case .video: return .video
        case .audio: return .audio
        case .file: return .file
        case .pdf: return .pdf
        default: return .image
        }
    }

    package static func media(_ item: EaselItem, options: Options) -> [(block: NoteBlock, depth: Int)] {
        let kind = blockKind(item.kind)
        let alt = item.altText ?? item.fileName ?? ""
        guard let path = options.assetPath(item) else {
            if let raw = item.url { return [(.paragraph(linked(alt.isEmpty ? displayName(raw) : alt, raw)), 0)] }
            return alt.isEmpty ? [] : [(.paragraph(NoteText(alt)), 0)]
        }
        var props = NoteBlockProps()
        props.source = path
        props.alt = alt
        return [(NoteBlock(kind, props: props), 0)]
    }

    package static func displayName(_ raw: String) -> String {
        guard let host = URL(string: raw)?.host, !host.isEmpty else { return raw }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    package static func linked(_ title: String, _ link: String) -> NoteText {
        var marks = NoteMarks()
        marks.link = link
        return NoteText(title, marks: marks)
    }

    package static func tableProps(_ table: EaselTable) -> NoteBlockProps {
        var props = NoteBlockProps()
        let rows = table.cells.map { row in row.map { NoteText($0.text.replacingOccurrences(of: "\n", with: " ")) } }
        props.table = NoteTable(rows: rows)
        return props
    }

    package static func lineBroken(_ text: NoteText) -> NoteText {
        text.trimmingTrailingNewlines()
    }

    package static func paragraphs(of item: EaselItem) -> [(block: NoteBlock, depth: Int)] {
        let source = item.text as NSString
        guard source.length > 0 else { return [] }
        var result: [(block: NoteBlock, depth: Int)] = []
        var location = 0
        while true {
            let newline = source.range(of: "\n", range: NSRange(location: location, length: source.length - location))
            let length = newline.location == NSNotFound ? source.length - location : newline.location - location
            let attributes = paragraphAttributes(of: item, at: location, length: length)
            var start = location
            if attributes?.lists.isEmpty == false,
               let prefix = source.substring(with: NSRange(location: location, length: length)).range(of: "^\t[^\t]+\t", options: .regularExpression) {
                start += (String(source.substring(with: NSRange(location: location, length: length))[prefix]) as NSString).length
            }
            let text = noteText(of: item, range: start..<(location + length))
            if !text.isEmpty || !result.isEmpty { result.append(block(for: text, attributes: attributes)) }
            if newline.location == NSNotFound { break }
            location = newline.location + 1
        }
        while let last = result.last, last.block.text.isEmpty, last.block.kind == .paragraph { result.removeLast() }
        return result
    }

    package static func paragraphAttributes(of item: EaselItem, at location: Int, length: Int) -> EaselRichText.Paragraph? {
        guard let runs = item.richText?.runs else { return nil }
        let probe = length > 0 ? location : max(0, location - 1)
        return runs.first { probe >= $0.location && probe < $0.location + $0.length }?.attributes.paragraph
    }

    package static func block(for text: NoteText, attributes: EaselRichText.Paragraph?) -> (block: NoteBlock, depth: Int) {
        if let level = attributes?.heading, level > 0 { return (.heading(min(level + 1, 6), text), 0) }
        guard let lists = attributes?.lists, let last = lists.last else { return (.paragraph(text), 0) }
        if last.marker == quoteMarker { return (NoteBlock(.quote, text: text), 0) }
        switch EaselChecklist.marker(last.marker) {
        case .divider?: return (NoteBlock(.divider), 0)
        case let marker?:
            var props = NoteBlockProps()
            props.checked = marker == .done
            return (NoteBlock(.todo, text: text, props: props), max(0, lists.count - 1))
        case nil: break
        }
        let depth = max(0, lists.count - 1)
        let numbered = last.marker.contains("decimal") || last.marker.contains("alpha") || last.marker.contains("roman")
        return (NoteBlock(numbered ? .numberedItem : .bulletedItem, text: text), depth)
    }

    package static func noteText(of item: EaselItem, range: Range<Int>) -> NoteText {
        let source = item.text as NSString
        let length = source.length
        let lower = min(max(0, range.lowerBound), length), upper = min(max(lower, range.upperBound), length)
        guard upper > lower else { return NoteText() }
        guard let runs = item.richText?.runs, !runs.isEmpty else {
            return NoteText(source.substring(with: NSRange(location: lower, length: upper - lower)).replacingOccurrences(of: "\u{FFFC}", with: ""))
        }
        var pieces: [(String, NoteMarks)] = []
        for run in runs {
            let start = max(lower, run.location), end = min(upper, run.location + run.length)
            guard end > start else { continue }
            if let inline = run.attributes.inline {
                var marks = marks(for: run.attributes)
                marks.link = nil
                marks.atom = inline.atom
                pieces.append((NoteAtom.character, marks))
                continue
            }
            let text = source.substring(with: NSRange(location: start, length: end - start)).replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { continue }
            pieces.append((text, marks(for: run.attributes)))
        }
        return NoteText(pieces: pieces)
    }

    package static func marks(for attributes: EaselRichText.Attributes) -> NoteMarks {
        var marks = NoteMarks()
        let font = attributes.font
        marks.bold = font.traits & boldTrait != 0 || font.weight >= 0.3
        marks.italic = font.traits & italicTrait != 0 || font.slant > 0
        marks.code = font.traits & monospaceTrait != 0 && attributes.background != nil
        marks.strikethrough = attributes.strike != 0
        marks.underline = attributes.underline != 0 && attributes.link == nil
        marks.link = attributes.link
        return marks
    }
}
