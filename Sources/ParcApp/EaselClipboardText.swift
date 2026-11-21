import AppKit

@MainActor
enum EaselClipboardText {
    static let privateTypes: [NSPasteboard.PasteboardType] = [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType,
                                                              EaselStyledText.legacyPasteboardType]

    static func blocks(from board: NSPasteboard) -> [NoteBlock]? {
        guard board.availableType(from: privateTypes) == nil else { return nil }
        let reading = NoteClipboard.read(board)
        switch NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) {
        case .blocks:
            return reading.archive?.blocks
        case .html:
            let parsed = reading.html.map { NoteHTMLReader.blocks(from: $0, baseURL: nil) } ?? []
            return parsed.isEmpty ? nil : parsed
        case .markdown:
            let parsed = NoteClipboard.markdownBlocks(reading.string ?? "")
            return parsed.isEmpty ? nil : parsed
        default:
            return nil
        }
    }

    static func attributed(from board: NSPasteboard, typing: [NSAttributedString.Key: Any], base: EaselTextStyle) -> NSAttributedString? {
        guard let blocks = blocks(from: board) else { return nil }
        let paragraphs = EaselBlockText.paragraphs(from: blocks)
        guard !paragraphs.isEmpty else { return nil }
        return attributed(from: paragraphs, typing: typing, base: base)
    }

    static func styledText(from board: NSPasteboard, style: EaselTextStyle, color: String) throws -> EaselStyledText? {
        let typing = EaselTextAppearance.attributed("x", style: style, color: color).attributes(at: 0, effectiveRange: nil)
        guard let value = attributed(from: board, typing: typing, base: style) else { return nil }
        return try EaselStyledText.capture(value, style: style, color: color)
    }

    static func attributed(from paragraphs: [EaselBlockText.Paragraph], typing: [NSAttributedString.Key: Any], base: EaselTextStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var ranges: [(range: NSRange, paragraph: EaselBlockText.Paragraph)] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: typing)) }
            let start = result.length
            result.append(inline(paragraph.text, typing: typing))
            ranges.append((NSRange(location: start, length: result.length - start), paragraph))
        }
        var edit = EaselParagraphEditing.Edit(text: result, selection: NSRange(location: 0, length: 0), typing: typing)
        for entry in ranges.reversed() {
            guard let kind = Self.kind(entry.paragraph.kind) else { continue }
            let here = NSRange(location: entry.range.location, length: 0)
            edit = EaselParagraphEditing.apply(kind, to: edit.text, selection: here, typing: typing, base: base)
            for _ in 0..<min(entry.paragraph.depth, 6) {
                guard let deeper = EaselParagraphEditing.indent(edit.text, selection: NSRange(location: entry.range.location, length: 0),
                                                                typing: typing, outdent: false, base: base) else { break }
                edit = deeper
            }
        }
        EaselParagraphEditing.renumber(&edit)
        return edit.text
    }

    static func kind(_ kind: EaselBlockText.Kind) -> EaselParagraphEditing.Kind? {
        switch kind {
        case .text: return nil
        case .heading(let level): return [.heading1, .heading2, .heading3, .heading4][min(max(level, 1), 4) - 1]
        case .bullet: return .bullets
        case .number: return .numbers
        case .quote: return .quote
        }
    }

    static func inline(_ text: NoteText, typing: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let source = text.string as NSString
        for run in text.runs() {
            let piece = source.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            var attributes = typing
            let font = (typing[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            var traits: NSFontTraitMask = []
            if run.marks.bold { traits.insert(.boldFontMask) }
            if run.marks.italic { traits.insert(.italicFontMask) }
            if run.marks.code {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: run.marks.bold ? .bold : .regular)
                attributes[.backgroundColor] = EaselTextAppearance.inlineCodeFill
            } else if !traits.isEmpty {
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits)
            }
            if run.marks.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.marks.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.marks.link, EaselRichText.validLink(link), let url = URL(string: link) { attributes[.link] = url }
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
    }

    static func writeFlavours(for blocks: [NoteBlock], into item: NSPasteboardItem) {
        guard !blocks.isEmpty else { return }
        let markdown = NoteMarkdown.serialize(NotePage(blocks: blocks), purpose: .export).trimmingCharacters(in: .newlines)
        if !markdown.isEmpty { item.setString(markdown, forType: NoteClipboard.markdownType) }
        let html = NotePageHTML.fragment(blocks)
        if !html.isEmpty { item.setString(html, forType: .html) }
    }
}
