import Foundation

@main @MainActor
struct NoteEaselBlockTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static let id = UUID(uuidString: "6F1C2A4E-9B1D-4C55-8E0A-3D2B1C0F9A77")!

    static func main() {
        addresses()
        documentDrags()
        pageKeys()
        picker()
        roundTrip()
        sizing()
        exports()
        print("NoteEaselBlockTests passed")
    }

    static func pageKeys() {
        let block = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!
        let other = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let key = NoteEaselPageKey.key(block: block, item: id)
        expect(key == NoteEaselPageKey.key(block: block, item: id), "page keys are stable for the same block and object")
        expect(NoteEaselPageKey.key(block: block, item: key) == id, "a page key leads back to its object")
        expect(key != id && key != block, "page keys never reuse the object or block id")
        expect(NoteEaselPageKey.key(block: other, item: id) != key, "the same Easel in two blocks gets two pages")
    }

    static func documentDrags() {
        let easel = NoteDocumentDrag(address: NoteEaselAddress.address(id), title: "Mood\nboard")
        let decoded = NoteDocumentDrag(encoded: easel.encoded)
        expect(decoded?.address == NoteEaselAddress.address(id) && decoded?.title == "Mood board", "drags round-trip on one title line")
        let block = decoded?.easelBlock
        expect(block.flatMap(NoteEaselAddress.id(of:)) == id && block.map(NoteEaselAddress.title(of:)) == "Mood board", "Easel drags become Easel blocks")
        let note = NoteDocumentDrag(address: "file:///Users/me/Notes/Ideas.md", title: "Ideas")
        expect(NoteDocumentDrag(encoded: note.encoded)?.easelBlock == nil, "note drags aren't Easels")
        expect(NoteDocumentDrag(encoded: "") == nil && NoteDocumentDrag(encoded: "\nTitle") == nil, "drags need an address")
        expect(NoteDocumentDrag(encoded: NoteEaselAddress.address(id))?.title == "", "a missing title stays empty")
    }

    static func addresses() {
        expect(NoteEaselAddress.address(id) == "parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77", "addresses use the Easel link form, lowercased")
        expect(NoteEaselAddress.id(from: "  PARC://Easel/6F1C2A4E-9B1D-4C55-8E0A-3D2B1C0F9A77\n") == id, "pasted links trim and ignore case")
        expect(NoteEaselAddress.id(from: "parc://easel/not-a-uuid") == nil, "broken ids aren't Easels")
        expect(NoteEaselAddress.id(from: "parc://easel/" + id.uuidString + "?x=1") == nil, "queries aren't Easel links")
        expect(NoteEaselAddress.id(from: "parc://easel/" + id.uuidString + "#a") == nil, "fragments aren't Easel links")
        expect(NoteEaselAddress.id(from: "https://easel/" + id.uuidString) == nil, "web addresses aren't Easels")
        expect(NoteEaselAddress.id(from: "parc://note/" + id.uuidString) == nil, "other Parc addresses aren't Easels")
        let block = NoteEaselAddress.block(id: id, title: "  Moodboard ")
        expect(block.kind == .easel && NoteEaselAddress.id(of: block) == id, "blocks carry the Easel id")
        expect(NoteEaselAddress.title(of: block) == "Moodboard", "titles are trimmed")
        expect(NoteEaselAddress.title(of: NoteEaselAddress.block(id: id, title: nil)) == "Easel", "untitled blocks say Easel")
    }

    static func picker() {
        let a = UUID(), b = UUID(), c = UUID()
        let easels = [NoteEaselPicker.Candidate(id: a, title: "Garden plans", itemCount: 3),
                      NoteEaselPicker.Candidate(id: b, title: "Plans", itemCount: 1),
                      NoteEaselPicker.Candidate(id: c, title: "Trip moodboard", itemCount: 0)]
        let all = NoteEaselPicker.choices(easels, query: "")
        expect(all.count == 4 && all.last?.action == .create("Untitled Easel") && all.last?.title == "New Easel",
               "an empty search lists every Easel, then New Easel")
        expect(all[0].subtitle == "3 objects" && all[1].subtitle == "1 object", "rows count objects")
        let plans = NoteEaselPicker.choices(easels, query: " plans ")
        expect(plans.map(\.action) == [.existing(b), .existing(a), .create("plans")], "exact matches come first, then word matches")
        expect(plans.last?.title == "New Easel “plans”", "New Easel takes its title from the search")
        expect(NoteEaselPicker.choices(easels, query: "MOOD").first?.action == .existing(c), "search ignores case")
        let many = (0..<20).map { NoteEaselPicker.Candidate(id: UUID(), title: "Board \($0)", itemCount: 0) }
        expect(NoteEaselPicker.choices(many, query: "board").count == NoteEaselPicker.limit + 1, "the list stays short")
    }

    static func roundTrip() {
        let source = "[Moodboard](parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77) <!-- parc easel width=\"0.6\" height=\"560\" align=\"left\" -->\n"
        let page = NoteMarkdown.parse(source)
        expect(page.blocks.count == 1 && page.blocks[0].kind == .easel, "the easel comment makes an Easel block")
        let block = page.blocks[0]
        expect(NoteEaselAddress.id(of: block) == id && block.props.alt == "Moodboard", "the link keeps the id and title")
        expect(block.props.width == 0.6 && block.props.height == 560 && block.props.alignment == .left, "width, height and alignment come back")
        expect(NoteMarkdown.serialize(page) == source, "the line writes back byte for byte")
        var plain = page
        plain.blocks[0].props.width = nil
        plain.blocks[0].props.height = nil
        plain.blocks[0].props.alignment = .center
        expect(NoteMarkdown.serialize(plain) == "[Moodboard](parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77) <!-- parc easel -->\n",
               "full width, the default height and centring write nothing")
        let auto = NoteMarkdown.parse("<parc://easel/6F1C2A4E-9B1D-4C55-8E0A-3D2B1C0F9A77> <!-- parc easel -->\n")
        expect(auto.blocks.first?.kind == .easel && NoteEaselAddress.id(of: auto.blocks[0]) == id, "a bare Easel address reads too")
        let link = NoteMarkdown.parse("[Moodboard](parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77)\n")
        expect(link.blocks.first?.kind == .paragraph, "a plain Easel link stays a link")
        let broken = NoteMarkdown.parse("[Moodboard](parc://easel/nope) <!-- parc easel -->\n")
        expect(broken.blocks.first?.kind == .paragraph, "a broken address stays a paragraph")
        let nested = NoteMarkdown.parse("- Item\n\n  [Board](parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77) <!-- parc easel -->\n")
        expect(nested.allBlocks().contains { $0.kind == .easel }, "Easels nest inside lists")
        expect(NoteMarkdown.parse(NoteMarkdown.serialize(nested)) == nested || NoteMarkdown.serialize(NoteMarkdown.parse(NoteMarkdown.serialize(nested))) == NoteMarkdown.serialize(nested),
               "nested Easels survive a round trip")
        expect(NotePlainText.line(block) == "parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77", "plain text keeps the address")
    }

    static func sizing() {
        expect(NotePDFLayout.displayWidth(fraction: nil, columnWidth: 700) == 700, "Easels start full width")
        expect(NotePDFLayout.displayWidth(fraction: 0.5, columnWidth: 700) == 350, "width is a fraction of the column")
        expect(NotePDFLayout.storedFraction(width: 698, columnWidth: 700) == nil, "near full width snaps back to full")
        expect(NotePDFLayout.storedFraction(width: 350, columnWidth: 700) == 0.5, "narrow widths store their fraction")
    }

    static func exports() {
        let page = NoteMarkdown.parse("[Moodboard](parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77) <!-- parc easel height=\"560\" -->\n")
        let portable = NoteMarkdown.serialize(page, purpose: .export)
        expect(portable == "[Moodboard](parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77)\n", "Markdown exports write a plain link")
        let card = NotePageHTML.document(page, title: "T", assets: { _ in nil }, embedImages: false)
        expect(card.contains("data-block=\"easel\"") && card.contains("href=\"parc://easel/6f1c2a4e-9b1d-4c55-8e0a-3d2b1c0f9a77\"")
               && !card.contains("class=\"easel-art\""), "without a snapshot HTML shows a link card")
        let art = NotePageHTML.document(page, title: "T", assets: { _ in nil }, embedImages: false, easelArt: { _ in Data([1, 2, 3]) })
        expect(art.contains("class=\"easel-art\"") && art.contains("data:image/png;base64,AQID"), "with a snapshot HTML shows the picture")
        let fragment = NotePageHTML.fragment(page.blocks)
        let back = NoteHTMLReader.blocks(from: fragment, baseURL: nil)
        expect(back.first?.kind == .easel && NoteEaselAddress.id(of: back[0]) == id && back[0].props.height == 560,
               "copied HTML pastes back as the same Easel")
    }
}
