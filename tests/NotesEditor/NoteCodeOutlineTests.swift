import Foundation

@main @MainActor
struct NoteCodeOutlineTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        extraction()
        indentation()
        titles()
        print("NoteCodeOutlineTests passed")
    }

    static func extraction() {
        let intro = NoteBlock.heading(1, "Intro")
        let details = NoteBlock.heading(2, "Details")
        let deep = NoteBlock.heading(3, "Deep")
        let fourth = NoteBlock.heading(4, "Fourth")
        let fifth = NoteBlock.heading(5, "Too deep")
        let hidden = NoteBlock.heading(2, "Hidden")
        let toggle = NoteBlock(.toggle, text: "More", children: [hidden])
        let side = NoteBlock.heading(2, "Side")
        let columns = NoteBlock(.columns, children: [NoteBlock(.column, children: [side]), NoteBlock(.column, children: [.paragraph("x")])])
        let empty = NoteBlock.heading(2, "  ")
        let page = NotePage(blocks: [intro, .paragraph("Body"), details, deep, fourth, fifth, toggle, columns, empty])
        let entries = NoteOutline.entries(in: page)
        expect(entries.map(\.id) == [intro.id, details.id, deep.id, fourth.id, side.id], "headings H1–H4 in page order, columns included")
        expect(!entries.contains { $0.id == hidden.id }, "headings tucked inside toggles stay out, like Notion")
        expect(!entries.contains { $0.id == empty.id }, "blank headings stay out until they get words")
        expect(!entries.contains { $0.id == fifth.id }, "H5 and below stay out")
        var toggleHeading = NoteBlock.heading(2, "Folding")
        toggleHeading.props.toggleable = true
        toggleHeading.children = [.heading(3, "Inside")]
        let folded = NoteOutline.entries(in: NotePage(blocks: [toggleHeading]))
        expect(folded.map(\.title) == ["Folding"], "a toggle heading counts, its children don't")
        expect(NoteOutline.entries(in: NotePage(blocks: [.paragraph("Nothing")])).isEmpty, "no headings, no entries")
    }

    static func indentation() {
        let page = NotePage(blocks: [.heading(1, "A"), .heading(2, "B"), .heading(3, "C"), .heading(2, "D")])
        expect(NoteOutline.entries(in: page).map(\.depth) == [0, 1, 2, 1], "each level indents one step")
        let shallow = NotePage(blocks: [.heading(2, "B"), .heading(3, "C"), .heading(2, "D")])
        expect(NoteOutline.entries(in: shallow).map(\.depth) == [0, 1, 0], "the biggest heading present sits flush left")
        expect(NoteOutline.entries(in: shallow).map(\.level) == [2, 3, 2], "levels are kept as written")
    }

    static func titles() {
        let mention = NoteText(pieces: [("See ", .plain)]) + .atom(.equation("E=mc^2")) + NoteText(" now")
        let page = NotePage(blocks: [.heading(1, mention), .heading(2, "Two\nlines"), .heading(3, "  padded  ")])
        expect(NoteOutline.entries(in: page).map(\.title) == ["See E=mc^2 now", "Two lines", "padded"],
               "titles read as plain text on one line")
    }
}
