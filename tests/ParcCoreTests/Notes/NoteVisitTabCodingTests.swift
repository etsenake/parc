import Foundation
import Testing
@testable import ParcCore

struct NoteVisitTabCodingTests {
    @Test func aNoteAheadSurvivesTabEncoding() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        tab.stepBackFromNote()
        let encoded = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: encoded)
        #expect(decoded == tab && decoded.hasVisitStepAhead, "The note entry survives encoding")
    }

    @Test func tabsSavedBeforeDocumentVisitsDecodeWithoutOne() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteVisitTestsSupport.webTab())) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "noteVisit")
        let old = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.noteVisit == nil, "Tabs saved before note entries decode without one")
    }

    @Test func invalidNoteVisitDataIsDiscardedWithoutLosingTheTab() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteVisitTestsSupport.webTab())) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "noteVisit")
        legacy["noteVisit"] = ["page": 3]
        let damaged = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(damaged.noteVisit == nil, "A damaged note entry is dropped instead of losing the tab")
    }

    @Test func anEaselVisitSurvivesTabEncoding() throws {
        let id = UUID()
        var tab = NoteVisitTestsSupport.webTab()
        tab.openDocumentVisit(.easel(id), title: " Board ")
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONEncoder().encode(tab))
        #expect(decoded == tab && decoded.noteVisit?.document == .easel(id), "The Easel step survives encoding")
    }

    @Test func anEaselVisitUsesTheSameRecordAsANoteVisit() throws {
        let id = UUID()
        let easel = InternalPage.easel(id).urlString
        var tab = NoteVisitTestsSupport.webTab()
        tab.openDocumentVisit(.easel(id), title: " Board ")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any] ?? [:]
        let saved = json["noteVisit"] as? [String: Any]
        #expect((saved?["note"] as? [String: Any])?["url"] as? String == easel, "It saves in the same record notes use")
    }

    @Test func aDocumentStackSurvivesTabEncoding() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        let tab = stack.tab
        let encoded = try JSONEncoder().encode(tab)
        #expect(try JSONDecoder().decode(BrowserTab.self, from: encoded) == tab, "The whole stack survives encoding")
    }

    @Test func aLegacySingleDocumentVisitDecodesAsAStack() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let page = "https://example.test/docs"
        let a = readme.absoluteString
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteVisitTestsSupport.webTab())) as? [String: Any] ?? [:]
        legacy["noteVisit"] = ["page": ["url": page, "title": "Docs"], "note": ["url": a, "title": "Readme"], "showsNote": true]
        let old = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.noteVisit == TabNoteVisit(page: .init(url: page, title: "Docs"), documents: [.init(url: a, title: "Readme")], position: 0), "A tab saved with one document step decodes as a one-step stack")
    }

    @Test func anOutOfBoundsStackIsDiscardedWithoutLosingTheTab() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let page = "https://example.test/docs"
        let a = readme.absoluteString
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteVisitTestsSupport.webTab())) as? [String: Any] ?? [:]
        legacy["noteVisit"] = ["page": ["url": page, "title": "Docs"], "note": ["url": a, "title": "Readme"], "showsNote": false,
                               "documents": [["url": a, "title": "Readme"]], "position": 4]
        let outside = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(outside.noteVisit == nil, "A stack pointing outside itself is dropped instead of losing the tab")
    }
}
