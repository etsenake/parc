import Foundation

enum NoteMarkdown {
    static func parse(_ source: String) -> NotePage {
        let blocks = source.components(separatedBy: "\n").filter { !$0.isEmpty }.map { NoteBlock.paragraph(NoteText($0)) }
        return NotePage(blocks: blocks)
    }

    static func serialize(_ page: NotePage) -> String {
        page.blocks.map { $0.text.plainText }.joined(separator: "\n\n") + "\n"
    }
}

enum NotePlainText {
    static func parse(_ source: String) -> NotePage {
        NotePage(blocks: source.components(separatedBy: "\n").map { NoteBlock.paragraph(NoteText($0)) })
    }

    static func serialize(_ page: NotePage) -> String {
        page.allBlocks().map { $0.text.plainText }.joined(separator: "\n")
    }
}
