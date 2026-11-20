import Foundation

enum NoteMarkdown {
    static func parse(_ source: String, customEmoji: Set<String> = []) -> NotePage {
        var bytes = Array(source.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var settings = NotePageSettings()
        var body = bytes[...]
        var hasFrontMatter = false
        if let (yaml, rest) = NoteMDFrontMatter.split(bytes) {
            settings = NoteMDFrontMatter.read(yaml)
            body = rest
            hasFrontMatter = true
        }
        let document = NoteMDBlockParser.parse(Array(body))
        let reader = NoteMDReader(references: document.references, footnotes: document.footnotes, customEmoji: customEmoji)
        var blocks = reader.sequence(document.root.children[...], documentEdges: !hasFrontMatter, trailingBlank: 0)
        let trailing = hasFrontMatter && document.root.children.isEmpty ? max(0, document.root.trailingBlank - 1) : document.root.trailingBlank
        blocks += Array(repeating: NoteBlock.paragraph(), count: trailing)
        return NotePage(settings: settings, blocks: blocks)
    }

    static func serialize(_ page: NotePage, customEmoji: Set<String> = []) -> String {
        NoteMDWriter(page: page, customEmoji: customEmoji).write(page)
    }
}

enum NotePlainText {
    static func parse(_ source: String) -> NotePage {
        NotePage(blocks: source.components(separatedBy: "\n").map { NoteBlock.paragraph(NoteText($0)) })
    }

    static func serialize(_ page: NotePage) -> String {
        page.allBlocks().map(line).joined(separator: "\n")
    }

    static func line(_ block: NoteBlock) -> String {
        guard block.kind.isMedia || block.kind == .bookmark || block.kind == .embed, block.text.isEmpty,
              let source = block.props.source, !source.isEmpty else { return block.text.plainText }
        return source
    }
}
