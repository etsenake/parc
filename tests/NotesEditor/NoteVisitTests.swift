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
            try easels(readme)
            try stacks(notes, readme: readme)
            try storeStacks(directory, notes: notes, readme: readme)
            try store(directory, readme: readme)
            try persistence(directory, readme: readme)
            try renamesAndDeletion(directory, notes: notes, readme: readme)
            try storeEasels(directory)
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

    static func easels(_ readme: URL) throws {
        let id = UUID(), other = UUID()
        let easel = InternalPage.easel(id).urlString
        var tab = webTab()
        try expect(tab.openDocumentVisit(.easel(id), title: " Board "), "A page can open an Easel over itself")
        try expect(tab.url == easel && tab.title == "Board" && tab.showsNoteOverPage, "The tab shows the Easel on top of the page")
        try expect(tab.noteVisit?.document == .easel(id) && tab.noteVisit?.noteFile == nil, "The step holds the Easel, not a note")
        try expect(tab.stepBackFromNote() && tab.url == "https://example.test/docs" && tab.hasNoteAhead, "Back shows the page")
        try expect(tab.stepForwardToNote() && tab.url == easel, "Forward returns to the Easel")

        var untitled = webTab()
        try expect(untitled.openDocumentVisit(.easel(id), title: "") && untitled.title == "Untitled Easel", "An untitled Easel gets its usual name")

        var mixed = webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        try expect(mixed.openDocumentVisit(.easel(id), title: "Board"), "An Easel opened over a note is one more step")
        try expect(mixed.url == easel && mixed.noteVisit?.page.url == "https://example.test/docs", "The page stays behind it")
        try expect(mixed.stepBackFromNote() && mixed.url == readme.absoluteString, "Back from the Easel shows the note")
        try expect(mixed.stepBackFromNote() && mixed.url == "https://example.test/docs", "Back from the note shows the page")
        try expect(mixed.stepForwardToNote() && mixed.stepForwardToNote() && mixed.url == easel, "Forward walks to the Easel")
        try expect(mixed.stepBackFromNote() && mixed.stepBackFromNote(), "Back to the page")
        try expect(mixed.openDocumentVisit(.easel(other), title: "Other") && mixed.noteVisit?.document == .easel(other)
                   && mixed.noteVisit?.documents.count == 1, "A new document from the page replaces the steps ahead, like a new navigation")
        try expect(mixed.stepBackFromNote() && mixed.stepForwardToNote() && mixed.url == InternalPage.easel(other).urlString
                   && !mixed.stepForwardToNote(), "Forward reaches the newest document and nothing past it")

        var easelTab = webTab(easel, title: "Board")
        try expect(!easelTab.openDocumentVisit(.note(readme), title: "Readme"), "An Easel tab with no page behind it stacks nothing")

        let renamed = mixed
        var follow = renamed
        try expect(follow.followNoteRename(from: InternalPage.easel(other).matcher(), to: InternalPage.easel(other).urlString, title: "Renamed")
                   && follow.noteVisit?.note.title == "Renamed", "A renamed Easel renames its step")
        try expect(follow.forgetNote(matching: InternalPage.easel(other).matcher()) && follow.noteVisit == nil
                   && follow.url == "https://example.test/docs", "A deleted Easel sends the tab back to its page")

        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONEncoder().encode(tab))
        try expect(decoded == tab && decoded.noteVisit?.document == .easel(id), "The Easel step survives encoding")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any] ?? [:]
        let saved = json["noteVisit"] as? [String: Any]
        try expect((saved?["note"] as? [String: Any])?["url"] as? String == easel, "It saves in the same record notes use")
    }

    static func stacks(_ notes: URL, readme: URL) throws {
        let board = UUID(), sketch = UUID()
        let guide = notes.appendingPathComponent("Chapter.md")
        try Data("# Chapter\n".utf8).write(to: guide)
        let a = readme.absoluteString, b = InternalPage.easel(board).urlString, c = guide.absoluteString
        let page = "https://example.test/docs"
        var tab = webTab()
        try expect(tab.openNoteVisit(url: readme, title: "Readme") && tab.openDocumentVisit(.easel(board), title: "Board")
                   && tab.openNoteVisit(url: guide, title: "Chapter"), "page → note → Easel → note opens in one tab")
        try expect(tab.url == c && tab.noteVisit?.documents.map(\.url) == [a, b, c], "Every document is its own step")
        try expect(tab.noteVisit?.behind.map(\.url) == [b, a, page] && tab.noteVisit?.ahead.isEmpty == true,
                   "The steps behind run nearest first down to the page")
        for expected in [b, a, page] {
            try expect(tab.stepBackFromNote() && tab.url == expected, "Back walks every step in order")
        }
        try expect(!tab.stepBackFromNote() && tab.noteVisit?.ahead.map(\.url) == [a, b, c], "The page's own Back takes over")
        for expected in [a, b, c] {
            try expect(tab.stepForwardToNote() && tab.url == expected, "Forward retraces them")
        }
        try expect(!tab.stepForwardToNote(), "Nothing past the newest step")
        try expect(tab.stepNoteVisit(by: -3) && tab.url == page && tab.stepNoteVisit(by: 2) && tab.url == b,
                   "A history list or swipe can jump several steps at once")
        try expect(!tab.stepNoteVisit(by: 2) && !tab.stepNoteVisit(by: -3) && !tab.stepNoteVisit(by: 0) && tab.url == b,
                   "Jumps past either end change nothing")
        tab.title = "Board, renamed in place"
        try expect(tab.openDocumentVisit(.easel(sketch), title: "Sketch"), "A document opened mid-stack")
        try expect(tab.noteVisit?.documents.map(\.url) == [a, b, InternalPage.easel(sketch).urlString],
                   "truncates the steps ahead, like any navigation")
        try expect(tab.noteVisit?.documents[1].title == "Board, renamed in place", "The step it left keeps its latest title")
        try expect(tab.openDocumentVisit(.easel(sketch), title: "Sketch 2") && tab.noteVisit?.documents.count == 3
                   && tab.title == "Sketch 2", "Opening the shown document again adds no step")

        var long = webTab()
        long.openNoteVisit(url: readme, title: "Readme")
        for _ in 0..<(TabNoteVisit.limit + 9) { long.openDocumentVisit(.easel(UUID()), title: "Board") }
        try expect(long.noteVisit?.documents.count == TabNoteVisit.limit && long.noteVisit?.position == TabNoteVisit.limit - 1,
                   "A tab keeps the newest 50 document steps, as Chromium keeps 50 page entries")
        try expect(long.noteVisit?.documents.first?.url != a, "The oldest steps go first")
        try expect(long.stepNoteVisit(by: -TabNoteVisit.limit) && long.url == page, "Back from the oldest kept step is still the page")

        let docsAt = { (tab: BrowserTab) in tab.noteVisit?.documents.map(\.url) ?? [] }
        var renamed = webTab()
        renamed.openNoteVisit(url: readme, title: "Readme"); renamed.openDocumentVisit(.easel(board), title: "Board")
        renamed.openNoteVisit(url: guide, title: "Chapter")
        try expect(renamed.followNoteRename(from: InternalPage.easel(board).matcher(), to: b, title: "Plans")
                   && renamed.noteVisit?.documents[1].title == "Plans" && renamed.url == c, "A rename reaches a step in the middle")
        try expect(renamed.stepBackFromNote() && renamed.title == "Plans", "and Back shows it by its new name")
        renamed.stepForwardToNote()
        try expect(renamed.forgetNote(matching: InternalPage.easel(board).matcher()) && docsAt(renamed) == [a, c]
                   && renamed.url == c, "Deleting a step in the middle keeps the shown one")
        try expect(renamed.stepBackFromNote() && renamed.url == a, "Back skips the deleted step")
        renamed.stepForwardToNote()
        try expect(renamed.forgetNote(matching: InternalPage.note(guide).matcher()) && renamed.url == a && renamed.title == "Readme"
                   && docsAt(renamed) == [a], "Deleting the shown step shows the nearest one behind it")

        var repeated = webTab()
        repeated.openNoteVisit(url: readme, title: "Readme"); repeated.openDocumentVisit(.easel(board), title: "Board")
        repeated.openNoteVisit(url: readme, title: "Readme")
        try expect(repeated.forgetNote(matching: InternalPage.easel(board).matcher()) && docsAt(repeated) == [a]
                   && repeated.noteVisit?.position == 0 && repeated.url == a, "Steps left side by side on one document merge")
        var aheadOnly = webTab()
        aheadOnly.openNoteVisit(url: readme, title: "Readme"); aheadOnly.openDocumentVisit(.easel(board), title: "Board")
        aheadOnly.stepNoteVisit(by: -2)
        try expect(aheadOnly.forgetNote(matching: InternalPage.note(readme).matcher()) && aheadOnly.url == page
                   && aheadOnly.noteVisit?.ahead.map(\.url) == [b], "Deleting a step ahead leaves the page and the rest of Forward")

        let encoded = try JSONEncoder().encode(tab)
        try expect(try JSONDecoder().decode(BrowserTab.self, from: encoded) == tab, "The whole stack survives encoding")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(webTab())) as? [String: Any] ?? [:]
        legacy["noteVisit"] = ["page": ["url": page, "title": "Docs"], "note": ["url": a, "title": "Readme"], "showsNote": true]
        let old = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(old.noteVisit == TabNoteVisit(page: .init(url: page, title: "Docs"), documents: [.init(url: a, title: "Readme")], position: 0),
                   "A tab saved with one document step decodes as a one-step stack")
        legacy["noteVisit"] = ["page": ["url": page, "title": "Docs"], "note": ["url": a, "title": "Readme"], "showsNote": false,
                               "documents": [["url": a, "title": "Readme"]], "position": 4]
        let outside = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(outside.noteVisit == nil, "A stack pointing outside itself is dropped instead of losing the tab")
    }

    static func storeStacks(_ directory: URL, notes: URL, readme: URL) throws {
        let location = directory.appendingPathComponent("stacks")
        let guide = notes.appendingPathComponent("Stacked.md")
        try Data("# Stacked\n".utf8).write(to: guide)
        let board = UUID(), page: UUID
        let a = readme.absoluteString, b = InternalPage.easel(board).urlString, c = guide.absoluteString
        do {
            let store = try BrowserStore(directory: location)
            page = store.open("https://example.test/stack")
            store.updateTab(page, title: "Stack", url: "https://example.test/stack")
            try expect(store.openDocumentOverPage(page, page: .note(readme), title: "Readme")
                       && store.openDocumentOverPage(page, page: .easel(board), title: "Board")
                       && store.openDocumentOverPage(page, page: .note(guide), title: "Stacked"), "The store stacks three documents")
            let before = store.state
            try expect(store.stepNoteVisit(page, forward: false) && store.state.tab(page)?.url == b, "Back shows the Easel")
            try expect(!store.state.preservesChromeLayout(relativeTo: before), "Moving between documents redraws the arrows")
            try expect(store.stepNoteVisit(page, by: -2) && store.state.tab(page)?.url == "https://example.test/stack",
                       "A jump lands on the page")
            try expect(store.stepNoteVisit(page, by: 2), "and back to the Easel")
            store.updateEaselTitle(id: board, profileID: store.activeSpace.profileID, title: "Plans")
            try expect(store.state.tab(page)?.title == "Plans" && store.state.tab(page)?.noteVisit?.documents.map(\.title) == ["Readme", "Plans", "Stacked"],
                       "Renaming an Easel in the stack renames its step")
            try store.save()
        }
        let store = try BrowserStore(directory: location)
        let restored = try unwrap(store.state.tab(page)?.noteVisit, "restored stack")
        try expect(restored.documents.map(\.url) == [a, b, c] && restored.position == 1 && store.state.tab(page)?.url == b,
                   "A restart restores every step and where the tab stood")
        let renamed = notes.appendingPathComponent("Moved.md")
        try FileManager.default.moveItem(at: guide, to: renamed)
        store.updateNoteFile(from: guide, to: renamed, title: "Moved")
        try expect(store.state.tab(page)?.noteVisit?.ahead == [.init(url: renamed.absoluteString, title: "Moved")]
                   && store.state.tab(page)?.url == b, "A renamed note ahead keeps its place")
        var finished: Error??
        store.deleteLocalDocument(.easel(board), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { finished = .some($0) })
        try expect(finished != nil && finished! == nil, "The Easel is deleted")
        let after = try unwrap(store.state.tab(page), "after delete")
        try expect(after.url == a && after.noteVisit?.documents.map(\.url) == [a, renamed.absoluteString],
                   "Deleting the shown Easel shows the note behind it and keeps the note ahead")
        try expect(store.stepNoteVisit(page, forward: true) && store.state.tab(page)?.url == renamed.absoluteString,
                   "Forward still reaches the note after it")
    }

    static func store(_ directory: URL, readme: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        let other = store.open("https://example.test/other")
        store.selectTab(page)
        let tabs = store.state.tabs.count
        try expect(store.openDocumentOverPage(page, page: .note(readme), title: ""), "A same-tab click opens the note in the page's tab")
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

        try expect(store.openDocumentOverPage(page, page: .note(readme), title: "Readme"), "Open the note again")
        store.updateTab(page, url: "https://example.test/typed")
        let typed = try unwrap(store.state.tab(page), "typed")
        try expect(typed.noteVisit == nil && typed.url == "https://example.test/typed", "Typing an address over the note leaves it")

        try expect(!store.openDocumentOverPage(other, page: .note(URL(string: "https://example.test/a.md")!), title: "a"), "Remote files aren't notes")
        try expect(!store.openDocumentOverPage(UUID(), page: .note(readme), title: "Readme"), "Unknown tabs open nothing")
        let archived = store.open("https://example.test/archived")
        store.closeTab(archived)
        try expect(!store.openDocumentOverPage(archived, page: .note(readme), title: "Readme"), "Archived tabs open nothing")

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
            try expect(store.openDocumentOverPage(page, page: .note(readme), title: "Readme"), "open")
            archived = store.open("https://example.test/archived")
            store.updateTab(archived, title: "Archived", url: "https://example.test/archived")
            try expect(store.openDocumentOverPage(archived, page: .note(readme), title: "Readme"), "open archived")
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
        try expect(store.openDocumentOverPage(shown, page: .note(readme), title: "Readme"), "shown")
        try expect(store.openDocumentOverPage(ahead, page: .note(readme), title: "Readme") && store.stepNoteVisit(ahead, forward: false), "ahead")
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

    static func storeEasels(_ directory: URL) throws {
        let location = directory.appendingPathComponent("easels")
        let id = UUID(), easel = InternalPage.easel(id).urlString
        let shown: UUID, ahead: UUID
        do {
            let store = try BrowserStore(directory: location)
            shown = store.open("https://example.test/shown")
            store.updateTab(shown, title: "Shown", url: "https://example.test/shown")
            ahead = store.open("https://example.test/ahead")
            store.updateTab(ahead, title: "Ahead", url: "https://example.test/ahead")
            let tabs = store.state.tabs.count
            try expect(store.openDocumentOverPage(shown, page: .easel(id), title: "Board"), "An Easel opens in the page's tab")
            try expect(store.state.tabs.count == tabs && store.state.tab(shown)?.url == easel, "No new tab; the tab shows the Easel")
            try expect(store.openDocumentOverPage(ahead, page: .easel(id), title: "Board") && store.stepNoteVisit(ahead, forward: false),
                       "Back from an Easel shows the page")
            store.updateEaselTitle(id: id, profileID: store.activeSpace.profileID, title: "Plans")
            try expect(store.state.tab(shown)?.title == "Plans" && store.state.tab(shown)?.noteVisit?.note.title == "Plans",
                       "Renaming the Easel renames the shown step")
            try expect(store.state.tab(ahead)?.noteVisit?.note.title == "Plans" && store.state.tab(ahead)?.title == "Ahead",
                       "and the step waiting ahead, without touching the page")
            let separate = try unwrap(store.openEasel(id: id, title: "Plans"), "separate Easel tab")
            try expect(separate != shown && separate != ahead, "Opening the Easel elsewhere gets its own tab")
            store.closeTab(separate)
            try store.save()
        }
        let store = try BrowserStore(directory: location)
        try expect(store.state.tab(shown)?.url == easel && store.state.tab(shown)?.showsNoteOverPage == true,
                   "After a restart the tab still shows the Easel over its page")
        try expect(store.state.tab(ahead)?.hasNoteAhead == true, "and the other tab still has it ahead")
        try expect(store.stepNoteVisit(shown, forward: false) && store.state.tab(shown)?.url == "https://example.test/shown",
                   "Back after a restart puts the page back")
        try expect(store.stepNoteVisit(shown, forward: true), "Forward again")
        var finished: Error??
        store.deleteLocalDocument(.easel(id), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { finished = .some($0) })
        try expect(finished != nil && finished! == nil, "The Easel is deleted")
        try expect(store.state.tab(shown)?.noteVisit == nil && store.state.tab(shown)?.url == "https://example.test/shown",
                   "A page showing the deleted Easel goes back to its page instead of closing")
        try expect(store.state.tab(ahead)?.noteVisit == nil && store.state.tab(ahead)?.url == "https://example.test/ahead",
                   "A page with the deleted Easel ahead just loses Forward")
    }
}
