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
            markdown()
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
        let note = URL(fileURLWithPath: "/Users/me/Notes/Roadmap.md")
        let mentionText = "See \u{FFFC} today"
        var mention = run(mentionText, link: nil, location: 4, length: 1)
        mention.attributes.inline = .note(note, title: "Roadmap")
        let mentioned = item(mentionText, runs: [run(mentionText, link: nil, location: 0, length: 4), mention,
                                                 run(mentionText, link: nil, location: 5, length: 6)])
        let mentions = EaselBacklinkScanner.outgoing(of: mentioned)
        expectEqual(mentions.count, 1, "note mentions count as backlinks")
        expectEqual(mentions.first?.kind, .mention, "they count as mentions")
        expectEqual(mentions.first?.target, NoteBacklinkScanner.targetKey(note.absoluteString, from: URL(fileURLWithPath: "/")), "mentions point at the note")
        expectEqual(mentions.first?.snippet.text, "See Roadmap today", "the snippet spells the mention out")
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
        var mention = run("\u{FFFC}", link: nil, location: 0, length: 1)
        mention.attributes.inline = .note(old, title: "Roadmap")
        guard let moved = EaselBacklinkRewriter.rewrite(document([item("\u{FFFC}", runs: [mention])]), move: move),
              let inline = moved.items[0].richText?.runs[0].attributes.inline else { failTest("mentions of the moved note are rewritten") }
        expectEqual(inline.noteURL?.path, new.path, "mentions follow the note")
        expectEqual(inline.title, "Plan B", "mentions take the note's new name")
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
        try historyWhileLocked()
        try linksWhileLocked()
        try retracting()
    }

    static func refuses(_ name: String, _ action: () throws -> Void) {
        do {
            try action()
            failTest("\(name) is refused while locked")
        } catch EaselStoreError.lockedDocument {
        } catch {
            failTest("\(name) fails with the lock error")
        }
    }

    static func historyWhileLocked() throws {
        let session = try EaselSession(inMemory: document([]), assets: [:])
        try session.perform("Edit") { $0.title = "A" }
        try session.perform("Lock Easel") { $0.locked = true }
        expect(session.canUndo, "undo is on right after locking")
        try session.undo()
        expect(!session.document.isLocked, "undo right after locking unlocks")
        expectEqual(session.document.title, "A", "unlocking by undo keeps earlier edits")
        expect(session.canRedo, "redo is on after undoing the lock")
        try session.redo()
        expect(session.document.isLocked, "redo locks again")
        try session.perform("Unlock Easel") { $0.locked = nil }
        try session.perform("Lock Easel") { $0.locked = true }
        try session.undo()
        try session.undo()
        expect(session.document.isLocked, "undoing an unlock locks again")
        try session.redo()
        expect(!session.document.isLocked, "redo re-applies an unlock")

        let mixed = try EaselSession(inMemory: document([]), assets: [:])
        try mixed.perform("Lock and rename") { $0.locked = true; $0.title = "X" }
        expect(!mixed.canUndo, "undo is off when the step is more than the lock")
        refuses("undo") { try mixed.undo() }
        expectEqual(mixed.document.title, "X", "a refused undo changes nothing")

        try mixed.perform("Unlock Easel") { $0.locked = nil }
        try mixed.undo()
        expect(mixed.document.isLocked, "undoing the unlock locks again")
        expect(!mixed.canUndo, "undo stays off for the step before it")
        expect(mixed.canRedo, "redo is on for the unlock")
        try mixed.redo()
        expect(!mixed.document.isLocked, "redo unlocks again")
    }

    static func retracting() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") ?? Data()
        let session = try EaselSession(inMemory: document([]), assets: [:])
        let id = try session.importPNG(png)
        var picture = EaselItem(kind: .image, frame: EaselRect(x: 0, y: 0, width: 20, height: 20))
        picture.assetID = id
        try session.perform("Send Here") { $0.items = [picture] }
        try session.retractLastStep()
        expect(session.document.items.isEmpty, "a retracted step leaves the Easel as it was")
        expect(!session.canRedo, "a retracted step cannot be redone")
        session.discardUnusedAssets([id])
        expect(session.inMemoryAssets[id] == nil, "a retracted step's assets can be discarded")
    }

    static func linksWhileLocked() throws {
        let old = URL(fileURLWithPath: "/Users/me/Notes/Roadmap.md")
        let new = URL(fileURLWithPath: "/Users/me/Notes/Plan B.md")
        let move = NoteBacklinkMove(fromKey: NoteFilePaths.key(for: old), from: old, to: new)
        let text = "Roadmap"
        let folder = NoteFileTestSupport.makeFolder("easel-locked-links")
        defer { NoteFileTestSupport.remove(folder) }
        let store = try EaselStore(directory: folder)
        let session = try store.create(title: "Plans")
        try session.perform("Add") { $0.items = [item(text, runs: [run(text, link: old.absoluteString, location: 0, length: 7)], url: old.absoluteString)] }
        try session.perform("Lock Easel") { $0.locked = true }
        try session.updateLinks { EaselBacklinkRewriter.rewrite($0, move: move) }
        expect(session.document.isLocked, "updating links keeps the lock")
        expectEqual(session.document.items[0].url, new.absoluteString, "a locked Easel's object links follow the note")
        expectEqual(session.document.items[0].richText?.runs[0].attributes.link, new.absoluteString, "a locked Easel's text links follow the note")
        expectEqual(session.document.title, "Plans", "only links change")
        try session.undo()
        expectEqual(session.document.items[0].url, new.absoluteString, "history follows the note too")
        let reopened = try EaselStore(directory: folder).load(session.document.id)
        expectEqual(reopened.document.items[0].url, new.absoluteString, "the new links are saved")
        try session.perform("Lock Easel") { $0.locked = true }
        refuses("a link edit") { try session.perform("Edit") { $0.items[0].url = old.absoluteString } }
    }

    static func styled(_ location: Int, _ length: Int, bold: Bool = false, link: String? = nil, heading: Int? = nil,
                       list: String? = nil) -> EaselRichText.Run {
        var font = EaselRichText.Font(name: "Helvetica", size: 15)
        if bold { font.traits = EaselMarkdown.boldTrait }
        var attributes = EaselRichText.Attributes(font: font, ink: "#000000FF", link: link)
        if heading != nil || list != nil {
            attributes.paragraph = EaselRichText.Paragraph(alignment: 0, direction: 0, lineBreak: 0, firstIndent: 0, headIndent: 0,
                tailIndent: 0, lineSpacing: 0, before: 0, after: 0, minimumHeight: 0, maximumHeight: 0, heightMultiple: 0,
                hyphenation: 0, tightening: 0, allowsTightening: false, defaultHyphenation: false, defaultTab: 0, tabs: [],
                lists: list.map { [EaselRichText.Paragraph.List(marker: $0, options: 0, start: 1)] } ?? [], heading: heading)
        }
        return EaselRichText.Run(location: location, length: length, attributes: attributes)
    }

    static func markdown() {
        let note = URL(fileURLWithPath: "/Users/me/Notes/Roadmap.md")
        var title = item("Plans\nBold move see Roadmap\nfirst\nsecond", runs: [
            styled(0, 6, heading: 1), styled(6, 4, bold: true), styled(10, 10), styled(20, 7, link: note.absoluteString),
            styled(27, 1), styled(28, 6, list: "{disc}"), styled(34, 6, list: "{disc}")])
        title.frame = EaselRect(x: 0, y: 0, width: 300, height: 100)
        var sticky = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 200, width: 100, height: 100))
        sticky.text = "Buy milk"
        var code = EaselItem(kind: .code, frame: EaselRect(x: 0, y: 400, width: 100, height: 100))
        code.text = "print(1)"
        code.language = "python"
        var table = EaselItem(kind: .table, frame: EaselRect(x: 0, y: 600, width: 100, height: 100))
        table.table = EaselTable(columnWidths: [100, 100], rowHeights: [30, 30], cells: [
            [EaselTableCell(text: "Name"), EaselTableCell(text: "Age")], [EaselTableCell(text: "Ada"), EaselTableCell(text: "36")]])
        var doc = document([title, sticky, code, table])
        doc.title = "Plans"
        let text = EaselMarkdown.markdown(doc)
        expect(text.hasPrefix("# Plans\n"), "the title leads")
        expect(text.contains("## Plans"), "Easel headings become Markdown headings: \(text)")
        expect(text.contains("**Bold**"), "bold text keeps its emphasis: \(text)")
        expect(text.contains("[Roadmap](") && text.contains("Roadmap.md"), "links keep their targets: \(text)")
        expect(text.contains("- first") && text.contains("- second"), "bullets become list items: \(text)")
        expect(text.contains("- Buy milk"), "stickies become list items: \(text)")
        expect(text.contains("```python"), "code keeps its fence and language: \(text)")
        expect(text.contains("| Name | Age |") && text.contains("| Ada  | 36  |"), "tables become Markdown tables: \(text)")
        let order = ["## Plans", "Buy milk", "```python", "| Name"].compactMap { text.range(of: $0)?.lowerBound }
        expect(order == order.sorted(), "objects read top to bottom")
        let listText = "\t\u{2610}\tmilk\n\t\u{2611}\teggs\n\t\u{2015}\t\nSee \u{FFFC}"
        var mention = styled(24, 1)
        mention.attributes.inline = .note(note, title: "Roadmap")
        let checklist = item(listText, runs: [styled(0, 8, list: EaselChecklist.openMarker), styled(8, 8, list: EaselChecklist.doneMarker),
                                              styled(16, 4, list: EaselChecklist.dividerMarker), styled(20, 4), mention])
        let listed = EaselMarkdown.markdown(document([checklist]))
        expect(listed.contains("- [ ] milk") && listed.contains("- [x] eggs"), "to-dos become task items: \(listed)")
        expect(listed.contains("---"), "dividers become rules: \(listed)")
        expect(listed.contains("Roadmap") && !listed.contains("\u{FFFC}"), "mentions keep the note's name: \(listed)")
        let words = EaselBoardText.stats(of: doc)
        expect(words.words >= 10, "words count text, stickies and tables")
    }
}
