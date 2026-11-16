import Foundation

@main @MainActor
struct NoteTabTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-tabs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory), documentID = UUID()
        let first = store.open("https://example.test/one"), second = store.open("https://example.test/two")
        store.setSplit([first, second])
        let note = store.openNote(id: documentID, title: "Project", inSplit: true)!
        let group = store.activeSplitLayout!
        try expect(store.state.selectedTabIDs == [first, second, note], "New Note in Split preserves original pane IDs")
        try expect(group.tabIDs == [first, second, note], "Original model split owns all panes")
        try expect(store.openNote(id: documentID, title: "Project") == note, "Opening existing note reuses original saved item")
        try expect(store.state.tabs.filter { InternalPage(urlString: $0.url)?.noteID == documentID }.count == 1, "Library reopening does not duplicate saved tab")
        try expect(store.state.tabs.first { $0.id == note }?.kind == .today, "A new Note is a Today tab")
        let profile = store.activeSpace.profileID
        store.updateNoteTitle(id: documentID, profileID: profile, title: "Changed title")
        try expect(store.state.tabs.first { $0.id == note }?.savedTitle == "Changed title", "Native title updates exact saved item")
        store.closeTabs([note])
        try expect(store.state.tabs.first { $0.id == note }?.archivedAt != nil, "Closing a Note archives the tab")
        try expect(store.openNote(id: documentID, title: "Changed title") == note, "Library reopen restores the archived Note")
        try expect(store.state.tabs.first { $0.id == note }?.archivedAt == nil && store.state.tabs.first { $0.id == note }?.kind == .today,
                   "Restored Notes return as live Today tabs")
        let url = InternalPage.note(documentID).urlString
        try expect(InternalPage(urlString: url) == .note(documentID), "Typed note address retains exact local identity")
        try expect(NavigationInput.resolve(url) == nil, "Native navigation resolver cannot turn local document into a webpage")
        try expect(InternalPage.isInternal("parc://note/invalid") && InternalPage(urlString: "parc://note/invalid") == nil, "Malformed reserved note never becomes browser page")
        try expect(BrowserInternalURL.publicString("chrome://note/" + documentID.uuidString) == "chrome://note/" + documentID.uuidString, "Chromium host never acquires local note identity")
        try expect(InternalPage(urlString: url + "?replace=true") == nil, "Unexpected query cannot address a note")
        var requested = Set<UUID>(), validate: (() -> Bool)?, finish: ((Bool) -> Void)?
        store.requestPageRetirement = { ids, gate, done in requested = ids; validate = gate; finish = done }
        var deleted = 0, replies: [Bool] = []
        func remove() { store.deleteLocalDocument(.note(documentID), profileID: profile, ownerValid: { true }, deleteDocument: { deleted += 1 }) { replies.append($0 == nil) } }
        remove()
        try expect(requested == [note] && deleted == 0, "Delete waits for exact original tab retirement")
        finish?(false)
        try expect(deleted == 0 && replies == [false] && store.state.tabs.contains { $0.id == note }, "Refusal preserves document and tab")
        remove(); store.updateTab(note, title: "Changed while waiting")
        try expect(validate?() == false, "Stale original saved-item snapshot refuses deletion")
        finish?(false)
        remove(); store.updateTab(first, url: url)
        try expect(validate?() == false, "A newly added document consumer invalidates the original close set")
        finish?(false); store.updateTab(first, url: "https://example.test/one")
        remove(); try expect(validate?() == true, "Fresh original snapshot authorizes retirement")
        finish?(true)
        try expect(deleted == 1 && replies == [false, false, false, true], "Delete executes once after genuine approval")
        try expect(!store.state.tabs.contains { $0.id == note }, "Accepted deletion removes exact saved item")
        let retained = store.state.splitLayouts.first { $0.id == group.id }
        try expect(retained?.tabIDs == [first, second] && retained?.widthFactors.count == 2, "Deleting a Note preserves surviving original split group and geometry")
        try expect(store.state.tabs.contains { $0.id == first } && store.state.tabs.contains { $0.id == second }, "Other live page identities survive")
        let empty = UUID()
        store.deleteLocalDocument(.note(empty), profileID: UUID(), ownerValid: { true }, deleteDocument: { deleted += 1 }) { replies.append($0 == nil) }
        try expect(deleted == 1 && replies.last == false, "Missing profile cannot delete local document")
        store.requestPageRetirement = nil
        let recoverID = UUID(), recoverTab = store.openNote(id: recoverID, title: "Retryable")!
        try store.save()
        let stateURL = directory.appendingPathComponent("session.json"), stateBytes = try Data(contentsOf: stateURL)
        try FileManager.default.removeItem(at: stateURL); try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: false)
        var removalCalls = 0, failure: Error?
        store.deleteLocalDocument(.note(recoverID), profileID: profile, ownerValid: { true }, deleteDocument: { removalCalls += 1 }) { failure = $0 }
        try expect(failure != nil && removalCalls == 0 && store.state.tabs.contains { $0.id == recoverTab }, "Session-file failure leaves original document and metadata intact")
        try FileManager.default.removeItem(at: stateURL); try stateBytes.write(to: stateURL)
        store.deleteLocalDocument(.note(recoverID), profileID: profile, ownerValid: { true }, deleteDocument: {
            removalCalls += 1; throw CocoaError(.fileWriteNoPermission)
        }) { failure = $0 }
        try expect(failure != nil && removalCalls == 1 && !store.state.tabs.contains { $0.id == recoverTab }, "Document failure reports error after references retire, leaving Library deletion retryable")
        store.deleteLocalDocument(.note(recoverID), profileID: profile, ownerValid: { true }, deleteDocument: { removalCalls += 1 }) { failure = $0 }
        try expect(failure == nil && removalCalls == 2, "Retry with no original tab references completes the same document deletion")
        let laterPage = store.open("https://example.test/easel-first")
        store.selectTab(laterPage)
        let easelID = UUID()
        let easel = store.openEasel(id: easelID, title: "Board", inSplit: true)!
        try expect(store.state.selectedTabIDs == [laterPage, easel], "New Easel joins as a later pane")
        try expect(store.activeSplitLayout?.tabIDs == [laterPage, easel], "The Easel keeps the original page identity")
        try expect(store.state.tabs.first { $0.id == easel }?.kind == .today, "A new Easel is a Today tab")
        try expect(store.separateTabFromSplit(easel, expected: store.activeSplitLayout!, focusedID: laterPage)
                   && store.state.selectedTabIDs == [laterPage], "Separating the Easel leaves the original first tab")
        try expect(store.openEasel(id: easelID, title: "Board", inSplit: true) == easel, "An existing Easel joins without cloning")
        try expect(store.state.selectedTabIDs == [laterPage, easel], "Open-in-split keeps the webpage as the first tab")
        print("NoteTabs: \(assertions) assertions passed")
    }
}
