import Foundation

@main @MainActor
struct EaselBoardTests {
    static let clock = ManualNoteClock()

    static func main() {
        exitOnFailure {
            NoteBacklinkIndex.clock = clock
            NoteBacklinkIndex.worker = .inline
            NoteFileSession.worker = .inline
            NoteLibrary.clock = clock
            NoteLibrary.worker = .inline
            validation()
            scanning()
            rewriting()
            try indexing()
            try locking()
            print("EaselBoardTests passed")
        }
    }

    static func run(_ text: String, link: String?, location: Int, length: Int) -> EaselRichText.Run {
        let font = EaselRichText.Font(name: "Helvetica", size: 15)
        return EaselRichText.Run(location: location, length: length,
                                 attributes: EaselRichText.Attributes(font: font, ink: "#000000FF", link: link))
    }

    static func item(_ text: String, runs: [EaselRichText.Run], url: String? = nil) -> EaselItem {
        var item = EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 200, height: 40))
        item.text = text
        item.richText = EaselRichText(runs: runs)
        item.url = url
        return item
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Plans", createdAt: Date(), modifiedAt: Date(), items: items)
    }

    static func validation() {
        expect(EaselRichText.validLink("file:///Users/me/Notes/Roadmap.md"), "note file links are valid")
        expect(EaselRichText.validLink("parc://easel/" + UUID().uuidString.lowercased()), "Easel links are valid")
        expect(!EaselRichText.validLink("file://evil.example/Users/me/a.md"), "remote file hosts are refused")
        expect(!EaselRichText.validLink("parc://settings"), "other parc addresses are refused")
        expect(EaselObjectLink.normalized("file:///Users/me/Notes/Roadmap.md") == "file:///Users/me/Notes/Roadmap.md", "objects can link to notes")
        var linked = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 40, height: 40))
        linked.url = "file:///Users/me/Notes/Roadmap.md"
        let doc = document([linked])
        let session = try? EaselSession(inMemory: doc, assets: [:])
        expect(session != nil, "a shape linked to a note saves")
        var card = EaselItem(kind: .link, frame: EaselRect(x: 0, y: 0, width: 40, height: 40))
        card.url = "file:///Users/me/Notes/Roadmap.md"
        expect((try? EaselSession(inMemory: document([card]), assets: [:])) == nil, "cards still need web addresses")
    }

    static func scanning() {
        let link = "file:///Users/me/Notes/Roadmap.md"
        let text = "See the Roadmap now"
        let plain = run(text, link: nil, location: 0, length: 8)
        let first = run(text, link: link, location: 8, length: 4)
        let second = run(text, link: link, location: 12, length: 3)
        let tail = run(text, link: nil, location: 15, length: 4)
        let found = EaselBacklinkScanner.outgoing(of: item(text, runs: [plain, first, second, tail]))
        expectEqual(found.count, 1, "adjacent runs with one link count once")
        expectEqual(found.first?.target, NoteBacklinkScanner.targetKey(link, from: URL(fileURLWithPath: "/")), "the target is the note's key")
        expect(found.first?.snippet.text.contains("Roadmap") == true, "the snippet shows the linked words")
        let object = item("Plan", runs: [run("Plan", link: nil, location: 0, length: 4)], url: link)
        expectEqual(EaselBacklinkScanner.outgoing(of: object).count, 1, "object links are found")
        let web = item("Web", runs: [run("Web", link: "https://example.com", location: 0, length: 3)])
        expect(EaselBacklinkScanner.outgoing(of: web).isEmpty, "web links are not backlinks")
    }

    static func rewriting() {
        let old = URL(fileURLWithPath: "/Users/me/Notes/Roadmap.md")
        let new = URL(fileURLWithPath: "/Users/me/Notes/Plan B.md")
        let move = NoteBacklinkMove(fromKey: NoteFilePaths.key(for: old), from: old, to: new)
        let text = "Roadmap"
        let doc = document([item(text, runs: [run(text, link: old.absoluteString + "#goals", location: 0, length: 7)], url: old.absoluteString)])
        guard let next = EaselBacklinkRewriter.rewrite(doc, move: move) else { failTest("links to the moved note are rewritten") }
        expectEqual(next.items[0].url, new.absoluteString, "object links follow the note")
        expectEqual(next.items[0].richText?.runs[0].attributes.link, new.absoluteString + "#goals", "text links follow the note and keep their heading")
        expectEqual(next.items[0].text, text, "only the link changes")
        let other = document([item(text, runs: [run(text, link: "file:///Users/me/Notes/Other.md", location: 0, length: 7)])])
        expect(EaselBacklinkRewriter.rewrite(other, move: move) == nil, "other links are left alone")
    }

    static func indexing() throws {
        let folder = NoteFileTestSupport.makeFolder("easel-backlinks")
        defer { NoteFileTestSupport.remove(folder) }
        let notes = folder.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let note = notes.appendingPathComponent("Roadmap.md")
        try "# Roadmap\n".write(to: note, atomically: true, encoding: .utf8)
        let store = try EaselStore(directory: folder.appendingPathComponent("Easels", isDirectory: true))
        let session = try store.create(title: "Plans")
        let text = "Roadmap"
        let linked = item(text, runs: [run(text, link: note.absoluteString, location: 0, length: 7)])
        try session.perform("Add") { $0.items = [linked] }
        let index = NoteBacklinkIndex()
        index.include(store)
        clock.advance(2)
        let found = index.backlinks(to: note)
        expectEqual(found.count, 1, "an Easel that links to a note is a backlink")
        expect(found.first?.isEasel == true, "the backlink is an Easel")
        expectEqual(found.first?.title, "Plans", "the Easel's title is shown")
        expectEqual(found.first?.destination.fragment, linked.id.uuidString.lowercased(), "it opens at the object")
    }

    static func locking() throws {
        let session = try EaselSession(inMemory: document([item("Hello", runs: [run("Hello", link: nil, location: 0, length: 5)])]), assets: [:])
        try session.perform("Lock Easel") { $0.locked = true }
        expect(session.document.isLocked, "the Easel locks")
        do {
            try session.perform("Edit") { $0.title = "Changed" }
            failTest("a locked Easel refuses edits")
        } catch EaselStoreError.lockedDocument {
        }
        try session.undo()
        expect(!session.document.isLocked, "undo unlocks the Easel")
        try session.perform("Edit") { $0.title = "Changed" }
        expectEqual(session.document.title, "Changed", "an unlocked Easel takes edits again")
        try session.perform("Lock Easel") { $0.locked = true }
        try session.perform("Unlock Easel") { $0.locked = nil }
        expect(!session.document.isLocked, "unlocking is allowed on a locked Easel")
        let encoded = String(decoding: try JSONEncoder().encode(session.document), as: UTF8.self)
        expect(!encoded.contains("locked"), "an unlocked Easel leaves the field out of the file")
    }
}
