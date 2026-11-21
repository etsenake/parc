import Combine
import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor struct NoteEmojiLibraryTests {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    func roots(notes: URL, work: URL) {
        let note = work.appendingPathComponent("Plan.md")
        let path = NoteFilePaths.canonical(notes).path
        #expect(NoteEmojiLibrary.root(for: note, notesFolders: [notes]).path == path, "a note in a subfolder uses its Notes folder")
        let loose = notes.deletingLastPathComponent().appendingPathComponent("Elsewhere/Readme.md")
        #expect(NoteEmojiLibrary.root(for: loose, notesFolders: [notes]).path == NoteFilePaths.canonical(loose.deletingLastPathComponent()).path, "a note outside every Notes folder uses its own folder")
        try? FileManager.default.createDirectory(at: NoteEmojiLibrary.directory(in: work), withIntermediateDirectories: true)
        #expect(NoteEmojiLibrary.root(for: note, notesFolders: [notes]).path == NoteFilePaths.canonical(work).path, "the nearest folder with a library wins")
        try? FileManager.default.removeItem(at: work.appendingPathComponent(NoteEmojiLibrary.folderName))
        #expect(NoteEmojiLibrary.library(for: note) === NoteEmojiLibrary.library(for: notes.appendingPathComponent("Other.md")), "notes in one folder share one library")
    }

    func editing(notes: URL) {
        let library = NoteEmojiLibrary.library(root: notes)
        var changes = 0
        let subscription = library.changes.sink { changes += 1 }
        defer { subscription.cancel() }
        #expect(library.isEmpty, "a new folder has no custom emoji")
        let added = try? library.add(png: png, name: "Party Parrot")
        #expect(added?.name == "party-parrot" && added?.file == "party-parrot.png", "names are tidied and files follow them")
        #expect(FileManager.default.fileExists(atPath: notes.appendingPathComponent(".parc/emoji/party-parrot.png").path), "the image lands in .parc/emoji")
        #expect(changes == 1, "adding announces a change")
        #expect(library.names == ["party-parrot"], "names list what's there")
        #expect(throwsError(.nameTaken("party-parrot")) { try library.add(png: png, name: "party parrot") }, "names stay unique")
        #expect(throwsError(.invalidName) { try library.add(png: png, name: "!!!") }, "names need letters or digits")
        #expect(library.uniqueName(for: "party parrot") == "party-parrot-2", "a taken name gets a number")
        _ = try? library.add(png: png, name: "cat")
        #expect(library.search("par").map(\.name) == ["party-parrot"], "search finds by prefix")
        #expect(library.search("parrot").map(\.name) == ["party-parrot"], "search finds by word")
        #expect(library.search("").map(\.name) == ["cat", "party-parrot"], "an empty search lists everything alphabetically")
        let renamed = try? library.rename("party-parrot", to: "Fiesta")
        #expect(renamed?.name == "fiesta" && renamed?.aliases == ["party-parrot"], "renames remember the old name")
        #expect(library.emoji(named: "party-parrot")?.name == "fiesta", "old names still find the emoji")
        #expect(library.imageURL(named: "party-parrot")?.lastPathComponent == "fiesta.png", "the image file follows the new name")
        #expect(library.names == ["cat", "fiesta", "party-parrot"], "names include old names")
        let manifest = (try? String(contentsOf: library.manifestURL, encoding: .utf8)) ?? ""
        #expect(manifest.contains("\"name\" : \"fiesta\"") && manifest.contains("\"party-parrot\""), "the manifest keeps names and old names")
        let reborn = try? library.add(png: png, name: "party-parrot")
        #expect(reborn?.name == "party-parrot" && library.emoji(named: "fiesta")?.aliases == [], "a new emoji can take an old name")
        #expect(throwsError(.nameTaken("cat")) { try library.rename("fiesta", to: "cat") }, "renames can't steal names")
        #expect((try? library.rename("cat", to: "cat"))?.name == "cat", "renaming to the same name is fine")
        try? library.remove("fiesta")
        #expect(library.emoji(named: "fiesta") == nil && !FileManager.default.fileExists(atPath: notes.appendingPathComponent(".parc/emoji/fiesta.png").path), "deleting removes the emoji and its image")
        #expect(throwsError(.missing) { try library.remove("fiesta") }, "deleting twice says it's gone")
        let fresh = NoteEmojiLibrary(root: notes)
        #expect(fresh.emoji.map(\.name) == ["cat", "party-parrot"], "the library reads back from disk")
    }

    func discovery(notes: URL) {
        let library = NoteEmojiLibrary.library(root: notes)
        let stray = notes.appendingPathComponent(".parc/emoji/thumbs_up.png")
        try? png.write(to: stray)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: stray.deletingLastPathComponent().path)
        library.refreshIfNeeded()
        #expect(library.emoji(named: "thumbs_up") != nil, "images dropped in by hand join the library")
        try? png.write(to: notes.appendingPathComponent(".parc/emoji/Not Valid.png"))
        #expect(NoteEmojiLibrary(root: notes).emoji(named: "not-valid") == nil, "files without a valid name are skipped")
    }

    func environment(notes: URL, work: URL) {
        let note = work.appendingPathComponent("Plan.md")
        let environment = NoteFileEnvironment(documentURL: note, isPlainText: false)
        #expect(environment.emojiLibrary === NoteEmojiLibrary.library(root: notes), "a note finds its folder's library")
        #expect(environment.resolve(":cat:")?.lastPathComponent == "cat.png", "shortcodes resolve to their images")
        #expect(environment.resolve(":nope:") == nil, "unknown shortcodes resolve to nothing")
        #expect(environment.customEmojiNames.contains("party-parrot"), "the environment lists the names")
        #expect(NoteTabIcon(":cat:", resolve: environment.resolve) == .image(URL(fileURLWithPath: environment.resolve(":cat:")!.path)), "a custom emoji icon is a tab icon image")
        #expect(NoteFileEnvironment(documentURL: note, isPlainText: true).emojiLibrary == nil, "plain text notes have no custom emoji")
    }

    func throwsError(_ expected: NoteEmojiLibraryError, _ body: () throws -> Void) -> Bool {
        do { try body() } catch let error as NoteEmojiLibraryError { return error == expected } catch { return false }
        return false
    }

    @Test func newNamesTurnMatchingTextIntoEmoji() {
        let text = NoteText("Hi :cat: and `:cat:` and :dog:")
        let upgraded = NoteCustomEmojiName.upgrading(text, names: ["cat"])
        #expect(upgraded.marks(at: 3).atom == .customEmoji("cat") && upgraded.plainText == "Hi :cat: and `:cat:` and :dog:", "new names turn matching text into emoji")
        var code = NoteMarks()
        code.code = true
        let coded = NoteText(":cat:", marks: code)
        #expect(NoteCustomEmojiName.upgrading(coded, names: ["cat"]) == coded, "code stays code")
        let page = NotePage(blocks: [NoteBlock(.toggle, text: "top", children: [.paragraph(":cat:")])])
        let upgradedPage = NoteCustomEmojiName.upgrading(page, names: ["cat"])
        #expect(upgradedPage.blocks[0].children[0].text == .atom(.customEmoji("cat")), "nested blocks upgrade too")
        let session = NotePageSession(page: page)
        session.edit("Type", kind: .text) { $0.blocks[0].text = "top!" }
        session.updateAllPagesMetadata { NoteCustomEmojiName.upgrading($0, names: ["cat"]) }
        #expect(session.page.blocks[0].children[0].text == .atom(.customEmoji("cat")), "the open page upgrades")
        session.undo()
        #expect(session.page.blocks[0].text == "top" && session.page.blocks[0].children[0].text == .atom(.customEmoji("cat")), "undo keeps the upgrade")
    }

    @Test func roots() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ParcEmojiLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let notes = base.appendingPathComponent("Notes", isDirectory: true)
        let work = notes.appendingPathComponent("Work", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        NoteEmojiLibrary.notesFolders = { [notes] }
        roots(notes: notes, work: work)
    }

    @Test func editing() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ParcEmojiLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let notes = base.appendingPathComponent("Notes", isDirectory: true)
        let work = notes.appendingPathComponent("Work", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        NoteEmojiLibrary.notesFolders = { [notes] }
        editing(notes: notes)
    }

    @Test func discovery() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ParcEmojiLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let notes = base.appendingPathComponent("Notes", isDirectory: true)
        let work = notes.appendingPathComponent("Work", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        NoteEmojiLibrary.notesFolders = { [notes] }
        editing(notes: notes)
        discovery(notes: notes)
    }

    @Test func environment() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ParcEmojiLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let notes = base.appendingPathComponent("Notes", isDirectory: true)
        let work = notes.appendingPathComponent("Work", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        NoteEmojiLibrary.notesFolders = { [notes] }
        editing(notes: notes)
        environment(notes: notes, work: work)
    }
}
}
