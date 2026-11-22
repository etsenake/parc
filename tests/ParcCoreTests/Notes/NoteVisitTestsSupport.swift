import Foundation
import Testing
@testable import ParcCore

enum NoteVisitTestsSupport {
    final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-visits-" + UUID().uuidString)
        let notes: URL
        let readme: URL

        init() throws {
            notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
            readme = notes.appendingPathComponent("Readme.md")
            try Data("# Read me\n".utf8).write(to: readme)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func webTab(_ url: String = "https://example.test/docs", title: String = "Docs", kind: TabKind = .today) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: UUID(), profileID: UUID(), url: url, title: title, kind: kind,
                   createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: title)
    }
    static func entry(_ id: String) -> TabNoteVisit.PageEntry {
        .init(id: id, url: "https://example.test/" + id, title: id.uppercased())
    }

    static func history(_ ids: [String], current: Int, navigating: Bool = false) -> TabNoteVisit.PageHistory {
        .init(entries: ids.map(entry), current: current, navigating: navigating)
    }

    struct Stack {
        let tab: BrowserTab
        let noteURL: String
        let board: UUID
        let easelURL: String
        let guide: URL
        let guideURL: String
    }

    static func stack(in fixture: Fixture) throws -> Stack {
        let readme = fixture.readme
        let notes = fixture.notes
        let board = UUID()
        let guide = notes.appendingPathComponent("Chapter.md")
        try Data("# Chapter\n".utf8).write(to: guide)
        let a = readme.absoluteString, b = InternalPage.easel(board).urlString, c = guide.absoluteString
        var tab = webTab()
        tab.openNoteVisit(url: readme, title: "Readme")
        tab.openDocumentVisit(.easel(board), title: "Board")
        tab.openNoteVisit(url: guide, title: "Chapter")
        return Stack(tab: tab, noteURL: a, board: board, easelURL: b, guide: guide, guideURL: c)
    }
}
