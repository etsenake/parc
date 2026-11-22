import Foundation
import Testing
@testable import Parc
@testable import ParcCore

enum NoteHandlesModelTestsSupport {
    static func ids(_ entries: [NoteBlockMenuEntry]) -> [String] { entries.map(\.id) }

    static func menu(_ blocks: [NoteBlock], isReadOnly: Bool = false, canMoveToNotes: Bool = false, supportsBlockLinks: Bool = false,
              columnLimit: Int = 0, tableEntries: [NoteBlockMenuEntry] = []) -> [NoteBlockMenuEntry] {
        NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: blocks, isReadOnly: isReadOnly, canMoveToNotes: canMoveToNotes,
                                                             supportsBlockLinks: supportsBlockLinks, tableEntries: tableEntries, columnLimit: columnLimit))
    }
}
