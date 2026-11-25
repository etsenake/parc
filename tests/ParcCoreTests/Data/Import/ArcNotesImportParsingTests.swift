import Foundation
import Testing
@testable import ParcCore

struct ArcNotesImportParsingTests {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x01, 0x02])

    static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    static func canonical(_ markdown: String) -> String { NoteMarkdown.serialize(NoteMarkdown.parse(markdown)) }

    static func rich(_ location: Int, _ length: Int, _ value: Any) -> [String: Any] {
        let fields: [String: Any] = ["range": ["location": location, "length": length], "value": value]
        return ["richText": fields]
    }

    static func block(_ id: String, text: String, properties: [Any], type: String = "fullBlob", content: [String] = []) -> [String: Any] {
        ["id": id, "type": type, "version": 1, "text": text, "content": content, "lastUpdatedAt": 815_000_000,
         "properties": properties]
    }

    static let meetingBlock = block("B1", text: "Agenda\nShip it\n", properties: [rich(0, 6, "h1"), rich(7, 4, "bold")])

    static func storable(id: String = "DOC-1", title: String = "Meeting notes", blocks: Any, roots: [String]? = ["B1"]) -> [String: Any] {
        var scratchpad: [String: Any] = ["blocks": blocks]
        if let roots { scratchpad["rootBlocks"] = roots }
        return ["version": 1, "arcDocument": ["id": id, "title": ["value": title, "lastUpdatedAt": 815_000_000],
                "createdAt": 814_000_000, "shareStatus": "privateDocument", "creatorID": "u",
                "data": ["scratchpad": scratchpad]]]
    }

    static func markdown(_ text: String, _ properties: [Any]) throws -> String {
        let object = try JSONSerialization.jsonObject(with: json(["p": properties]))
        let decoded = try #require(object as? [String: Any])
        return ArcNotesImport.markdown(text: text, properties: decoded["p"] as? [Any] ?? [])
    }

    @Test func aStoredNoteWithPairedBlocksBecomesAHeadingAndBoldText() throws {
        let data = try Self.json(Self.storable(blocks: ["B1", Self.meetingBlock]))
        let notes = ArcNotesImport.notes(json: data, name: "DOC-1")
        let note = try #require(notes.first)
        #expect(notes.count == 1 && note.id == "DOC-1" && note.title == "Meeting notes")
        #expect(Self.canonical(note.markdown) == Self.canonical("# Agenda\n\n**Ship** it\n"))
        #expect(note.markdown.contains("# Agenda") && note.markdown.contains("**Ship** it"))
    }

    @Test func dictionaryBlocksReadTheSameAsPairedBlocks() throws {
        let pairs = try Self.json(Self.storable(blocks: ["B1", Self.meetingBlock]))
        let dictionary = try Self.json(Self.storable(blocks: ["B1": Self.meetingBlock]))
        let paired = ArcNotesImport.notes(json: pairs, name: "x")
        let keyed = ArcNotesImport.notes(json: dictionary, name: "x")
        #expect(keyed.map(\.markdown) == paired.map(\.markdown) && !keyed.isEmpty)
    }

    @Test func aBareDocumentWithAPlainTitleAndListedBlocksKeepsBlockOrderWithoutRoots() throws {
        let document: [String: Any] = ["id": "DOC-2", "title": "Loose",
            "data": ["scratchpad": ["blocks": [Self.block("A", text: "First", properties: []),
                                               Self.block("B", text: "Second", properties: [Self.rich(0, 6, "italic")])]]]]
        let data = try Self.json(document)
        let note = try #require(ArcNotesImport.notes(json: data, name: "file-name").first)
        #expect(note.id == "DOC-2" && note.title == "Loose")
        #expect(Self.canonical(note.markdown) == Self.canonical("First\n\n*Second*\n"))
    }

    @Test func childBlocksFollowTheirParentAndAMissingIDFallsBackToTheFileName() throws {
        let document: [String: Any] = ["arcDocument": ["title": ["value": "Nested"], "data": ["scratchpad": [
            "rootBlocks": ["R"],
            "blocks": ["R", Self.block("R", text: "Parent", properties: [], content: ["C", "ghost"]),
                       "C", Self.block("C", text: "Child", properties: [])]]]]]
        let data = try Self.json(document)
        let note = try #require(ArcNotesImport.notes(json: data, name: "NESTED-ID").first)
        #expect(note.id == "NESTED-ID")
        #expect(Self.canonical(note.markdown) == Self.canonical("Parent\n\nChild\n"))
    }

    @Test func bulletAndNumberedListsNestByLevel() throws {
        let text = "one\nnested\ntwo\nfirst\nsecond"
        let result = try Self.markdown(text, [
            Self.rich(0, 4, ["unorderedList": ["level": 0]]), Self.rich(4, 7, ["unorderedList": ["level": 1]]),
            Self.rich(11, 4, ["unorderedList": ["level": 0]]), Self.rich(15, 12, ["orderedList": ["level": 0]])])
        #expect(Self.canonical(result) == Self.canonical("- one\n  - nested\n- two\n\n1. first\n2. second\n"))
    }

    @Test func oneBasedListLevelsStartAtTheLeftEdge() throws {
        let result = try Self.markdown("top\ninner", [
            Self.rich(0, 4, ["unorderedList": ["level": 1]]), Self.rich(4, 5, ["unorderedList": ["level": 2]])])
        #expect(Self.canonical(result) == Self.canonical("- top\n  - inner\n"))
    }

    @Test func checklistsKeepTheirTicks() throws {
        let result = try Self.markdown("done\nopen", [
            Self.rich(0, 5, ["checklist": ["checked": true]]), Self.rich(5, 4, ["checklist": ["checked": false]])])
        #expect(Self.canonical(result) == Self.canonical("- [x] done\n- [ ] open\n"))
    }

    @Test func formattedAndBareHyperlinksBecomeLinks() throws {
        let result = try Self.markdown("Read the docs or https://example.org", [
            Self.rich(5, 8, ["formattedHyperlink": ["url": "https://example.com/docs"]]), Self.rich(17, 19, "hyperlink")])
        #expect(Self.canonical(result)
                == Self.canonical("Read [the docs](https://example.com/docs) or [https://example.org](https://example.org)\n"))
    }

    @Test func italicStrikethroughCodeAndUnderlineStayInline() throws {
        let result = try Self.markdown("a b c d", [Self.rich(0, 1, "italic"), Self.rich(2, 1, "strikethrough"),
                                                  Self.rich(4, 1, ["code": [:]]), Self.rich(6, 1, "underline")])
        #expect(Self.canonical(result) == Self.canonical("*a* ~~b~~ `c` <u>d</u>\n"))
    }

    @Test func quotesAndCodeBlocksBecomeTheirOwnBlocks() throws {
        let result = try Self.markdown("wise words\nlet a = 1\nlet b = 2", [
            Self.rich(0, 11, "quote"), Self.rich(11, 19, ["codeBlock": ["language": "swift"]])])
        #expect(Self.canonical(result) == Self.canonical("> wise words\n\n```swift\nlet a = 1\nlet b = 2\n```\n"))
    }

    @Test func unknownFormatsAndBlockTypesKeepTheirTextAsPlainText() throws {
        let pad: [String: Any] = ["rootBlocks": ["A", "B"], "blocks": [
            "A", Self.block("A", text: "Glitter stays", properties: [Self.rich(0, 7, ["sparkle": [:]])]),
            "B", Self.block("B", text: "Plain fallback", properties: [Self.rich(0, 5, ["wobble": ["level": 2]])],
                            type: "mysteryBlock")]]
        let object = try JSONSerialization.jsonObject(with: Self.json(pad))
        let decoded = try #require(object as? [String: Any])
        #expect(Self.canonical(ArcNotesImport.markdown(scratchpad: decoded))
                == Self.canonical("Glitter stays\n\nPlain fallback\n"))
    }

    @Test func arrayAndStringRangesWithAndWithoutTheRichTextWrapperAllCount() throws {
        let result = try Self.markdown("Bold move", [
            ["richText": ["range": [0, 4], "value": ["bold": [:]]]],
            ["range": "{5, 4}", "value": "italic"]])
        #expect(Self.canonical(result) == Self.canonical("**Bold** *move*\n"))
    }

    @Test func rangesThatRunFarPastTheTextAreClampedInsteadOfCrashing() throws {
        let properties: [[String: Any]] = [
            ["range": "{5, 9223372036854775807}", "value": "italic"],
            ["range": ["location": 0, "length": Int.max], "value": "underline"],
            ["range": ["lowerBound": 0, "upperBound": Int.max], "value": "bold"],
            ["range": [Int.max, 1], "value": "code"]]
        let result = try Self.markdown("Bold move", properties)
        let expected = try Self.markdown("Bold move", [
            Self.rich(5, 4, "italic"), Self.rich(0, 9, "underline"), Self.rich(0, 9, "bold")])
        #expect(Self.canonical(result) == Self.canonical(expected) && result.contains("move"))
    }

    @Test func formattingListsAndPicturesFarIntoALongNoteKeepTheirPlace() throws {
        let filler = String(repeating: "a", count: 2000)
        let text = filler + "\nBold tail\nitem\n\u{FFFC}"
        let data = try Self.json(Self.storable(blocks: ["B1", Self.block("B1", text: text, properties: [
            Self.rich(2001, 4, "bold"), Self.rich(2011, 5, ["unorderedList": ["level": 0]]),
            Self.rich(2016, 1, ["image": ["_0": Self.png.base64EncodedString()]])])]))
        let note = try #require(ArcNotesImport.notes(json: data, name: "x").first)
        #expect(note.page.blocks.map(\.kind) == [.paragraph, .paragraph, .bulletedItem, .image])
        #expect(note.page.blocks.first?.text.string == filler)
        #expect(note.markdown.contains("**Bold** tail"))
        #expect(note.page.blocks[2].text.string == "item")
        #expect(note.droppedImages == 0 && note.images.count == 1)
    }

    @Test func blankLinesCollapseAndSpecialCharactersStayLiteral() throws {
        let result = try Self.markdown("# not a heading\n\n\n*stars* and [brackets]", [])
        #expect(Self.canonical(result) == Self.canonical("\\# not a heading\n\n\\*stars\\* and \\[brackets\\]\n"))
    }

    @Test func embeddedPicturesBecomeImageBlocksAndUnreadableOnesAreCounted() throws {
        let document = Self.storable(blocks: ["B1", Self.block("B1", text: "Look\u{FFFC}\u{FFFC}", properties: [
            Self.rich(4, 1, ["image": ["_0": Self.png.base64EncodedString()]]),
            Self.rich(5, 1, ["image": ["_0": ["blob": 42]]])])])
        let data = try Self.json(document)
        let note = try #require(ArcNotesImport.notes(json: data, name: "x").first)
        #expect(note.page.blocks.map(\.kind) == [.paragraph, .image])
        #expect(note.page.blocks.last?.props.source == "arc-note-image-0.png")
        #expect(note.images["arc-note-image-0.png"] == SidebarImport.Note.Image(data: Self.png, fileExtension: "png"))
        #expect(note.droppedImages == 1)
    }

    @Test func remotePicturesKeepTheirAddress() throws {
        let data = try Self.json(Self.storable(blocks: ["B1", Self.block("B1", text: "\u{FFFC}",
            properties: [Self.rich(0, 1, ["image": ["url": "https://example.com/cat.png"]])])]))
        let result = ArcNotesImport.notes(json: data, name: "x")
        #expect(result.first?.page.blocks.map(\.kind) == [.image])
        #expect(result.first?.page.blocks.first?.props.source == "https://example.com/cat.png")
    }

    @Test func anExportedHTMLNoteDropsItsRepeatedTitleAndSavesInlinePictures() throws {
        let html = "<h1>Meeting notes</h1><h2>Agenda</h2><ul><li>Ship</li></ul>"
            + "<p><a href=\"https://example.com\">site</a></p><img src=\"data:image/png;base64,\(Self.png.base64EncodedString())\">"
        let exported: [String: Any] = ["id": "DOC-9", "title": "Meeting notes", "html": html, "lastUpdatedAt": 815_000_000]
        let data = try Self.json(exported)
        let note = try #require(ArcNotesImport.notes(json: data, name: "x").first)
        #expect(note.id == "DOC-9" && note.title == "Meeting notes")
        #expect(note.page.blocks.first?.kind == .heading && note.page.blocks.first?.text.string == "Agenda")
        #expect(note.page.blocks.contains { $0.kind == .bulletedItem && $0.text.string == "Ship" })
        let picture = try #require(note.page.blocks.first { $0.kind == .image })
        #expect(picture.props.source == "arc-note-image-0.png" && note.images.count == 1)
    }

    @Test func aNotesFolderReadsStoredExportedAndHTMLNotesAndSkipsTheRest() throws {
        try DataFixtures.withTemporaryDirectory { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.json(Self.storable(blocks: ["B1", Self.meetingBlock])).write(to: folder.appendingPathComponent("DOC-1.json"))
            try Data("<html><head><title>Trip &amp; ideas</title></head><body><p>Pack light</p></body></html>".utf8)
                .write(to: folder.appendingPathComponent("trip.html"))
            try Data("not json".utf8).write(to: folder.appendingPathComponent("broken.json"))
            try Data("skip".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            let notes = ArcNotesImport.notes(in: folder)
            #expect(notes.map(\.id) == ["DOC-1", "trip"])
            #expect(notes.map(\.title) == ["Meeting notes", "Trip & ideas"])
            #expect(Self.canonical(notes[1].markdown) == Self.canonical("Pack light\n"))
        }
    }

    @Test func sidebarNotesKeepTheirPlaceAndMissingOrUnusedOnesAreAccountedFor() throws {
        let data = try Self.json(Self.storable(blocks: ["B1", Self.meetingBlock]))
        let note = try #require(ArcNotesImport.notes(json: data, name: "x").first)
        let spare = SidebarImport.Note(id: "DOC-SPARE", title: "Spare", page: NotePage(blocks: [.paragraph("Hi")]))
        let items: [Any] = [
            "T1", ["id": "T1", "childrenIds": [], "data": ["tab": ["savedURL": "https://example.test/a", "savedTitle": "A"]]],
            "N1", ["id": "N1", "title": NSNull(), "childrenIds": [], "data": ["arcDocument": ["arcDocumentID": "DOC-1", "isEditable": true]]],
            "N2", ["id": "N2", "title": "Gone", "childrenIds": [], "data": ["arcDocument": ["arcDocumentID": "DOC-404", "isEditable": true]]]]
        let arc = try SidebarImport(arcData: ArcSidebarImportTestsSupport.document(items: items, pinned: ["T1", "N1", "N2"]),
                                    notes: [note, spare])
        #expect(arc.spaces[0].pinned == [.tab(SidebarImport.Tab(title: "A", url: "https://example.test/a")), .tab(.note(note))])
        #expect(arc.skippedItemCount == 1)
        #expect(arc.notes == [spare])
        #expect(arc.warnings == ["1 Arc note wasn’t saved on this Mac, so it stayed behind."])
    }

    @Test func aNoteInsideASplitViewStaysInTheSplitAndTitlesMatchWhenIDsDont() throws {
        let note = SidebarImport.Note(id: "export-file", title: "Plans", page: NotePage(blocks: [.paragraph("Go")]))
        let items: [Any] = [
            "V", ["id": "V", "childrenIds": ["T1", "N1"], "data": ["splitView": ["layoutOrientation": "horizontal"]]],
            "T1", ["id": "T1", "childrenIds": [], "data": ["tab": ["savedURL": "https://example.test/a", "savedTitle": "A"]]],
            "N1", ["id": "N1", "title": "Plans", "childrenIds": [], "data": ["arcDocument": ["arcDocumentID": "DOC-7", "isEditable": true]]]]
        let arc = try SidebarImport(arcData: ArcSidebarImportTestsSupport.document(items: items, pinned: ["V"]), notes: [note])
        guard case let .split(_, _, tabs, _, _)? = arc.spaces[0].pinned.first else {
            Issue.record("Expected a split")
            return
        }
        #expect(tabs.map(\.note) == [nil, note])
        #expect(arc.notes.isEmpty && arc.skippedItemCount == 0)
    }
}
