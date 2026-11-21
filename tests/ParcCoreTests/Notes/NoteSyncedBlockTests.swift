import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteSyncedBlockTests: NoteFixtures {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("parc-synced-tests-" + UUID().uuidString, isDirectory: true)

    final class Engines { var all: [NoteSyncedBlocks] = [] }
    let engines = Engines()

    func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    func makeEngine() -> NoteSyncedBlocks {
        let engine = NoteSyncedBlocks()
        engines.all.append(engine)
        return engine
    }

    func original(_ anchor: String?, _ texts: [String]) -> NoteBlock {
        var block = NoteBlock(.synced, children: texts.map { .paragraph(NoteText($0)) })
        block.props.anchor = anchor
        return block
    }

    func copy(_ target: String, _ texts: [String]) -> NoteBlock {
        var block = NoteBlock(.synced, children: texts.map { .paragraph(NoteText($0)) })
        block.props.target = target
        return block
    }

    func session(_ blocks: [NoteBlock]) -> NotePageSession {
        NotePageSession(page: NotePage(blocks: blocks))
    }

    func attach(_ engine: NoteSyncedBlocks, _ session: NotePageSession, _ name: String) {
        engine.attach(session, location: { url(name) })
    }

    func site(_ session: NotePageSession, _ index: Int = 0) -> NoteBlock {
        session.page.syncedSites()[index]
    }

    func texts(_ session: NotePageSession, _ index: Int = 0) -> [String] {
        site(session, index).children.map(\.text.string)
    }

    func type(_ text: String, in session: NotePageSession, site index: Int = 0, child: Int = 0) {
        let id = site(session, index).children[child].id
        session.edit("Typing", kind: .text, coalescing: .typing(id, .body), affected: [id]) { page in
            page.update(id) { $0.text = NoteText(text) }
        }
    }

    func pair() -> (NoteSyncedBlocks, NotePageSession, NotePageSession) {
        let engine = makeEngine()
        let a = session([.paragraph("Intro"), original("k3x9qa", ["One"])])
        let b = session([copy("A.md#k3x9qa", ["stale"]), .paragraph("After")])
        attach(engine, a, "A.md")
        attach(engine, b, "B.md")
        return (engine, a, b)
    }

    @Test func copiesResolveOnAttach() {
        let (_, a, b) = pair()
        #expect(texts(b) == ["One"], "the copy shows the original's live content")
        let originalChild = site(a).children[0].id
        #expect(site(b).children[0].id == NoteSyncedBlocks.mix(originalChild, site(b).id), "copy blocks get stable mirrored ids")
        #expect(!b.canUndo, "resolving a copy is not an undo step")
    }

    @Test func copiesResolveWhenTheOriginalArrivesLater() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["Live"])])
        let b = session([copy("A.md#k3x9qa", ["Snapshot"])])
        attach(engine, b, "B.md")
        #expect(texts(b) == ["Snapshot"], "without the original the snapshot stays")
        #expect(engine.info(for: site(b).id, in: b)?.isMissing == true, "and the copy says it can't find the original")
        attach(engine, a, "A.md")
        #expect(texts(b) == ["Live"], "the copy catches up once the original opens")
        #expect(engine.info(for: site(b).id, in: b)?.isMissing == false, "and it's found")
    }

    @Test func typingInACopyEditsTheOriginal() {
        let (_, a, b) = pair()
        type("One!", in: b)
        #expect(texts(a) == ["One!"], "the original follows the copy")
        #expect(a.undoActionName == NoteSyncedBlocks.stepName, "the original gets a synced step")
        #expect(a.undoDepth == 1, "one step in the original")
    }

    @Test func undoFromTheCopySide() {
        let (_, a, b) = pair()
        type("One!", in: b)
        b.undo()
        #expect(texts(b) == ["One"], "undo in the copy reverts the copy")
        #expect(texts(a) == ["One"], "and the original")
        #expect(!a.canUndo && a.canRedo, "the original's step moved to redo alongside")
    }

    @Test func undoFromTheOriginalSide() {
        let (_, a, b) = pair()
        type("One!", in: b)
        a.undo()
        #expect(texts(a) == ["One"], "undo in the original reverts it")
        #expect(texts(b) == ["One"], "and the copy that was typed in")
        #expect(!b.canUndo && b.canRedo, "the copy's typing step waits in redo")
    }

    @Test func redoFromTheOtherSide() {
        let (_, a, b) = pair()
        type("One!", in: b)
        a.undo()
        b.redo()
        #expect(texts(b) == ["One!"], "redo in the copy brings the typing back")
        #expect(texts(a) == ["One!"], "and in the original")
        #expect(a.canUndo && !a.canRedo, "the original's step came back too")
        b.undo()
        a.redo()
        #expect(texts(b) == ["One!"], "redo in the original brings the copy along")
    }

    @Test func typingCoalescesIntoOneSharedStep() {
        let (_, a, b) = pair()
        type("O", in: b)
        type("On", in: b)
        type("One more", in: b)
        #expect(b.undoDepth == 1, "typing coalesces in the copy")
        #expect(a.undoDepth == 1, "and the original keeps one matching step")
        a.undo()
        #expect(texts(b) == ["One"], "one undo from the original reverts the whole burst")
    }

    @Test func undoFromAThirdNote() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["One"])])
        let b = session([copy("A.md#k3x9qa", [])])
        let c = session([copy("A.md#k3x9qa", [])])
        attach(engine, a, "A.md")
        attach(engine, b, "B.md")
        attach(engine, c, "C.md")
        type("Two", in: a)
        #expect(texts(b) == ["Two"], "every copy follows the original")
        #expect(texts(c) == ["Two"], "every copy follows the original")
        c.undo()
        #expect(texts(a) == ["One"], "undo in any copy reverts the original")
        #expect(texts(b) == ["One"], "and the other copies")
        #expect(!b.canUndo, "the other copy's step retraced")
    }

    @Test func sameNoteCopyEditsTheOriginalInOneStep() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["One"]), .paragraph("Between"), copy("#k3x9qa", [])])
        attach(engine, a, "A.md")
        #expect(texts(a, 1) == ["One"], "a copy in the same note resolves")
        type("Uno", in: a, site: 1)
        #expect(texts(a, 0) == ["Uno"], "typing in it edits the original right there")
        #expect(a.undoDepth == 1, "in the same undo step")
        a.undo()
        #expect(texts(a, 0) == ["One"], "one undo reverts both")
        #expect(texts(a, 1) == ["One"], "one undo reverts both")
    }

    @Test func busyOriginalGetsACompensatingStep() {
        let (_, a, b) = pair()
        type("One!", in: b)
        let intro = a.page.blocks[0].id
        a.edit("Typing", kind: .text, coalescing: .typing(intro, .body), affected: [intro]) { page in
            page.update(intro) { $0.text = "Intro!" }
        }
        b.undo()
        #expect(texts(a) == ["One"], "the original follows the undo even with newer work on top")
        #expect(a.page.blocks[0].text.string == "Intro!", "and keeps that newer work")
        a.undo()
        #expect(texts(a) == ["One!"], "undoing that catch-up step brings the edit back")
        #expect(texts(b) == ["One!"], "in the copy too")
    }

    @Test func unrelatedUndoKeepsLiveContent() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["Live"])])
        let b = session([copy("A.md#k3x9qa", ["Snapshot"]), .paragraph("Note")])
        attach(engine, b, "B.md")
        let note = b.page.blocks[1].id
        b.edit("Typing", kind: .text, coalescing: .typing(note, .body), affected: [note]) { page in page.update(note) { $0.text = "Note!" } }
        attach(engine, a, "A.md")
        #expect(texts(b) == ["Live"], "the copy went live")
        b.undo()
        #expect(b.page.blocks[1].text.string == "Note", "the unrelated edit undid")
        #expect(texts(b) == ["Live"], "and the copy stayed live instead of reviving the snapshot")
    }

    @Test func missingOriginalKeepsTheSnapshot() {
        let engine = makeEngine()
        let b = session([copy("Nowhere.md#k3x9qa", ["Snapshot"])])
        attach(engine, b, "B.md")
        type("Edited", in: b)
        #expect(texts(b) == ["Edited"], "a copy without its original still edits locally")
        let info = engine.info(for: site(b).id, in: b)
        #expect(info?.isMissing == true && info?.isOriginal == false, "and reports the missing original")
    }

    @Test func deletedOriginalComesBackWithUndo() {
        let (engine, a, b) = pair()
        let id = site(a).id
        a.edit("Delete") { page in page.remove(id) }
        #expect(engine.info(for: site(b).id, in: b)?.isMissing == true, "deleting the original leaves the copy on its own")
        #expect(texts(b) == ["One"], "with its last content")
        a.undo()
        #expect(engine.info(for: site(b).id, in: b)?.isMissing == false, "undo brings the original back")
        type("Back", in: b)
        #expect(texts(a) == ["Back"], "and the link works again")
    }

    @Test func renamedOriginalIsFoundByItsAnchor() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["One"])])
        let b = session([copy("Old%20name.md#k3x9qa", ["stale"])])
        engine.attach(a, location: { url("New name.md") })
        attach(engine, b, "B.md")
        #expect(texts(b) == ["One"], "the copy finds the renamed original by its id")
        #expect(site(b).props.target == "New%20name.md#k3x9qa", "and points at the new name from now on")
        #expect(!b.canUndo, "fixing the reference is not an undo step")
    }

    @Test func externalReloadRefreshesCopies() {
        let (_, a, b) = pair()
        var reloaded = a.page
        reloaded.update(site(a).id) { $0.children = [.paragraph("From disk")] }
        a.replacePage(reloaded)
        #expect(texts(b) == ["From disk"], "copies refresh when the original's file changes")
        #expect(!b.canUndo, "without adding undo steps to the copy")
    }

    @Test func anchorsStayWithTheOriginal() {
        let engine = makeEngine()
        var inner = NoteBlock.paragraph("Pinned")
        inner.props.anchor = "pin123"
        var synced = NoteBlock(.synced, children: [inner])
        synced.props.anchor = "k3x9qa"
        let a = session([synced])
        let b = session([copy("A.md#k3x9qa", [])])
        attach(engine, a, "A.md")
        attach(engine, b, "B.md")
        #expect(site(b).children[0].props.anchor == nil, "copies never repeat block ids")
        type("Pinned!", in: b)
        #expect(site(a).children[0].props.anchor == "pin123", "the original keeps its block link through copy edits")
    }

    @Test func turnIntoSyncedWrapsTheSelection() {
        let a = session([.paragraph("One"), .paragraph("Two"), .paragraph("Three")])
        let ids = Array(a.page.blocks.prefix(2).map(\.id))
        let id = a.turnIntoSynced(ids)
        #expect(id != nil, "the selection turns into a synced block")
        #expect(a.page.blocks.map(\.kind) == [.synced, .paragraph], "wrapped in place")
        #expect(texts(a) == ["One", "Two"], "with the blocks inside")
        #expect(a.selection == .blocks([id!]), "and the new block selected")
        #expect(!a.page.canTurnIntoSynced([a.page.blocks[0].children[0].id]), "blocks already inside a synced block can't nest another")
        a.undo()
        #expect(a.page.blocks.map(\.text.string) == ["One", "Two", "Three"], "undo unwraps")
    }

    @Test func slashInsertsAnEmptySyncedBlock() {
        let a = session([.paragraph()])
        let id = a.insertSyncedBlock(replacing: a.page.blocks[0].id)
        #expect(id != nil, "the slash command makes a synced block")
        #expect(a.page.blocks.map(\.kind) == [.synced], "replacing the empty line")
        guard case .text(let anchor, _) = a.selection else { Issue.record("the caret goes inside"); return }
        #expect(anchor.block == a.page.blocks[0].children[0].id, "into its first line")
    }

    @Test func duplicatingAnOriginalMakesACopy() {
        let engine = makeEngine()
        let a = session([original(nil, ["One"])])
        attach(engine, a, "A.md")
        let copies = a.duplicateBlocks([site(a).id])
        let anchor = site(a).props.anchor
        #expect(anchor != nil, "the original gets an id to point at")
        #expect(a.page.block(copies[0])?.props.target == "#" + (anchor ?? ""), "the duplicate is a synced copy")
        type("Both", in: a, site: 1)
        #expect(texts(a, 0) == ["Both"], "and stays in sync")
    }

    @Test func pastedTwinOriginalBecomesACopy() {
        let (_, a, b) = pair()
        let twin = site(a).withFreshIDs()
        b.edit("Paste") { page in page.blocks.append(twin) }
        let pasted = b.page.block(twin.id)
        #expect(pasted?.isSyncedCopy == true, "a second original with the same id turns into a copy")
        #expect(pasted?.props.target == "A.md#k3x9qa", "pointing at the first one")
    }

    @Test func unsyncTurnsACopyIntoBlocks() {
        let (_, a, b) = pair()
        #expect(b.unsync(site(b).id), "unsync works on a copy")
        #expect(b.page.blocks.map(\.text.string) == ["One", "After"], "the copy becomes ordinary blocks")
        type("One!", in: a)
        #expect(b.page.blocks[0].text.string == "One", "and stops following the original")
        b.undo()
        #expect(texts(b) == ["One!"], "undo makes it a live copy again")
    }

    @Test func unsyncAllFreesEveryCopy() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["One"]), copy("#k3x9qa", [])])
        let b = session([copy("A.md#k3x9qa", [])])
        let c = session([copy("A.md#k3x9qa", [])])
        attach(engine, a, "A.md")
        attach(engine, b, "B.md")
        attach(engine, c, "C.md")
        #expect(engine.unsyncAll(site(a).id, in: a) == 3, "three copies let go")
        for note in [a, b, c] { #expect(note.page.syncedSites().isEmpty, "no synced blocks remain") }
        #expect(a.page.blocks.map(\.text.string) == ["One", "One"], "everything stays as ordinary blocks")
        b.undo()
        #expect(!a.page.syncedSites().isEmpty && !c.page.syncedSites().isEmpty, "undo in a copy restores the sync everywhere")
        type("Again", in: a)
        #expect(texts(c) == ["Again"], "and it's live again")
    }

    @Test func copyAndSyncBuildsAPortableReference() {
        let engine = makeEngine()
        let a = session([original(nil, ["One"])])
        let b = session([copy("A.md#zz9zz9", [])])
        engine.attach(a, location: { url("Folder/A note.md") })
        engine.attach(b, location: { url("Folder/Sub/B.md") })
        let reference = engine.reference(for: site(a).id, in: a)
        let anchor = site(a).props.anchor ?? ""
        #expect(!anchor.isEmpty, "copying an original gives it an id")
        #expect(reference?.props.target == "A%20note.md#" + anchor, "the reference names the note beside the copy")
        #expect(reference?.children.map(\.text.string) == ["One"], "with a snapshot of the content")
        let local = session([original("loc123", ["x"]), copy("#loc123", [])])
        engine.attach(local, location: { url("Folder/Local.md") })
        #expect(engine.reference(for: site(local, 1).id, in: local)?.props.target == "Local.md#loc123", "a same-note copy names its note")
    }

    @Test func pastedReferencesToTheSameNoteGoLocal() {
        let block = copy("A.md#k3x9qa", ["x"])
        #expect(block.localizingSyncedTargets(documentURL: url("A.md")).props.target == "#k3x9qa", "same note references shorten")
        #expect(block.localizingSyncedTargets(documentURL: url("B.md")).props.target == "A.md#k3x9qa", "others stay")
    }

    @Test func cutAndPasteKeepsTheOriginal() {
        let (engine, a, b) = pair()
        let moving = site(a).withFreshIDs()
        #expect(moving.props.anchor == "k3x9qa", "a fresh copy of an original keeps its id for moving")
        let c = session([.paragraph("Here")])
        attach(engine, c, "C.md")
        a.edit("Cut") { page in page.remove(site(a).id) }
        c.edit("Paste") { page in page.blocks.append(moving) }
        #expect(c.page.syncedSites().first?.isSyncedOriginal == true, "pasting a cut original keeps it an original")
        #expect(site(b).props.target == "C.md#k3x9qa", "copies follow it to its new note")
        type("Moved", in: b)
        #expect(texts(c) == ["Moved"], "and stay live")
    }

    @Test func holdsOpenOriginalsAndLetsThemGo() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["Held"])])
        let b = session([copy("A.md#k3x9qa", ["stale"])])
        attach(engine, b, "B.md")
        var opened: [String] = []
        var ended = 0
        engine.opener = { target in
            opened.append(target.lastPathComponent)
            guard target.lastPathComponent == "A.md" else { return nil }
            attach(engine, a, "A.md")
            return NoteSyncedLease {
                ended += 1
                engine.detach(a)
            }
        }
        let hold = engine.hold(b)
        #expect(opened == ["A.md"], "the hold opens the original's note")
        #expect(texts(b) == ["Held"], "so the copy goes live")
        #expect(hold.heldCount == 1, "and keeps it open")
        b.edit("Delete") { page in page.remove(site(b).id) }
        #expect(ended == 1, "once no copy needs it, the note is let go")
        hold.end()
        #expect(ended == 1, "ending the hold doesn't let go twice")
    }

    @Test func holdsFindMovedOriginalsInTheLibrary() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["Moved"])])
        let b = session([copy("Gone.md#k3x9qa", ["stale"])])
        attach(engine, b, "B.md")
        engine.originalFinder = { anchor, _ in anchor == "k3x9qa" ? [url("Elsewhere/A.md")] : [] }
        engine.opener = { target in
            guard target.lastPathComponent == "A.md" else { return nil }
            attach(engine, a, "Elsewhere/A.md")
            return NoteSyncedLease { engine.detach(a) }
        }
        let hold = engine.hold(b)
        #expect(texts(b) == ["Moved"], "the copy finds its original in the library")
        #expect(site(b).props.target == "Elsewhere/A.md#k3x9qa", "and remembers where it went")
        hold.end()
    }

    @Test func infoListsOtherNotes() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["One"])])
        let b = session([copy("A.md#k3x9qa", [])])
        attach(engine, a, "A.md")
        attach(engine, b, "B.md")
        engine.noteFinder = { _, _ in [url("C.md"), url("B.md")] }
        let fromCopy = engine.info(for: site(b).id, in: b)
        #expect(fromCopy?.notes.map(\.lastPathComponent) == ["A.md", "C.md"], "a copy lists the original first, then closed notes")
        let fromOriginal = engine.info(for: site(a).id, in: a)
        #expect(fromOriginal?.notes.map(\.lastPathComponent) == ["B.md", "C.md"], "the original lists every other note")
        #expect(fromOriginal?.isOriginal == true, "and knows it's the original")
    }

    @Test func syncedBlocksNeverNest() {
        let a = session([original("k3x9qa", ["Inside"]), copy("#k3x9qa", ["Inside"])])
        let target = site(a, 0).children[0].id
        a.moveBlocks([site(a, 1).id], to: .after(target))
        #expect(a.page.syncedSites().count == 2, "a synced block can't be dragged into another one")
        #expect(texts(a, 0) == ["Inside"], "the original keeps its content")
    }

    @Test func backspaceStaysInside() {
        let a = session([.paragraph("Before"), original("k3x9qa", ["One", "Two"])])
        let synced = site(a).id
        let first = site(a).children[0].id, second = site(a).children[1].id
        a.mergeBackward(second)
        #expect(texts(a) == ["OneTwo"], "backspace inside joins lines within the synced block")
        a.mergeBackward(first)
        #expect(texts(a) == ["OneTwo"], "backspace at the very start never pulls content out")
        #expect(a.selection == .blocks([synced]), "it selects the synced block instead")
        let b = session([original("k3x9qa", ["", "Keep"])])
        b.mergeBackward(site(b).children[0].id)
        #expect(texts(b) == ["Keep"], "an empty first line just goes away")
    }

    @Test func closedCopiesCatchUp() {
        let engine = makeEngine()
        let a = session([original("k3x9qa", ["One"])])
        attach(engine, a, "A.md")
        let closed = session([copy("A.md#k3x9qa", ["One"])])
        var opened = 0, ended = 0
        engine.noteFinder = { _, _ in [url("Closed.md")] }
        engine.opener = { target in
            guard target.lastPathComponent == "Closed.md" else { return nil }
            opened += 1
            attach(engine, closed, "Closed.md")
            return NoteSyncedLease {
                ended += 1
                engine.detach(closed)
            }
        }
        type("Two", in: a)
        engine.refreshClosedCopies(of: NoteSyncedGroup(file: NoteFilePaths.key(for: url("A.md")), anchor: "k3x9qa"))
        #expect(opened == 1, "a closed note with a copy opens in the background")
        #expect(texts(closed) == ["Two"], "its snapshot catches up")
        #expect(ended == 1, "and it's let go again to save and close")
    }

    @Test func emptiedBlocksKeepALine() {
        let (_, a, b) = pair()
        let id = site(b).id
        b.edit("Delete") { page in page.update(id) { $0.children = [] } }
        #expect(texts(b) == [""], "a synced block always keeps a line to type in")
        #expect(texts(a) == [""], "and the original matches")
        #expect(b.undoDepth == 1, "in the same undo step")
        b.undo()
        #expect(texts(a) == ["One"], "undo brings the content back everywhere")
    }
}
