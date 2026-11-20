import AppKit

@main @MainActor
struct DuplicateUndoTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-duplicate-undo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let first = BrowserFolder(id: UUID(), spaceID: space.id, name: "First")
        let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: first.id, isExpanded: false)
        let second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
        let target = BrowserFolder(id: UUID(), spaceID: space.id, name: "Target")
        let notesFolder = root.appendingPathComponent("Parc Notes")
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        let noteFile = notesFolder.appendingPathComponent("Original Note.md")
        try Data("Original body\n".utf8).write(to: noteFile)
        let noteAvailable: @MainActor () throws -> Void = {
            guard FileManager.default.fileExists(atPath: noteFile.path) else { throw CocoaError(.fileNoSuchFile) }
        }
        let easels = try EaselStore(directory: root.appendingPathComponent("Easels"))
        let easel = try easels.create(title: "Shared Easel")
        let noteBytes = try Data(contentsOf: noteFile)
        func tab(_ title: String, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                         kind: kind, folderID: parent, createdAt: Date(timeIntervalSince1970: 10),
                         lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let n = tab("Note", parent: nested.id, url: InternalPage.note(noteFile).urlString)
        let w = tab("Web", parent: nested.id)
        let e = tab("Easel", parent: second.id, url: InternalPage.easel(easel.document.id).urlString)
        let loose = tab("Loose", parent: second.id), today = tab("Today", kind: .today), keep = tab("Keep")
        let split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id,
            tabIDs: [n.id, w.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.folders = [first, nested, second, target]; state.tabs = [n, w, e, loose, today, keep]; state.splitLayouts = [split]
        let pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
        let todayLocation = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today)
        let secondLocation = SidebarContainerLocation(spaceID: space.id, folderID: second.id, section: .pinned)
        let targetLocation = SidebarContainerLocation(spaceID: space.id, folderID: target.id, section: .pinned)
        state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .folder(first.id), .folder(second.id), .folder(target.id)]
        state.sidebarItemOrder[secondLocation.key] = [.tab(loose.id), .tab(e.id)]
        state.selectedTabIDs = [keep.id]; state.selectionBySpace[space.id.uuidString] = [keep.id]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
        let initial = store.state
        let firstLocation = SidebarContainerLocation(spaceID: space.id, folderID: first.id, section: .pinned)
        let nestedLocation = SidebarContainerLocation(spaceID: space.id, folderID: nested.id, section: .pinned)
        let containers = [pinned, todayLocation, secondLocation, targetLocation, firstLocation, nestedLocation]
        func layout(_ state: BrowserState) -> [[SidebarItemReference]] { containers.map { SidebarHierarchy.children(in: $0, state: state) } }
        var documentsBlocked = false
        let references = [n.id: SidebarDocumentReference(page: .note(noteFile), profileID: profile.id) {
                              if documentsBlocked { throw CocoaError(.fileReadNoPermission) }
                              try noteAvailable() },
                          e.id: SidebarDocumentReference(page: .easel(easel.document.id), profileID: profile.id) { try easels.validateReference(easel.document.id) }]
        let items: [SidebarItemReference] = [.folder(first.id), .tab(e.id), .tab(today.id)]
        let duplicate = SidebarDuplicateTarget(items: items, spaceID: space.id, profileID: profile.id, state: initial)!
        let urls = Dictionary(uniqueKeysWithValues: duplicate.tabs.map { ($0.id, $0.savedURL) })
        let copy = try store.duplicateSidebarItems(duplicate, destinations: urls, documents: references)!
        let duplicated = store.state
        let copiedIDs = Set(copy.tabIDs)
        let record = SidebarCopyUndo(actionName: SidebarCopyUndo.duplicateName, roots: copy.roots, spaceID: space.id,
            profileID: profile.id, documents: Array(references.values), openTabIDs: copy.openTabIDs, state: duplicated)!
        try check(Set(record.tabs.map(\.id)) == copiedIDs && record.folders.count == 2 && record.groups.count == 1, "Record owns exactly the copied folders, tabs and whole split")
        try check(record.documentReferences.count == 2 && record.documentsAreAvailable, "Typed copies keep the original document references")

        var retired: [Set<UUID>] = [], allowRetirement = true
        store.requestPageRetirement = { ids, canCommit, done in retired.append(ids); done(allowRetirement && canCommit()) }
        var restored: [SidebarCopyUndo] = [], removals = 0, undoUsable = true
        func remove(_ record: SidebarCopyUndo, _ target: FolderRemovalTarget, _ done: @escaping (SidebarCopyUndo?) -> Void) {
            var refreshed: SidebarCopyUndo?
            removals += 1
            store.removeSidebarCopy(record, target: target, shouldCommit: { true }, didCommit: { refreshed = $0 }) { result in
                done((try? result.get()) == true ? refreshed : nil)
            }
        }
        let manager = FolderUndoManager()
        manager.appendSidebarCopy(record, store: store, canUse: { _, direction in direction == .redo || undoUsable }, remove: remove,
                                  didRestore: { restored.append($0) }, onError: { _ in })
        try check(manager.canUndo && manager.undoMenuItemTitle == "Undo Duplicate", "Duplicate registers one window Undo step")
        undoUsable = false
        try check(!manager.canUndo, "Undo waits while the window cannot retire a copy, such as a page still opening")
        undoUsable = true

        var renamed = store.state
        let copiedFolderID = record.folders.first { $0.parentID == nil }!.id
        renamed.folders[renamed.folders.firstIndex { $0.id == copiedFolderID }!].name = "Renamed copy"
        let copiedWeb = record.tabs.first { $0.savedURL == w.savedURL }!.id
        renamed.tabs[renamed.tabs.firstIndex { $0.id == copiedWeb }!].url = "https://saved.invalid/Web/next"
        try store.commitProfileSettings(renamed)
        let edited = store.state

        allowRetirement = false
        manager.undo()
        try check(store.state == edited && manager.canUndo && !manager.canRedo, "Declined page consent leaves every copy and the Undo step in place")
        try check(retired.last == copiedIDs, "Undo asks exactly the copied pages, and only them, to close")
        allowRetirement = true
        manager.undo()
        let undone = store.state
        try check(undone.tabs.allSatisfy { !copiedIDs.contains($0.id) } && undone.tabs == initial.tabs, "Undo removes every copy and leaves the original tabs untouched")
        try check(undone.folders == initial.folders && undone.splitLayouts == initial.splitLayouts, "Copied folders and split leave; originals keep their records")
        try check(layout(undone) == layout(initial), "Every container returns to its pre-Duplicate order")
        try check(undone.selectedTabIDs == initial.selectedTabIDs && undone.activeSpaceID == initial.activeSpaceID, "Undo keeps the window's selection")
        try check(try Data(contentsOf: noteFile) == noteBytes && easels.load(easel.document.id) === easel, "Undo never touches the shared Note or Easel")
        try check(store.archivedItems(profileID: profile.id).allSatisfy { $0.tabs.allSatisfy { !copiedIDs.contains($0.id) } }, "Undone copies do not land in the archive")
        try check(manager.canRedo && manager.redoMenuItemTitle == "Redo Duplicate" && !manager.canUndo, "Undo moves the step to Redo")
        let reloaded = try BrowserStore(directory: root)
        try check(reloaded.state.tabs.allSatisfy { !copiedIDs.contains($0.id) }, "The removal is saved")

        documentsBlocked = true
        try check(!manager.canRedo, "Redo waits while a copied document cannot be validated")
        documentsBlocked = false
        try check(manager.canRedo, "Redo returns when the document validates again")
        manager.redo()
        let redone = store.state
        try check(layout(redone) == layout(edited), "Redo puts the same copies back in the same places")
        try check(redone.tabs.filter { copiedIDs.contains($0.id) } == edited.tabs.filter { copiedIDs.contains($0.id) }, "Redo restores the copies with their identities and later edits")
        try check(redone.folders.first { $0.id == copiedFolderID }?.name == "Renamed copy", "A copy renamed before Undo comes back renamed")
        let copiedFolderIDs = Set(record.folders.map(\.id)), copiedGroupIDs = Set(record.groups.map(\.id))
        try check(redone.folders.filter { copiedFolderIDs.contains($0.id) } == edited.folders.filter { copiedFolderIDs.contains($0.id) }
            && redone.splitLayouts.filter { copiedGroupIDs.contains($0.id) } == edited.splitLayouts.filter { copiedGroupIDs.contains($0.id) }
            && redone.splitLayouts.filter { copiedGroupIDs.contains($0.id) }.count == 1, "Redo restores the nested copied folder and the copied split as they were")
        try check(record.folders.allSatisfy { folder in
            let location = SidebarContainerLocation(spaceID: space.id, folderID: folder.id, section: .pinned)
            return SidebarHierarchy.children(in: location, state: redone) == SidebarHierarchy.children(in: location, state: edited)
                && !SidebarHierarchy.children(in: location, state: redone).isEmpty
        }, "Redo restores the order inside every copied folder")
        try check(restored.count == 1 && restored[0].openTabIDs == copy.openTabIDs, "Redo hands back the pages Duplicate opened")
        try check(manager.canUndo && !manager.canRedo, "Redo makes the copy undoable again")
        try check(try BrowserStore(directory: root).state.tabs.filter { copiedIDs.contains($0.id) }.count == copiedIDs.count, "Redo is saved")

        manager.undo()
        let away = SidebarHierarchy.moving([.folder(second.id)], to: targetLocation, before: nil,
            expected: SidebarHierarchySnapshot(state: store.state, spaceID: space.id, profileID: profile.id)!, state: store.state)!
        try store.commitProfileSettings(away)
        manager.redo()
        try check(SidebarHierarchy.children(in: pinned, state: store.state) == [.tab(keep.id), .folder(first.id), copy.roots[0], .folder(target.id)],
                  "Redo skips a neighbor that moved away and lands beside the next survivor")
        let back = SidebarHierarchy.moving([.folder(second.id)], to: pinned, before: .folder(target.id),
            expected: SidebarHierarchySnapshot(state: store.state, spaceID: space.id, profileID: profile.id)!, state: store.state)!
        try store.commitProfileSettings(back)
        try check(layout(store.state) == layout(edited), "Moving the neighbor back restores the duplicated layout")

        var moved = store.state
        let copiedToday = record.tabs.first { $0.kind == .today }!.id
        moved.tabs[moved.tabs.firstIndex { $0.id == copiedToday }!].kind = .pinned
        try store.commitProfileSettings(moved)
        let removalsBefore = removals
        try check(!manager.canUndo, "A copy moved before Undo retires the step instead of removing the moved item")
        manager.undo(); manager.redo()
        try check(store.state == moved && removals == removalsBefore && !manager.canRedo, "The retired step never runs in either direction")

        let unrelated = try store.duplicateSidebarItems(SidebarDuplicateTarget(items: [.folder(first.id)], spaceID: space.id,
            profileID: profile.id, state: store.state)!, destinations: [n.id: n.savedURL, w.id: w.savedURL], documents: [n.id: references[n.id]!])!
        let folderCopy = SidebarCopyUndo(actionName: SidebarCopyUndo.duplicateName, roots: unrelated.roots, spaceID: space.id,
            profileID: profile.id, documents: Array(references.values), openTabIDs: unrelated.openTabIDs, state: store.state)!
        var grown = store.state
        let extra = tab("Added later", parent: folderCopy.folders.first { $0.parentID == nil }!.id)
        grown.tabs.append(extra)
        try store.commitProfileSettings(grown)
        try check(folderCopy.matchingTarget(in: store.state) == nil, "A tab added to a copied folder protects the folder from Undo")
        grown.tabs.removeAll { $0.id == extra.id }
        try store.commitProfileSettings(grown)

        let copiedSelection = folderCopy.tabs.first { InternalPage(urlString: $0.savedURL) == nil }!.id
        var focused = store.state
        focused.selectedTabIDs = [copiedSelection]; focused.selectionBySpace[space.id.uuidString] = [copiedSelection]
        try store.commitProfileSettings(focused)
        let folderTarget = folderCopy.matchingTarget(in: store.state)!
        let selection = FolderRemovalSelection.resolve(target: folderTarget, state: store.state, selected: [copiedSelection],
            focused: copiedSelection, available: { _ in true })!
        var outcome: Result<Bool, Error>?
        store.removeSidebarCopy(folderCopy, target: folderTarget, selection: selection, shouldCommit: { true }) { outcome = $0 }
        try check(!selection.tabIDs.isEmpty && (try? outcome?.get()) == true && store.state.selectedTabIDs == selection.tabIDs
            && selection.tabIDs.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "Undoing a selected copy moves selection to a surviving item")
        try check(store.state.tabs.allSatisfy { !Set(folderCopy.tabs.map(\.id)).contains($0.id) }, "The selected copy and its folder are removed")

        let source = CommandBarFolderMoveSource(items: [.tab(loose.id)], spaceID: space.id, profileID: profile.id, state: store.state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: store.state).first { $0.folder.folderID == target.id }!
        let beforeFolderCopy = store.state
        let pinnedCopy = try store.copyCommandBarItemsToFolder(move, destinations: [loose.id: loose.savedURL])!
        let pinRecord = SidebarCopyUndo(actionName: SidebarCopyUndo.folderCopyName, roots: pinnedCopy.roots, spaceID: space.id,
            profileID: profile.id, documents: [], openTabIDs: pinnedCopy.openTabIDs, state: store.state)!
        let pinManager = FolderUndoManager()
        pinManager.appendSidebarCopy(pinRecord, store: store, canUse: { _, _ in true }, remove: remove,
                                     didRestore: { restored.append($0) }, onError: { _ in })
        try check(pinManager.undoMenuItemTitle == "Undo Copy to Folder", "Pin to folder copies name their own step")
        pinManager.undo()
        try check(store.state.tabs.allSatisfy { !pinnedCopy.tabIDs.contains($0.id) } && layout(store.state) == layout(beforeFolderCopy), "Undo takes the folder copy back out of the destination folder")
        pinManager.redo()
        try check(SidebarHierarchy.children(in: targetLocation, state: store.state) == pinnedCopy.roots, "Redo puts the folder copy back at the end of the destination folder")

        var retiring: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in retiring = done }
        store.closeTabs([pinnedCopy.tabIDs[0]]) { _ in }
        try check(!pinManager.canUndo, "A copy that is already closing blocks Undo")
        retiring?(false)
        try check(pinManager.canUndo, "Undo returns after the other close is declined")

        store.requestPageRetirement = { _, canCommit, done in done(canCommit()) }
        func dragCopy(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
                      before: SidebarItemReference? = nil) throws -> (SidebarDuplicateResult, FolderUndoManager, SidebarCopyUndo) {
            let made = SidebarItemsCopy(items: items, spaceID: space.id, profileID: profile.id, state: store.state)!
            let sources = Dictionary(uniqueKeysWithValues: made.tabs.map { ($0.id, $0.savedURL) })
            let docs = Dictionary(uniqueKeysWithValues: made.tabs.compactMap { tab -> (UUID, SidebarDocumentReference)? in
                guard let page = InternalPage(urlString: tab.savedURL) else { return nil }
                return references.values.first { $0.page == page }.map { (tab.id, $0) }
            })
            let result = try store.copySidebarItems(made, to: destination, before: before, destinations: sources, documents: docs)!
            let record = SidebarCopyUndo(actionName: SidebarCopyUndo.dragCopyName, roots: result.roots, spaceID: space.id,
                profileID: profile.id, documents: Array(docs.values), openTabIDs: result.openTabIDs, state: store.state)!
            let manager = FolderUndoManager()
            manager.appendSidebarCopy(record, store: store, canUse: { _, _ in true }, remove: remove,
                                      didRestore: { restored.append($0) }, onError: { _ in })
            return (result, manager, record)
        }
        let beforeDrag = store.state
        let anchor = SidebarHierarchy.children(in: targetLocation, state: store.state).first
        let (dragged, dragManager, dragRecord) = try dragCopy([.tab(keep.id), .folder(second.id)], to: targetLocation, before: anchor)
        let draggedLayout = layout(store.state)
        try check(dragManager.undoMenuItemTitle == "Undo Copy" && dragRecord.documentReferences.count == 2 && dragRecord.documentsAreAvailable,
                  "An Option-drag copy registers Undo Copy and keeps its Easel aliases' references")
        dragManager.undo()
        try check(layout(store.state) == layout(beforeDrag) && store.state.tabs == beforeDrag.tabs && store.state.folders == beforeDrag.folders,
                  "Undo Copy removes the dragged copies and leaves the originals and the folder they landed in untouched")
        try check(dragManager.redoMenuItemTitle == "Redo Copy", "Redo Copy follows")
        dragManager.redo()
        try check(layout(store.state) == draggedLayout && Array(SidebarHierarchy.children(in: targetLocation, state: store.state).prefix(2)) == dragged.roots,
                  "Redo puts the copies back at the drop spot")
        try check(try Data(contentsOf: noteFile) == noteBytes && easels.load(easel.document.id) === easel, "Copying and undoing never touch the shared documents")

        let splitBefore = store.state
        let (splitCopy, splitManager, _) = try dragCopy([.split(split.id)], to: pinned, before: .tab(keep.id))
        guard case .split(let splitCopyID)? = splitCopy.roots.first else { throw NSError(domain: "split drag copy", code: 1) }
        try check(SidebarHierarchy.children(in: pinned, state: store.state).first == .split(splitCopyID) && splitManager.canUndo,
                  "A whole-split Option-drag copy can now be undone")
        splitManager.undo()
        try check(store.state.splitLayouts == splitBefore.splitLayouts && layout(store.state) == layout(splitBefore), "Undo removes the copied split whole")
        splitManager.redo()
        try check(store.state.splitLayouts.contains { $0.id == splitCopyID } && SidebarHierarchy.children(in: pinned, state: store.state).first == .split(splitCopyID),
                  "Redo brings the copied split back with the same identity")

        var withFavorite = store.state
        let favorite = tab("Favorite", kind: .favorite)
        withFavorite.tabs.append(favorite)
        try store.commitProfileSettings(withFavorite)
        let tray = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .favorite, profileID: profile.id)
        let (trayCopy, trayManager, trayRecord) = try dragCopy([.tab(keep.id)], to: tray)
        try check(trayRecord.includesFavorites && SidebarHierarchy.children(in: tray, state: store.state) == [.tab(favorite.id)] + trayCopy.roots,
                  "A copy dropped on the Favorites tray is recorded with the tray")
        trayManager.undo()
        try check(SidebarHierarchy.children(in: tray, state: store.state) == [.tab(favorite.id)] && store.state.tab(trayCopy.tabIDs[0]) == nil,
                  "Undo takes the copied Favorite back out of the tray")
        trayManager.redo()
        try check(SidebarHierarchy.children(in: tray, state: store.state) == [.tab(favorite.id)] + trayCopy.roots, "Redo returns it to the tray")
        trayManager.undo()
        var full = store.state
        full.tabs += (0..<11).map { tab("Filler\($0)", kind: .favorite) }
        try store.commitProfileSettings(full)
        try check(!trayManager.canRedo, "A full tray holds Redo back instead of overfilling it")
        let (outCopy, outManager, outRecord) = try dragCopy([.tab(favorite.id)], to: pinned)
        try check(!outRecord.includesFavorites && store.state.tab(outCopy.tabIDs[0])?.kind == .pinned, "A Favorite tile copied into Pinned is an ordinary pinned copy")
        outManager.undo()
        try check(store.state.tab(outCopy.tabIDs[0]) == nil && store.state.tab(favorite.id) != nil, "Undo removes only the copy, never the Favorite")

        var roomy = store.state
        roomy.tabs.removeAll { $0.title.hasPrefix("Filler") }
        let there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profile.id)
        var awayTab = tab("Away"); awayTab.spaceID = there.id
        roomy.spaces.append(there); roomy.tabs.append(awayTab)
        try store.commitProfileSettings(roomy)
        let (shared, _, sharedRecord) = try dragCopy([.tab(keep.id)], to: tray)
        let sharedID = shared.tabIDs[0]
        var elsewhere = store.state
        elsewhere.activeSpaceID = there.id; elsewhere.selectedTabIDs = [sharedID]; elsewhere.selectionBySpace[there.id.uuidString] = [sharedID]
        try store.commitProfileSettings(elsewhere)
        let sharedTarget = sharedRecord.matchingTarget(in: store.state)!
        let handoff = FolderRemovalSelection.resolve(target: sharedTarget, state: store.state, spaceID: there.id,
            selected: [sharedID], focused: sharedID, available: { _ in true })
        try check(handoff?.spaceID == there.id && handoff?.tabIDs == [awayTab.id],
                  "Undoing a tray copy selected in another Space of the same data hands selection to that Space's own tab")
        try check(FolderRemovalSelection.resolve(target: dragRecord.matchingTarget(in: store.state)!, state: store.state, spaceID: there.id,
            selected: [awayTab.id], focused: awayTab.id, available: { _ in true }) == nil,
                  "Copies outside the tray still resolve selection only in their own Space")
        var sharedOutcome: Result<Bool, Error>?
        store.removeSidebarCopy(sharedRecord, target: sharedTarget, selection: handoff, shouldCommit: { true }) { sharedOutcome = $0 }
        try check((try? sharedOutcome?.get()) == true && store.state.tab(sharedID) == nil && store.state.activeSpaceID == there.id
                  && store.state.selectedTabIDs == [awayTab.id], "The other Space keeps showing a real tab after the tray copy is undone")
        print("\(count) duplicate undo assertions passed")
    }
}
