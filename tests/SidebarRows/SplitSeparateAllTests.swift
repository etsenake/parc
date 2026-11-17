import Foundation

@main @MainActor struct SplitSeparateAllTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-separate-all-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let slotStore = try BrowserStore(directory: root.appendingPathComponent("slots"), now: { now })
        let sibling = slotStore.open("https://sibling.invalid")
        let firstChild = slotStore.open("https://first.invalid"), secondChild = slotStore.open("https://second.invalid")
        _ = slotStore.open("https://other-sibling.invalid")
        slotStore.setSplit([secondChild, firstChild])
        let slotGroup = slotStore.activeSplitLayout!
        let slotSnapshot = SidebarHierarchySnapshot(state: slotStore.state, spaceID: slotStore.activeSpaceID,
            profileID: slotStore.activeSpace.profileID, includesFavorites: true)!
        try check(try slotStore.moveSidebarItem(.split(slotGroup.id),
            to: SidebarContainerLocation(spaceID: slotStore.activeSpaceID, folderID: nil, section: .today),
            before: .tab(sibling), expected: slotSnapshot), "The whole split moves before an unrelated sibling")
        let splitOrder = SidebarTodayArchive.order(in: slotStore.state, spaceID: slotStore.activeSpaceID)
        try check(slotStore.separateAllTabsFromSplit(expected: slotGroup, focusedID: firstChild),
                  "A moved split separates all children")
        try check(SidebarTodayArchive.order(in: slotStore.state, spaceID: slotStore.activeSpaceID) == splitOrder,
                  "Separated children replace the moved split's exact slot in pane order")
        let store = try BrowserStore(directory: root, now: { now })
        let a = store.open("https://one.invalid", kind: .pinned)
        let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
        let folder = store.createFolder(name: "Original")
        store.moveTab(a, toSpace: store.activeSpaceID, folderID: folder)
        store.setSplit([a,b,c]); store.setSplitLayout(orientation: .vertical, widthFactors: [1,2,3])
        let space = store.activeSpaceID
        let group = store.activeSplitLayout!, folders = store.state.folders
        let archive = store.state.recentlyClosedIDs, history = store.state.history
        let placements = store.state.tabs.map { ($0.id, $0.kind, $0.folderID, $0.url) }

        let stale = BrowserSplitLayout(id: group.id, sidebarAnchorID: group.sidebarAnchorID, spaceID: group.spaceID,
                                       tabIDs: [a,b], orientation: group.orientation, widthFactors: [0.5, 0.5], stacks: nil)
        let before = store.state
        try check(!store.separateAllTabsFromSplit(expected: stale, focusedID: b) && store.state == before,
                  "A stale membership receipt refuses without mutation")
        try check(store.separateAllTabsFromSplit(expected: group, focusedID: b), "The displayed split separates all of its tabs")
        try check(!store.state.splitLayouts.contains { $0.id == group.id }, "The container dissolves")
        try check(store.state.selectedTabIDs == [b] && store.state.selectionBySpace[space.uuidString] == [b],
                  "The focused original stays displayed alone")
        try check(store.state.tabs.map { ($0.id, $0.kind, $0.folderID, $0.url) }.elementsEqual(placements, by: { $0 == $1 }),
                  "Every child keeps its saved section, folder and URL")
        try check(store.state.tabs.first { $0.id == b }?.lastAccessed == now, "The kept page is stamped as accessed")
        try check(store.state.folders == folders && store.state.recentlyClosedIDs == archive && store.state.history == history,
                  "Separation is not a close, archive or navigation")
        let loaded = try BrowserStore(directory: root, now: { now })
        try check(loaded.state.selectedTabIDs == [b] && !loaded.state.splitLayouts.contains { $0.id == group.id },
                  "Selection and dissolution persist together")

        store.setSplit([a,b,c]); let displayed = store.activeSplitLayout!
        try check(store.separateAllTabsFromSplit(expected: displayed, focusedID: UUID()) && store.state.selectedTabIDs == [a],
                  "A focus outside the split keeps the first child displayed")

        store.setSplit([b,c]); let background = store.activeSplitLayout!
        store.setSplit([a])
        try check(store.state.selectedTabIDs == [a], "Another page is displayed")
        try check(store.separateAllTabsFromSplit(expected: background, focusedID: a), "A background split separates")
        try check(store.state.selectedTabIDs == [a] && !store.state.splitLayouts.contains { $0.id == background.id },
                  "A background separation leaves the displayed selection")
        store.setSplit([b,c]); store.setSplitLayout(orientation: .horizontal, widthFactors: [1,3])
        let shown = store.activeSplitLayout!
        try check(store.flipSplitOrientation(expected: shown), "The displayed split flips")
        let flipped = store.activeSplitLayout!
        try check(flipped.id == shown.id && flipped.orientation == .vertical && flipped.widthFactors == shown.widthFactors
                  && store.state.selectedTabIDs == [b,c], "Orientation flips; proportions, identity and selection stay")
        try check(!store.flipSplitOrientation(expected: shown), "A stale receipt refuses")
        store.setSplit([a])
        try check(store.flipSplitOrientation(expected: flipped) && store.state.selectedTabIDs == [a]
                  && store.state.splitLayouts.first { $0.id == flipped.id }?.orientation == .horizontal,
                  "A background split flips without changing the display")
        try check(try BrowserStore(directory: root, now: { now }).state.splitLayouts.first { $0.id == flipped.id }?.orientation == .horizontal,
                  "The flip persists")

        let home = store.activeSpaceID
        let other = store.createSpace(name: "Other")
        store.selectSpace(other)
        let away = store.open("https://away.invalid")
        let saved = store.open("https://saved.invalid", kind: .pinned)
        let awayB = store.open("https://away-b.invalid")
        store.setSplit([away, awayB]); let awayGroup = store.activeSplitLayout!
        store.setSplit([saved])
        let savedRecord = store.state.tabs.first { $0.id == saved }!
        store.selectSpace(home)
        let t = store.open("https://here.invalid"); store.setSplit([t])
        let todayDraft = SplitPaneInsertion(paneID: t, operation: .addAfter, state: store.state)!
        try check(store.insertSplitPane(todayDraft, tabID: away, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:]),
                  "A Today tab from another Space joins the split")
        let joined = store.state.tabs.first { $0.id == away }!
        try check(store.activeSpaceID == home && store.state.selectedTabIDs == [t, away]
                  && joined.spaceID == home && joined.kind == .today && joined.folderID == nil,
                  "It moves into this Space; the window keeps its Space")
        try check(!store.state.splitLayouts.contains { $0.id == awayGroup.id } && store.state.tabs.contains { $0.id == awayB && $0.spaceID == other },
                  "Its old split, left with one child, dissolves in its own Space")
        let pinnedDraft = SplitPaneInsertion(paneID: away, operation: .addAfter, state: store.state)!
        let homeID = UUID()
        try check(store.insertSplitPane(pinnedDraft, tabID: saved, navigationURL: nil, creation: nil,
                                        savedHomeIDs: [saved: homeID], documents: [:]),
                  "A pinned tab from another Space joins the split")
        let copy = store.state.tabs.first { $0.id == homeID }
        try check(store.state.selectedTabIDs == [t, away, saved] && store.state.tabs.first { $0.id == saved }?.spaceID == home
                  && copy?.spaceID == other && copy?.kind == .pinned && copy?.url == savedRecord.savedURL,
                  "Its saved home stays in its own Space")
        try check(store.state.selectionBySpace[other.uuidString] == [homeID], "The other Space remembers the saved home, not the moved page")
        store.selectSpace(other)
        let b1 = store.open("https://b1.invalid"), b2 = store.open("https://b2.invalid"), b3 = store.open("https://b3.invalid")
        let filler = store.open("https://filler.invalid")
        store.setSplit([b1, b2, b3]); let bGroup = store.activeSplitLayout!
        store.setSplit([filler])
        let bToday = SidebarContainerLocation(spaceID: other, folderID: nil, section: .today)
        let bSlot = SidebarHierarchy.children(in: bToday, state: store.state).firstIndex(of: .split(bGroup.id))!
        store.selectSpace(home)
        let q = store.open("https://q.invalid"); _ = store.open("https://above-q.invalid")
        store.setSplit([q])
        let aToday = SidebarContainerLocation(spaceID: home, folderID: nil, section: .today)
        let qSlot = SidebarHierarchy.children(in: aToday, state: store.state).firstIndex(of: .tab(q))!
        let slotDraft = SplitPaneInsertion(paneID: q, operation: .addAfter, state: store.state)!
        try check(store.insertSplitPane(slotDraft, tabID: b1, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:]),
                  "The origin split's anchor joins from another Space")
        let survivor = store.state.splitLayouts.first { $0.id == bGroup.id }
        try check(survivor?.tabIDs == [b2, b3] && survivor?.sidebarAnchorID == b2
                  && SidebarHierarchy.children(in: bToday, state: store.state).firstIndex(of: .split(bGroup.id)) == bSlot,
                  "The origin split keeps its slot under its new anchor")
        let joinedGroup = store.activeSplitLayout!
        try check(SidebarHierarchy.children(in: aToday, state: store.state).firstIndex(of: .split(joinedGroup.id)) == qSlot,
                  "The destination split stays at the target pane's slot")

        store.selectSpace(other)
        let far = store.open("https://far.invalid")
        store.selectSpace(home)
        let focusTab = store.open("https://focus.invalid"); store.setSplit([focusTab])
        try check(store.insertCommandBarSplit(after: focusTab, expectedSelection: [focusTab], tabID: far),
                  "Option-Return accepts a tab from another Space of the Profile")
        try check(store.state.selectedTabIDs == [focusTab, far] && store.activeSpaceID == home
                  && store.state.tabs.first { $0.id == far }?.spaceID == home, "It joins this split without a Space switch")

        let notes = try NoteStore(directory: root.appendingPathComponent("notes"), diskSaveDelay: 0)
        let farNote = try notes.create(), farNote2 = try notes.create()
        store.selectSpace(other)
        let noteTab = store.openNote(id: farNote.document.id, title: "Far Note")!, noteTab2 = store.openNote(id: farNote2.document.id, title: "Far Note 2")!
        store.setKind(noteTab, .pinned); store.setKind(noteTab2, .pinned)
        store.selectSpace(home)
        let notePane = store.open("https://note-pane.invalid"); store.setSplit([notePane])
        let noteDraft = SplitPaneInsertion(paneID: notePane, operation: .addAfter, state: store.state)!
        let noteHomes = OriginalSplitDrop.savedHomes(source: noteTab, state: store.state, selection: noteDraft.selection, layout: noteDraft.layout,
                                                     target: .insert(noteDraft.index), orientation: noteDraft.orientation, spaceID: home)!
        try check(noteHomes.map(\.id) == [noteTab], "The pinned Note is planned a home before the move")
        let noteProfile = store.activeSpace.profileID
        let noteRef = SidebarDocumentReference(page: .note(farNote.document.id), profileID: noteProfile) { try notes.validateReference(farNote.document.id) }
        let noteHomeID = UUID()
        try check(store.insertSplitPane(noteDraft, tabID: noteTab, navigationURL: nil, creation: nil,
                                        savedHomeIDs: [noteTab: noteHomeID], documents: [noteTab: noteRef]),
                  "Add Split accepts a pinned Note from another Space")
        try check(store.state.tabs.first { $0.id == noteHomeID }?.spaceID == other && store.state.selectedTabIDs.contains(noteTab),
                  "Its saved home stays in its Space and the Note joins")
        let ref2 = SidebarDocumentReference(page: .note(farNote2.document.id), profileID: noteProfile) { try notes.validateReference(farNote2.document.id) }
        let homeID2 = UUID(), noteSelection = store.state.selectedTabIDs
        try check(store.insertCommandBarSplit(after: noteTab, expectedSelection: noteSelection, tabID: noteTab2,
                                              savedHomeIDs: [noteTab2: homeID2], documents: [noteTab2: ref2]),
                  "Option-Return accepts a pinned Note from another Space with its planned home")
        try check(store.state.tabs.first { $0.id == homeID2 }?.spaceID == other, "Option-Return uses the planned home ID")

        store.selectSpace(home)
        let p1 = store.open("https://p1.invalid"), p2 = store.open("https://p2.invalid")
        let outer = store.createFolder(name: "Outer")
        store.setSplit([p1, p2]); let pinnedGroup = store.activeSplitLayout!
        let profile = store.activeSpace.profileID
        let intoOuter = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
        try check(try store.moveSidebarItem(.split(pinnedGroup.id), to: SidebarContainerLocation(spaceID: home, folderID: outer, section: .pinned),
                                            before: nil, expected: intoOuter), "The split moves into a folder")
        store.toggleFolder(outer)
        store.selectSpace(other)
        let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
        let beforeFolder = store.state, folderID = UUID()
        let receipt = try store.createFolder(containing: [.split(pinnedGroup.id)], folderID: folderID, expected: snapshot)
        let made = store.state.folders.first { $0.id == folderID }
        try check(receipt != nil && made?.name == SidebarFolderFromItems.defaultName && made?.parentID == outer && made?.spaceID == home,
                  "The folder takes the default name inside the split's own parent folder")
        try check(store.state.folders.first { $0.id == outer }?.isExpanded == true, "Its collapsed ancestor expands")
        try check(store.activeSpaceID == other, "It is made in the window's Space while another window's Space is active")
        store.renameFolder(outer, name: "Renamed outer")
        store.updateTab(p1, title: "Changed title")
        store.renameFolder(folderID, name: "Named by the prompt")
        try check([p1, p2].allSatisfy { id in store.state.tabs.first { $0.id == id }?.folderID == folderID }
                  && store.state.splitLayouts.contains { $0.id == pinnedGroup.id && $0.tabIDs == [p1, p2] },
                  "The whole split moves into it and stays a split")
        try check(SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: home, folderID: folderID, section: .pinned),
                                            state: store.state) == [.split(pinnedGroup.id)], "The folder holds the split")
        try check(try store.createFolder(containing: [.split(pinnedGroup.id)], folderID: UUID(), expected: snapshot) == nil,
                  "A stale hierarchy refuses")
        try check(try BrowserStore(directory: root, now: { now }).state.folders.contains { $0.id == folderID }, "Folder and move persist")
        let undoReceipt = try store.revertFolderCreation(receipt!, undo: true)
        try check(undoReceipt != nil, "Undo removes the folder")
        try check(!store.state.folders.contains { $0.id == folderID } && store.state.sidebarItemOrder == beforeFolder.sidebarItemOrder
                  && [p1, p2].allSatisfy { id in store.state.tabs.first { $0.id == id }?.folderID == outer }
                  && store.state.tabs.first { $0.id == p1 }?.title == "Changed title"
                  && store.state.folders.first { $0.id == outer }?.name == "Renamed outer",
                  "Undo after unrelated edits restores the items' placement and keeps those edits")
        try check(try store.revertFolderCreation(undoReceipt!, undo: true) == nil, "Undo applies once")
        try check(try store.revertFolderCreation(undoReceipt!, undo: false) != nil
                  && store.state.folders.first { $0.id == folderID }?.name == "Named by the prompt",
                  "Redo recreates the same folder with the name entered after creation")
        store.selectSpace(home)
        let todayItem = store.open("https://loose.invalid"); store.setSplit([todayItem])
        let looseSnapshot = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
        let todayFolder = UUID()
        try check(try store.createFolder(containing: [.tab(todayItem)], folderID: todayFolder, expected: looseSnapshot) != nil
                  && store.state.folders.first { $0.id == todayFolder }?.parentID == nil
                  && store.state.tabs.first { $0.id == todayItem }?.folderID == todayFolder,
                  "A Today item's folder is made in the pinned root")
        store.selectSpace(home)
        let x = store.open("https://x.invalid"), y = store.open("https://y.invalid"), z = store.open("https://z.invalid")
        let todayOrder = SidebarTodayArchive.order(in: store.state, spaceID: home)
        try check(todayOrder.firstIndex(of: z)! < todayOrder.firstIndex(of: x)!, "New Today tabs open at the top, so the sidebar order differs from the array order")
        try check(SidebarTodayArchive.admits(anchorID: y, order: todayOrder, ids: [x], state: store.state, spaceID: home, profileID: profile),
                  "The current Today order admits an archive group")
        try check(!SidebarTodayArchive.admits(anchorID: y, order: store.state.tabs.filter { $0.kind == .today && $0.spaceID == home && $0.archivedAt == nil }.map(\.id),
                                              ids: [x], state: store.state, spaceID: home, profileID: profile),
                  "The tab array order is not the sidebar's order")
        print("SplitSeparateAllTests: \(count) assertions passed")
    }
}
