import Foundation
@testable import ParcCore

enum NotePageToolsTestsSupport {
    static func samplePage() -> (NotePage, [NoteBlockID]) {
        var bold = NoteMarks.plain
        bold.bold = true
        let intro = NoteBlock.paragraph(NoteText(pieces: [("Park parks ", .plain), ("PARK", bold), (" at the park.", .plain)]))
        var tableProps = NoteBlockProps()
        tableProps.table = NoteTable(rows: [["Park", "Ride"], ["Bench", "parked"]])
        let table = NoteBlock(.table, props: tableProps)
        var imageProps = NoteBlockProps()
        imageProps.source = "Attachments/park.png"
        imageProps.caption = "A park at dusk"
        let image = NoteBlock(.image, props: imageProps)
        var toggleProps = NoteBlockProps()
        toggleProps.expanded = false
        let hidden = NoteBlock.paragraph("Secret park")
        let toggle = NoteBlock(.toggle, text: "Folded", props: toggleProps, children: [hidden])
        let code = NoteBlock(.code, text: "let park = 1")
        let mention = NoteBlock.paragraph(NoteText.atom(.page(target: "park.md", title: "Park")) + NoteText(" park"))
        let divider = NoteBlock(.divider)
        let blocks = [intro, table, image, toggle, code, mention, divider]
        return (NotePage(blocks: blocks), [intro.id, table.id, image.id, toggle.id, hidden.id, code.id, mention.id])
    }
}
