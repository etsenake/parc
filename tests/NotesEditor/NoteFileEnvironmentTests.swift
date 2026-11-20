import Foundation

@main @MainActor
struct NoteFileEnvironmentTests {
    static var folder: URL!

    static func main() {
        exitOnFailure {
            NoteFileSession.clock = ManualNoteClock()
            NoteFileSession.worker = .inline
            NoteLibrary.clock = ManualNoteClock()
            NoteLibrary.worker = .inline
            folder = NoteFileTestSupport.makeFolder("environment")
            defer { NoteFileTestSupport.remove(folder) }
            resolving()
            try importingFiles()
            try importingData()
            linking()
            try searching()
            print("NoteFileEnvironmentTests passed")
        }
    }

    static func environment(for name: String) -> NoteFileEnvironment {
        let note = NoteFileTestSupport.write("", to: folder.appendingPathComponent(name))
        return NoteFileEnvironment(documentURL: note, isPlainText: false)
    }

    static func resolving() {
        let env = environment(for: "Notes/Page.md")
        let notes = folder.appendingPathComponent("Notes", isDirectory: true)
        expectEqual(env.resolve("Attachments/My%20Image.png")?.path, notes.appendingPathComponent("Attachments/My Image.png").path,
                    "percent-encoded relative paths resolve against the note's folder")
        expectEqual(env.resolve("Attachments/My Image.png")?.path, notes.appendingPathComponent("Attachments/My Image.png").path,
                    "raw relative paths resolve too")
        expectEqual(env.resolve("<Attachments/a b.png>")?.path, notes.appendingPathComponent("Attachments/a b.png").path,
                    "angle-bracket destinations resolve")
        expectEqual(env.resolve("../Shared/pic.png")?.path, folder.appendingPathComponent("Shared/pic.png").path, "parent paths resolve")
        expectEqual(env.resolve("/tmp/absolute.png")?.path, "/private/tmp/absolute.png", "absolute paths stay absolute, canonically")
        expectEqual(env.resolve("~/x.png")?.path, (NSHomeDirectory() as NSString).appendingPathComponent("x.png"), "tildes expand")
        expectEqual(env.resolve("file:///tmp/a%20b.png")?.path, "/private/tmp/a b.png", "file URLs resolve")
        expectEqual(env.resolve("https://example.com/a.png")?.absoluteString, "https://example.com/a.png", "web URLs pass through")
        expectEqual(env.resolve("https://example.com/a b.png")?.host, "example.com", "web URLs with spaces still resolve")
        expectEqual(env.resolve("//cdn.example.com/x.png")?.scheme, "https", "protocol-relative URLs get https")
        expectEqual(env.resolve("mailto:hi@example.com")?.scheme, "mailto", "other schemes pass through")
        let section = env.resolve("Other%20Page.md#Next%20steps")
        expectEqual(section?.path, notes.appendingPathComponent("Other Page.md").path, "fragments split from the path")
        expectEqual(section?.fragment, "Next%20steps", "and ride along on the URL")
        expectEqual(env.resolve("#Top")?.path, env.documentURL?.path, "bare fragments point at the note itself")
        NoteFileTestSupport.write("", to: notes.appendingPathComponent("notes:2024.md"))
        expectEqual(env.resolve("notes:2024.md")?.path, notes.appendingPathComponent("notes:2024.md").path,
                    "a colon in an existing file name isn't a scheme")
        expect(env.resolve("   ") == nil, "blank sources don't resolve")
        expect(NoteFileEnvironment(documentURL: folder.appendingPathComponent("x.md"), isPlainText: true).isPlainText, "plain text is flagged")
    }

    static func importingFiles() throws {
        let env = environment(for: "Trip.md")
        let outside = NoteFileTestSupport.makeFolder("outside")
        defer { NoteFileTestSupport.remove(outside) }
        let photo = NoteFileTestSupport.write(Data([1, 2, 3]), to: outside.appendingPathComponent("Beach (day 1).png"))
        let first = try env.importAsset(from: photo)
        expectEqual(first, "Attachments/Beach%20%28day%201%29.png", "imports land in Attachments with a readable, encoded name")
        expectEqual(NoteFileTestSupport.bytes(folder.appendingPathComponent("Attachments/Beach (day 1).png")), [1, 2, 3], "the file is copied")
        expectEqual(env.resolve(first)?.path, folder.appendingPathComponent("Attachments/Beach (day 1).png").path, "the link resolves back")
        expectEqual(try env.importAsset(from: photo), first, "importing the same file again reuses the copy")
        NoteFileTestSupport.write(Data([9, 9]), to: photo)
        expectEqual(try env.importAsset(from: photo), "Attachments/Beach%20%28day%201%29%202.png", "a different file with the same name counts up")
        let inside = NoteFileTestSupport.write(Data([4]), to: folder.appendingPathComponent("Pictures/local.png"))
        expectEqual(try env.importAsset(from: inside), "Pictures/local.png", "files already beside the note are linked, not copied")
        let hidden = NoteFileTestSupport.write(Data([5]), to: outside.appendingPathComponent(".secret"))
        expectEqual(try env.importAsset(from: hidden), "Attachments/secret", "dot files don't stay hidden")
        let web = URL(string: "https://example.com/cat.gif")!
        expectEqual(try env.importAsset(from: web), "https://example.com/cat.gif", "web images are linked as they are")
        expectThrows(NoteFileError.missing, "missing files can't be imported") {
            _ = try env.importAsset(from: outside.appendingPathComponent("nope.png"))
        }
    }

    static func importingData() throws {
        let env = environment(for: "Paste/Board.md")
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 11, 20, 14, 3, 22)
        let stamp = Calendar.current.date(from: components)!
        env.now = { stamp }
        expectEqual(try env.importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil),
                    "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22.png", "pasted images get dated names")
        expectEqual(try env.importAsset(data: Data([2]), fileExtension: ".PNG", suggestedName: nil),
                    "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22%202.png", "a second paste in the same second counts up")
        expectEqual(try env.importAsset(data: Data([1]), fileExtension: "png", suggestedName: nil),
                    "Attachments/Pasted%20image%202026-11-20%20at%2014.03.22.png", "pasting identical data reuses the file")
        expectEqual(try env.importAsset(data: Data([3]), fileExtension: "pdf", suggestedName: nil),
                    "Attachments/Pasted%20file%202026-11-20%20at%2014.03.22.pdf", "other pasted files say file")
        expectEqual(try env.importAsset(data: Data([4]), fileExtension: "jpg", suggestedName: "Screen Shot.jpg"),
                    "Attachments/Screen%20Shot.jpg", "suggested names are kept without doubling the extension")
        expectEqual(try env.importAsset(data: Data([5]), fileExtension: "png", suggestedName: "a/b:c"),
                    "Attachments/a-b-c.png", "suggested names are sanitized")
        let pasted = folder.appendingPathComponent("Paste/Attachments/Pasted image 2026-11-20 at 14.03.22.png")
        expectEqual(NoteFileTestSupport.bytes(pasted), [1], "the data is written beside the note")
    }

    static func linking() {
        let env = environment(for: "Projects/Plan.md")
        let projects = folder.appendingPathComponent("Projects", isDirectory: true)
        let sibling = NoteFileTestSupport.write("", to: projects.appendingPathComponent("Budget (draft).md"))
        let child = NoteFileTestSupport.write("", to: projects.appendingPathComponent("Ideas/Café list.md"))
        let parent = NoteFileTestSupport.write("", to: folder.appendingPathComponent("Inbox.txt"))
        expectEqual(env.linkTarget(for: sibling), "Budget%20%28draft%29.md", "siblings link by name")
        expectEqual(env.linkTarget(for: child), "Ideas/Café%20list.md", "children link through their folder")
        expectEqual(env.linkTarget(for: parent), "../Inbox.txt", "parents link with ../")
        for note in [sibling, child, parent] {
            expectEqual(env.resolveNoteLink(env.linkTarget(for: note)), note, "links round-trip: \(note.lastPathComponent)")
        }
        let viaVar = URL(fileURLWithPath: sibling.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        expectEqual(env.linkTarget(for: viaVar), "Budget%20%28draft%29.md", "links canonicalize the target")
        expectEqual(env.resolveNoteLink("Budget (draft)"), sibling, "extensionless links find the Markdown file")
        expectEqual(env.resolveNoteLink("Budget%20%28draft%29.md#Totals"), sibling, "fragments are dropped for notes")
        expect(env.resolveNoteLink("Attachments/photo.png") == nil, "non-notes aren't note links")
        expect(env.resolveNoteLink("https://example.com/page.md") == nil, "web links aren't note links")
        expectEqual(env.resolveNoteLink("Not there yet.md"), NoteFilePaths.canonical(projects.appendingPathComponent("Not there yet.md")),
                    "links to missing notes still resolve so they can show as missing")
        let elsewhere = URL(fileURLWithPath: "/Volumes/Elsewhere/Far.md")
        expectEqual(env.linkTarget(for: elsewhere), elsewhere.absoluteString, "notes on other roots link absolutely")
    }

    static func searching() throws {
        let root = folder.appendingPathComponent("Library", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        let here = try library.createNote(title: "Garden journal")
        _ = try library.createNote(title: "Garden supplies")
        NoteFileTestSupport.write("tomatoes\n", to: root.appendingPathComponent("Deep/Veg.md"))
        let env = NoteFileEnvironment(documentURL: here, isPlainText: false)
        let found = env.searchNotes("garden", limit: 10).map(\.title)
        expectEqual(found, ["Garden supplies"], "search skips the note itself")
        expectEqual(env.searchNotes("tomatoes", limit: 10).map(\.title), ["Veg"], "search covers the whole library")
        expectEqual(env.searchNotes("", limit: 1).count, 1, "limits apply")

        let loose = NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/One.md"))
        NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/Two.md"))
        NoteFileTestSupport.write("", to: folder.appendingPathComponent("Loose/Nested/Three.md"))
        let looseEnv = NoteFileEnvironment(documentURL: loose, isPlainText: false)
        expectEqual(looseEnv.searchNotes("", limit: 10).map(\.title), ["Two"], "notes outside a library search their own folder only")
    }
}
