import Foundation

@main @MainActor
struct NoteVisitTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { failTest(message) }
    }
    static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { failTest(message) }
        return value
    }

    static func main() {
        exitOnFailure {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-visits-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
            let readme = notes.appendingPathComponent("Readme.md")
            try Data("# Read me\n".utf8).write(to: readme)
            try transitions(readme)
            try store(directory, readme: readme)
            try persistence(directory, readme: readme)
            try renamesAndDeletion(directory, notes: notes, readme: readme)
            print("NoteVisits: \(assertions) assertions passed")
        }
    }

    static func webTab(_ url: String = "https://example.test/docs", title: String = "Docs", kind: TabKind = .today) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: UUID(), profileID: UUID(), url: url, title: title, kind: kind,
                   createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: title)
    }

    static func transitions(_ readme: URL) throws {
        var tab = webTab()
        try expect(tab.openNoteVisit(url: readme, title: ""), "A page can open a note over itself")
        try expect(tab.url == readme.absoluteString && tab.title == "Readme", "The tab's address and title follow the note")
        try expect(tab.savedURL == tab.url && tab.savedTitle == "Readme", "A Today tab's saved address follows what shows")
        try expect(tab.showsNoteOverPage && !tab.hasNoteAhead, "The note shows on top of the page")
        try expect(tab.noteVisit?.page == .init(url: "https://example.test/docs", title: "Docs"), "The page entry remembers where it was")
        try expect(!tab.openNoteVisit(url: readme, title: "Again"), "A note can't open over a note")
        try expect(!tab.stepForwardToNote(), "Forward does nothing while the note shows")
        try expect(tab.stepBackFromNote(), "Back leaves the note")
        try expect(tab.url == "https://example.test/docs" && tab.title == "Docs", "Back shows the page's address and title")
        try expect(tab.hasNoteAhead && !tab.showsNoteOverPage, "The note waits ahead after Back")
        try expect(!tab.stepBackFromNote(), "Back from the page is the page's own business")
        tab.title = "Docs, updated"
        try expect(tab.stepForwardToNote(), "Forward returns to the note")
        try expect(tab.url == readme.absoluteString && tab.title == "Readme", "Forward shows the note again")
        try expect(tab.noteVisit?.page.title == "Docs, updated", "Forward takes the page's latest title along")
        try expect(tab.followPageUnderNote(url: "https://example.test/docs#intro", title: nil), "The hidden page can still move")
        try expect(tab.url == readme.absoluteString, "A hidden page's moves never change what the tab shows")
        try expect(!tab.followPageUnderNote(url: nil, title: ""), "Empty updates change nothing")
        try expect(tab.stepBackFromNote() && tab.url == "https://example.test/docs#intro", "Back lands on the page where it moved")

        var pinned = webTab(kind: .pinned)
        pinned.savedURL = "https://example.test/"
        try expect(pinned.openNoteVisit(url: readme, title: "Readme"), "Pinned pages open notes too")
        try expect(pinned.savedURL == "https://example.test/", "A pinned tab keeps its home address")

        var blank = webTab("about:blank", title: "New tab")
        try expect(!blank.openNoteVisit(url: readme, title: "Readme"), "A blank tab has no page to go back to")
        var note = webTab(readme.absoluteString, title: "Readme")
        try expect(!note.openNoteVisit(url: readme, title: "Readme"), "A note tab doesn't stack notes")
        var archived = webTab()
        archived.archivedAt = Date()
        try expect(!archived.openNoteVisit(url: readme, title: "Readme"), "Archived tabs don't open notes")
        var web = webTab()
        try expect(!web.openNoteVisit(url: URL(string: "https://example.test/readme.md")!, title: "x"), "Only local note files count")

        var forgotten = webTab()
        forgotten.openNoteVisit(url: readme, title: "Readme")
        let matcher = InternalPage.note(readme).matcher()
        try expect(forgotten.forgetNote(matching: matcher), "A deleted note leaves the tab")
        try expect(forgotten.noteVisit == nil && forgotten.url == "https://example.test/docs", "Forgetting a shown note goes back to the page")
        var ahead = webTab()
        ahead.openNoteVisit(url: readme, title: "Readme"); ahead.stepBackFromNote()
        try expect(ahead.forgetNote(matching: matcher) && ahead.noteVisit == nil && ahead.url == "https://example.test/docs",
                   "Forgetting a note ahead just drops the Forward entry")
        try expect(!ahead.forgetNote(matching: matcher), "Nothing left to forget")

        let encoded = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: encoded)
        try expect(decoded == tab && decoded.hasNoteAhead, "The note entry survives encoding")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(webTab())) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "noteVisit")
        let old = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(old.noteVisit == nil, "Tabs saved before note entries decode without one")
        legacy["noteVisit"] = ["page": 3]
        let damaged = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(damaged.noteVisit == nil, "A damaged note entry is dropped instead of losing the tab")
    }

    static func store(_ directory: URL, readme: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        let other = store.open("https://example.test/other")
        store.selectTab(page)
        let tabs = store.state.tabs.count
        try expect(store.openNoteOverPage(page, url: readme, title: ""), "A same-tab click opens the note in the page's tab")
        try expect(store.state.tabs.count == tabs && store.state.selectedTabIDs == [page], "No new tab, and the tab stays selected")
        let shown = try unwrap(store.state.tab(page), "tab")
        try expect(shown.url == readme.absoluteString && shown.title == "Readme" && shown.showsNoteOverPage, "The tab shows the note")
        try expect(store.openNote(url: readme, title: "Readme") != page, "Opening the note elsewhere gets its own tab, not the page's")
        let separate = store.state.tabs.first { $0.url == readme.absoluteString && $0.id != page }
        try expect(separate != nil && separate?.noteVisit == nil, "The separate note tab is an ordinary note tab")
        store.selectTab(page)

        store.updatePageUnderNote(page, title: "Docs — Section", url: "https://example.test/docs#section")
        let followed = try unwrap(store.state.tab(page), "followed")
        try expect(followed.url == readme.absoluteString && followed.noteVisit?.page.url == "https://example.test/docs#section",
                   "The hidden page's address is remembered without changing the tab")
        try expect(store.stepNoteVisit(page, forward: false), "Back shows the page")
        let back = try unwrap(store.state.tab(page), "back")
        try expect(back.url == "https://example.test/docs#section" && back.title == "Docs — Section" && back.hasNoteAhead,
                   "Back puts the page's address and title on the tab and keeps the note ahead")
        try expect(!store.stepNoteVisit(page, forward: false), "A second Back is the page's own")
        store.updateTab(page, title: "Docs, retitled")
        try expect(store.state.tab(page)?.hasNoteAhead == true, "A title change keeps the Forward entry")
        try expect(store.stepNoteVisit(page, forward: true), "Forward shows the note again")
        try expect(store.state.tab(page)?.url == readme.absoluteString, "Forward puts the note back on the tab")
        try expect(store.stepNoteVisit(page, forward: false), "And Back again")
        store.updateTab(page, url: "https://example.test/elsewhere")
        let moved = try unwrap(store.state.tab(page), "moved")
        try expect(moved.noteVisit == nil && moved.url == "https://example.test/elsewhere", "A new page navigation drops the Forward note")
        try expect(!store.stepNoteVisit(page, forward: true), "Forward has nothing to show after that")

        try expect(store.openNoteOverPage(page, url: readme, title: "Readme"), "Open the note again")
        store.updateTab(page, url: "https://example.test/typed")
        let typed = try unwrap(store.state.tab(page), "typed")
        try expect(typed.noteVisit == nil && typed.url == "https://example.test/typed", "Typing an address over the note leaves it")

        try expect(!store.openNoteOverPage(other, url: URL(string: "https://example.test/a.md")!, title: "a"), "Remote files aren't notes")
        try expect(!store.openNoteOverPage(UUID(), url: readme, title: "Readme"), "Unknown tabs open nothing")
        let archived = store.open("https://example.test/archived")
        store.closeTab(archived)
        try expect(!store.openNoteOverPage(archived, url: readme, title: "Readme"), "Archived tabs open nothing")

        let state = store.state
        var next = state
        let nextIndex = try unwrap(next.tabs.firstIndex { $0.id == page }, "index")
        next.tabs[nextIndex].openNoteVisit(url: readme, title: "Readme")
        try expect(!next.preservesChromeLayout(relativeTo: state), "Showing a note over a page redraws the window")
        var titled = state
        titled.tabs[nextIndex].title = "Something else"
        try expect(titled.preservesChromeLayout(relativeTo: state), "A plain title change still takes the quick path")
    }

    static func persistence(_ directory: URL, readme: URL) throws {
        let location = directory.appendingPathComponent("restart")
        let page: UUID, archived: UUID
        do {
            let store = try BrowserStore(directory: location)
            page = store.open("https://example.test/docs")
            store.updateTab(page, title: "Docs", url: "https://example.test/docs")
            try expect(store.openNoteOverPage(page, url: readme, title: "Readme"), "open")
            archived = store.open("https://example.test/archived")
            store.updateTab(archived, title: "Archived", url: "https://example.test/archived")
            try expect(store.openNoteOverPage(archived, url: readme, title: "Readme"), "open archived")
            store.closeTab(archived)
            try store.save()
        }
        let restored = try BrowserStore(directory: location)
        let tab = try unwrap(restored.state.tab(page), "restored tab")
        try expect(tab.url == readme.absoluteString && tab.showsNoteOverPage, "After a restart the tab still shows the note")
        try expect(tab.noteVisit?.page.url == "https://example.test/docs", "and remembers the page to go Back to")
        try expect(restored.stepNoteVisit(page, forward: false) && restored.state.tab(page)?.url == "https://example.test/docs",
                   "Back after a restart puts the page's address back, ready to load")
        let gone = try unwrap(restored.state.tab(archived), "archived tab")
        try expect(gone.archivedAt != nil && gone.showsNoteOverPage && gone.url == readme.absoluteString,
                   "An archived tab keeps showing its note, with the page behind it")
        try expect(!restored.stepNoteVisit(archived, forward: false), "Archived tabs don't step")
    }

    static func renamesAndDeletion(_ directory: URL, notes: URL, readme: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("files"))
        let shown = store.open("https://example.test/shown")
        store.updateTab(shown, title: "Shown", url: "https://example.test/shown")
        let ahead = store.open("https://example.test/ahead")
        store.updateTab(ahead, title: "Ahead", url: "https://example.test/ahead")
        try expect(store.openNoteOverPage(shown, url: readme, title: "Readme"), "shown")
        try expect(store.openNoteOverPage(ahead, url: readme, title: "Readme") && store.stepNoteVisit(ahead, forward: false), "ahead")
        let renamed = notes.appendingPathComponent("Guide.md")
        try FileManager.default.moveItem(at: readme, to: renamed)
        store.updateNoteFile(from: readme, to: renamed, title: "Guide")
        try expect(store.state.tab(shown)?.url == renamed.absoluteString && store.state.tab(shown)?.title == "Guide"
                   && store.state.tab(shown)?.noteVisit?.note.url == renamed.absoluteString, "A rename follows the shown note")
        try expect(store.state.tab(ahead)?.noteVisit?.note == .init(url: renamed.absoluteString, title: "Guide")
                   && store.state.tab(ahead)?.url == "https://example.test/ahead", "A rename follows a note waiting ahead")
        try expect(store.stepNoteVisit(ahead, forward: true) && store.state.tab(ahead)?.url == renamed.absoluteString,
                   "Forward lands on the renamed file")
        store.stepNoteVisit(ahead, forward: false)

        let plain = try unwrap(store.openNote(url: renamed, title: "Guide"), "plain note tab")
        var finished: Error??
        store.deleteLocalDocument(.note(renamed), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  completion: { finished = .some($0) })
        try expect(finished != nil && finished! == nil, "The note moves to the Trash")
        try expect(!store.state.containsTab(plain), "The plain note tab goes with it")
        let back = try unwrap(store.state.tab(shown), "shown after delete")
        try expect(back.noteVisit == nil && back.url == "https://example.test/shown" && back.title == "Shown",
                   "A page showing the deleted note goes back to its page instead of closing")
        try expect(store.state.tab(ahead)?.noteVisit == nil && store.state.tab(ahead)?.url == "https://example.test/ahead",
                   "A page with the deleted note ahead just loses Forward")
    }
}
