import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor final class NoteFileEnvironmentTests {
    init() {
        NoteFileSession.clock = NoteManualClock()
        NoteFileSession.worker = .inline
        NoteLibrary.clock = NoteManualClock()
        NoteLibrary.worker = .inline
        folder = NoteFileTestSupport.makeFolder("environment")
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    var folder: URL!

    func environment(for name: String) -> NoteFileEnvironment {
        let note = NoteFileTestSupport.write("", to: folder.appendingPathComponent(name))
        return NoteFileEnvironment(documentURL: note, isPlainText: false)
    }

    @Test func percentEncodedRelativePathsResolveAgainstTheNotesFolder() {
        let env = environment(for: "Notes/Page.md")
        let notes = folder.appendingPathComponent("Notes", isDirectory: true)
        #expect(env.resolve("Attachments/My%20Image.png")?.path == notes.appendingPathComponent("Attachments/My Image.png").path, "percent-encoded relative paths resolve against the note's folder")
        #expect(env.resolve("Attachments/My Image.png")?.path == notes.appendingPathComponent("Attachments/My Image.png").path, "raw relative paths resolve too")
        #expect(env.resolve("<Attachments/a b.png>")?.path == notes.appendingPathComponent("Attachments/a b.png").path, "angle-bracket destinations resolve")
        #expect(env.resolve("../Shared/pic.png")?.path == folder.appendingPathComponent("Shared/pic.png").path, "parent paths resolve")
        #expect(env.resolve("/tmp/absolute.png")?.path == "/private/tmp/absolute.png", "absolute paths stay absolute, canonically")
        #expect(env.resolve("~/x.png")?.path == (NSHomeDirectory() as NSString).appendingPathComponent("x.png"), "tildes expand")
        #expect(env.resolve("file:///tmp/a%20b.png")?.path == "/private/tmp/a b.png", "file URLs resolve")
        #expect(env.resolve("https://example.com/a.png")?.absoluteString == "https://example.com/a.png", "web URLs pass through")
        #expect(env.resolve("https://example.com/a b.png")?.host == "example.com", "web URLs with spaces still resolve")
        #expect(env.resolve("//cdn.example.com/x.png")?.scheme == "https", "protocol-relative URLs get https")
        #expect(env.resolve("mailto:hi@example.com")?.scheme == "mailto", "other schemes pass through")
        let section = env.resolve("Other%20Page.md#Next%20steps")
        #expect(section?.path == notes.appendingPathComponent("Other Page.md").path, "fragments split from the path")
        #expect(section?.fragment == "Next%20steps", "and ride along on the URL")
        #expect(env.resolve("#Top")?.path == env.documentURL?.path, "bare fragments point at the note itself")
        NoteFileTestSupport.write("", to: notes.appendingPathComponent("notes:2024.md"))
        #expect(env.resolve("notes:2024.md")?.path == notes.appendingPathComponent("notes:2024.md").path, "a colon in an existing file name isn't a scheme")
        #expect(env.resolve("   ") == nil, "blank sources don't resolve")
        #expect(NoteFileEnvironment(documentURL: folder.appendingPathComponent("x.md"), isPlainText: true).isPlainText, "plain text is flagged")
    }

    @Test func importsLandInAttachmentsWithAReadableEncodedName() throws {
        let env = environment(for: "Trip.md")
        let outside = NoteFileTestSupport.makeFolder("outside")
        defer { NoteFileTestSupport.remove(outside) }
        let photo = NoteFileTestSupport.write(Data([1, 2, 3]), to: outside.appendingPathComponent("Beach (day 1).png"))
        let first = try env.importAsset(from: photo)
        #expect(first == "Attachments/Beach%20%28day%201%29.png", "imports land in Attachments with a readable, encoded name")
        #expect(NoteFileTestSupport.bytes(folder.appendingPathComponent("Attachments/Beach (day 1).png")) == [1, 2, 3], "the file is copied")
        #expect(env.resolve(first)?.path == folder.appendingPathComponent("Attachments/Beach (day 1).png").path, "the link resolves back")
        #expect((try env.importAsset(from: photo)) == first, "importing the same file again reuses the copy")
        NoteFileTestSupport.write(Data([9, 9]), to: photo)
        #expect((try env.importAsset(from: photo)) == "Attachments/Beach%20%28day%201%29%202.png", "a different file with the same name counts up")
        let inside = NoteFileTestSupport.write(Data([4]), to: folder.appendingPathComponent("Pictures/local.png"))
        #expect((try env.importAsset(from: inside)) == "Pictures/local.png", "files already beside the note are linked, not copied")
        let hidden = NoteFileTestSupport.write(Data([5]), to: outside.appendingPathComponent(".secret"))
        #expect((try env.importAsset(from: hidden)) == "Attachments/secret", "dot files don't stay hidden")
        let web = URL(string: "https://example.com/cat.gif")!
        #expect((try env.importAsset(from: web)) == "https://example.com/cat.gif", "web images are linked as they are")
        #expect(throws: NoteFileError.missing, "missing files can't be imported") {
            _ = try env.importAsset(from: outside.appendingPathComponent("nope.png"))
        }
    }

    @Test func pastedImagesGetDatedNames() throws {
        let env = environment(for: "Paste/Board.md")
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 11, 20, 14, 3, 22)
        let stamp = Calendar.current.date(from: components)!
        env.now = { stamp }
        #expect((try env.importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil)) == "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22.png", "pasted images get dated names")
        #expect((try env.importAsset(data: Data([2]), fileExtension: ".PNG", suggestedName: nil)) == "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22%202.png", "a second paste in the same second counts up")
        #expect((try env.importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil)) == "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22.png", "pasting identical data reuses the file")
        #expect((try env.importAsset(data: Data([3]), fileExtension: "pdf", suggestedName: nil)) == "Attachments/Pasted%20file%202026-11-20%20at%2014.03.22.pdf", "other pasted files say file")
        #expect((try env.importAsset(data: Data([4]), fileExtension: "jpg", suggestedName: "Screen Shot.jpg")) == "Attachments/Screen%20Shot.jpg", "suggested names are kept without doubling the extension")
        #expect((try env.importAsset(data: Data([5]), fileExtension: "png", suggestedName: "a/b:c")) == "Attachments/a-b-c.png", "suggested names are sanitized")
        let pasted = folder.appendingPathComponent("Paste/Attachments/Pasted image 2026-11-20 at 14.03.22.png")
        #expect(NoteFileTestSupport.bytes(pasted) == [1], "the data is written beside the note")
    }

    @Test func siblingsLinkByName() {
        let env = environment(for: "Projects/Plan.md")
        let projects = folder.appendingPathComponent("Projects", isDirectory: true)
        let sibling = NoteFileTestSupport.write("", to: projects.appendingPathComponent("Budget (draft).md"))
        let child = NoteFileTestSupport.write("", to: projects.appendingPathComponent("Ideas/Café list.md"))
        let parent = NoteFileTestSupport.write("", to: folder.appendingPathComponent("Inbox.txt"))
        #expect(env.linkTarget(for: sibling) == "Budget%20%28draft%29.md", "siblings link by name")
        #expect(env.linkTarget(for: child) == "Ideas/Café%20list.md", "children link through their folder")
        #expect(env.linkTarget(for: parent) == "../Inbox.txt", "parents link with ../")
        for note in [sibling, child, parent] {
            #expect(env.resolveNoteLink(env.linkTarget(for: note)) == note, "links round-trip: \(note.lastPathComponent)")
        }
        let viaVar = URL(fileURLWithPath: sibling.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        #expect(env.linkTarget(for: viaVar) == "Budget%20%28draft%29.md", "links canonicalize the target")
        #expect(env.resolveNoteLink("Budget (draft)") == sibling, "extensionless links find the Markdown file")
        #expect(env.resolveNoteLink("Budget%20%28draft%29.md#Totals") == sibling, "fragments are dropped for notes")
        #expect(env.resolveNoteLink("Attachments/photo.png") == nil, "non-notes aren't note links")
        #expect(env.resolveNoteLink("https://example.com/page.md") == nil, "web links aren't note links")
        #expect(env.resolveNoteLink("Not there yet.md") == NoteFilePaths.canonical(projects.appendingPathComponent("Not there yet.md")), "links to missing notes still resolve so they can show as missing")
        let elsewhere = URL(fileURLWithPath: "/Volumes/Elsewhere/Far.md")
        #expect(env.linkTarget(for: elsewhere) == elsewhere.absoluteString, "notes on other roots link absolutely")
    }

    @Test func searchSkipsTheNoteItself() throws {
        let root = folder.appendingPathComponent("Library", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        let here = try library.createNote(title: "Garden journal")
        _ = try library.createNote(title: "Garden supplies")
        NoteFileTestSupport.write("tomatoes\n", to: root.appendingPathComponent("Deep/Veg.md"))
        let env = NoteFileEnvironment(documentURL: here, isPlainText: false)
        let found = env.searchNotes("garden", limit: 10).map(\.title)
        #expect(found == ["Garden supplies"], "search skips the note itself")
        #expect(env.searchNotes("tomatoes", limit: 10).map(\.title) == ["Veg"], "search covers the whole library")
        #expect(env.searchNotes("", limit: 1).count == 1, "limits apply")

        let loose = NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/One.md"))
        NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/Two.md"))
        NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/Nested/Three.md"))
        let looseEnv = NoteFileEnvironment(documentURL: loose, isPlainText: false)
        #expect(looseEnv.searchNotes("", limit: 10).map(\.title) == ["Two"], "notes outside a library search their own folder only")
    }

    @Test func newNotesLandBesideThePageWithTidyNames() throws {
        let root = folder.appendingPathComponent("Created", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        let page = try library.createNote(title: "Page")
        _ = try library.notes()
        var heard = 0
        let watch = library.changes.sink { heard += 1 }
        let env: NoteEnvironment = NoteFileEnvironment(documentURL: page, isPlainText: false)
        let made = try env.createNote(titled: "Ideas: next/steps")
        #expect(made == root.appendingPathComponent("Ideas- next-steps.md"), "new notes land beside the page with tidy names")
        #expect(NoteFileTestSupport.bytes(made) == [], "and start empty")
        #expect((try env.createNote(titled: "Ideas: next/steps").lastPathComponent) == "Ideas- next-steps 2.md", "taken names count up")
        #expect((try env.createNote(titled: "  ").lastPathComponent) == "Untitled.md", "blank titles are untitled")
        #expect(heard >= 3, "the library hears about each new note")
        let titles = try library.notes().map(\.title)
        #expect(titles.contains("Ideas- next-steps 2"), "and lists it right away")
        #expect(env.linkTarget(for: made) == "Ideas-%20next-steps.md", "new notes link relatively")
        let detached: NoteEnvironment = NoteDetachedEnvironment(documentURL: page)
        #expect((try detached.createNote(titled: "Detached").lastPathComponent) == "Detached.md", "the default works for any environment")
        #expect(throws: NoteFileError.missing, "no document, no folder") { _ = try NoteDetachedEnvironment().createNote(titled: "x") }
        watch.cancel()
    }
}
}
