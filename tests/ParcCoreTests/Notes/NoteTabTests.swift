import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteTabTests {
    func addresses(_ project: URL) throws {
        let page = InternalPage.note(project)
        #expect(InternalPage(urlString: page.urlString) == page, "A note tab's address is its file URL and round-trips")
        #expect(page.urlString == project.absoluteString && page.noteURL?.path == project.path, "The address is the plain file URL")
        let spaced = URL(fileURLWithPath: "/tmp/Parc Notes/Trip plan.md")
        #expect(InternalPage(urlString: spaced.absoluteString)?.noteURL?.path == "/tmp/Parc Notes/Trip plan.md", "Spaces in note paths survive")
        #expect(InternalPage(urlString: "file:///tmp/a/../Notes/x.md") == .note(URL(fileURLWithPath: "/tmp/Notes/x.md")), "Equivalent paths name the same note")
        #expect(InternalPage(urlString: project.absoluteString + "#heading") == page, "A heading anchor still opens the same note")
        #expect(InternalPage(urlString: "file:///tmp/readme.TXT")?.noteURL != nil && InternalPage(urlString: "file:///tmp/a.markdown")?.noteURL != nil, "Text and every Markdown extension open as notes")
        #expect(InternalPage(urlString: "file:///tmp/page.html") == nil && !InternalPage.isInternal("file:///tmp/page.html"), "Other local files keep going to the web view")
        #expect(InternalPage(urlString: "https://example.com/readme.md") == nil, "Markdown on the web stays a web page")
        #expect(InternalPage(urlString: "file://server.example/share/x.md") == nil, "Files on another host never become notes")
        #expect(InternalPage.isInternal(project.absoluteString) && NavigationInput.resolve(project.absoluteString) == nil, "The web resolver never turns a note into a webpage")
        let retired = "parc://note/" + UUID().uuidString.lowercased()
        #expect(InternalPage(urlString: retired) == nil && InternalPage.isInternal(retired) && InternalPage.isRetiredNoteAddress(retired), "Old parc://note addresses resolve to nothing but stay reserved, so they fail instead of reaching Chromium")
        #expect(BrowserInternalURL.publicString("chrome://note/x") == "chrome://note/x", "Chromium's own hosts never become note addresses")
        #expect(InternalPage.noteTitle("  ", file: project) == "Project" && InternalPage.noteTitle("Named", file: project) == "Named", "An empty title falls back to the file name")
        #expect(page.sidebarFallbackSymbol == InternalPage.noteFallbackSymbol && page.untitledTitle == "Untitled", "Note rows keep their glyph")
    }

    func tabs(_ directory: URL, project: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("tabs"))
        let first = store.open("https://example.test/one"), second = store.open("https://example.test/two")
        store.setSplit([first, second])
        let note = try unwrap(store.openNote(url: project, title: "Project", inSplit: true), "New Note in Split")
        let group = try unwrap(store.activeSplitLayout, "split layout")
        #expect(store.state.selectedTabIDs == [first, second, note] && group.tabIDs == [first, second, note], "New Note in Split preserves the original panes and joins last")
        #expect(store.openNote(url: project, title: "Project") == note, "Opening an open note reuses its tab")
        #expect(store.openNote(url: URL(string: project.absoluteString + "#top")!, title: "Project") == note, "An anchored link reuses it too")
        #expect(store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(project) }.count == 1, "Reopening never duplicates the tab")
        #expect(store.state.tabs.first { $0.id == note }?.kind == .today, "A new note is a Today tab")
        store.updateNoteFile(from: project, to: project, title: "Typing a title")
        #expect(store.state.tabs.first { $0.id == note }?.title == "Typing a title"
                   && store.state.tabs.first { $0.id == note }?.savedTitle == "Typing a title", "Title changes reach the tab")
        let renamed = project.deletingLastPathComponent().appendingPathComponent("Renamed.md")
        store.updateNoteFile(from: project, to: renamed, title: "Renamed")
        let moved = try unwrap(store.state.tabs.first { $0.id == note }, "renamed tab")
        #expect(moved.url == InternalPage.note(renamed).canonical.urlString && moved.savedURL == moved.url && moved.title == "Renamed", "Renaming moves the tab's address and title")
        let stamp = store.stateRevision
        store.updateNoteFile(from: project, to: renamed, title: "Renamed")
        #expect(store.stateRevision == stamp, "A repeated rename from another window changes nothing")
        store.closeTabs([note])
        #expect(store.state.tabs.first { $0.id == note }?.archivedAt != nil, "Closing a note archives its tab")
        #expect(store.openNote(url: renamed, title: "Renamed") == note, "Reopening restores the archived tab")
        #expect(store.state.tabs.first { $0.id == note }.map { $0.archivedAt == nil && $0.kind == .today } == true, "Restored notes come back as live Today tabs")
        let host = store.open("https://example.test/host")
        store.selectTab(host)
        let other = directory.appendingPathComponent("Other.txt")
        let plain = try unwrap(store.openNote(url: other, title: ""), "plain text note")
        #expect(store.state.tabs.first { $0.id == plain }?.title == "Other", "A text file's tab is named after the file")
        #expect(store.openNote(url: URL(fileURLWithPath: "/tmp/page.html"), title: "Page") == nil, "Only note files open as notes")
        let easelID = UUID()
        store.selectTab(host)
        let easel = try unwrap(store.openEasel(id: easelID, title: "Board", inSplit: true), "Easel in split")
        #expect(store.state.selectedTabIDs == [host, easel] && store.state.tabs.first { $0.id == easel }?.url == "parc://easel/" + easelID.uuidString.lowercased(), "Easels keep their parc://easel addresses")
        let privateStore = BrowserStore(privateParentProfileID: store.activeSpace.profileID, engineProfilePath: "/tmp/parc-private-notes",
                                        directory: directory.appendingPathComponent("private"), settings: store.state.settings)
        #expect(privateStore.openNote(url: renamed, title: "Renamed") == nil, "Private windows never open notes")
    }

    func pageLinks(_ directory: URL, project: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("links"))
        let page = store.open("https://example.test/page")
        _ = store.open("https://example.test/other")
        store.selectTab(page)
        let creation = TabCreationProvenance(referrerID: page, activeTabID: page, profileID: store.activeSpace.profileID, state: store.state)
        let note = try unwrap(store.openNote(url: project, title: "Project", inBackground: true, creation: creation), "background note")
        let tab = try unwrap(store.state.tabs.first { $0.id == note }, "note tab")
        #expect(store.state.selectedTabIDs == [page], "A Command-clicked note leaves the page selected")
        #expect(tab.referrerID == page && tab.activeTabBeforeCreationID == page, "The note remembers the page that linked it")
        let order = SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .today),
                                              state: store.state)
        #expect(order.firstIndex(of: .tab(note)) == order.firstIndex(of: .tab(page)).map { $0 + 1 }, "The note lands right after its page")
        #expect(store.openNote(url: project, title: "Project", inBackground: true, creation: creation) == note
                   && store.state.selectedTabIDs == [page], "A note that already has a tab stays in the background")
        #expect(store.openNote(url: project, title: "Project", inSplit: true, inBackground: true) == nil, "A background note never joins a split")
        let front = directory.appendingPathComponent("Front.md")
        let shown = try unwrap(store.openNote(url: front, title: "", creation: creation), "clicked note")
        #expect(store.state.selectedTabIDs == [shown] && store.state.tabs.first { $0.id == shown }?.referrerID == page, "A plain click opens the note in front, still tied to its page")
    }

    func deletion(_ directory: URL, notes: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("deletion"))
        let profile = store.activeSpace.profileID
        let file = notes.appendingPathComponent("Doomed.md")
        try Data("bye\n".utf8).write(to: file)
        let first = store.open("https://example.test/one"), second = store.open("https://example.test/two")
        store.setSplit([first, second])
        let note = try unwrap(store.openNote(url: file, title: "Doomed", inSplit: true), "note in split")
        let group = try unwrap(store.activeSplitLayout, "split")
        let otherProfile = store.createProfile(name: "Elsewhere")
        let away = store.createSpace(name: "Away")
        store.assignProfile(otherProfile, toSpace: away)
        let alias = try unwrap(store.openNote(url: file, title: "Doomed"), "note in another Profile")
        #expect(store.state.tabs.first { $0.id == alias }?.profileID == otherProfile && store.state.tabs.first { $0.id == alias }?.spaceID == away, "Any Profile can open the same note file in its own tab")
        var requested = Set<UUID>(), validate: (() -> Bool)?, finish: ((Bool) -> Void)?
        store.requestPageRetirement = { ids, gate, done in requested = ids; validate = gate; finish = done }
        var deleted = 0, replies: [Bool] = []
        func remove() {
            store.deleteLocalDocument(.note(file), profileID: profile, ownerValid: { true }, deleteDocument: { deleted += 1 }) { replies.append($0 == nil) }
        }
        remove()
        #expect(requested == [note, alias] && deleted == 0, "Deleting a note waits for every tab on that file, in every Profile, to retire")
        finish?(false)
        #expect(deleted == 0 && replies == [false] && store.state.tabs.contains { $0.id == note }, "Refusal keeps the file and its tabs")
        remove(); store.updateTab(note, title: "Changed while waiting")
        #expect(validate?() == false, "A tab that changed during consent refuses the deletion")
        finish?(false)
        remove(); store.updateTab(first, url: file.absoluteString)
        #expect(validate?() == false, "A tab that started showing the note during consent refuses too")
        finish?(false); store.updateTab(first, url: "https://example.test/one")
        remove(); #expect(validate?() == true, "A fresh snapshot authorizes the deletion")
        finish?(true)
        #expect(deleted == 1 && replies == [false, false, false, true], "The file is removed once, after real approval")
        #expect(!store.state.tabs.contains { $0.id == note || $0.id == alias }, "Every tab on the deleted note retires")
        let retained = store.state.splitLayouts.first { $0.id == group.id }
        #expect(retained?.tabIDs == [first, second] && retained?.widthFactors.count == 2, "The surviving split keeps its panes and geometry")
        store.deleteLocalDocument(.note(file), profileID: UUID(), ownerValid: { true }, deleteDocument: { deleted += 1 }) { replies.append($0 == nil) }
        #expect(deleted == 1 && replies.last == false, "An unknown Profile cannot delete a note")
        store.requestPageRetirement = nil
        let trashable = notes.appendingPathComponent("Trash me.md")
        try Data("x".utf8).write(to: trashable)
        let tab = try unwrap(store.openNote(url: trashable, title: "Trash me"), "note to fail")
        try store.save()
        let stateURL = store.directory.appendingPathComponent("session.json"), stateBytes = try Data(contentsOf: stateURL)
        try FileManager.default.removeItem(at: stateURL); try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: false)
        var failure: Error?, removals = 0
        store.deleteLocalDocument(.note(trashable), profileID: profile, ownerValid: { true }, deleteDocument: { removals += 1 }) { failure = $0 }
        #expect(failure != nil && removals == 0 && store.state.tabs.contains { $0.id == tab }, "A session save failure leaves the file and tab alone")
        try FileManager.default.removeItem(at: stateURL); try stateBytes.write(to: stateURL)
        store.deleteLocalDocument(.note(trashable), profileID: profile, ownerValid: { true }, deleteDocument: {
            removals += 1; throw CocoaError(.fileWriteNoPermission)
        }) { failure = $0 }
        #expect(failure != nil && removals == 1 && !store.state.tabs.contains { $0.id == tab }, "A file failure reports after the tabs retire")
        store.deleteLocalDocument(.note(trashable), profileID: profile, ownerValid: { true }, deleteDocument: { removals += 1 }) { failure = $0 }
        #expect(failure == nil && removals == 2, "Retrying with no tabs left finishes the deletion")
    }

    func spellings(_ directory: URL, notes: URL) throws {
        let store = try BrowserStore(directory: directory.appendingPathComponent("spellings"))
        let profile = store.activeSpace.profileID
        let real = notes.appendingPathComponent("Plans", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let plan = real.appendingPathComponent("Plan.md")
        try Data("plan\n".utf8).write(to: plan)
        let alias = notes.appendingPathComponent("Plans Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let viaVar = URL(fileURLWithPath: plan.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        let viaPrivate = URL(fileURLWithPath: "/private" + viaVar.path)
        let viaAlias = alias.appendingPathComponent("Plan.md")
        let tab = try unwrap(store.openNote(url: viaVar, title: "Plan"), "note via /var")
        #expect(store.openNote(url: viaPrivate, title: "Plan") == tab && store.openNote(url: viaAlias, title: "Plan") == tab, "The /private spelling and a symlinked folder reuse the same tab")
        #expect(InternalPage.note(viaVar) == .note(viaAlias) && InternalPage.note(viaAlias) == .note(viaPrivate), "Every spelling of one file is the same note")
        let caseInsensitive = pathconf(real.path, _PC_CASE_SENSITIVE) == 0
        if caseInsensitive {
            #expect(store.openNote(url: real.appendingPathComponent("plan.md"), title: "plan") == tab, "Another case reuses the tab too")
        }
        store.updateTab(tab, url: viaAlias.absoluteString)
        let moved = real.appendingPathComponent("Moved.md")
        try FileManager.default.moveItem(at: plan, to: moved)
        let renamedFrom = caseInsensitive ? URL(fileURLWithPath: plan.path.uppercased()) : plan
        store.updateNoteFile(from: renamedFrom, to: moved, title: "Moved")
        let after = try unwrap(store.state.tabs.first { $0.id == tab }, "moved tab")
        #expect(after.url == InternalPage.note(moved).canonical.urlString && after.title == "Moved", "A rename still finds the tab after the old path is gone, whatever spelling either side used")
        #expect(store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(moved) }.count == 1, "No second tab appears")
        let other = try unwrap(store.openNote(url: real.appendingPathComponent("Other.md"), title: "Other"), "a different note")
        #expect(other != tab && InternalPage.note(moved) != .note(real.appendingPathComponent("Other.md")), "Different files stay different notes")
        store.updateTab(tab, url: InternalPage.note(URL(fileURLWithPath: moved.path.replacingOccurrences(of: "/private/var/", with: "/var/"))).urlString)
        var requested = Set<UUID>(), validate: (() -> Bool)?, finish: ((Bool) -> Void)?
        store.requestPageRetirement = { ids, gate, done in requested = ids; validate = gate; finish = done }
        var deleted = 0
        store.deleteLocalDocument(.note(alias.appendingPathComponent("Moved.md")), profileID: profile, ownerValid: { true },
                                  deleteDocument: { deleted += 1 }) { _ in }
        #expect(requested == [tab] && validate?() == true, "Deleting through another spelling still retires the note's tab")
        finish?(true)
        #expect(deleted == 1 && !store.state.tabs.contains { $0.id == tab }, "and the tab goes away with the file")
        store.requestPageRetirement = nil
    }

    func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: message, code: 2) }
        return value
    }

    @Test func addresses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-tabs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let project = notes.appendingPathComponent("Project.md")
        try Data("# Plans\n".utf8).write(to: project)
        try addresses(project)
    }

    @Test func tabs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-tabs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let project = notes.appendingPathComponent("Project.md")
        try Data("# Plans\n".utf8).write(to: project)
        try tabs(directory, project: project)
    }

    @Test func pageLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-tabs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let project = notes.appendingPathComponent("Project.md")
        try Data("# Plans\n".utf8).write(to: project)
        try pageLinks(directory, project: project)
    }

    @Test func deletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-tabs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let project = notes.appendingPathComponent("Project.md")
        try Data("# Plans\n".utf8).write(to: project)
        try deletion(directory, notes: notes)
    }

    @Test func spellings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-tabs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("Parc Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let project = notes.appendingPathComponent("Project.md")
        try Data("# Plans\n".utf8).write(to: project)
        try spellings(directory, notes: notes)
    }
}
