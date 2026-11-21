import Foundation

package struct NoteOutlineEntry: Hashable {
    package var id: NoteBlockID
    package var level: Int
    package var depth: Int
    package var title: String

    package init(id: NoteBlockID, level: Int, depth: Int, title: String) {
        self.id = id
        self.level = level
        self.depth = depth
        self.title = title
    }
}

package enum NoteOutline {
    package static func entries(in page: NotePage, levels: ClosedRange<Int> = 1...4) -> [NoteOutlineEntry] {
        var found: [(id: NoteBlockID, level: Int, title: String)] = []
        func walk(_ blocks: [NoteBlock]) {
            for block in blocks {
                switch block.kind {
                case .heading where levels.contains(block.props.level):
                    let title = Self.title(of: block.text)
                    if !title.isEmpty { found.append((block.id, block.props.level, title)) }
                case .columns, .column, .synced:
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

    package static func title(of text: NoteText) -> String {
        text.plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
