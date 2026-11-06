import AppKit

/// Real persistent BrowserStore and the window's FolderUndoManager. All files
/// are temporary; native page owners are represented by their consent boundary.
@main @MainActor
struct CloseUndoTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-close-undo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let there = BrowserSpace(id: UUID(), name: "There", symbol: "square", color: "123456", profileID: profile.id)
        func tab(_ title: String, _ space: BrowserSpace, kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
            let url = "https://" + title.lowercased().replacingOccurrences(of: " ", with: "-") + ".invalid/"
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                         kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                         lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let folder = BrowserFolder(id: UUID(), spaceID: here.id, name: "Pinned folder")
        let pinned = tab("Pinned", here, kind: .pinned), filed = tab("Filed", here, kind: .pinned, folder: folder.id)
        let first = tab("First", here), left = tab("Left", here), right = tab("Right", here), last = tab("Last", here)
        let elsewhere = tab("Elsewhere", there), elsewhereToo = tab("Elsewhere too", there)
        var earlier = tab("Earlier archive", here); earlier.archivedAt = Date(timeIntervalSince1970: 1_000)
        let split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Pair", spaceID: here.id,
            tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        var seed = BrowserState(profiles: [profile], spaces: [here, there], activeSpaceID: here.id)
        seed.folders = [folder]
        seed.tabs = [pinned, filed, first, left, right, last, elsewhere, elsewhereToo, earlier]
        seed.splitLayouts = [split]
        let today = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
        let thereToday = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .today)
        let pinnedList = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
        seed.sidebarItemOrder[today.key] = [.tab(last.id), .tab(left.id), .tab(first.id)]
        seed.sidebarItemOrder[pinnedList.key] = [.folder(folder.id), .tab(pinned.id)]
        seed.sidebarItemOrder[thereToday.key] = [.tab(elsewhereToo.id), .tab(elsewhere.id)]
        seed.selectedTabIDs = [first.id]; seed.selectionBySpace[here.id.uuidString] = [first.id]
        let sessionURL = root.appendingPathComponent("session.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(seed).write(to: sessionURL)
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let initial = store.state
        let hereIDs: Set = [first.id, left.id, right.id, last.id]
        try check(SidebarHierarchy.children(in: today, state: initial) == [.tab(last.id), .split(split.id), .tab(first.id)],
                  "Fixture Today list holds a split between two tabs")

        var authorize: (() -> Bool)?, finish: ((Bool) -> Void)?, autoApprove = false
        store.requestPageRetirement = { _, canCommit, done in
            if autoApprove { done(canCommit()) } else { authorize = canCommit; finish = done }
        }
        func approve() { _ = authorize?(); finish?(true) }
        func todayIDs(_ space: BrowserSpace) -> Set<UUID> {
            Set(store.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == space.id && $0.profileID == profile.id }.map(\.id))
        }
        // The window's Clear: SpaceClearToday's targets, the shared close with
        // the clear-button reason, and the record built from the committed close.
        var record: ClosedTabsUndo?, committed: Bool?
        func clear(_ space: BrowserSpace) {
            record = nil; committed = nil
            let ids = todayIDs(space)
            let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: store.state.activeSpaceID,
                profileID: profile.id, state: store.state, selected: store.state.selectedTabIDs,
                focused: store.state.selectedTabIDs.last, available: { _ in true })
            store.closeTabs(ids, reason: .clearButton, selection: selection, didCommit: { before in
                record = ClosedTabsUndo(prompt: .clear, ids: ids, spaceID: space.id, profileID: profile.id, focusedTabID: nil,
                                        before: before, after: store.state)
            }, shouldCommit: { true }) { committed = $0 }
        }

        clear(here)
        try check(committed == nil && record == nil && store.state == initial, "Clear waits for page consent without mutation")
        finish?(false)
        try check(committed == false && record == nil && store.state == initial, "Refused consent clears nothing and records no Undo")
        clear(here)
        try check(authorize?() == true, "Original pages admit the Clear"); finish?(true)
        let cleared = store.state, clearRecord = record!
        try check(committed == true && cleared.tabs.filter { hereIDs.contains($0.id) }.allSatisfy {
            $0.archivedAt != nil && $0.archiveProvenance?.reason == .clearButton
        }, "Clear archives every Today tab with the clear-button reason")
        let leftProvenance = cleared.tabs.first { $0.id == left.id }?.archiveProvenance
        try check(leftProvenance?.groupID != nil && leftProvenance?.groupID == cleared.tabs.first { $0.id == right.id }?.archiveProvenance?.groupID
                  && leftProvenance?.split == split && cleared.splitLayouts.isEmpty, "The split archives as one item and leaves the sidebar")
        let pinnedNow = cleared.tabs.first { $0.id == pinned.id }!
        var stamped = pinned; stamped.lastAccessed = pinnedNow.lastAccessed; stamped.isUnread = pinnedNow.isUnread
        try check(cleared.selectedTabIDs == [pinned.id] && pinnedNow == stamped, "Clear selects the next item, here the pinned tab, as any close does")
        try check([filed, elsewhere, elsewhereToo, earlier].allSatisfy { cleared.tabs.contains($0) } && cleared.folders == [folder]
                  && cleared.sidebarItemOrder[pinnedList.key] == initial.sidebarItemOrder[pinnedList.key],
                  "Pinned items, folders, the other Space and the earlier archive are untouched")
        try check(SidebarHierarchy.children(in: today, state: cleared).isEmpty, "Today list is empty")
        try check(clearRecord.actionName == "Clear Tabs" && clearRecord.tabs.count == 4 && clearRecord.groups == [split]
                  && clearRecord.order == SidebarHierarchy.children(in: today, state: initial), "The record holds originals, the split and the Today order")
        try check(ClosedTabsUndo(prompt: .clear, ids: [first.id], spaceID: here.id, profileID: profile.id, focusedTabID: nil,
                                 before: initial, after: initial) == nil, "A close that took nothing out of the sidebar has no Undo")
        var lone = initial; lone.tabs.removeAll { $0.id == right.id || $0.id == left.id || $0.id == last.id }; lone.splitLayouts = []
        var loneCleared = lone; loneCleared.tabs[loneCleared.tabs.firstIndex { $0.id == first.id }!].archivedAt = Date()
        try check(ClosedTabsUndo(prompt: .clear, ids: [first.id], spaceID: here.id, profileID: profile.id, focusedTabID: nil,
                                 before: lone, after: loneCleared)?.actionName == "Clear Tab",
                  "One tab names Clear Tab")

        let content = PArcToastContent.clearedTabs
        try check(content.body == .shortcut(leading: "Cleared Tabs! Use", shortcut: "⌘Z", trailing: "to undo.")
                  && content.accessibilityText == "Cleared Tabs! Use ⌘Z to undo." && content.showsShortcut,
                  "Toast reads Cleared Tabs! Use ⌘Z to undo.")

        var usable = true, undone = 0, errors: [Error] = [], redoCurrent: (() -> Bool)?
        // Tabs the window can neither use nor move here (closing, or mid-move): its canUse refuses them.
        var refused = Set<UUID>(), lastOperation: ClosedTabsUndoOperation?
        // The window's Redo close: the ordinary close whose commit rechecks `current`.
        func register(_ record: ClosedTabsUndo, in manager: FolderUndoManager, on other: BrowserStore? = nil) -> Bool {
            let owner = other ?? store
            lastOperation = nil
            manager.appendClosedTabs(record, store: owner, canUse: { ids, _ in usable && ids.isDisjoint(with: refused) },
                                     close: { ids, current, done in
                redoCurrent = current
                var next: ClosedTabsUndo?
                owner.closeTabs(ids, reason: .manual, didCommit: { before in
                    next = ClosedTabsUndo(prompt: record.prompt, ids: ids, spaceID: record.spaceID, profileID: record.profileID,
                                          focusedTabID: nil, before: before, after: owner.state)
                }, shouldCommit: current) { done($0 ? next : nil) }
            }, didUndo: { _ in undone += 1 }, onError: { errors.append($0) }) { lastOperation = $0 }
            return lastOperation != nil
        }
        var closedItems = WindowClosedItems()
        // Reopen's record of the same close, as the window's close path keeps it.
        let reopenIntent = ClosedItemIntent(ids: hereIDs, state: initial, spaceID: here.id, profileID: profile.id, focusedTabID: first.id)!
        closedItems.record(reopenIntent, in: cleared)
        try check(closedItems.nextStep(in: store.state, restorable: { _ in false }) != nil, "Clear also leaves Reopen Closed Tab steps")

        let window = FolderUndoManager()
        try check(register(clearRecord, in: window), "A committed Clear registers on the window's Undo (toast follows)")
        try check(window.canUndo && window.undoMenuItemTitle == "Undo Clear Tabs", "Edit menu reads Undo Clear Tabs")
        // ⌘Z from another Space of the same window.
        _ = store.setWindowPresentation(spaceID: there.id, selectedTabIDs: [elsewhere.id])
        let beforeUndo = store.state
        usable = false
        try check(!window.canUndo, "A busy window owner disables Undo without discarding it")
        usable = true
        window.undo()
        let restored = store.state
        try check(undone == 1 && !window.isBusy && errors.isEmpty, "Undo commits")
        try check(initial.tabs.filter { hereIDs.contains($0.id) }.allSatisfy { restored.tabs.contains($0) },
                  "Undo restores the exact pre-Clear records, archive entries included")
        try check(restored.splitLayouts == [split], "The split regroups with its ID, title, orientation and widths")
        try check(SidebarHierarchy.children(in: today, state: restored) == SidebarHierarchy.children(in: today, state: initial),
                  "Undo restores the original Today order")
        try check(restored.activeSpaceID == there.id && restored.selectedTabIDs == beforeUndo.selectedTabIDs
                  && restored.selectionBySpace == beforeUndo.selectionBySpace, "Undo restores into the cleared Space without selecting")
        try check(restored.recentlyClosedIDs.allSatisfy { !hereIDs.contains($0) } && restored.tabs.contains(earlier)
                  && restored.tabs.filter { !hereIDs.contains($0.id) } == beforeUndo.tabs.filter { !hereIDs.contains($0.id) }
                  && restored.folders == beforeUndo.folders, "Undo touches only the cleared tabs")
        let reloaded = try BrowserStore(directory: root)
        try check(reloaded.state.tabs == restored.tabs && reloaded.state.splitLayouts == restored.splitLayouts
                  && reloaded.state.sidebarItemOrder == restored.sidebarItemOrder, "Undo is on disk before it publishes")
        try check(closedItems.nextStep(in: store.state, restorable: { _ in false }) == nil, "Undo expires the Clear's Reopen steps")
        try check(window.canRedo && !window.canUndo && window.redoMenuItemTitle == "Redo Clear Tabs", "Redo Clear Tabs follows")

        window.redo()
        try check(window.isBusy && store.state == restored, "Redo waits for fresh page consent")
        finish?(false)
        try check(!window.isBusy && window.canRedo && store.state == restored, "Refused Redo keeps the tabs and the Redo")
        try check(redoCurrent?() == true, "Redo's commit check passes while its tabs are unchanged")
        window.redo(); approve()
        let redone = store.state
        try check(hereIDs.allSatisfy { id in redone.tabs.first { $0.id == id }?.archiveProvenance?.reason == .manual },
                  "Redo archives again as a manual close")
        try check(redone.splitLayouts.isEmpty && redone.activeSpaceID == there.id && redone.selectedTabIDs == restored.selectedTabIDs,
                  "Redo leaves another Space's selection alone")
        try check(window.canUndo && !window.canRedo && window.undoMenuItemTitle == "Undo Clear Tabs", "Redo returns the group to Undo")
        window.undo()
        try check(initial.tabs.filter { hereIDs.contains($0.id) }.allSatisfy { store.state.tabs.contains($0) } && store.state.splitLayouts == [split]
                  && SidebarHierarchy.children(in: today, state: store.state) == SidebarHierarchy.children(in: today, state: initial),
                  "Undo after Redo restores the redone close")
        // Redo covers only tabs that are live Today tabs again.
        try check(clearRecord.redoIDs(in: store.state) == hereIDs, "Every restored tab is a Redo target")
        _ = store.setWindowPresentation(spaceID: here.id, selectedTabIDs: [first.id])

        // Two Spaces cleared in one window undo last first.
        autoApprove = true
        clear(here); let hereRecord = record!
        _ = store.setWindowPresentation(spaceID: there.id, selectedTabIDs: [elsewhere.id])
        clear(there); let thereRecord = record!
        let stack = FolderUndoManager()
        try check(register(hereRecord, in: stack) && register(thereRecord, in: stack), "Each Clear registers its own group")
        stack.undo()
        try check(todayIDs(there) == [elsewhere.id, elsewhereToo.id] && todayIDs(here).isEmpty, "The later Clear undoes first")
        try check(SidebarHierarchy.children(in: thereToday, state: store.state) == SidebarHierarchy.children(in: thereToday, state: initial),
                  "Its Space's order returns")
        stack.undo()
        try check(todayIDs(here) == hereIDs && store.state.splitLayouts == [split], "Then the earlier Clear")

        // Two windows keep separate stacks over the shared store.
        clear(here); let windowA = record!
        clear(there); let windowB = record!
        let firstWindow = FolderUndoManager(), secondWindow = FolderUndoManager()
        try check(register(windowA, in: firstWindow) && register(windowB, in: secondWindow), "Each window registers its own Clear")
        firstWindow.undo()
        try check(todayIDs(here) == hereIDs && todayIDs(there).isEmpty && secondWindow.canUndo && !firstWindow.canUndo,
                  "Undo in one window leaves the other window's Clear")
        secondWindow.undo()
        try check(todayIDs(there) == [elsewhere.id, elsewhereToo.id], "The other window undoes its own")

        // Reopen and Archive changes made after the Clear: Undo returns the rest.
        let reopenIntent2 = ClosedItemIntent(ids: hereIDs, state: store.state, spaceID: here.id, profileID: profile.id, focusedTabID: nil)!
        clear(here); let partial = record!
        var reopen = WindowClosedItems()
        reopen.record(reopenIntent2, in: store.state)
        guard case .items(let step)? = reopen.nextStep(in: store.state, restorable: { _ in false }) else { throw NSError(domain: "Expected Reopen step", code: 1) }
        try check(try store.restoreClosedItem(step), "Reopen Closed Tab takes one step of the Clear")
        let reopened = Set(step.tabIDs)
        let deleted = [first.id, last.id].first { !reopened.contains($0) }!
        store.deleteArchivedTabs([deleted])
        try check(!store.state.tabs.contains { $0.id == deleted }, "One cleared tab is deleted from the Archive")
        let partialWindow = FolderUndoManager()
        try check(register(partial, in: partialWindow) && partialWindow.canUndo, "The rest stays undoable")
        lastOperation?.didReopen(step)
        let reopenedRecords = store.state.tabs.filter { reopened.contains($0.id) }
        partialWindow.undo()
        let remaining = hereIDs.subtracting(reopened).subtracting([deleted])
        try check(remaining.allSatisfy { id in store.state.tabs.contains(initial.tabs.first { $0.id == id }!) },
                  "Undo restores the tabs still archived as cleared")
        try check(reopenedRecords.allSatisfy { store.state.tabs.contains($0) } && !store.state.tabs.contains { $0.id == deleted },
                  "A reopened tab stays as reopened and a deleted one stays deleted")
        let order = SidebarHierarchy.children(in: today, state: store.state)
        try check(Set(order).count == order.count && order.flatMap { SidebarHierarchy.tabIDs(in: $0, state: store.state, spaceID: here.id) }.count
                  == todayIDs(here).count, "Each live Today tab appears once")
        try check(partialWindow.redoMenuItemTitle == "Redo " + ClosedTabsUndo.Prompt.clear.name(count: partial.itemCount(of: hereIDs.subtracting(reopened))),
                  "Redo is named by the group's remaining items")
        partialWindow.redo()
        try check(reopened.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }
                  && remaining.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } },
                  "Redo archives only what Undo restored; the reopened tab stays live")
        try check(partialWindow.undoMenuItemTitle == "Undo " + ClosedTabsUndo.Prompt.clear.name(
                      count: remaining.count + (remaining.isSuperset(of: [left.id, right.id]) ? 1 : 0)),
                  "The redone close is named by its own items")
        partialWindow.undo()
        try check(remaining.isSubset(of: todayIDs(here)), "Undo after that Redo restores the same tabs")

        //
        let livePut = todayIDs(here)
        clear(here); let putBack = record!
        let putWindow = FolderUndoManager()
        try check(register(putBack, in: putWindow), "Registers")
        let returned = [first.id, last.id].first { livePut.contains($0) }!
        try check(!store.restoreArchivedTab(returned, destination: .putBack(currentSpaceID: here.id, requestedSpaceID: here.id)).isEmpty
                  && store.state.tabs.contains { $0.id == returned && $0.archivedAt == nil }, "Put Back returns one cleared tab")
        putWindow.undo()
        try check(todayIDs(here) == livePut, "Undo restores the rest")
        putWindow.redo()
        try check(livePut.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } },
                  "Redo archives the put-back tab again")
        putWindow.undo()
        try check(todayIDs(here) == livePut, "Undo restores them all")

        // An archived tab edited since (a Note renamed in the Library) is still this Clear's and keeps its edits.
        var edited = cleared
        if let index = edited.tabs.firstIndex(where: { $0.id == first.id }) {
            edited.tabs[index].title = "Edited in the Library"; edited.tabs[index].url = "https://edited.invalid/"
        }
        let editedBack = clearRecord.restoring(edited)!.tabs.first { $0.id == first.id }!
        try check(clearRecord.restorableIDs(in: edited).contains(first.id) && editedBack.title == "Edited in the Library"
                  && editedBack.url == "https://edited.invalid/" && editedBack.archivedAt == nil && editedBack.archiveProvenance == nil
                  && editedBack.kind == .today, "An archived tab edited since comes back with its edits")
        var rearchived = cleared
        if let index = rearchived.tabs.firstIndex(where: { $0.id == first.id }) { rearchived.tabs[index].archivedAt = Date(timeIntervalSince1970: 2_000_000_000) }
        try check(!clearRecord.restorableIDs(in: rearchived).contains(first.id), "A tab archived again since is not this Clear's")

        // Pure restoration: a split pane deleted since returns its partner alone in the split's slot.
        var halfGone = cleared
        halfGone.tabs.removeAll { $0.id == right.id }
        let alone = clearRecord.restoring(halfGone)!
        try check(alone.splitLayouts.isEmpty && SidebarHierarchy.children(in: today, state: alone) == [.tab(last.id), .tab(left.id), .tab(first.id)],
                  "A split that cannot regroup returns its remaining pane alone in place")
        var joined = cleared
        let later = tab("Later", here)
        joined.tabs.append(later)
        joined.sidebarItemOrder[today.key] = [.tab(later.id)]
        let survivor = clearRecord.restoring(joined)!
        try check(SidebarHierarchy.children(in: today, state: survivor) == [.tab(last.id), .split(split.id), .tab(first.id), .tab(later.id)],
                  "Restored items take their places around a tab opened since")
        var moved = store.state
        if let index = moved.tabs.firstIndex(where: { $0.id == remaining.first }) { moved.tabs[index].kind = .pinned }
        try check(!partial.redoIDs(in: moved).contains(remaining.first ?? UUID()), "Redo never archives a tab pinned since")

        // Failure and invalidation.
        autoApprove = true
        let live = todayIDs(here)
        // Identical bytes skip the write, so leave this Undo's result unwritten.
        _ = store.setWindowPresentation(spaceID: there.id, selectedTabIDs: [])
        clear(here); let failing = record!
        let failingWindow = FolderUndoManager()
        try check(register(failing, in: failingWindow), "Registers")
        let bytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        let archivedBefore = store.state
        failingWindow.undo()
        try check(errors.count == 1 && store.state == archivedBefore && failingWindow.canUndo, "A failed write keeps the Clear archived and Undo retryable")
        try FileManager.default.removeItem(at: sessionURL); try bytes.write(to: sessionURL)
        failingWindow.undo()
        try check(todayIDs(here) == live && failingWindow.canRedo, "Retry restores")
        store.closeTabs(live, reason: .manual, shouldCommit: { true })
        try check(!failingWindow.canRedo && !failingWindow.canUndo, "Archiving the restored tabs by hand retires the Redo")
        clear(there); let busyRecord = record!
        let busy = FolderUndoManager()
        try check(register(busyRecord, in: busy), "Registers")
        autoApprove = false
        busy.undo()
        _ = store.setWindowPresentation(spaceID: there.id, selectedTabIDs: [])
        busy.redo()
        try check(busy.isBusy && busy.isRedoing, "Redo waits for page consent")
        approve()
        try check(!busy.isBusy && busy.canUndo, "The Redo finishes")

        // A second store: a three-pane split that is the window's selected split.
        let sideRoot = root.appendingPathComponent("side")
        try FileManager.default.createDirectory(at: sideRoot, withIntermediateDirectories: true)
        let side = BrowserSpace(id: UUID(), name: "Side", symbol: "circle", color: "FEDCBA", profileID: profile.id)
        let sidePinned = tab("Side pinned", side, kind: .pinned)
        let a = tab("A", side), b = tab("B", side), c = tab("C", side), d = tab("D", side), e = tab("E", side)
        let trio = BrowserSplitLayout(sidebarAnchorID: a.id, customTitle: "Trio", spaceID: side.id,
            tabIDs: [a.id, b.id, c.id], orientation: .horizontal, widthFactors: [0.2, 0.3, 0.5])
        var sideSeed = BrowserState(profiles: [profile], spaces: [side], activeSpaceID: side.id)
        sideSeed.tabs = [sidePinned, a, b, c, d, e]; sideSeed.splitLayouts = [trio]
        let sideToday = SidebarContainerLocation(spaceID: side.id, folderID: nil, section: .today)
        sideSeed.sidebarItemOrder[sideToday.key] = [.tab(e.id), .tab(a.id), .tab(d.id)]
        sideSeed.selectedTabIDs = trio.tabIDs; sideSeed.selectionBySpace[side.id.uuidString] = trio.tabIDs
        try encoder.encode(sideSeed).write(to: sideRoot.appendingPathComponent("session.json"))
        let sideStore = try BrowserStore(directory: sideRoot, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        sideStore.requestPageRetirement = store.requestPageRetirement
        let sideInitial = sideStore.state
        let sideOrder = SidebarHierarchy.children(in: sideToday, state: sideInitial)
        try check(sideOrder == [.tab(e.id), .split(trio.id), .tab(d.id)] && sideInitial.selectedTabIDs == trio.tabIDs,
                  "The trio is the selected split")
        func clearSide(_ ids: Set<UUID>) -> ClosedTabsUndo? {
            var made: ClosedTabsUndo?
            let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: sideStore.state.activeSpaceID,
                profileID: profile.id, state: sideStore.state, selected: sideStore.state.selectedTabIDs,
                focused: sideStore.state.selectedTabIDs.last, available: { _ in true })
            sideStore.closeTabs(ids, reason: .clearButton, selection: selection, didCommit: { before in
                made = ClosedTabsUndo(prompt: .clear, ids: ids, spaceID: side.id, profileID: profile.id, focusedTabID: nil,
                                      before: before, after: sideStore.state)
            }, shouldCommit: { true })
            return made
        }
        autoApprove = true
        let whole = clearSide([a.id, b.id, c.id, d.id, e.id])!
        let replacement = sideStore.state.selectedTabIDs
        try check(replacement == [sidePinned.id] && sideStore.state.splitLayouts.isEmpty, "Clearing the selected split selects the pinned tab")
        let sideWindow = FolderUndoManager()
        try check(register(whole, in: sideWindow, on: sideStore), "Registers")
        sideWindow.undo()
        try check(sideStore.state.activeSpaceID == side.id && sideStore.state.selectedTabIDs == replacement,
                  "Undo with the cleared Space active keeps the replacement selected")
        try check(sideStore.state.splitLayouts == sideInitial.splitLayouts && SidebarHierarchy.children(in: sideToday, state: sideStore.state) == sideOrder,
                  "The selected split returns whole, in place")

        // A Clear that leaves panes this window can use or move here, as after a
        // Library card Clear whose other panes another window shows: the pane rejoins.
        let one = clearSide([a.id])!
        try check(one.actionName == "Clear Tab", "One pane from a split that survives is one item")
        try check(sideStore.state.splitLayouts.first { $0.id == trio.id }?.tabIDs == [b.id, c.id] && one.memberships[a.id]?.dissolved == false,
                  "Clearing one pane leaves the split's other two")
        let paneWindow = FolderUndoManager()
        try check(register(one, in: paneWindow, on: sideStore), "Registers")
        paneWindow.undo()
        let rejoinedTrio = sideStore.state.splitLayouts.first { $0.id == trio.id }
        try check(rejoinedTrio?.tabIDs == trio.tabIDs && rejoinedTrio?.sidebarAnchorID == trio.sidebarAnchorID
                  && zip(rejoinedTrio?.widthFactors ?? [], trio.widthFactors).allSatisfy { abs($0 - $1) < 1e-9 }
                  && SidebarHierarchy.children(in: sideToday, state: sideStore.state) == sideOrder,
                  "Undo of a Library card Clear whose split's other panes another window shows puts the pane back into that split at its place, share and sidebar slot")
        let beforePair = sideStore.state.splitLayouts.first { $0.id == trio.id }
        let pair = clearSide([a.id, b.id])!
        try check(!sideStore.state.splitLayouts.contains { $0.id == trio.id } && pair.memberships[a.id]?.dissolved == true,
                  "Clearing two panes dissolves the split")
        try check(pair.actionName == "Clear Tabs" && whole.actionName == "Clear Tabs", "Splits name Clear Tabs")
        let pairWindow = FolderUndoManager()
        try check(register(pair, in: pairWindow, on: sideStore), "Registers")
        pairWindow.undo()
        let regroupedTrio = sideStore.state.splitLayouts.first { $0.id == trio.id }
        try check(regroupedTrio != nil && regroupedTrio == beforePair
                  && SidebarHierarchy.children(in: sideToday, state: sideStore.state) == sideOrder, "Undo regroups the split the Clear dissolved")

        // Redo's commit rechecks its tabs, as the Clear's own close does.
        let loose = clearSide([d.id, e.id])!
        let looseWindow = FolderUndoManager()
        try check(register(loose, in: looseWindow, on: sideStore), "Registers")
        looseWindow.undo()
        autoApprove = false
        looseWindow.redo(); finish?(false)
        try check(looseWindow.canRedo && redoCurrent?() == true, "A refused Redo keeps its tabs and check")
        sideStore.setKind(d.id, .pinned)
        try check(redoCurrent?() == false, "Redo's commit check fails once one of its tabs is pinned")
        autoApprove = true
        looseWindow.redo()
        try check(sideStore.state.tabs.first { $0.id == d.id }.map { $0.kind == .pinned && $0.archivedAt == nil } == true
                  && sideStore.state.tabs.first { $0.id == e.id }?.archivedAt != nil, "Redo then archives only the tab still in Today")

        // Panes that can't come here right now (closing, or mid-move between
        // windows): Undo leaves them as they are.
        refused = [b.id, c.id]
        let foreignPanes = clearSide([a.id])!
        let foreignWindow = FolderUndoManager()
        try check(register(foreignPanes, in: foreignWindow, on: sideStore), "Registers")
        foreignWindow.undo()
        try check(sideStore.state.splitLayouts.first { $0.id == trio.id }?.tabIDs == [b.id, c.id]
                  && SidebarHierarchy.children(in: sideToday, state: sideStore.state) == [.split(trio.id), .tab(a.id)],
                  "With the other panes busy elsewhere, the pane comes back alone beside the split")
        refused = [c.id]
        let lastPair = clearSide([b.id])!
        try check(lastPair.actionName == "Clear Tabs", "A pane that dissolves its split names the split too counts")
        let lastPairWindow = FolderUndoManager()
        try check(register(lastPair, in: lastPairWindow, on: sideStore), "Registers")
        lastPairWindow.undo()
        try check(!sideStore.state.splitLayouts.contains { $0.id == trio.id }
                  && [b.id, c.id].allSatisfy { id in sideStore.state.tabs.contains { $0.id == id && $0.archivedAt == nil } },
                  "Nor does Undo regroup a split whose last other pane is busy elsewhere")
        refused = []

        // Every other close: Command-W, a pane's close, a row's Archive Tab.
        let archRoot = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archRoot, withIntermediateDirectories: true)
        let work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "FFEEDD", profileID: profile.id)
        let shelf = BrowserFolder(id: UUID(), spaceID: work.id, name: "Shelf")
        let docID = UUID()
        var note = tab("Note", work, kind: .pinned, folder: shelf.id)
        note.url = "parc://note/" + docID.uuidString.lowercased(); note.savedURL = note.url
        let shelved = tab("Shelved", work, kind: .pinned, folder: shelf.id), keep = tab("Keep", work, kind: .pinned)
        let t1 = tab("T1", work), t2 = tab("T2", work), t3 = tab("T3", work), s1 = tab("S1", work), s2 = tab("S2", work)
        let duo = BrowserSplitLayout(sidebarAnchorID: s1.id, customTitle: "Duo", spaceID: work.id,
            tabIDs: [s1.id, s2.id], orientation: .horizontal, widthFactors: [0.4, 0.6])
        var archSeed = BrowserState(profiles: [profile], spaces: [work], activeSpaceID: work.id)
        archSeed.folders = [shelf]
        archSeed.tabs = [note, shelved, keep, t1, t2, t3, s1, s2]; archSeed.splitLayouts = [duo]
        let workToday = SidebarContainerLocation(spaceID: work.id, folderID: nil, section: .today)
        let workPinned = SidebarContainerLocation(spaceID: work.id, folderID: nil, section: .pinned)
        let shelfBox = SidebarContainerLocation(spaceID: work.id, folderID: shelf.id, section: .pinned)
        archSeed.sidebarItemOrder[workToday.key] = [.tab(t1.id), .tab(s1.id), .tab(t2.id), .tab(t3.id)]
        archSeed.sidebarItemOrder[workPinned.key] = [.folder(shelf.id), .tab(keep.id)]
        archSeed.sidebarItemOrder[shelfBox.key] = [.tab(note.id), .tab(shelved.id)]
        archSeed.selectedTabIDs = [t2.id]; archSeed.selectionBySpace[work.id.uuidString] = [t2.id]
        try encoder.encode(archSeed).write(to: archRoot.appendingPathComponent("session.json"))
        let arch = try BrowserStore(directory: archRoot, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        arch.requestPageRetirement = store.requestPageRetirement
        let archInitial = arch.state
        @MainActor func workOrder() -> [SidebarItemReference] { SidebarHierarchy.children(in: workToday, state: arch.state) }
        let workOriginal = workOrder()
        try check(workOriginal == [.tab(t1.id), .split(duo.id), .tab(t2.id), .tab(t3.id)], "Fixture: a split between Today tabs")
        // The window's close path: its focused tab, the shared close and the record of what it committed.
        func close(_ ids: Set<UUID>, focused: UUID?, prompt: ClosedTabsUndo.Prompt = .archive) -> ClosedTabsUndo? {
            var made: ClosedTabsUndo?
            let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: arch.state.activeSpaceID,
                profileID: profile.id, state: arch.state, selected: arch.state.selectedTabIDs,
                focused: arch.state.selectedTabIDs.last, available: { _ in true })
            arch.closeTabs(ids, reason: prompt == .clear ? .clearButton : .manual, selection: selection, didCommit: { before in
                made = ClosedTabsUndo(prompt: prompt, ids: ids, spaceID: work.id, profileID: profile.id,
                                      focusedTabID: focused, before: before, after: arch.state)
            }, shouldCommit: { true })
            return made
        }
        autoApprove = true
        let focusedClose = close([t2.id], focused: t2.id)!
        try check(focusedClose.prompt == .archive && focusedClose.actionName == "Archive Tab" && focusedClose.focusedTabID == t2.id,
                  "Command-W on the focused tab is one Archive Tab group that remembers its focus")
        try check(arch.state.tabs.first { $0.id == t2.id }?.archiveProvenance?.reason == .manual, "It archives as a manual close")
        let archWindow = FolderUndoManager()
        try check(register(focusedClose, in: archWindow, on: arch) && archWindow.undoMenuItemTitle == "Undo Archive Tab",
                  "Edit menu reads Undo Archive Tab")
        var presented = WindowPresentation(state: arch.state, ready: true)
        let selectedAfterClose = arch.state.selectedTabIDs
        archWindow.undo()
        try check(workOrder() == workOriginal && arch.state.tabs.contains(t2), "Undo returns the tab to its place")
        try check(arch.state.selectedTabIDs == selectedAfterClose, "The store leaves selection to the window")
        try check(presented.finishClosedTabsUndo(focusedClose, state: arch.state, available: { _ in true })
                  && presented.selectedTabIDs == [t2.id], "The window selects the tab that was focused when it closed")
        try check(archWindow.redoMenuItemTitle == "Redo Archive Tab", "Redo Archive Tab follows")
        archWindow.redo()
        try check(arch.state.tabs.first { $0.id == t2.id }?.archivedAt != nil && archWindow.undoMenuItemTitle == "Undo Archive Tab",
                  "Redo archives it again and returns the group to Undo")
        archWindow.undo()
        _ = arch.setWindowPresentation(spaceID: work.id, selectedTabIDs: [t1.id])

        let background = close([t3.id], focused: t1.id)!
        var unfocused = WindowPresentation(state: arch.state, ready: true)
        try check(background.focusedTabID == nil, "A tab that wasn't focused records no focus")
        let backgroundWindow = FolderUndoManager()
        try check(register(background, in: backgroundWindow, on: arch), "Registers")
        backgroundWindow.undo()
        try check(workOrder() == workOriginal && !unfocused.finishClosedTabsUndo(background, state: arch.state, available: { _ in true })
                  && unfocused.selectedTabIDs == [t1.id], "Its Undo selects nothing")

        try check(close([keep.id], focused: keep.id) == nil && arch.state.tabs.contains { $0.id == keep.id && $0.archivedAt == nil },
                  "Closing a pinned tab only unloads it, so it registers no Undo deselect")

        let paneClose = close([s1.id], focused: nil)!
        try check(paneClose.actionName == "Archive Tabs" && !arch.state.splitLayouts.contains { $0.id == duo.id }
                  && workOrder() == [.tab(t1.id), .tab(s2.id), .tab(t2.id), .tab(t3.id)],
                  "A pane whose close dissolves its split names the split too; the other pane keeps the slot")
        let paneWindow2 = FolderUndoManager()
        try check(register(paneClose, in: paneWindow2, on: arch), "Registers")
        paneWindow2.undo()
        try check(arch.state.splitLayouts == [duo] && workOrder() == workOriginal, "Undo regroups the split in its slot")

        try check(close([note.id], focused: note.id) == nil && arch.state.tabs.contains { $0.id == note.id && $0.archivedAt == nil && $0.kind == .pinned }
                  && SidebarHierarchy.children(in: shelfBox, state: arch.state) == [.tab(note.id), .tab(shelved.id)],
                  "A pinned Note only unloads in its folder, so it registers no Undo either")

        // Clear, then Command-W: Command-Z undoes the later close first.
        let mixed = FolderUndoManager()
        let cleanAll = close([t1.id, t3.id, s1.id, s2.id, t2.id], focused: nil, prompt: .clear)!
        try check(register(cleanAll, in: mixed, on: arch), "Clear registers")
        mixed.undo()
        _ = arch.setWindowPresentation(spaceID: work.id, selectedTabIDs: [t2.id])
        let clearedAgain = close([t1.id, t3.id, s1.id, s2.id], focused: nil, prompt: .clear)!
        let lastClose = close([t2.id], focused: t2.id)!
        let ordered = FolderUndoManager()
        try check(register(clearedAgain, in: ordered, on: arch) && register(lastClose, in: ordered, on: arch)
                  && ordered.undoMenuItemTitle == "Undo Archive Tab", "The later close is on top")
        ordered.undo()
        try check(arch.state.tabs.contains { $0.id == t2.id && $0.archivedAt == nil } && arch.state.tabs.first { $0.id == t1.id }?.archivedAt != nil
                  && ordered.undoMenuItemTitle == "Undo Clear Tabs", "Undo restores the later close, then offers the Clear")
        ordered.undo()
        try check(workOrder() == workOriginal, "Then the Clear")

        // A close that commits while a Redo still waits joins when that Redo finishes.
        let deferred = FolderUndoManager()
        let first1 = close([t1.id], focused: nil)!
        try check(register(first1, in: deferred, on: arch), "Registers")
        deferred.undo()
        autoApprove = false
        deferred.redo()
        try check(deferred.isRedoing, "Redo waits for page consent")
        autoApprove = true
        let meanwhile = close([t3.id], focused: nil)!
        try check(!register(meanwhile, in: deferred, on: arch) && lastOperation == nil, "The new group waits for the Redo, with no toast yet")
        let waitingOperation = { lastOperation }
        approve()
        try check(waitingOperation() != nil && !deferred.isBusy, "It joins once the Redo finishes, and its toast could show")
        deferred.undo()
        try check(arch.state.tabs.contains { $0.id == t1.id && $0.archivedAt == nil } && arch.state.tabs.first { $0.id == t3.id }?.archivedAt != nil,
                  "The redone close completed last, so it is on top")
        deferred.undo()
        try check(workOrder() == workOriginal, "Then the close that committed during the Redo")
        let refusedRedo = FolderUndoManager()
        let second1 = close([t1.id], focused: nil)!
        try check(register(second1, in: refusedRedo, on: arch), "Registers")
        refusedRedo.undo()
        autoApprove = false
        refusedRedo.redo()
        autoApprove = true
        let meanwhile2 = close([t3.id], focused: nil)!
        _ = register(meanwhile2, in: refusedRedo, on: arch)
        finish?(false)
        try check(!refusedRedo.isBusy && !refusedRedo.canRedo && refusedRedo.canUndo,
                  "A refused Redo lets the waiting group in, which clears the Redo")
        refusedRedo.undo()
        try check(workOrder() == workOriginal, "Undo restores it")

        // A private window's close removes its tabs; Undo puts the records back.
        let privateStore = BrowserStore(privateParentProfileID: profile.id, engineProfilePath: root.appendingPathComponent("otr").path,
                                        directory: root, settings: store.state.settings)
        privateStore.requestPageRetirement = store.requestPageRetirement
        let p3 = privateStore.openResolvedURL(URL(string: "https://three.invalid/")!)
        let p2 = privateStore.openResolvedURL(URL(string: "https://two.invalid/")!)
        let p1 = privateStore.openResolvedURL(URL(string: "https://one.invalid/")!)
        let privateSpace = privateStore.activeSpaceID, privateProfile = privateStore.activeSpace.profileID
        let privateToday = SidebarContainerLocation(spaceID: privateSpace, folderID: nil, section: .today)
        let privateOrder = SidebarHierarchy.children(in: privateToday, state: privateStore.state)
        let privateRecords = privateStore.state.tabs
        try check(privateOrder == [.tab(p1), .tab(p2), .tab(p3)], "Fixture: three private tabs")
        var privateRecord: ClosedTabsUndo?
        privateStore.closeTabs([p2], didCommit: { before in
            privateRecord = ClosedTabsUndo(prompt: .archive, ids: [p2], spaceID: privateSpace, profileID: privateProfile,
                                           focusedTabID: nil, before: before, after: privateStore.state)
        }, shouldCommit: { true })
        try check(!privateStore.state.tabs.contains { $0.id == p2 } && privateRecord?.actionName == "Archive Tab"
                  && privateRecord?.archivedTabs.isEmpty == true, "The private close removes the tab and records it")
        let privateWindow = FolderUndoManager()
        try check(register(privateRecord!, in: privateWindow, on: privateStore) && privateWindow.undoMenuItemTitle == "Undo Archive Tab",
                  "A private window's close joins its Undo")
        privateWindow.undo()
        try check(privateStore.state.tabs.first { $0.id == p2 } == privateRecords.first { $0.id == p2 }
                  && SidebarHierarchy.children(in: privateToday, state: privateStore.state) == privateOrder,
                  "Undo puts the private tab back in its place")
        privateWindow.redo()
        try check(!privateStore.state.tabs.contains { $0.id == p2 } && privateWindow.canUndo, "Redo removes it again")
        privateWindow.undo()
        var privateClear: ClosedTabsUndo?
        privateStore.closeTabs([p1, p2, p3], reason: .clearButton, didCommit: { before in
            privateClear = ClosedTabsUndo(prompt: .clear, ids: [p1, p2, p3], spaceID: privateSpace, profileID: privateProfile,
                                          focusedTabID: nil, before: before, after: privateStore.state)
        }, shouldCommit: { true })
        try check(privateStore.state.tabs.isEmpty && privateClear?.actionName == "Clear Tabs", "A private Clear removes every tab")
        let privateClearWindow = FolderUndoManager()
        try check(register(privateClear!, in: privateClearWindow, on: privateStore), "and registers, so its toast shows")
        privateClearWindow.undo()
        try check(SidebarHierarchy.children(in: privateToday, state: privateStore.state) == privateOrder, "Undo returns them all")

        // Close Peek: Undo opens the Peek again over its parent; Redo closes exactly that Peek.
        let peekRecord = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/a")!, parentTabID: t1.id, profileID: profile.id)
        var opened: [ClosedPeekRecord] = [], openWorks = false, closeRequests: [UUID] = [], closeWorks = true
        var livePeeks = Set<UUID>()
        func appendPeek(to manager: FolderUndoManager, appended: @escaping (ClosedPeekUndoOperation) -> Void) {
            manager.appendClosedPeek(peekRecord, state: { arch.state }, canOpen: { _ in true }, open: { operation in
                opened.append(operation.record)
                guard openWorks else { return false }
                // The window's adoption of the Peek the engine offers.
                let adopted = UUID(); livePeeks.insert(adopted); operation.openedPeek = adopted
                return true
            }, isOpen: { operation in operation.openedPeek.map(livePeeks.contains) == true },
               canClose: { operation in operation.openedPeek.map(livePeeks.contains) == true }, close: { operation, done in
                closeRequests.append(operation.openedPeek!)
                guard closeWorks else { done(nil); return }
                livePeeks.remove(operation.openedPeek!)
                done(ClosedPeekRecord(id: UUID(), url: operation.record.url, parentTabID: operation.record.parentTabID,
                                      profileID: operation.record.profileID))
            }, appended: appended)
        }
        var peekOperation: ClosedPeekUndoOperation?
        let peekWindow = FolderUndoManager()
        appendPeek(to: peekWindow) { peekOperation = $0 }
        try check(peekOperation != nil && peekWindow.undoMenuItemTitle == "Undo Close Peek", "A closed Peek reads Undo Close Peek")
        peekWindow.undo()
        try check(opened == [peekRecord] && peekWindow.canUndo && !peekWindow.canRedo, "A Peek that can't open keeps its Undo")
        openWorks = true
        peekWindow.undo()
        let reopenedPeek = peekOperation?.openedPeek
        try check(opened.count == 2 && reopenedPeek != nil && peekWindow.redoMenuItemTitle == "Redo Close Peek",
                  "Undo opens it again and remembers that Peek; Redo Close Peek follows")
        let otherPeek = UUID(); livePeeks.insert(otherPeek)
        closeWorks = false
        peekWindow.redo()
        try check(closeRequests == [reopenedPeek!] && peekWindow.canRedo, "A refused close keeps the Redo")
        closeWorks = true
        peekWindow.redo()
        try check(closeRequests == [reopenedPeek!, reopenedPeek!] && livePeeks == [otherPeek] && peekWindow.canUndo
                  && peekOperation?.record.id != peekRecord.id && peekOperation?.openedPeek == nil,
                  "Redo closes the Peek Undo opened, not another over the same parent, and takes that close's record")
        peekOperation?.didReopen(peekOperation!.record)
        try check(!peekWindow.canUndo, "Once Reopen Closed Tab took the Peek's step, Undo has nothing left")
        let promoted = FolderUndoManager()
        var promotedOperation: ClosedPeekUndoOperation?
        appendPeek(to: promoted) { promotedOperation = $0 }
        promoted.undo()
        livePeeks.remove(promotedOperation!.openedPeek!)
        try check(!promoted.canRedo, "A reopened Peek that left some other way (expanded, say) leaves nothing to redo")
        let archivedParent = FolderUndoManager()
        appendPeek(to: archivedParent) { _ in }
        _ = close([t1.id], focused: nil)
        try check(!archivedParent.canUndo, "A Peek whose parent left the sidebar can't come back")
        // Clear takes the focused Today tab: Undo Clear Tabs reselects it.
        _ = arch.setWindowPresentation(spaceID: work.id, selectedTabIDs: [t2.id])
        let todayLive = Set(arch.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == work.id }.map(\.id))
        let focusedClear = close(todayLive, focused: t2.id, prompt: .clear)!
        try check(todayLive.contains(t2.id) && focusedClear.prompt == .clear && focusedClear.focusedTabID == t2.id,
                  "A Clear that takes the focused Today tab remembers it")
        let focusedClearWindow = FolderUndoManager()
        try check(register(focusedClear, in: focusedClearWindow, on: arch), "Registers")
        var afterClear = WindowPresentation(state: arch.state, ready: true)
        focusedClearWindow.undo()
        try check(afterClear.finishClosedTabsUndo(focusedClear, state: arch.state, available: { _ in true })
                  && afterClear.selectedTabIDs == [t2.id], "Undo Clear Tabs selects the tab that was focused")

        // A pinned tab and a Today tab closed together.
        let mixedClose = close([keep.id, t3.id], focused: nil)!
        try check(mixedClose.tabs.map(\.id) == [t3.id] && mixedClose.actionName == "Archive Tab"
                  && arch.state.tabs.contains { $0.id == keep.id && $0.archivedAt == nil && $0.kind == .pinned },
                  "A mixed close archives only the Today tab; the pinned one unloads in place")
        let mixedWindow = FolderUndoManager()
        try check(register(mixedClose, in: mixedWindow, on: arch), "Registers")
        mixedWindow.undo()
        try check(arch.state.tabs.contains { $0.id == t3.id && $0.archivedAt == nil }
                  && arch.state.tabs.contains { $0.id == keep.id && $0.archivedAt == nil && $0.kind == .pinned },
                  "Undo returns the Today tab and leaves the pinned one alone")

        // Back/forward entries of closed pages, kept in memory for Undo and Reopen.
        var history = ClosedPageHistory<NSObject>(limit: 2)
        let pageA = UUID(), pageB = UUID(), pageC = UUID()
        let entriesA = NSObject(), entriesB = NSObject(), entriesC = NSObject()
        history.closed(pageA, state: entriesA)
        try check(history.takeRestored(pageA) == nil, "A closed tab's entries wait for Undo or Reopen")
        history.restore([pageA])
        try check(history.takeRestored(pageA) === entriesA && history.takeRestored(pageA) == nil,
                  "A restored tab's first page takes them, once")
        history.closed(pageA, state: entriesA); history.closed(pageB, state: entriesB); history.closed(pageC, state: entriesC)
        history.restore([pageA, pageB, pageC])
        try check(history.takeRestored(pageA) == nil && history.takeRestored(pageB) === entriesB, "The oldest go past the limit")
        history.closed(pageC, state: entriesA)
        try check(history.takeRestored(pageC) == nil && history.take(pageC) === entriesA,
                  "Closing again waits for a new restore; a closed Peek's are taken by its record")
        history.closed(pageB, state: entriesB); history.restore([pageB]); history.unrestore([pageB])
        try check(history.takeRestored(pageB) == nil, "A Reopen that failed gives no entries")
        history.closed(pageC, state: entriesC); history.restore([pageC]); history.pageCreated(pageC)
        try check(history.takeRestored(pageC) == nil && history.take(pageC) == nil,
                  "A page created for the tab any other way drops its restored entries")
        arch.closedPageHistory.closed(pageA, state: entriesA)
        try check(!(try JSONEncoder().encode(arch.state)).isEmpty && arch.closedPageHistory.take(pageA) === entriesA,
                  "The store keeps closed pages' entries for every window, outside its saved state")
        var waiters = PeekUndoSlotWaiters()
        let shownParent = UUID(), hiddenParent = UUID()
        waiters.refused(shownParent); waiters.refused(hiddenParent)
        try check(waiters.release(selected: [UUID(), shownParent]) == [shownParent] && waiters.release(selected: [hiddenParent]).isEmpty,
                  "A Peek refused while another Undo's Peek was adopted retries when that ends if its parent is selected, once")
        _ = archInitial
        print("\(count) close undo assertions passed")
    }
}
