import Foundation
import Testing
@testable import ParcCore

@MainActor struct SplitPaneControlsTests {
    @Test static func scenario() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pane-controls-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = try BrowserStore(directory: root, now: { now })
        let saved = store.open("https://one.invalid", kind: .pinned)
        let folder = store.createFolder(name: "Original parent")
        store.moveTab(saved, toSpace: store.activeSpaceID, folderID: folder)
        let a = store.open("https://one.invalid/today")
        let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
        store.setSplit([a,b,c]); store.setSplitLayout(orientation: .vertical, widthFactors: [1,2,3])
        let original = store.activeSplitLayout!, tabs = store.state.tabs, archive = store.state.recentlyClosedIDs
        #expect(!store.moveSplitPane(a, offset: -1, expected: original), "First pane cannot move before start")
        #expect(!store.moveSplitPane(c, offset: 1, expected: original), "Last pane cannot move after end")
        #expect(!store.moveSplitPane(a, offset: Int.min, expected: original), "Untrusted offset refuses without overflow")
        #expect(store.moveSplitPane(b, offset: 1, expected: original), "Move original pane down")
        let moved = store.activeSplitLayout!
        #expect(moved.tabIDs == [a,c,b] && moved.id == original.id, "Move retains original group and ordered page IDs")
        #expect(moved.widthFactors == [original.widthFactors[0], original.widthFactors[2], original.widthFactors[1]], "Original pane proportions move with content")
        #expect(moved.orientation == .vertical && moved.sidebarAnchorID == original.sidebarAnchorID, "Move preserves container orientation and anchor")
        #expect(store.state.tabs == tabs && store.state.recentlyClosedIDs == archive, "Move does not recreate pages or close originals")
        #expect(store.state.selectedTabIDs == moved.tabIDs && store.state.selectionBySpace[store.activeSpaceID.uuidString] == moved.tabIDs, "Order and window selection publish together")
        #expect(try BrowserStore(directory: root).activeSplitLayout == moved, "Move is durably restored")
        let unchanged = store.state
        #expect(!store.moveSplitPane(b, offset: -1, expected: original) && store.state == unchanged, "Stale menu receipt refuses")
        #expect(store.moveSplitPane(b, offset: -1, expected: moved), "Inverse original move remains available")
        #expect(store.activeSplitLayout == original, "Inverse move restores original metadata and ratios")
        #expect(!SplitPaneOperation.movePrevious.isEnabled(index: 0, count: 3) && SplitPaneOperation.moveNext.isEnabled(index: 0, count: 3), "Native menu neighbor availability")
        #expect(!SplitPaneOperation.addAfter.isEnabled(index: 0, count: 4), "Actual four-content maximum")
        #expect(!SplitPaneOperation.separate.isEnabled(index: 0, count: 1), "No separation for sole pane")
        #expect(SplitPaneOperation.copyLinks.isEnabled(index: 0, count: 2) && !SplitPaneOperation.copyLinks.isEnabled(index: 0, count: 1),
                  "Copy Links is a populated-split action")
        let beforeDraft = store.state
        let draft = SplitPaneInsertion(paneID: b, operation: .addAbove, state: store.state)!
        #expect(draft.index == 1 && draft.orientation == .vertical && draft.selection == [a,b,c], "Exact target top insertion")
        #expect(draft.previewFactors.count == 4 && abs(draft.previewFactors.reduce(0,+) - 1) < 0.00001, "Temporary geometry stays normalized")
        let previousFactors = store.activeSplitLayout!.widthFactors, pendingFactors = draft.previewFactors
        #expect(abs(pendingFactors[1] - 0.25) < 0.00001, "Pending pane receives one over the new pane count")
        #expect(zip(previousFactors, [pendingFactors[0], pendingFactors[2], pendingFactors[3]]).allSatisfy { abs($0 * 0.75 - $1) < 0.00001 },
                  "Existing panes keep their relative factors")
        #expect(store.state == beforeDraft, "Creating a temporary destination never persists a placeholder")
        let id = UUID(), url = URL(string: "https://four.invalid/post-result")!
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: b, profileID: store.activeSpace.profileID, state: store.state)
        #expect(store.insertSplitPane(draft, tabID: id, navigationURL: url, creation: creation, savedHomeIDs: [:], documents: [:]), "Accepted genuine navigation inserts one record atomically")
        #expect(store.state.selectedTabIDs == [a,id,b,c] && store.activeSplitLayout?.id == original.id, "New pane uses requested slot in original container")
        let created = store.state.tabs.first { $0.id == id }!
        #expect(created.url == url.absoluteString && created.kind == .today && created.activeTabBeforeCreationID == b, "Destination metadata and original creation source preserved")
        #expect(tabs.allSatisfy { store.state.tabs.contains($0) }, "Existing pages and saved records retain exact identity")
        #expect(SplitPaneInsertion(paneID: id, operation: .addAfter, state: store.state) == nil, "Fifth pane cannot be drafted")
        let full = store.state
        #expect(!store.insertSplitPane(draft, tabID: UUID(), navigationURL: url, creation: nil, savedHomeIDs: [:], documents: [:]) && store.state == full, "Previously admitted draft cannot replay after membership changed")
        #expect(try BrowserStore(directory: root).state.selectedTabIDs == [a,id,b,c], "Accepted pane and group persist together")
        _ = store.separateSplitPane(b)
        let single = SplitPaneInsertion(paneID: b, operation: .addAfter, state: store.state)!
        #expect(single.selection.count == 1 && single.index == 1, "Main Add supports a single original content")
        let noteFile = root.appendingPathComponent("Shared Note.md")
        let noteID = store.openNote(url: noteFile, title: "Shared Note")!
        store.selectTab(b)
        let local = SplitPaneInsertion(paneID: b, operation: .addBelow, state: store.state)!
        let oldNote = store.state.tabs.first { $0.id == noteID }!
        #expect(store.insertSplitPane(local, tabID: noteID, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:]), "Existing original local Note can fill a blank pane")
        #expect(store.state.tabs.first { $0.id == noteID }?.url == oldNote.url && store.state.selectedTabIDs == [b,noteID], "Original local record is moved, never cloned")
        #expect(store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(noteFile) }.count == 1,
                  "A Today Note does not leave a saved home")
        #expect(store.separateTabFromSplit(noteID, expected: store.activeSplitLayout!, focusedID: b)
                  && store.state.selectedTabIDs == [b], "Separating the Note restores the original first pane")
        let easels = try EaselStore(directory: root.appendingPathComponent("easels"))
        let easel = try easels.create()
        let easelID = store.openEasel(id: easel.document.id, title: "Shared Easel")!
        store.selectTab(b)
        let easelPane = SplitPaneInsertion(paneID: b, operation: .addAfter, state: store.state)!
        let oldEasel = store.state.tabs.first { $0.id == easelID }!
        #expect(store.insertSplitPane(easelPane, tabID: easelID, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:]), "Existing original local Easel can fill a blank pane")
        #expect(store.state.tabs.first { $0.id == easelID }?.url == oldEasel.url && store.state.selectedTabIDs == [b,easelID], "Original Easel record is moved, never cloned")
        #expect(store.state.tabs.filter { InternalPage(urlString: $0.url)?.easelID == easel.document.id }.count == 1,
                  "A Today Easel does not leave a saved home")
        #expect(try easels.load(easel.document.id) === easel, "Shared Easel session remains original")
        let laterHost = store.open("https://later.invalid/host")
        store.selectTab(laterHost)
        let createdNote = root.appendingPathComponent("Untitled.md")
        let createdNoteTab = UUID()
        let addLeft = SplitPaneInsertion(paneID: laterHost, operation: .addBefore, state: store.state)!
        #expect(addLeft.index == 0 && addLeft.orientation == .horizontal && addLeft.selection == [laterHost], "Add Left drafts the first slot")
        let beforeCreatedNote = store.state
        #expect(!store.insertSplitPane(addLeft, tabID: UUID(), navigationURL: url, creation: nil, savedHomeIDs: [:], documents: [:],
            localPage: .note(createdNote), localTitle: "Untitled") && store.state == beforeCreatedNote,
                  "A local page and a navigation URL cannot materialize together")
        #expect(store.insertSplitPane(addLeft, tabID: createdNoteTab, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:],
            localPage: .note(createdNote), localTitle: "Untitled"),
                  "A new Note occupies Add Split's drafted slot")
        #expect(store.state.selectedTabIDs == [createdNoteTab, laterHost], "Add Left puts the new Note in the first slot, not after the host")
        #expect(store.activeSplitLayout?.orientation == .horizontal, "Add Left keeps the drafted horizontal orientation")
        #expect(store.state.tabs.first { $0.id == createdNoteTab }?.url == InternalPage.note(createdNote).urlString,
                  "The new Note tab addresses the created document")
        #expect(store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(createdNote) }.count == 1,
                  "A new Today Note does not leave a saved home")
        #expect(store.separateTabFromSplit(createdNoteTab, expected: store.activeSplitLayout!, focusedID: laterHost)
                  && store.state.selectedTabIDs == [laterHost], "Separating the new Note restores the original host")
        let createdEasel = try easels.create()
        let createdEaselTab = UUID()
        let addTop = SplitPaneInsertion(paneID: laterHost, operation: .addAbove, state: store.state)!
        #expect(addTop.index == 0 && addTop.orientation == .vertical && addTop.selection == [laterHost], "Add Top drafts a vertical first slot")
        let beforeClone = store.state
        #expect(!store.insertSplitPane(addTop, tabID: UUID(), navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:],
            localPage: .note(createdNote), localTitle: "Untitled") && store.state == beforeClone,
                  "The same new Note document cannot open a second tab")
        #expect(store.insertSplitPane(addTop, tabID: createdEaselTab, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:],
            localPage: .easel(createdEasel.document.id), localTitle: createdEasel.document.title),
                  "A new Easel occupies Add Top's drafted slot")
        #expect(store.state.selectedTabIDs == [createdEaselTab, laterHost], "Add Top puts the new Easel above the host, not appended")
        #expect(store.activeSplitLayout?.orientation == .vertical, "Add Top keeps the drafted vertical orientation")
        store.selectTab(saved)
        let pinned = SplitPaneInsertion(paneID: saved, operation: .addAfter, state: store.state)!
        let newID = UUID(), home = UUID()
        let beforePinned = store.state
        #expect(!store.insertSplitPane(pinned, tabID: newID, navigationURL: url, creation: nil, savedHomeIDs: [:], documents: [:]), "Saved original needs a real saved-home receipt")
        #expect(store.state == beforePinned, "Missing home does not leak a partial new tab")
        #expect(store.insertSplitPane(pinned, tabID: newID, navigationURL: url, creation: nil, savedHomeIDs: [saved:home], documents: [:]), "Pinned original moves with a fresh saved home")
        #expect(store.state.tabs.first { $0.id == home }?.folderID == folder && store.state.tabs.first { $0.id == home }?.kind == .pinned, "Home retains exact parent section")
        #expect(store.state.tabs.first { $0.id == saved }?.kind == .today && store.state.selectedTabIDs == [saved,newID], "Live original becomes the pane; saved home never replaces its page")
        let pending = SplitPaneInsertion(paneID: saved, operation: .addBelow, state: store.state)!
        var foreign = store.state; foreign.spaces[0].profileID = UUID()
        #expect(!pending.isCurrent(in: foreign), "Destination profile changes invalidate the original draft")
        var removedProfile = store.state; removedProfile.profiles.removeAll { $0.id == pending.profileID }
        #expect(!pending.isCurrent(in: removedProfile), "Removed original profile invalidates draft")
        var archived = store.state; archived.tabs[archived.tabs.firstIndex { $0.id == saved }!].archivedAt = now
        #expect(!pending.isCurrent(in: archived), "Retired original invalidates draft")
        var changed = store.state; changed.splitLayouts[changed.splitLayouts.firstIndex { $0.id == pending.layout?.id }!].widthFactors = [0.75,0.25]
        #expect(!pending.isCurrent(in: changed), "Changed group geometry invalidates exact draft")
        let failureState = store.state, failureID = UUID()
        try FileManager.default.removeItem(at: root); try Data().write(to: root)
        #expect(!store.insertSplitPane(pending, tabID: failureID, navigationURL: url, creation: nil, savedHomeIDs: [:], documents: [:]), "Actual storage failure refuses pane materialization")
        #expect(store.state == failureState && store.persistenceError != nil, "Failed save preserves originals and no orphan tab")
        #expect(!store.moveSplitPane(saved, offset: 1, expected: store.activeSplitLayout!), "Storage failure also refuses reorder")
        #expect(store.state == failureState, "Failed reorder does not publish visual order")
        try FileManager.default.removeItem(at: root); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(store.insertSplitPane(pending, tabID: failureID, navigationURL: url, creation: nil, savedHomeIDs: [:], documents: [:]), "Same original receipt retries after storage recovery")
        #expect(store.persistenceError == nil, "Successful retry clears durable error")
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        let linkNote = store.openResolvedURL(URL(string: InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString)!)
        let linkEasel = store.openResolvedURL(URL(string: InternalPage.easel(UUID()).urlString)!)
        let linkSettings = store.openResolvedURL(URL(string: "parc://settings/")!)
        let linkBlank = store.openResolvedURL(URL(string: "about:blank")!)
        #expect(FolderLinks.links(in: store.state, tabIDs: [c, a, b], spaceID: space, profileID: profile).map(\.tabID) == [c, a, b],
                  "Copy Links copies every page's address in pane order")
        #expect(FolderLinks.links(in: store.state, tabIDs: [linkNote, b, linkSettings, linkEasel, a, linkBlank, b], spaceID: space, profileID: profile).map(\.tabID) == [linkNote, b, a],
                  "Notes copy their file, Easels, Parc pages and blank tabs are skipped, and a page is copied once")
        #expect(FolderLinks.links(in: store.state, tabIDs: [linkEasel, linkSettings], spaceID: space, profileID: profile).isEmpty,
                  "A split without a web page has nothing to copy, so its Copy Links stays disabled")
        #expect(FolderLinks.links(in: store.state, tabIDs: [a, b], spaceID: space, profileID: UUID()).isEmpty,
                  "Another Profile's pages are never copied")
    }
}
