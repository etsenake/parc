import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor final class NoteFileEnvironmentTests {
    let folder = NoteFileTestSupport.makeFolder("environment")
    let outside = NoteFileTestSupport.makeFolder("outside")
    lazy var files = NoteFileTestSupport.files(clock: NoteManualClock())

    deinit {
        NoteFileTestSupport.remove(folder)
        NoteFileTestSupport.remove(outside)
    }

    var notes: URL { folder.appendingPathComponent("Notes", isDirectory: true) }

    func environment(for name: String) -> NoteFileEnvironment {
        let note = NoteFileTestSupport.write("", to: folder.appendingPathComponent(name))
        return NoteFileEnvironment(documentURL: note, isPlainText: false, files: files)
    }

    @Test(arguments: [
        ("Attachments/My%20Image.png", "Notes/Attachments/My Image.png"),
        ("Attachments/My Image.png", "Notes/Attachments/My Image.png"),
        ("<Attachments/a b.png>", "Notes/Attachments/a b.png"),
        ("../Shared/pic.png", "Shared/pic.png"),
        ("Other%20Page.md#Next%20steps", "Notes/Other Page.md"),
    ])
    func relativePathsResolveAgainstTheNotesFolder(source: String, expected: String) {
        #expect(environment(for: "Notes/Page.md").resolve(source)?.path == folder.appendingPathComponent(expected).path)
    }

    @Test(arguments: [
        ("/tmp/absolute.png", "/private/tmp/absolute.png"),
        ("~/x.png", (NSHomeDirectory() as NSString).appendingPathComponent("x.png")),
        ("file:///tmp/a%20b.png", "/private/tmp/a b.png"),
    ])
    func absolutePathsTildesAndFileURLsResolveCanonically(source: String, expected: String) {
        #expect(environment(for: "Notes/Page.md").resolve(source)?.path == expected)
    }

    @Test func webURLsPassThroughEvenWithSpaces() {
        let env = environment(for: "Notes/Page.md")
        #expect(env.resolve("https://example.com/a.png")?.absoluteString == "https://example.com/a.png")
        #expect(env.resolve("https://example.com/a b.png")?.host == "example.com")
    }

    @Test(arguments: [("//cdn.example.com/x.png", "https"), ("mailto:hi@example.com", "mailto")])
    func otherAddressesKeepOrGainTheirScheme(source: String, scheme: String) {
        #expect(environment(for: "Notes/Page.md").resolve(source)?.scheme == scheme)
    }

    @Test func fragmentsRideAlongOnTheURL() {
        #expect(environment(for: "Notes/Page.md").resolve("Other%20Page.md#Next%20steps")?.fragment == "Next%20steps")
    }

    @Test func bareFragmentsPointAtTheNoteItself() {
        let env = environment(for: "Notes/Page.md")
        #expect(env.resolve("#Top")?.path == env.documentURL?.path)
    }

    @Test func aColonInAnExistingFileNameIsNotAScheme() {
        let env = environment(for: "Notes/Page.md")
        NoteFileTestSupport.write("", to: notes.appendingPathComponent("notes:2024.md"))
        #expect(env.resolve("notes:2024.md")?.path == notes.appendingPathComponent("notes:2024.md").path)
    }

    @Test func blankSourcesDoNotResolve() {
        #expect(environment(for: "Notes/Page.md").resolve("   ") == nil)
    }

    @Test func plainTextIsFlagged() {
        #expect(NoteFileEnvironment(documentURL: folder.appendingPathComponent("x.md"), isPlainText: true, files: files).isPlainText)
    }

    func photo() -> (NoteFileEnvironment, URL) {
        let env = environment(for: "Trip.md")
        return (env, NoteFileTestSupport.write(Data([1, 2, 3]), to: outside.appendingPathComponent("Beach (day 1).png")))
    }

    @Test func importsLandInAttachmentsWithAReadableEncodedName() throws {
        let (env, photo) = photo()
        let first = try env.importAsset(from: photo)
        #expect(first == "Attachments/Beach%20%28day%201%29.png")
        #expect(NoteFileTestSupport.bytes(folder.appendingPathComponent("Attachments/Beach (day 1).png")) == [1, 2, 3])
        #expect(env.resolve(first)?.path == folder.appendingPathComponent("Attachments/Beach (day 1).png").path)
    }

    @Test func importingTheSameFileAgainReusesTheCopy() throws {
        let (env, photo) = photo()
        let first = try env.importAsset(from: photo)
        #expect(try env.importAsset(from: photo) == first)
    }

    @Test func aDifferentFileWithTheSameNameCountsUp() throws {
        let (env, photo) = photo()
        _ = try env.importAsset(from: photo)
        NoteFileTestSupport.write(Data([9, 9]), to: photo)
        #expect(try env.importAsset(from: photo) == "Attachments/Beach%20%28day%201%29%202.png")
    }

    @Test func filesAlreadyBesideTheNoteAreLinkedNotCopied() throws {
        let env = environment(for: "Trip.md")
        let inside = NoteFileTestSupport.write(Data([4]), to: folder.appendingPathComponent("Pictures/local.png"))
        #expect(try env.importAsset(from: inside) == "Pictures/local.png")
    }

    @Test func dotFilesDoNotStayHidden() throws {
        let env = environment(for: "Trip.md")
        let hidden = NoteFileTestSupport.write(Data([5]), to: outside.appendingPathComponent(".secret"))
        #expect(try env.importAsset(from: hidden) == "Attachments/secret")
    }

    @Test func webImagesAreLinkedAsTheyAre() throws {
        #expect(try environment(for: "Trip.md").importAsset(from: URL(string: "https://example.com/cat.gif")!) == "https://example.com/cat.gif")
    }

    @Test func missingFilesCannotBeImported() {
        let env = environment(for: "Trip.md")
        #expect(throws: NoteFileError.missing) { _ = try env.importAsset(from: self.outside.appendingPathComponent("nope.png")) }
    }

    func pasteBoard() -> NoteFileEnvironment {
        let env = environment(for: "Paste/Board.md")
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 11, 20, 14, 3, 22)
        let stamp = Calendar.current.date(from: components)!
        env.now = { stamp }
        return env
    }

    @Test(arguments: [
        ("png", nil, "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22.png"),
        ("pdf", nil, "Attachments/Pasted%20file%202026-11-20%20at%2014.03.22.pdf"),
        ("jpg", "Screen Shot.jpg", "Attachments/Screen%20Shot.jpg"),
        ("png", "a/b:c", "Attachments/a-b-c.png"),
    ] as [(String, String?, String)])
    func pastedDataGetsDatedOrSanitizedNames(fileExtension: String, suggested: String?, expected: String) throws {
        #expect(try pasteBoard().importAsset(data: Data([1]), fileExtension: fileExtension, suggestedName: suggested) == expected)
    }

    @Test func aSecondPasteInTheSameSecondCountsUpAndIdenticalDataReusesTheFile() throws {
        let env = pasteBoard()
        let first = try env.importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil)
        #expect(try env.importAsset(data: Data([2]), fileExtension: ".PNG", suggestedName: nil) == "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22%202.png")
        #expect(try env.importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil) == first)
    }

    @Test func pastedDataIsWrittenBesideTheNote() throws {
        _ = try pasteBoard().importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil)
        #expect(NoteFileTestSupport.bytes(folder.appendingPathComponent("Paste/Attachments/Pasted image 2026-11-20 at 14.03.22.png")) == [1])
    }

    var projects: URL { folder.appendingPathComponent("Projects", isDirectory: true) }

    func linked() -> (NoteFileEnvironment, sibling: URL, child: URL, parent: URL) {
        let env = environment(for: "Projects/Plan.md")
        return (env, NoteFileTestSupport.write("", to: projects.appendingPathComponent("Budget (draft).md")),
                NoteFileTestSupport.write("", to: projects.appendingPathComponent("Ideas/Café list.md")),
                NoteFileTestSupport.write("", to: folder.appendingPathComponent("Inbox.txt")))
    }

    @Test func siblingsChildrenAndParentsLinkRelatively() {
        let (env, sibling, child, parent) = linked()
        #expect(env.linkTarget(for: sibling) == "Budget%20%28draft%29.md")
        #expect(env.linkTarget(for: child) == "Ideas/Café%20list.md")
        #expect(env.linkTarget(for: parent) == "../Inbox.txt")
    }

    @Test(arguments: [0, 1, 2])
    func linksRoundTrip(which: Int) {
        let (env, sibling, child, parent) = linked()
        let note = [sibling, child, parent][which]
        #expect(env.resolveNoteLink(env.linkTarget(for: note)) == note)
    }

    @Test func linksCanonicalizeTheTarget() {
        let (env, sibling, _, _) = linked()
        #expect(env.linkTarget(for: URL(fileURLWithPath: sibling.path.replacingOccurrences(of: "/private/var/", with: "/var/"))) == "Budget%20%28draft%29.md")
    }

    @Test(arguments: ["Budget (draft)", "Budget%20%28draft%29.md#Totals"])
    func extensionlessAndFragmentedLinksFindTheMarkdownFile(target: String) {
        let (env, sibling, _, _) = linked()
        #expect(env.resolveNoteLink(target) == sibling)
    }

    @Test(arguments: ["Attachments/photo.png", "https://example.com/page.md"])
    func nonNotesAndWebLinksAreNotNoteLinks(target: String) {
        #expect(linked().0.resolveNoteLink(target) == nil)
    }

    @Test func linksToMissingNotesStillResolveSoTheyCanShowAsMissing() {
        #expect(linked().0.resolveNoteLink("Not there yet.md") == NoteFilePaths.canonical(projects.appendingPathComponent("Not there yet.md")))
    }

    @Test func notesOnOtherRootsLinkAbsolutely() {
        let elsewhere = URL(fileURLWithPath: "/Volumes/Elsewhere/Far.md")
        #expect(environment(for: "Projects/Plan.md").linkTarget(for: elsewhere) == elsewhere.absoluteString)
    }

    func searchable() throws -> (NoteFileEnvironment, URL) {
        let root = folder.appendingPathComponent("Library", isDirectory: true)
        let library = files.library(folder: root)
        let here = try library.createNote(title: "Garden journal")
        _ = try library.createNote(title: "Garden supplies")
        NoteFileTestSupport.write("tomatoes\n", to: root.appendingPathComponent("Deep/Veg.md"))
        return (NoteFileEnvironment(documentURL: here, isPlainText: false, files: files), root)
    }

    @Test func searchSkipsTheNoteItself() throws {
        #expect(try searchable().0.searchNotes("garden", limit: 10).map(\.title) == ["Garden supplies"])
    }

    @Test func searchCoversTheWholeLibrary() throws {
        #expect(try searchable().0.searchNotes("tomatoes", limit: 10).map(\.title) == ["Veg"])
    }

    @Test func searchLimitsApply() throws {
        #expect(try searchable().0.searchNotes("", limit: 1).count == 1)
    }

    @Test func notesOutsideALibrarySearchTheirOwnFolderOnly() {
        let loose = NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/One.md"))
        NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/Two.md"))
        NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/Nested/Three.md"))
        let env = NoteFileEnvironment(documentURL: loose, isPlainText: false, files: files)
        #expect(env.searchNotes("", limit: 10).map(\.title) == ["Two"])
    }

    func creating() throws -> (NoteEnvironment, NoteLibrary, URL) {
        let root = folder.appendingPathComponent("Created", isDirectory: true)
        let library = files.library(folder: root)
        let page = try library.createNote(title: "Page")
        _ = try library.notes()
        return (NoteFileEnvironment(documentURL: page, isPlainText: false, files: files), library, root)
    }

    @Test func newNotesLandEmptyBesideThePageWithTidyNames() throws {
        let (env, _, root) = try creating()
        let made = try env.createNote(titled: "Ideas: next/steps")
        #expect(made == root.appendingPathComponent("Ideas- next-steps.md"))
        #expect(NoteFileTestSupport.bytes(made) == [])
    }

    @Test(arguments: [("Ideas: next/steps", "Ideas- next-steps 2.md"), ("  ", "Untitled 2.md")])
    func takenAndBlankTitlesCountUpOrBecomeUntitled(title: String, expected: String) throws {
        let (env, _, _) = try creating()
        _ = try env.createNote(titled: title)
        #expect(try env.createNote(titled: title).lastPathComponent == expected)
    }

    @Test func theLibraryHearsAboutAndListsANewNoteRightAway() throws {
        let (env, library, _) = try creating()
        var heard = 0
        let watch = library.changes.sink { heard += 1 }
        defer { watch.cancel() }
        _ = try env.createNote(titled: "Ideas")
        #expect(heard > 0)
        #expect(try library.notes().map(\.title).contains("Ideas"))
    }

    @Test func newNotesLinkRelatively() throws {
        let (env, _, _) = try creating()
        #expect(env.linkTarget(for: try env.createNote(titled: "Ideas: next/steps")) == "Ideas-%20next-steps.md")
    }

    @Test func theDefaultNoteCreationWorksForAnyEnvironmentWithADocument() throws {
        let page = NoteFileTestSupport.write("", to: folder.appendingPathComponent("Detached/Page.md"))
        let environment = NoteDetachedEnvironment(documentURL: page, files: files)
        #expect(try environment.createNote(titled: "Detached").lastPathComponent == "Detached.md")
    }

    @Test func noDocumentMeansNoFolderForANewNote() {
        #expect(throws: NoteFileError.missing) { _ = try NoteDetachedEnvironment().createNote(titled: "x") }
    }
}
