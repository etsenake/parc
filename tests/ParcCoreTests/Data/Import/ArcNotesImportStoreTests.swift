import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ArcNotesImportStoreTests {
    private typealias Parsing = ArcNotesImportParsingTests
    private static let date = Date(timeIntervalSinceReferenceDate: 815_100_000)

    private static func container(_ id: String, _ children: [String]) -> [Any] {
        [id, ["id": id, "childrenIds": children, "data": ["itemContainer": [:]]]]
    }

    private static func tab(_ id: String, _ url: String) -> [Any] {
        [id, ["id": id, "childrenIds": [], "data": ["tab": ["savedURL": url, "savedTitle": id]]]]
    }

    private static func note(_ id: String, document: String) -> [Any] {
        [id, ["id": id, "title": NSNull(), "childrenIds": [], "data": ["arcDocument": ["arcDocumentID": document, "isEditable": true]]]]
    }

    private static func sidebar() throws -> Data {
        let items: [Any] = container("P1", ["T1", "N1", "T2"]) + container("U1", ["N3"]) + container("F1", ["NF"])
            + tab("T1", "https://example.test/a") + note("N1", document: "DOC-1") + tab("T2", "https://example.test/b")
            + note("N3", document: "DOC-3") + note("NF", document: "DOC-F")
        return try Parsing.json(["sidebar": ["containers": [["global": [:]], [
            "spaces": ["S1", ["id": "S1", "title": "Work", "profile": ["default": true],
                              "containerIDs": ["pinned", "P1", "unpinned", "U1"]]],
            "items": items, "topAppsContainerIDs": [["default": true], "F1"]]]]])
    }

    private static func notes() throws -> [SidebarImport.Note] {
        let meeting = try Parsing.json(Parsing.storable(blocks: ["B1", Parsing.meetingBlock]))
        let pictured = try Parsing.json(Parsing.storable(id: "DOC-3", title: "Moodboard", blocks: ["B1",
            Parsing.block("B1", text: "Colours\u{FFFC}", properties: [Parsing.rich(7, 1, ["image": ["_0": Parsing.png.base64EncodedString()]])])]))
        let favorite = try Parsing.json(Parsing.storable(id: "DOC-F", title: "Daily", blocks: ["B1",
            Parsing.block("B1", text: "Water plants", properties: [Parsing.rich(0, 12, ["checklist": ["checked": false]])])]))
        let spare = try Parsing.json(Parsing.storable(id: "DOC-S", title: "Spare", blocks: ["B1",
            Parsing.block("B1", text: "Nobody pinned me", properties: [])]))
        return [meeting, pictured, favorite, spare].flatMap { ArcNotesImport.notes(json: $0, name: "x") }
    }

    private static func markdownFiles(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
    }

    private static func withImport(_ body: (BrowserState, UUID, SidebarImport, NoteFiles, URL) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let files = NoteFileTestSupport.files(clock: NoteManualClock())
            let store = try BrowserStore(directory: directory, now: { Self.date })
            let standardID = store.state.profiles[0].id
            let folder = files.folders.folder(for: standardID)
            defer { NoteFileTestSupport.remove(folder) }
            let arc = try SidebarImport(arcData: Self.sidebar(), notes: Self.notes())
            try body(store.state, standardID, arc, files, folder)
        }
    }

    private static func insert(_ arc: SidebarImport, into state: BrowserState, standardID: UUID, files: NoteFiles) throws -> BrowserState {
        try arc.inserting(into: state, profiles: [(.standard, "Personal")], standardProfileID: standardID, at: Self.date,
                          noteFiles: files).state
    }

    private static func tabs(_ state: BrowserState, spaceID: UUID, section: TabKind, profileID: UUID? = nil) -> [BrowserTab] {
        let key = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: section, profileID: profileID).key
        return (state.sidebarItemOrder[key] ?? []).compactMap { item in
            guard case .tab(let id) = item else { return nil }
            return state.tabs.first { $0.id == id }
        }
    }

    private static func file(_ tab: BrowserTab?) throws -> URL {
        try #require(tab.flatMap { InternalPage.noteFile($0.url) })
    }

    @Test func noteTabsSitWhereTheArcItemsWereWithTheirMarkdownOnDisk() throws {
        try Self.withImport { state, standardID, arc, files, folder in
            let imported = try Self.insert(arc, into: state, standardID: standardID, files: files)
            let spaceID = try #require(imported.arcImportedSpaces["S1"])
            let pinned = Self.tabs(imported, spaceID: spaceID, section: .pinned)
            #expect(pinned.count == 3)
            #expect(pinned.first?.url == "https://example.test/a" && pinned.last?.url == "https://example.test/b")
            let middle = try #require(pinned.dropFirst().first)
            let meeting = try Self.file(middle)
            #expect(middle.kind == .pinned && middle.title == "Meeting notes" && meeting.lastPathComponent == "Meeting notes.md")
            let meetingNote = try #require(Self.notesByID()["DOC-1"])
            let written = try String(contentsOf: meeting, encoding: .utf8)
            #expect(written == meetingNote.markdown)

            let today = Self.tabs(imported, spaceID: spaceID, section: .today)
            let moodboard = try Self.file(today.first)
            #expect(today.count == 1 && today.first?.kind == .today && today.first?.title == "Moodboard")
            let attachments = NoteAttachments.folder(for: moodboard)
            let pictures = try FileManager.default.contentsOfDirectory(at: attachments, includingPropertiesForKeys: nil)
            #expect(pictures.count == 1 && pictures.first.flatMap { try? Data(contentsOf: $0) } == Parsing.png)
            let saved = try String(contentsOf: moodboard, encoding: .utf8)
            #expect(!saved.contains(ArcNotesImport.imagePrefix))
            #expect(NoteMarkdown.parse(saved).blocks.map(\.kind) == [.paragraph, .image])

            let favorites = imported.tabs.filter { $0.kind == .favorite && $0.profileID == standardID }
            let daily = try Self.file(favorites.first)
            #expect(favorites.count == 1 && favorites.first?.title == "Daily" && daily.lastPathComponent == "Daily.md")

            #expect(Self.markdownFiles(in: folder) == ["Daily.md", "Meeting notes.md", "Moodboard.md", "Spare.md"])
            #expect(!imported.tabs.contains { $0.title == "Spare" })
        }
    }

    @Test func importingAgainAddsNoTabsAndNoNoteFiles() throws {
        try Self.withImport { state, standardID, arc, files, folder in
            let first = try Self.insert(arc, into: state, standardID: standardID, files: files)
            let second = try Self.insert(arc, into: first, standardID: standardID, files: files)
            #expect(second.tabs.count == first.tabs.count && second.spaces.count == first.spaces.count)
            #expect(Self.markdownFiles(in: folder).count == 4)
        }
    }

    @Test func aDeletedSpaceImportedAgainReusesTheSameNoteFiles() throws {
        try Self.withImport { state, standardID, arc, files, folder in
            var first = try Self.insert(arc, into: state, standardID: standardID, files: files)
            let firstSpace = try #require(first.arcImportedSpaces["S1"])
            let original = try Self.file(Self.tabs(first, spaceID: firstSpace, section: .pinned).dropFirst().first)
            first.tabs.removeAll { $0.spaceID == firstSpace && $0.kind != .favorite }
            first.spaces.removeAll { $0.id == firstSpace }
            let second = try Self.insert(arc, into: first, standardID: standardID, files: files)
            let spaceID = try #require(second.arcImportedSpaces["S1"])
            let again = try Self.file(Self.tabs(second, spaceID: spaceID, section: .pinned).dropFirst().first)
            #expect(spaceID != firstSpace && second.spaces.count == first.spaces.count + 1)
            #expect(NoteFilePaths.sameItem(again, original))
            #expect(Self.markdownFiles(in: folder).count == 4)
        }
    }

    @Test func aDifferentNoteWithTheSameNameIsLeftAloneAndTheImportGetsTheNextName() throws {
        try Self.withImport { state, standardID, arc, files, folder in
            let canonical = NoteFilePaths.canonical(folder)
            try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
            let mine = canonical.appendingPathComponent("Meeting notes.md")
            try Data("My own words\n".utf8).write(to: mine)
            let imported = try Self.insert(arc, into: state, standardID: standardID, files: files)
            let spaceID = try #require(imported.arcImportedSpaces["S1"])
            let note = try Self.file(Self.tabs(imported, spaceID: spaceID, section: .pinned).dropFirst().first)
            let untouched = try String(contentsOf: mine, encoding: .utf8)
            #expect(note.lastPathComponent == "Meeting notes 2.md" && untouched == "My own words\n")
        }
    }

    private static func notesByID() throws -> [String: SidebarImport.Note] {
        Dictionary(try notes().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
