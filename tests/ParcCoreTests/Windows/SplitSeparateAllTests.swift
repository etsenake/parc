import Foundation
import Testing
@testable import ParcCore

@MainActor struct SplitSeparateAllTests {
    @Test static func scenario() throws {
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
        #expect(try slotStore.moveSidebarItem(.split(slotGroup.id),
            to: SidebarContainerLocation(spaceID: slotStore.activeSpaceID, folderID: nil, section: .today),
            before: .tab(sibling), expected: slotSnapshot), "The whole split moves before an unrelated sibling")
        let splitOrder = SidebarTodayArchive.order(in: slotStore.state, spaceID: slotStore.activeSpaceID)
        #expect(slotStore.separateAllTabsFromSplit(expected: slotGroup, focusedID: firstChild),
                  "A moved split separates all children")
        #expect(SidebarTodayArchive.order(in: slotStore.state, spaceID: slotStore.activeSpaceID) == splitOrder,
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
        #expect(!store.separateAllTabsFromSplit(expected: stale, focusedID: b) && store.state == before,
                  "A stale membership receipt refuses without mutation")
        #expect(store.separateAllTabsFromSplit(expected: group, focusedID: b), "The displayed split separates all of its tabs")
        #expect(!store.state.splitLayouts.contains { $0.id == group.id }, "The container dissolves")
        #expect(store.state.selectedTabIDs == [b] && store.state.selectionBySpace[space.uuidString] == [b],
                  "The focused original stays displayed alone")
        #expect(store.state.tabs.map { ($0.id, $0.kind, $0.folderID, $0.url) }.elementsEqual(placements, by: { $0 == $1 }),
                  "Every child keeps its saved section, folder and URL")
        #expect(store.state.tabs.first { $0.id == b }?.lastAccessed == now, "The kept page is stamped as accessed")
        #expect(store.state.folders == folders && store.state.recentlyClosedIDs == archive && store.state.history == history,
                  "Separation is not a close, archive or navigation")
        let loaded = try BrowserStore(directory: root, now: { now })
        #expect(loaded.state.selectedTabIDs == [b] && !loaded.state.splitLayouts.contains { $0.id == group.id },
                  "Selection and dissolution persist together")

        store.setSplit([a,b,c]); let displayed = store.activeSplitLayout!
        #expect(store.separateAllTabsFromSplit(expected: displayed, focusedID: UUID()) && store.state.selectedTabIDs == [a],
                  "A focus outside the split keeps the first child displayed")

        store.setSplit([b,c]); let background = store.activeSplitLayout!
        store.setSplit([a])
        #expect(store.state.selectedTabIDs == [a], "Another page is displayed")
        #expect(store.separateAllTabsFromSplit(expected: background, focusedID: a), "A background split separates")
        #expect(store.state.selectedTabIDs == [a] && !store.state.splitLayouts.contains { $0.id == background.id },
                  "A background separation leaves the displayed selection")
        store.setSplit([b,c]); store.setSplitLayout(orientation: .horizontal, widthFactors: [1,3])
        let shown = store.activeSplitLayout!
        #expect(store.flipSplitOrientation(expected: shown), "The displayed split flips")
        let flipped = store.activeSplitLayout!
        #expect(flipped.id == shown.id && flipped.orientation == .vertical && flipped.widthFactors == shown.widthFactors
                  && store.state.selectedTabIDs == [b,c], "Orientation flips; proportions, identity and selection stay")
        #expect(!store.flipSplitOrientation(expected: shown), "A stale receipt refuses")
        store.setSplit([a])
        #expect(store.flipSplitOrientation(expected: flipped) && store.state.selectedTabIDs == [a]
                  && store.state.splitLayouts.first { $0.id == flipped.id }?.orientation == .horizontal,
                  "A background split flips without changing the display")
        #expect(try BrowserStore(directory: root, now: { now }).state.splitLayouts.first { $0.id == flipped.id }?.orientation == .horizontal,
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
        #expect(store.insertSplitPane(todayDraft, tabID: away, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:]),
                  "A Today tab from another Space joins the split")
        let joined = store.state.tabs.first { $0.id == away }!
        #expect(store.activeSpaceID == home && store.state.selectedTabIDs == [t, away]
                  && joined.spaceID == home && joined.kind == .today && joined.folderID == nil,
                  "It moves into this Space; the window keeps its Space")
        #expect(!store.state.splitLayouts.contains { $0.id == awayGroup.id } && store.state.tabs.contains { $0.id == awayB && $0.spaceID == other },
                  "Its old split, left with one child, dissolves in its own Space")
        let pinnedDraft = SplitPaneInsertion(paneID: away, operation: .addAfter, state: store.state)!
        let homeID = UUID()
        #expect(store.insertSplitPane(pinnedDraft, tabID: saved, navigationURL: nil, creation: nil,
                                        savedHomeIDs: [saved: homeID], documents: [:]),
                  "A pinned tab from another Space joins the split")
        let copy = store.state.tabs.first { $0.id == homeID }
        #expect(store.state.selectedTabIDs == [t, away, saved] && store.state.tabs.first { $0.id == saved }?.spaceID == home
                  && copy?.spaceID == other && copy?.kind == .pinned && copy?.url == savedRecord.savedURL,
                  "Its saved home stays in its own Space")
        #expect(store.state.selectionBySpace[other.uuidString] == [homeID], "The other Space remembers the saved home, not the moved page")
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
        #expect(store.insertSplitPane(slotDraft, tabID: b1, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:]),
                  "The origin split's anchor joins from another Space")
        let survivor = store.state.splitLayouts.first { $0.id == bGroup.id }
        #expect(survivor?.tabIDs == [b2, b3] && survivor?.sidebarAnchorID == b2
                  && SidebarHierarchy.children(in: bToday, state: store.state).firstIndex(of: .split(bGroup.id)) == bSlot,
                  "The origin split keeps its slot under its new anchor")
        let joinedGroup = store.activeSplitLayout!
        #expect(SidebarHierarchy.children(in: aToday, state: store.state).firstIndex(of: .split(joinedGroup.id)) == qSlot,
                  "The destination split stays at the target pane's slot")

        store.selectSpace(other)
        let far = store.open("https://far.invalid")
        store.selectSpace(home)
        let focusTab = store.open("https://focus.invalid"); store.setSplit([focusTab])
        #expect(store.insertCommandBarSplit(after: focusTab, expectedSelection: [focusTab], tabID: far),
                  "Option-Return accepts a tab from another Space of the Profile")
        #expect(store.state.selectedTabIDs == [focusTab, far] && store.activeSpaceID == home
                  && store.state.tabs.first { $0.id == far }?.spaceID == home, "It joins this split without a Space switch")

        let farNote = root.appendingPathComponent("Far Note.md"), farNote2 = root.appendingPathComponent("Far Note 2.md")
        try Data().write(to: farNote); try Data().write(to: farNote2)
        store.selectSpace(other)
        let noteTab = store.openNote(url: farNote, title: "Far Note")!, noteTab2 = store.openNote(url: farNote2, title: "Far Note 2")!
        store.setKind(noteTab, .pinned); store.setKind(noteTab2, .pinned)
        store.selectSpace(home)
        let notePane = store.open("https://note-pane.invalid"); store.setSplit([notePane])
        let noteDraft = SplitPaneInsertion(paneID: notePane, operation: .addAfter, state: store.state)!
        let noteHomes = OriginalSplitDrop.savedHomes(source: noteTab, state: store.state, selection: noteDraft.selection, layout: noteDraft.layout,
                                                     target: .insert(noteDraft.index), orientation: noteDraft.orientation, spaceID: home)!
        #expect(noteHomes.map(\.id) == [noteTab], "The pinned Note is planned a home before the move")
        let noteProfile = store.activeSpace.profileID
        let noteRef = SidebarDocumentReference(page: .note(farNote), profileID: noteProfile) { guard FileManager.default.fileExists(atPath: farNote.path) else { throw CocoaError(.fileNoSuchFile) } }
        let noteHomeID = UUID()
        #expect(store.insertSplitPane(noteDraft, tabID: noteTab, navigationURL: nil, creation: nil,
                                        savedHomeIDs: [noteTab: noteHomeID], documents: [noteTab: noteRef]),
                  "Add Split accepts a pinned Note from another Space")
        #expect(store.state.tabs.first { $0.id == noteHomeID }?.spaceID == other && store.state.selectedTabIDs.contains(noteTab),
                  "Its saved home stays in its Space and the Note joins")
        let ref2 = SidebarDocumentReference(page: .note(farNote2), profileID: noteProfile) { guard FileManager.default.fileExists(atPath: farNote2.path) else { throw CocoaError(.fileNoSuchFile) } }
        let homeID2 = UUID(), noteSelection = store.state.selectedTabIDs
        #expect(store.insertCommandBarSplit(after: noteTab, expectedSelection: noteSelection, tabID: noteTab2,
                                              savedHomeIDs: [noteTab2: homeID2], documents: [noteTab2: ref2]),
                  "Option-Return accepts a pinned Note from another Space with its planned home")
        #expect(store.state.tabs.first { $0.id == homeID2 }?.spaceID == other, "Option-Return uses the planned home ID")

        store.selectSpace(home)
        let p1 = store.open("https://p1.invalid"), p2 = store.open("https://p2.invalid")
        let outer = store.createFolder(name: "Outer")
        store.setSplit([p1, p2]); let pinnedGroup = store.activeSplitLayout!
        let profile = store.activeSpace.profileID
        let intoOuter = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
        #expect(try store.moveSidebarItem(.split(pinnedGroup.id), to: SidebarContainerLocation(spaceID: home, folderID: outer, section: .pinned),
                                            before: nil, expected: intoOuter), "The split moves into a folder")
        store.toggleFolder(outer)
        store.selectSpace(other)
        let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
        let beforeFolder = store.state, folderID = UUID()
        let receipt = try store.createFolder(containing: [.split(pinnedGroup.id)], folderID: folderID, expected: snapshot)
        let made = store.state.folders.first { $0.id == folderID }
        #expect(receipt != nil && made?.name == SidebarFolderFromItems.defaultName && made?.parentID == outer && made?.spaceID == home,
                  "The folder takes the default name inside the split's own parent folder")
        #expect(store.state.folders.first { $0.id == outer }?.isExpanded == true, "Its collapsed ancestor expands")
        #expect(store.activeSpaceID == other, "It is made in the window's Space while another window's Space is active")
        store.renameFolder(outer, name: "Renamed outer")
        store.updateTab(p1, title: "Changed title")
        store.renameFolder(folderID, name: "Named by the prompt")
        #expect([p1, p2].allSatisfy { id in store.state.tabs.first { $0.id == id }?.folderID == folderID }
                  && store.state.splitLayouts.contains { $0.id == pinnedGroup.id && $0.tabIDs == [p1, p2] },
                  "The whole split moves into it and stays a split")
        #expect(SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: home, folderID: folderID, section: .pinned),
                                            state: store.state) == [.split(pinnedGroup.id)], "The folder holds the split")
        #expect(try store.createFolder(containing: [.split(pinnedGroup.id)], folderID: UUID(), expected: snapshot) == nil,
                  "A stale hierarchy refuses")
        #expect(try BrowserStore(directory: root, now: { now }).state.folders.contains { $0.id == folderID }, "Folder and move persist")
        let undoReceipt = try store.revertFolderCreation(receipt!, undo: true)
        #expect(undoReceipt != nil, "Undo removes the folder")
        #expect(!store.state.folders.contains { $0.id == folderID } && store.state.sidebarItemOrder == beforeFolder.sidebarItemOrder
                  && [p1, p2].allSatisfy { id in store.state.tabs.first { $0.id == id }?.folderID == outer }
                  && store.state.tabs.first { $0.id == p1 }?.title == "Changed title"
                  && store.state.folders.first { $0.id == outer }?.name == "Renamed outer",
                  "Undo after unrelated edits restores the items' placement and keeps those edits")
        #expect(try store.revertFolderCreation(undoReceipt!, undo: true) == nil, "Undo applies once")
        #expect(try store.revertFolderCreation(undoReceipt!, undo: false) != nil
                  && store.state.folders.first { $0.id == folderID }?.name == "Named by the prompt",
                  "Redo recreates the same folder with the name entered after creation")
        store.selectSpace(home)
        let todayItem = store.open("https://loose.invalid"); store.setSplit([todayItem])
        let looseSnapshot = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
        let todayFolder = UUID()
        #expect(try store.createFolder(containing: [.tab(todayItem)], folderID: todayFolder, expected: looseSnapshot) != nil
                  && store.state.folders.first { $0.id == todayFolder }?.parentID == nil
                  && store.state.tabs.first { $0.id == todayItem }?.folderID == todayFolder,
                  "A Today item's folder is made in the pinned root")
        store.selectSpace(home)
        let x = store.open("https://x.invalid"), y = store.open("https://y.invalid"), z = store.open("https://z.invalid")
        let todayOrder = SidebarTodayArchive.order(in: store.state, spaceID: home)
        #expect(todayOrder.firstIndex(of: z)! < todayOrder.firstIndex(of: x)!, "New Today tabs open at the top, so the sidebar order differs from the array order")
        #expect(SidebarTodayArchive.admits(anchorID: y, order: todayOrder, ids: [x], state: store.state, spaceID: home, profileID: profile),
                  "The current Today order admits an archive group")
        #expect(!SidebarTodayArchive.admits(anchorID: y, order: store.state.tabs.filter { $0.kind == .today && $0.spaceID == home && $0.archivedAt == nil }.map(\.id),
                                              ids: [x], state: store.state, spaceID: home, profileID: profile),
                  "The tab array order is not the sidebar's order")
    }
}
