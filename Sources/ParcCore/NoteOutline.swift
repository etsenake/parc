import Foundation

struct NoteOutlineEntry: Hashable {
    var id: NoteBlockID
    var level: Int
    var depth: Int
    var title: String
}

enum NoteOutline {
    static func entries(in page: NotePage, levels: ClosedRange<Int> = 1...3) -> [NoteOutlineEntry] {
        var found: [(id: NoteBlockID, level: Int, title: String)] = []
        func walk(_ blocks: [NoteBlock]) {
            for block in blocks {
                switch block.kind {
                case .heading where levels.contains(block.props.level):
                    let title = Self.title(of: block.text)
                    if !title.isEmpty { found.append((block.id, block.props.level, title)) }
                case .columns, .column:
                    walk(block.children)
                default:
                    break
                }
            }
        }
        walk(page.blocks)
        guard let top = found.map(\.level).min() else { return [] }
        return found.map { NoteOutlineEntry(id: $0.id, level: $0.level, depth: $0.level - top, title: $0.title) }
    }

    static func title(of text: NoteText) -> String {
        text.plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
