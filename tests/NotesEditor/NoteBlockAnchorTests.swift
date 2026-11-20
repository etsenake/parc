import Combine
import Foundation

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 29)
    }
}

struct RepeatingGenerator: RandomNumberGenerator {
    var values: [UInt64]
    var position = 0
    mutating func next() -> UInt64 {
        defer { position += 1 }
        return values[min(position, values.count - 1)]
    }
}

@main @MainActor
struct NoteBlockAnchorTests {
    static func main() {
        githubSlugs()
        headingSlugsDeduplicate()
        anchorLookup()
        anchorsAreShortAndUnique()
        ensureAnchorWritesWithoutUndo()
        metadataSurvivesUndoAndRedo()
        metadataKeepsTypingCoalesced()
        metadataRespectsReadOnly()
        copiesDropAnchors()
        undoEffectsRunWithHistory()
        createdFileGoesToTrashAndBack()
        editedFileStaysPut()
        print("NoteBlockAnchorTests passed")
    }

    static func githubSlugs() {
        expectEqual(NoteAnchor.githubSlug("Hello, World!"), "hello-world", "punctuation drops and spaces become dashes")
        expectEqual(NoteAnchor.githubSlug("A  B"), "a--b", "every space becomes its own dash, like GitHub")
        expectEqual(NoteAnchor.githubSlug("snake_case-ok"), "snake_case-ok", "underscores and dashes stay")
        expectEqual(NoteAnchor.githubSlug("Ünïcode Straße 2"), "ünïcode-straße-2", "letters from every script stay")
        expectEqual(NoteAnchor.githubSlug("C# & F#"), "c--f", "symbols vanish but their spaces don't")
        expectEqual(NoteAnchor.githubSlug("🎉 Party"), "-party", "emoji drop out")
    }

    static func headingSlugsDeduplicate() {
        let page = NotePage(blocks: [heading(1, "Intro"), para("Intro"), heading(2, "Intro"), heading(3, "Intro-1"), heading(2, "Next step")])
        expectEqual(page.headingSlugs().map(\.slug), ["intro", "intro-1", "intro-1-1", "next-step"], "repeats count up the way GitHub does")
    }

    static func anchorLookup() {
        var anchored = para("Pinned")
        anchored.props.anchor = "k3x9qa"
        let page = NotePage(blocks: [heading(1, "My Plan"), anchored, toggle("Box", [heading(2, "Inside Out")])])
        let plan = page.blocks[0].id, inside = page.blocks[2].children[0].id
        expectEqual(page.block(forAnchor: "k3x9qa"), anchored.id, "an exact anchor wins")
        expectEqual(page.block(forAnchor: "#k3x9qa"), anchored.id, "a leading hash is fine")
        expectEqual(page.block(forAnchor: "my-plan"), plan, "headings answer to their GitHub slug")
        expectEqual(page.block(forAnchor: "My%20Plan"), plan, "and to their plain, percent-encoded text")
        expectEqual(page.block(forAnchor: "inside-out"), inside, "nested headings count too")
        expectEqual(page.block(forAnchor: "K3X9QA"), nil, "anchors are exact")
        expectEqual(page.block(forAnchor: "nowhere"), nil, "unknown anchors find nothing")
        expectEqual(page.block(forAnchor: ""), nil, "an empty fragment finds nothing")
    }

    static func anchorsAreShortAndUnique() {
        var generator = SeededGenerator(state: 7)
        for _ in 0..<200 {
            let anchor = NoteAnchor.make(using: &generator)
            expect(anchor.count == NoteAnchor.length && anchor.first!.isLetter && NoteAnchor.isValid(anchor), "anchors are six fragment-safe characters starting with a letter: \(anchor)")
        }
        var taken = para("Taken")
        taken.props.anchor = "aaaaaa"
        let page = NotePage(blocks: [taken, heading(1, "Abbbbb")])
        var repeating = RepeatingGenerator(values: Array(repeating: 0, count: 6) + Array(repeating: 1, count: 6) + Array(repeating: 2, count: 6))
        let fresh = page.uniqueAnchor(using: &repeating, avoiding: ["acccccc"])
        expect(fresh != "aaaaaa" && fresh != "abbbbb", "a new anchor skips existing anchors and heading slugs: \(fresh)")
        expect(!NoteAnchor.isValid("has space") && !NoteAnchor.isValid("") && !NoteAnchor.isValid("quote\""), "odd anchors are refused")
    }

    static func ensureAnchorWritesWithoutUndo() {
        let session = makeSession([para("One"), para("Two")])
        let two = session.id("Two")
        var changes: [NotePageChange] = []
        let subscription = session.changes.sink { changes.append($0) }
        var generator = SeededGenerator(state: 11)
        let anchor = session.ensureAnchor(for: two, using: &generator)
        expect(anchor != nil && session.page.block(two)?.props.anchor == anchor, "the block keeps its new anchor")
        expect(!session.canUndo, "assigning an anchor isn't an undo step")
        expectEqual(changes.count, 1, "but it announces one change so the file saves")
        expect(changes.first?.kind == .text && changes.first?.blocks == [two], "a quiet text-kind change for just that block")
        expectEqual(session.ensureAnchor(for: two, using: &generator), anchor, "asking again reuses the anchor")
        expectEqual(changes.count, 1, "and changes nothing")
        expectEqual(session.ensureAnchor(for: NoteBlockID(), using: &generator), nil, "missing blocks get nothing")
        subscription.cancel()
    }

    static func metadataSurvivesUndoAndRedo() {
        let session = makeSession([para("Keep"), para("Other")])
        let keep = session.id("Keep")
        session.caret("Other", 5)
        session.type("!")
        session.updateBlockMetadata(keep) { $0.props.anchor = "keep01" }
        session.undo()
        expectEqual(session.page.block(keep)?.props.anchor, "keep01", "undoing an earlier edit keeps the anchor")
        session.redo()
        expectEqual(session.page.block(keep)?.props.anchor, "keep01", "and so does redo")
        expectOutline(session.page, "p Keep\np Other!", "while the text history still works")

        let fresh = makeSession([para("Gone"), para("Stays")])
        let gone = fresh.id("Gone"), stays = fresh.id("Stays")
        var first = SeededGenerator(state: 3)
        let old = fresh.ensureAnchor(for: gone, using: &first)
        fresh.deleteBlocks([gone])
        var same = SeededGenerator(state: 3)
        let assigned = fresh.ensureAnchor(for: stays, using: &same)
        expect(old != nil && assigned != nil && assigned != old, "anchors still waiting in the undo history aren't reused")
        fresh.undo()
        expectEqual(fresh.page.blockAnchors.count, 2, "so undoing the delete never makes twins")
    }

    static func metadataKeepsTypingCoalesced() {
        let clock = TestClock()
        let session = makeSession([para(""), para("Card")], clock: clock)
        let card = session.id("Card")
        session.setSelection(.caret(NotePosition(session.page.blocks[0].id, 0)))
        session.type("H")
        clock.advance(0.2)
        session.updateBlockMetadata(card) { $0.props.anchor = "card01" }
        clock.advance(0.2)
        session.type("i")
        expectEqual(session.undoDepth, 1, "a metadata write between keystrokes doesn't split the typing")
        session.undo()
        expectOutline(session.page, "p\np Card", "the burst undoes in one go")
        expectEqual(session.page.block(card)?.props.anchor, "card01", "and the metadata stays")
    }

    static func metadataRespectsReadOnly() {
        let session = makeSession([para("Locked")])
        session.isReadOnly = true
        let id = session.id("Locked")
        session.updateBlockMetadata(id) { $0.props.anchor = "nope01" }
        expectEqual(session.page.block(id)?.props.anchor, nil, "read-only sessions take no metadata")
        expectEqual(session.ensureAnchor(for: id), nil, "and hand out no new anchors")
    }

    static func copiesDropAnchors() {
        var anchored = para("Original")
        anchored.props.anchor = "orig01"
        var parent = toggle("Parent", [anchored])
        parent.props.anchor = "par001"
        let session = makeSession([parent])
        let copies = session.duplicateBlocks([session.id("Parent")])
        let copy = session.page.block(copies[0])
        expect(copy?.props.anchor == nil && copy?.children.first?.props.anchor == nil, "duplicates don't steal anchors")
        expectEqual(session.page.blockAnchors, ["orig01", "par001"], "the originals keep theirs")
        session.turnInto([session.id("Original")], kind: .heading) { $0.level = 2 }
        expectEqual(session.page.block(session.page.blocks[0].children[0].id)?.props.anchor, "orig01", "turning a block into another keeps its anchor")
    }

    static func undoEffectsRunWithHistory() {
        let session = makeSession([para("A")])
        var log: [String] = []
        let effect = NoteUndoEffect(undo: { log.append("undo") }, redo: { log.append("redo") })
        session.edit("Change", effect: effect) { page in page.update(page.blocks[0].id) { $0.text = NoteText("B") } }
        session.undo()
        expectEqual(log, ["undo"], "undo runs the effect")
        expectOutline(session.page, "p A", "after restoring the page")
        session.redo()
        expectEqual(log, ["undo", "redo"], "redo runs it again")
        session.edit("Nothing", effect: effect) { _ in }
        expectEqual(session.undoDepth, 1, "an edit that changes nothing records nothing")
        session.group("Both") {
            session.edit("One", effect: NoteUndoEffect(undo: { log.append("first") }, redo: {})) { page in
                page.update(page.blocks[0].id) { $0.text = NoteText("C") }
            }
            session.edit("Two", effect: NoteUndoEffect(undo: { log.append("second") }, redo: {})) { page in
                page.update(page.blocks[0].id) { $0.text = NoteText("D") }
            }
        }
        session.undo()
        expectEqual(Array(log.suffix(2)), ["second", "first"], "a group undoes its effects newest first")
        session.clearHistory()
        session.undo()
        expectEqual(log.count, 4, "cleared history forgets effects")
    }

    static func createdFileGoesToTrashAndBack() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-tests-\(UUID().uuidString)")
        let trash = root.appendingPathComponent("Trash")
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Spun Off.md")
        let contents = Data("Hello\n".utf8)
        try? contents.write(to: url)
        let mover: (URL) throws -> URL? = { source in
            let destination = trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        let created = NoteCreatedFile(url: url, contents: contents, trash: mover)
        let session = makeSession([para("Spun Off")])
        session.edit("Turn Into Page", effect: created.effect) { page in page.update(page.blocks[0].id) { $0.kind = .pageLink } }
        session.undo()
        expect(!FileManager.default.fileExists(atPath: url.path) && created.isWithdrawn, "undo moves the untouched page to the Trash")
        session.redo()
        expect(FileManager.default.contents(atPath: url.path) == contents, "redo brings it back")
        session.undo()
        try? FileManager.default.removeItem(at: trash.appendingPathComponent("Spun Off.md"))
        session.redo()
        expect(FileManager.default.contents(atPath: url.path) == contents, "even an emptied Trash can't stop redo, the page is rewritten")
    }

    static func editedFileStaysPut() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Busy.md")
        let contents = Data("Draft\n".utf8)
        try? Data("Draft, now longer\n".utf8).write(to: url)
        var trashed = false
        let created = NoteCreatedFile(url: url, contents: contents, trash: { _ in trashed = true; return nil })
        created.withdraw()
        expect(!trashed && !created.isWithdrawn && FileManager.default.fileExists(atPath: url.path), "a page someone edited is left alone")
        created.restore()
        expect(FileManager.default.contents(atPath: url.path) == Data("Draft, now longer\n".utf8), "and restore doesn't touch it either")
        let failing = NoteCreatedFile(url: url, contents: Data("Draft, now longer\n".utf8), trash: { _ in throw CocoaError(.fileWriteNoPermission) })
        failing.withdraw()
        expect(!failing.isWithdrawn && FileManager.default.fileExists(atPath: url.path), "a Trash that says no leaves the file where it was")
    }
}
