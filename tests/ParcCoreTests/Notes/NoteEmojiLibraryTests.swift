import Combine
import Foundation
import Testing
@testable import ParcCore

struct NoteCustomEmojiUpgradeTests {
    @Test func newNamesTurnMatchingTextIntoEmoji() {
        let upgraded = NoteCustomEmojiName.upgrading(NoteText("Hi :cat: and `:cat:` and :dog:"), names: ["cat"])
        #expect(upgraded.marks(at: 3).atom == .customEmoji("cat"))
        #expect(upgraded.plainText == "Hi :cat: and `:cat:` and :dog:")
    }

    @Test func codeStaysCode() {
        var code = NoteMarks()
        code.code = true
        let coded = NoteText(":cat:", marks: code)
        #expect(NoteCustomEmojiName.upgrading(coded, names: ["cat"]) == coded)
    }

    @Test func nestedBlocksUpgradeToo() {
        let page = NotePage(blocks: [NoteBlock(.toggle, text: "top", children: [.paragraph(":cat:")])])
        #expect(NoteCustomEmojiName.upgrading(page, names: ["cat"]).blocks[0].children[0].text == .atom(.customEmoji("cat")))
    }

    @MainActor
    func upgradedSession() -> NotePageSession {
        let session = NotePageSession(page: NotePage(blocks: [NoteBlock(.toggle, text: "top", children: [.paragraph(":cat:")])]))
        session.edit("Type", kind: .text) { $0.blocks[0].text = "top!" }
        session.updateAllPagesMetadata { NoteCustomEmojiName.upgrading($0, names: ["cat"]) }
        return session
    }

    @MainActor
    @Test func theOpenPageUpgrades() {
        #expect(upgradedSession().page.blocks[0].children[0].text == .atom(.customEmoji("cat")))
    }

    @MainActor
    @Test func undoKeepsTheUpgrade() {
        let session = upgradedSession()
        session.undo()
        #expect(session.page.blocks[0].text == "top" && session.page.blocks[0].children[0].text == .atom(.customEmoji("cat")))
    }
}

@MainActor final class NoteEmojiLibraryTests {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    let base = NoteFileTestSupport.makeFolder("emoji-library")
    var notes: URL { base.appendingPathComponent("Notes", isDirectory: true) }
    var work: URL { notes.appendingPathComponent("Work", isDirectory: true) }
    lazy var files = NoteFileTestSupport.files(clock: NoteManualClock(), notesFolders: { [notes] in [notes] })
    lazy var library = files.emojiLibrary(root: notes)

    init() {
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("Notes/Work", isDirectory: true), withIntermediateDirectories: true)
    }

    deinit {
        NoteFileTestSupport.remove(base)
    }

    func throwsError(_ expected: NoteEmojiLibraryError, _ body: () throws -> Void) -> Bool {
        do { try body() } catch let error as NoteEmojiLibraryError { return error == expected } catch { return false }
        return false
    }

    @discardableResult
    func add(_ name: String) -> NoteCustomEmoji? { try? library.add(png: png, name: name) }

    @Test func aNoteInASubfolderUsesItsNotesFolder() {
        #expect(NoteEmojiLibrary.root(for: work.appendingPathComponent("Plan.md"), notesFolders: [notes]).path == notes.path)
    }

    @Test func aNoteOutsideEveryNotesFolderUsesItsOwnFolder() {
        let loose = base.appendingPathComponent("Elsewhere/Readme.md")
        #expect(NoteEmojiLibrary.root(for: loose, notesFolders: [notes]).path == loose.deletingLastPathComponent().path)
    }

    @Test func theNearestFolderWithALibraryWins() throws {
        try FileManager.default.createDirectory(at: NoteEmojiLibrary.directory(in: work), withIntermediateDirectories: true)
        #expect(NoteEmojiLibrary.root(for: work.appendingPathComponent("Plan.md"), notesFolders: [notes]).path == work.path)
    }

    @Test func notesInOneFolderShareOneLibrary() {
        #expect(files.emojiLibrary(for: work.appendingPathComponent("Plan.md")) === files.emojiLibrary(for: notes.appendingPathComponent("Other.md")))
    }

    @Test func eachFileEnvironmentKeepsItsOwnLibraries() {
        #expect(NoteFileTestSupport.files(clock: NoteManualClock()).emojiLibrary(root: notes) !== library)
    }

    @Test func aNewFolderHasNoCustomEmoji() {
        #expect(library.isEmpty)
    }

    @Test func namesAreTidiedAndImagesLandInTheParcEmojiFolder() {
        let added = add("Party Parrot")
        #expect(added?.name == "party-parrot" && added?.file == "party-parrot.png")
        #expect(FileManager.default.fileExists(atPath: notes.appendingPathComponent(".parc/emoji/party-parrot.png").path))
        #expect(library.names == ["party-parrot"])
    }

    @Test func addingAnnouncesAChangeOnTheLibraryAndTheEnvironment() {
        var changes = 0, announced: [NoteEmojiLibrary] = []
        let subscriptions = [library.changes.sink { changes += 1 }, files.emojiChanges.sink { announced.append($0) }]
        defer { subscriptions.forEach { $0.cancel() } }
        add("cat")
        #expect(changes == 1)
        #expect(announced.count == 1 && announced.first === library)
    }

    @Test func namesStayUnique() {
        add("Party Parrot")
        #expect(throwsError(.nameTaken("party-parrot")) { try library.add(png: png, name: "party parrot") })
    }

    @Test func namesNeedLettersOrDigits() {
        #expect(throwsError(.invalidName) { try library.add(png: png, name: "!!!") })
    }

    @Test func aTakenNameGetsANumber() {
        add("Party Parrot")
        #expect(library.uniqueName(for: "party parrot") == "party-parrot-2")
    }

    @Test(arguments: [("par", ["party-parrot"]), ("parrot", ["party-parrot"]), ("", ["cat", "party-parrot"])])
    func searchFindsByPrefixOrWordAndListsEverythingWhenEmpty(query: String, expected: [String]) {
        add("Party Parrot")
        add("cat")
        #expect(library.search(query).map(\.name) == expected)
    }

    @discardableResult
    func renamed() -> NoteCustomEmoji? {
        add("Party Parrot")
        add("cat")
        return try? library.rename("party-parrot", to: "Fiesta")
    }

    @Test func renamesRememberTheOldName() {
        let fiesta = renamed()
        #expect(fiesta?.name == "fiesta" && fiesta?.aliases == ["party-parrot"])
        #expect(library.names == ["cat", "fiesta", "party-parrot"])
    }

    @Test func oldNamesStillFindTheRenamedEmojiAndItsImage() {
        renamed()
        #expect(library.emoji(named: "party-parrot")?.name == "fiesta")
        #expect(library.imageURL(named: "party-parrot")?.lastPathComponent == "fiesta.png")
    }

    @Test func theManifestKeepsNamesAndOldNames() {
        renamed()
        let manifest = (try? String(contentsOf: library.manifestURL, encoding: .utf8)) ?? ""
        #expect(manifest.contains("\"name\" : \"fiesta\"") && manifest.contains("\"party-parrot\""))
    }

    @Test func aNewEmojiCanTakeAnOldName() {
        renamed()
        #expect(add("party-parrot")?.name == "party-parrot")
        #expect(library.emoji(named: "fiesta")?.aliases == [])
    }

    @Test func renamesCannotStealNames() {
        renamed()
        #expect(throwsError(.nameTaken("cat")) { try library.rename("fiesta", to: "cat") })
    }

    @Test func renamingToTheSameNameIsFine() {
        add("cat")
        #expect((try? library.rename("cat", to: "cat"))?.name == "cat")
    }

    @Test func deletingRemovesTheEmojiAndItsImage() throws {
        add("cat")
        try library.remove("cat", trash: FileManager.default.removeItem(at:))
        #expect(library.emoji(named: "cat") == nil)
        #expect(!FileManager.default.fileExists(atPath: notes.appendingPathComponent(".parc/emoji/cat.png").path))
    }

    @Test func deletingTwiceSaysItIsGone() throws {
        add("cat")
        try library.remove("cat", trash: FileManager.default.removeItem(at:))
        #expect(throwsError(.missing) { try library.remove("cat", trash: FileManager.default.removeItem(at:)) })
    }

    @Test func theLibraryReadsBackFromDisk() {
        add("cat")
        add("Party Parrot")
        #expect(NoteEmojiLibrary(root: notes, announcing: PassthroughSubject()).emoji.map(\.name) == ["cat", "party-parrot"])
    }

    @Test func imagesDroppedInByHandJoinTheLibrary() throws {
        add("cat")
        let stray = notes.appendingPathComponent(".parc/emoji/thumbs_up.png")
        try png.write(to: stray)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: stray.deletingLastPathComponent().path)
        library.refreshIfNeeded()
        #expect(library.emoji(named: "thumbs_up") != nil)
    }

    @Test func filesWithoutAValidNameAreSkipped() throws {
        add("cat")
        try png.write(to: notes.appendingPathComponent(".parc/emoji/Not Valid.png"))
        #expect(NoteEmojiLibrary(root: notes, announcing: PassthroughSubject()).emoji(named: "not-valid") == nil)
    }

    func environment(plainText: Bool = false) -> NoteFileEnvironment {
        NoteFileEnvironment(documentURL: work.appendingPathComponent("Plan.md"), isPlainText: plainText, files: files)
    }

    @Test func aNoteFindsItsFoldersLibrary() {
        #expect(environment().emojiLibrary === library)
    }

    @Test func shortcodesResolveToTheirImagesAndUnknownOnesToNothing() {
        add("cat")
        #expect(environment().resolve(":cat:")?.lastPathComponent == "cat.png")
        #expect(environment().resolve(":nope:") == nil)
    }

    @Test func theEnvironmentListsTheNames() {
        add("Party Parrot")
        #expect(environment().customEmojiNames.contains("party-parrot"))
    }

    @Test func aCustomEmojiIconIsATabIconImage() throws {
        add("cat")
        let env = environment()
        let image = try #require(env.resolve(":cat:"))
        #expect(NoteTabIcon(":cat:", resolve: env.resolve) == .image(URL(fileURLWithPath: image.path)))
    }

    @Test func plainTextNotesHaveNoCustomEmoji() {
        #expect(environment(plainText: true).emojiLibrary == nil)
    }
}
