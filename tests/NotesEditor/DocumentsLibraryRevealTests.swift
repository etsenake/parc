import Foundation

@main
struct DocumentsLibraryRevealTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-library-reveal-" + UUID().uuidString, isDirectory: true)
        let library = root.appendingPathComponent("Parc Notes", isDirectory: true)
        let trips = library.appendingPathComponent("Trips", isDirectory: true)
        let elsewhere = root.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: trips, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lisbon = trips.appendingPathComponent("Lisbon.md"), packing = library.appendingPathComponent("Packing.md")
        let stray = elsewhere.appendingPathComponent("Groceries.md")
        for url in [lisbon, packing, stray] { try? Data("x".utf8).write(to: url) }
        let easel = UUID(), other = UUID()

        expect(DocumentsLibraryReveal.folder(for: .note(packing), library: library) == nil, "a note in the library needs no folder scope")
        expect(DocumentsLibraryReveal.folder(for: .note(lisbon), library: library) == nil, "nor does one in a library subfolder")
        expect(DocumentsLibraryReveal.folder(for: .easel(easel), library: library) == nil, "Easels only list unscoped")
        expect(DocumentsLibraryReveal.folder(for: .note(stray), library: library)?.path == NoteFilePaths.canonical(elsewhere).path,
               "a note outside the library is revealed by browsing its own folder")

        let visible: [DocumentsLibraryReveal.Target] = [.easel(other), .note(packing), .easel(easel), .note(NoteFilePaths.canonical(lisbon))]
        expect(DocumentsLibraryReveal.index(of: .easel(easel), in: visible) == 2, "finds the Easel by id")
        let indirect = URL(fileURLWithPath: trips.path + "/../Trips/Lisbon.md")
        expect(DocumentsLibraryReveal.index(of: .note(indirect), in: visible) == 3, "finds the note however its path is spelled")
        expect(DocumentsLibraryReveal.index(of: .note(stray), in: visible) == nil, "a hidden note isn't found")

        expect(!DocumentsLibraryReveal.clearsQuery("lisbon", target: .note(lisbon), visible: visible), "a search that shows the item stays")
        expect(DocumentsLibraryReveal.clearsQuery("socks", target: .easel(UUID()), visible: visible), "a search that hides it is cleared")
        expect(!DocumentsLibraryReveal.clearsQuery("  ", target: .easel(UUID()), visible: visible), "blank search has nothing to clear")
        print("DocumentsLibraryRevealTests: ok")
    }
}
