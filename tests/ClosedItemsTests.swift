import Foundation
import Combine

@main @MainActor
struct ClosedItemsTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { throw NSError(domain: message, code: assertions) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parc-reopen-component-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try BrowserStore(directory: dir, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        var first = WindowClosedItems(), second = WindowClosedItems()
        func close(_ ids: Set<UUID>, focus: UUID? = nil) -> ClosedItemIntent {
            let intent = ClosedItemIntent(ids: ids, state: store.state, spaceID: space, profileID: profile, focusedTabID: focus)!
            store.closeTabs(ids)
            return intent
        }
        let a = store.open("https://a.test"), b = store.open("https://b.test")
        first.record(close([a]), in: store.state)
        try expect(first.next(in: store.state)?.tabIDs == [a], "original window records manual close")
        try expect(second.next(in: store.state) == nil, "other window never scans shared recentlyClosedIDs")
        let pin = store.open("https://saved.test", kind: .pinned)
        store.updateTab(pin, title: "Navigated", url: "https://saved.test/next")
        first.record(close([pin]), in: store.state)
        let saved = first.next(in: store.state)!
        try expect(saved.kind == .saved && saved.tabIDs == [pin], "saved close wins over older Archive")
        try expect(saved.tabs[0].url == saved.tabs[0].savedURL, "saved close uses existing original saved destination")
        try expect(try store.restoreClosedItem(saved), "saved original is selectable again")
        try expect(store.selectedTabID == pin, "saved reopen selects exact ID")
        try expect(first.consume(saved), "successful saved reopen consumes exact slot")
        try expect(!first.consume(saved), "duplicate consumption cannot pop older step")
        try expect(first.next(in: store.state)?.tabIDs == [a], "older original-window Archive remains")
        let prior = first.next(in: store.state)!
        try expect(try store.restoreClosedItem(prior), "archived original restores")
        try expect(first.consume(prior) && first.next(in: store.state) == nil, "Archive step consumes once")
        try expect(store.state.tabs.filter { $0.id == a }.count == 1, "no cloned saved identity")

        first.record(close([pin]), in: store.state)
        let priorSaved = first.next(in: store.state)!
        first.selected([pin])
        try expect(first.next(in: store.state) == nil, "explicit saved revisit consumes priority")
        first.record(close([pin]), in: store.state)
        first.record(close([b]), in: store.state)
        try expect(first.next(in: store.state)?.tabIDs == [b], "Archive commit clears older saved priority")
        try expect(!first.consume(priorSaved), "old saved token cannot consume newer Archive")

        let c = store.open("https://c.test"), d = store.open("https://d.test")
        store.setSplit([c, d])
        let layout = store.state.splitLayouts.first { $0.tabIDs == [c, d] }!
        first.record(close([c, d], focus: d), in: store.state)
        let group = first.next(in: store.state)!
        try expect(group.tabIDs == [c, d] && group.split == layout, "complete original split is one step")
        try expect(group.focusedTabID == d, "original split focus retained")
        try expect(try store.restoreClosedItem(group), "complete archived split restores atomically")
        try expect(store.state.selectedTabIDs == [c, d] && store.state.splitLayouts.contains(layout), "original split IDs/order/geometry restored")
        try expect(first.consume(group), "complete split consumes one step")
        try expect(!group.isValid(in: store.state), "restored original cannot be replayed")

        let e = store.open("https://e.test"), f = store.open("https://f.test")
        second.record(close([e, f]), in: store.state)
        let last = second.next(in: store.state)!
        try expect(last.tabIDs == [f], "multi-item group pops last stable step")
        _ = try store.restoreClosedItem(last); _ = second.consume(last)
        try expect(second.next(in: store.state)?.tabIDs == [e], "earlier step remains in original group")
        try expect(first.next(in: store.state)?.tabIDs == [b], "other physical window ordering remains independent")

        let before = store.state
        let pending = ClosedItemIntent(ids: [c], state: store.state, spaceID: space, profileID: profile, focusedTabID: c)!
        var reply: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in reply = done }
        var committed = false
        store.closeTabs([c]) { allowed in committed = allowed }
        try expect(store.retiringTabIDs.contains(c) && store.state == before, "beforeunload preparation changes no model/cache")
        reply?(false)
        try expect(!committed && store.state == before, "refused beforeunload preserves original model")
        second.record(pending, in: store.state)
        try expect(second.next(in: store.state)?.tabIDs == [e], "noncommitted afterimage cannot forge close record")
        store.requestPageRetirement = nil

        let record = second.next(in: store.state)!
        var corrupt = store.state
        corrupt.spaces.removeAll { $0.id == space }
        try expect(!record.isValid(in: corrupt), "missing original Space invalidates instead of borrowing another profile")
        corrupt = store.state; corrupt.tabs[corrupt.tabs.firstIndex { $0.id == e }!].profileID = UUID()
        try expect(!record.isValid(in: corrupt), "profile reassignment invalidates original token")
        corrupt = store.state; corrupt.tabs[corrupt.tabs.firstIndex { $0.id == e }!].url += "/changed"
        try expect(!record.isValid(in: corrupt), "changed archived afterimage cannot be restored by stale token")
        try expect(ClosedItemIntent(ids: [UUID()], state: store.state, spaceID: space, profileID: profile, focusedTabID: nil) == nil,
                   "unknown close target never enters cache")

        corrupt = store.state
        corrupt.splitLayouts.append(BrowserSplitLayout(spaceID: space, tabIDs: [e, c], orientation: .horizontal, widthFactors: [0.5, 0.5]))
        try expect(!record.isValid(in: corrupt), "an old record cannot break a surviving or newly grouped item")
        let stable = store.state
        try store.save()
        let file = dir.appendingPathComponent("session.json"), backup = dir.appendingPathComponent("backup.json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var failed = false
        do { _ = try store.restoreClosedItem(record) } catch { failed = true }
        try expect(failed && store.state == stable, "save refusal leaves exact archived state untouched")
        try expect(second.next(in: store.state)?.id == record.id, "save refusal retains retryable exact step")
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
        try expect(try store.restoreClosedItem(record), "retry commits same original record")
        try expect(second.consume(record), "only successful retry consumes step")
        let reloaded = try BrowserStore(directory: dir)
        try expect(reloaded.state.tabs.first { $0.id == e }?.archivedAt == nil, "restoration persists before cache consumption")
        var freshWindow = WindowClosedItems()
        try expect(freshWindow.next(in: reloaded.state) == nil, "new physical window never inherits old process cache")

        first.record(close([pin]), in: store.state)
        let p2 = store.open("https://other-saved.test", kind: .favorite)
        first.record(close([p2]), in: store.state)
        try expect(first.next(in: store.state)?.tabIDs == [p2], "latest saved close replaces single priority slot")
        store.removeTab(p2)
        try expect(first.next(in: store.state)?.tabIDs == [b], "deleted saved target expires without identity resurrection")
        store.deleteArchivedTabs([b])
        try expect(first.next(in: store.state) == nil, "permanently deleted Archive steps expire")
        try archiveRetirement(directory: dir.appendingPathComponent("archive-retirement"))
        try bulkSavedReopen(directory: dir.appendingPathComponent("bulk"))
        try partialSplitReopen(directory: dir.appendingPathComponent("partial"))
        try peekAndFolderSteps(directory: dir.appendingPathComponent("steps"))
        print("ClosedItems: \(assertions) assertions passed")
    }

    static func archiveRetirement(directory: URL) throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let store = try BrowserStore(directory: directory, now: { now })
        let profile = store.activeSpace.profileID, space = store.activeSpaceID
        let a = store.open("https://a.invalid"), b = store.open("https://b.invalid")
        store.setSplit([a, b])
        let intent = ClosedItemIntent(ids: [a, b], state: store.state, spaceID: space, profileID: profile, focusedTabID: a)!
        store.closeTabs([a, b])
        var closed = WindowClosedItems(); closed.record(intent, in: store.state)
        let record = closed.next(in: store.state)!
        let item = store.archivedItems(profileID: profile).first { $0.tabs.contains { $0.id == a } }!
        let lease = store.acquireArchivePreview(id: item.id, profileID: profile)!
        try expect(store.acquireArchivePreview(id: item.id, profileID: profile) == nil, "one preview owns the original group")
        try expect(store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space)).isEmpty, "ordinary restore cannot steal a leased group")
        try expect(try !store.restoreClosedItem(record), "Reopen cannot steal a leased group")
        store.updateTab(a, title: "New title")
        try expect(store.archivePreviewIsValid(lease), "mutable title does not invalidate the preview identity")
        var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        store.deleteArchivedTabs([a], profileID: profile)
        try expect(requests.count == 1 && requests[0].0 == [a, b], "partial deletion reserves the whole preview group")
        try expect(store.archivePreviewIsValid(lease), "preview remains valid during retirement")
        try expect(store.restoreArchivePreview(lease, destination: .previousSpace(fallbackSpaceID: space)).isEmpty, "promotion cannot race retirement")
        store.deleteArchivedTabs([b], profileID: profile)
        store.removeTab(a)
        try expect(requests.count == 1, "overlapping deletion and general removal cannot supersede archive retirement")
        requests[0].2(false)
        try expect(store.state.tabs.contains { $0.id == a } && store.archivePreviewIsValid(lease), "refusal retains archive and lease")
        store.deleteArchivedTabs([a], profileID: profile)
        try expect(requests[1].1(), "unchanged group approves retirement")
        requests[1].2(true)
        try expect(store.state.tabs.contains { $0.id == a } && store.archivePreviewIsValid(lease), "unreleased preview lease prevents model deletion after completion")
        store.deleteArchivedTabs([a], profileID: profile)
        try expect(requests[2].1(), "unchanged retry approves retirement")
        store.releaseArchivePreview(lease)
        var deletionReentry: ArchivePreviewLease?
        let deleteObserver = store.statePublisher.dropFirst().sink { _ in deletionReentry = store.acquireArchivePreview(id: item.id, profileID: profile) }
        requests[2].2(true)
        deleteObserver.cancel()
        try expect(deletionReentry == nil, "state publication cannot admit the item being deleted")
        try expect(!store.state.tabs.contains { $0.id == a } && store.state.tabs.contains { $0.id == b }, "successful partial deletion keeps the other member")
        requests[0].2(true)
        try expect(store.state.tabs.contains { $0.id == b }, "stale completion cannot remove a surviving group member")
        let remaining = store.archivedItems(profileID: profile).first { $0.tabs.contains { $0.id == b } }!
        let second = store.acquireArchivePreview(id: remaining.id, profileID: profile)!
        store.deleteArchivedTabs([b])
        store.updateTab(b, title: "Edited during consent")
        try expect(!requests[3].1(), "changed archive snapshot refuses before unload")
        requests[3].2(false)
        try expect(store.state.tabs.contains { $0.id == b } && store.archivePreviewIsValid(second), "stale mutation keeps changed record and preview")
        var promotionReentry: ArchivePreviewLease?
        let promotionObserver = store.statePublisher.dropFirst().sink { _ in promotionReentry = store.acquireArchivePreview(id: remaining.id, profileID: profile) }
        try expect(store.restoreArchivePreview(second, destination: .previousSpace(fallbackSpaceID: space)) == [b], "preview restores the current original after a mutable edit")
        promotionObserver.cancel()
        try expect(promotionReentry == nil, "state publication cannot readmit the original preview during promotion")
        try expect(!store.archivePreviewIsValid(second), "successful promotion consumes lease")
        store.requestPageRetirement = nil
        store.closeTabs([b]); store.clearArchive(profileID: profile)
        try expect(!store.state.tabs.contains { $0.id == b }, "no native owner retains synchronous clear behavior")

        let expiring = store.open("https://expired.invalid"); store.closeTabs([expiring])
        requests.removeAll(); store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
        try expect(requests.count == 1 && requests[0].0 == [expiring], "expiry uses native retirement at the retention boundary")
        requests[0].2(false)
        try expect(store.state.tabs.contains { $0.id == expiring }, "refused expiry retains the record")
        store.requestPageRetirement = nil
        store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
        try expect(!store.state.tabs.contains { $0.id == expiring }, "model-only expiry removes the record")

        let document = UUID(), easel = store.openResolvedURL(URL(string: InternalPage.easel(document).urlString)!)
        store.closeTabs([easel])
        let documentLease = store.acquireArchivePreview(id: easel, profileID: profile)!
        let other = store.openEasel(id: document, title: "Board")!
        try expect(other != easel && store.archivePreviewIsValid(documentLease), "opening an Easel never resurrects its leased archive identity")
        requests.removeAll(); store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        var deleted = false, completed: Error?
        store.deleteLocalDocument(.easel(document), profileID: profile, ownerValid: { true }, deleteDocument: { deleted = true }, completion: { completed = $0 })
        try expect(requests.count == 1 && requests[0].0 == [easel, other], "document retirement includes live and archived aliases")
        try expect(requests[0].1(), "unchanged document aliases approve")
        requests[0].2(true)
        try expect(!deleted && completed != nil && store.state.tabs.contains { $0.id == easel }, "unreleased preview refuses document deletion")
        store.releaseArchivePreview(documentLease)
    }

    static func peekAndFolderSteps(directory: URL) throws {
        let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        var cache = WindowClosedItems()
        func top() -> ClosedItemStep? { cache.nextStep(in: store.state, restorable: { store.canUndoFolderDeletion($0) }) }

        let parent = store.open("https://parent.invalid")
        let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!,
            parentTabID: parent, profileID: profile)
        cache.recordPeek(peek, in: store.state)
        guard case .peek(let restored)? = top() else { throw NSError(domain: "dismissed Peek must be the top step", code: 1) }
        try expect(restored == peek, "dismissed Peek records its parent item and current URL")
        try expect(cache.next(in: store.state) == nil, "an item-only query never mistakes a Peek step for a tab")
        let local = ClosedPeekRecord(id: UUID(), url: URL(string: "file:///tmp/peek")!, parentTabID: parent, profileID: profile)
        try expect(!local.isValid(in: store.state), "only an HTTP(S) Peek can reopen")
        var removing = store.state
        removing.profileRemovals.append(ProfileRemovalRecord(id: UUID(), profileID: profile, profileName: "Removing"))
        try expect(!peek.isValid(in: removing), "a Profile being removed cannot reopen its Peek")
        try expect(!cache.consume(stepID: UUID()) && cache.consume(stepID: peek.id) && top() == nil,
            "only the exact Peek step consumes")

        let pinned = store.open("https://saved.invalid", kind: .pinned)
        let savedIntent = ClosedItemIntent(ids: [pinned], state: store.state, spaceID: space, profileID: profile, focusedTabID: pinned)!
        store.closeTabs([pinned]); cache.record(savedIntent, in: store.state)
        cache.recordPeek(peek, in: store.state)
        guard case .items(let saved)? = top(), saved.kind == .saved else {
            throw NSError(domain: "saved slot must precede a later Peek", code: 2)
        }
        try expect(cache.consume(saved), "saved priority consumes first")
        guard case .peek? = top() else { throw NSError(domain: "Peek step must remain after saved Reopen", code: 3) }

        let older = store.open("https://older.invalid")
        let olderIntent = ClosedItemIntent(ids: [older], state: store.state, spaceID: space, profileID: profile, focusedTabID: older)!
        store.closeTabs([older]); cache.record(olderIntent, in: store.state)
        cache.recordPeek(peek, in: store.state)
        store.closeTabs([parent])
        guard case .items(let survivor)? = top(), survivor.tabIDs == [older] else {
            throw NSError(domain: "an archived Peek parent must expire its step", code: 4)
        }
        try expect(try store.restoreClosedItem(survivor) && cache.consume(survivor), "the older close remains reachable")

        let folder = store.createFolder(name: "Reading")
        let inner = store.open("https://inner.invalid"), second = store.open("https://second.invalid")
        store.moveTab(inner, toSpace: space, folderID: folder)
        store.moveTab(second, toSpace: space, folderID: folder)
        let expanded = store.state.folders.first { $0.id == folder }!
        try expect(try store.setFolderExpanded(false, expected: expanded, profileID: profile), "folder collapses before Delete")
        let collapsed = store.state.folders.first { $0.id == folder }!
        let pin = store.open("https://priority.invalid", kind: .pinned)
        let pinIntent = ClosedItemIntent(ids: [pin], state: store.state, spaceID: space, profileID: profile, focusedTabID: pin)!
        store.closeTabs([pin]); cache.record(pinIntent, in: store.state)
        func delete(_ id: UUID) -> FolderDeletionUndo? {
            guard let target = FolderRemovalTarget(folderID: id, spaceID: space, profileID: profile, state: store.state) else { return nil }
            var undo: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { undo = $0 }) { _ in }
            return undo
        }
        guard let deleted = delete(folder) else { throw NSError(domain: "folder Delete must commit", code: 5) }
        cache.recordFolderDeletion(deleted)
        guard case .folder(let step)? = top(), step.id == deleted.id else {
            throw NSError(domain: "a folder Delete must replace saved priority as the top step", code: 6)
        }
        try expect(try store.undoFolderDeletion(step, shouldCommit: { true }) && cache.consume(stepID: step.id),
            "Reopen restores the deletion through its original transaction")
        try expect(store.state.folders.first { $0.id == folder } == collapsed
            && store.state.tabs.filter { [inner, second].contains($0.id) }.allSatisfy { $0.archivedAt == nil && $0.folderID == folder },
            "original folder, collapsed flag and children return")
        try expect(top() == nil, "the step is consumed once")

        try expect(try store.setFolderExpanded(true, expected: collapsed, profileID: profile), "folder expands before Delete")
        guard let again = delete(folder) else { throw NSError(domain: "second folder Delete must commit", code: 7) }
        cache.recordFolderDeletion(again)
        try expect(try store.undoFolderDeletion(again, shouldCommit: { true }), "folder Undo restores first")
        try expect(store.state.folders.first { $0.id == folder }?.isExpanded == true, "an expanded folder returns expanded")
        try expect(top() == nil, "a deletion already restored by Undo expires its Reopen step")
    }

    static func partialSplitReopen(directory: URL) throws {
        let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        var cache = WindowClosedItems()
        func approx(_ left: [Double]?, _ right: [Double]) -> Bool {
            guard let left, left.count == right.count else { return false }
            return zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
        }
        func split(_ ids: [UUID], _ orientation: SplitOrientation, _ factors: [Double]) -> BrowserSplitLayout {
            store.setSplit(ids); _ = store.setSplitLayout(orientation: orientation, widthFactors: factors)
            return store.state.splitLayouts.first { $0.tabIDs == ids }!
        }
        func close(_ ids: Set<UUID>, focus: UUID? = nil) {
            let intent = ClosedItemIntent(ids: ids, state: store.state, spaceID: space, profileID: profile, focusedTabID: focus)!
            store.closeTabs(ids)
            cache.record(intent, in: store.state)
        }
        func group(_ id: UUID) -> BrowserSplitLayout? { store.state.splitLayouts.first { $0.id == id } }
        func reopen(_ expected: [UUID], regroupable: (UUID) -> Bool = { _ in true }) throws {
            let record = cache.next(in: store.state)!
            try expect(record.tabIDs == expected, "Reopen takes the expected original pane step")
            try expect(try store.restoreClosedItem(record, regroupable: regroupable), "partial split pane restores through the store")
            try expect(cache.consume(record), "partial split step consumes once")
        }

        let a = store.open("https://a.invalid"), b = store.open("https://b.invalid"), c = store.open("https://c.invalid")
        let three = split([a, b, c], .vertical, [0.2, 0.3, 0.5])
        close([b], focus: b)
        try expect(group(three.id)?.tabIDs == [a, c], "closing one of three panes keeps the original container")
        let middle = cache.next(in: store.state)!.membership
        try expect(middle?.layout.id == three.id && middle?.layout.tabIDs == [a, b, c] && middle?.index == 1
            && middle?.dissolved == false, "close records the original container and index without regrouping")
        try reopen([b])
        try expect(group(three.id)?.tabIDs == [a, b, c] && group(three.id)?.orientation == .vertical
            && approx(group(three.id)?.widthFactors, [0.2, 0.3, 0.5]), "pane rejoins at its original index and share")
        try expect(store.state.selectedTabIDs == [a, b, c], "Reopen selects the rejoined split, not a lone pane")
        try expect(store.state.splitLayouts.filter { $0.tabIDs.contains(b) }.count == 1, "no duplicate group is appended")

        let d = store.open("https://d.invalid"), e = store.open("https://e.invalid")
        let pair = split([d, e], .vertical, [0.25, 0.75])
        close([d], focus: d)
        try expect(group(pair.id) == nil, "closing one of two panes dissolves the container")
        try expect(cache.next(in: store.state)?.membership?.dissolved == true, "dissolving close records regrouping")
        try reopen([d])
        try expect(group(pair.id)?.tabIDs == [d, e] && group(pair.id)?.orientation == .vertical
            && approx(group(pair.id)?.widthFactors, [0.25, 0.75])
            && group(pair.id)?.sidebarAnchorID == pair.sidebarAnchorID,
            "original container regroups with its identity, order, orientation, ratios and anchor")
        try expect(store.state.selectedTabIDs == [d, e], "regrouped split is selected")
        let disk = try BrowserStore(directory: directory)
        try expect(disk.state.splitLayouts.contains { $0.id == pair.id && $0.tabIDs == [d, e] }, "regrouping persists before consumption")

        let f = store.open("https://f.invalid"), g = store.open("https://g.invalid")
        let h = store.open("https://h.invalid"), i = store.open("https://i.invalid")
        let four = split([f, g, h, i], .horizontal, [0.1, 0.2, 0.3, 0.4])
        close([g, h], focus: h)
        try expect(group(four.id)?.tabIDs == [f, i], "two of four panes close from one surviving container")
        try reopen([h])
        try expect(group(four.id)?.tabIDs == [f, h, i], "later pane returns at its adjusted index")
        try reopen([g])
        try expect(group(four.id)?.tabIDs == [f, g, h, i] && approx(group(four.id)?.widthFactors, [0.1, 0.2, 0.3, 0.4]),
            "successive Reopens restore the original order and ratios")

        let j = store.open("https://j.invalid"), k = store.open("https://k.invalid"), l = store.open("https://l.invalid")
        let trio = split([j, k, l], .horizontal, [0.5, 0.25, 0.25])
        close([k, l], focus: l)
        try expect(group(trio.id) == nil, "two of three closed together dissolves the container")
        try reopen([l])
        try expect(group(trio.id)?.tabIDs == [j, l] && approx(group(trio.id)?.widthFactors, [2.0 / 3, 1.0 / 3]),
            "first pane regroups the original container with the survivor")
        try reopen([k])
        try expect(group(trio.id)?.tabIDs == [j, k, l] && approx(group(trio.id)?.widthFactors, [0.5, 0.25, 0.25]),
            "second pane rejoins the regrouped container at its original index")

        let m = store.open("https://m.invalid"), n = store.open("https://n.invalid")
        let owned = split([m, n], .horizontal, [0.5, 0.5])
        close([n], focus: n)
        try reopen([n], regroupable: { $0 != m })
        try expect(group(owned.id) == nil && store.state.selectedTabIDs == [n], "refused survivor leaves the pane alone")

        let shownElsewhere = NativePageOwnership(), thisWindow = UUID(), otherWindow = UUID()
        let survivor = store.open("https://survivor.invalid"), returning = store.open("https://returning.invalid")
        let shared = split([survivor, returning], .vertical, [0.4, 0.6])
        close([returning], focus: returning)
        try expect(shownElsewhere.claim(survivor, owner: otherWindow, page: "survivor-page"), "the survivor's page is in another window")
        try reopen([returning], regroupable: { id in
            shownElsewhere.canUse(id, owner: thisWindow) || (shownElsewhere.isClaimed(id) && shownElsewhere.claimSnapshot(id).transfer == nil)
        })
        try expect(group(shared.id)?.tabIDs == [survivor, returning] && approx(group(shared.id)?.widthFactors, [0.4, 0.6]),
            "a survivor shown in another window rejoins the split with its geometry")

        let o = store.open("https://o.invalid"), p = store.open("https://p.invalid"), q = store.open("https://q.invalid")
        let left = split([o, p], .horizontal, [0.5, 0.5])
        close([p], focus: p)
        let other = split([o, q], .horizontal, [0.4, 0.6])
        try reopen([p])
        try expect(group(left.id) == nil && group(other.id)?.tabIDs == [o, q] && store.state.selectedTabIDs == [p],
            "regrouping never steals a pane from a newer group")

        let o1 = store.open("https://o1.invalid"), o2 = store.open("https://o2.invalid"), o3 = store.open("https://o3.invalid")
        let o4 = store.open("https://o4.invalid")
        let skippedTrio = split([o1, o2, o3], .horizontal, [1, 1, 1])
        close([o2, o3], focus: o3)
        let elsewhere = split([o1, o4], .horizontal, [0.5, 0.5])
        try reopen([o3])
        try expect(group(skippedTrio.id) == nil && store.state.selectedTabIDs == [o3], "a grouped survivor skips regrouping")
        try reopen([o2])
        try expect(group(skippedTrio.id) == nil && store.state.selectedTabIDs == [o2] && group(elsewhere.id)?.tabIDs == [o1, o4],
            "two ungrouped returning panes still do not regroup around a grouped child")

        let r = store.open("https://r.invalid"), s = store.open("https://s.invalid"), t = store.open("https://t.invalid")
        let u = store.open("https://u.invalid"), v = store.open("https://v.invalid")
        let full = split([r, s, t], .horizontal, [1, 1, 1])
        close([s], focus: s)
        store.setSplit([r, t, u, v])
        try expect(group(full.id)?.tabIDs == [r, t, u, v], "surviving container was refilled to four panes")
        try reopen([s])
        try expect(group(full.id)?.tabIDs == [r, t, u, v] && store.state.selectedTabIDs == [s],
            "a four-pane container refuses insertion and the pane returns alone")

        let w = store.open("https://w.invalid"), x = store.open("https://x.invalid")
        let lone = split([w, x], .horizontal, [0.5, 0.5])
        close([x], focus: x)
        close([w], focus: w)
        let skipped = cache.next(in: store.state)!
        try expect(skipped.tabIDs == [w] && skipped.membership == nil, "the unsplit survivor closes as a plain pane")
        try expect(cache.consume(skipped), "survivor step is discarded without restoring it")
        try reopen([x])
        try expect(group(lone.id) == nil && store.state.selectedTabIDs == [x],
            "fewer than two existing original children returns the pane alone")

        let y = store.open("https://y.invalid"), z = store.open("https://z.invalid"), zz = store.open("https://zz.invalid")
        let checked = split([y, z, zz], .horizontal, [1, 1, 1])
        let intent = ClosedItemIntent(ids: [z], state: store.state, spaceID: space, profileID: profile, focusedTabID: z)!
        store.closeTabs([z])
        var replaced = store.state
        replaced.splitLayouts[replaced.splitLayouts.firstIndex { $0.id == checked.id }!].id = UUID()
        try expect(intent.membership(of: z, in: replaced) == nil, "a changed container records no regrouping")
        try expect(intent.membership(of: z, in: store.state)?.index == 1, "the exact afterimage records the original index")

        let p1 = store.open("https://p1.invalid"), p2 = store.open("https://p2.invalid"), p3 = store.open("https://p3.invalid")
        let reordered = split([p1, p3, p2], .horizontal, [0.5, 0.2, 0.3])
        close([p3, p2], focus: p2)
        try expect(group(reordered.id) == nil, "two of three closed together dissolves the reordered container")
        try reopen([p3])
        try expect(group(reordered.id)?.tabIDs == [p1, p3], "the model-later step regroups first")
        try reopen([p2])
        try expect(group(reordered.id)?.tabIDs == [p1, p3, p2] && approx(group(reordered.id)?.widthFactors, [0.5, 0.2, 0.3]),
            "any Reopen order rebuilds the original pane order and ratios")
    }

    static func bulkSavedReopen(directory: URL) throws {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try BrowserStore(directory: directory, now: { now })
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        let oldest = store.open("https://first.invalid", kind: .pinned)
        let recent = store.open("https://recent.invalid", kind: .pinned)
        let newestShared = store.open("https://shared.invalid", kind: .pinned)
        let today = store.open("https://archive.invalid")
        var first = WindowClosedItems(), second = WindowClosedItems()
        func intent(_ ids: Set<UUID>, focus: UUID? = nil) -> ClosedItemIntent {
            ClosedItemIntent(ids: ids, state: store.state, spaceID: space,
                profileID: profile, focusedTabID: focus)!
        }
        let archived = intent([today]); store.closeTabs([today]); first.record(archived, in: store.state)
        first.recordSelection([oldest], focusedTabID: oldest, state: store.state, at: now.addingTimeInterval(0.1))
        first.recordSelection([recent], focusedTabID: recent, state: store.state, at: now.addingTimeInterval(0.2))
        second.recordSelection([newestShared], focusedTabID: newestShared, state: store.state, at: now + 1)
        now += 1
        store.selectTab(newestShared)
        store.updateWindowRecords([BrowserWindowRecord(sidebarWidth: 228, itemLastActiveDates: first.itemLastActiveDates)])
        try store.save()
        let restoredRecord = try BrowserStore(directory: directory).windowRecords[0]
        var restored = WindowClosedItems(itemLastActiveDates: restoredRecord.itemLastActiveDates)
        let bulk = intent([oldest,recent,newestShared])
        store.closeTabs([oldest,recent,newestShared])
        first.record(bulk, in: store.state); second.record(bulk, in: store.state)
        restored.record(bulk, in: store.state)
        try expect(restored.next(in: store.state)?.tabIDs == [recent], "the real session store retains same-second saved-item recency")
        let selected = first.next(in: store.state)!
        try expect(selected.tabIDs == [recent], "bulk saved Close chooses this window's most recent original, not model/storage/shared date order")
        try expect(second.next(in: store.state)?.tabIDs == [newestShared], "another physical window keeps independent saved recency")
        try expect(try store.restoreClosedItem(selected), "most recent original saved item restores through real store")
        try expect(first.consume(selected), "bulk saved winner consumes once")
        try expect(first.next(in: store.state)?.tabIDs == [today], "bulk saved Close creates one priority, not an invented stack of remaining saved items")
        var equal = WindowClosedItems(), unseen = WindowClosedItems()
        equal.recordSelection([recent], focusedTabID: recent, state: store.state, at: now)
        equal.recordSelection([oldest], focusedTabID: oldest, state: store.state, at: now)
        let tied = intent([oldest,recent]); store.closeTabs([oldest,recent])
        equal.record(tied, in: store.state); unseen.record(tied, in: store.state)
        try expect(equal.next(in: store.state)?.tabIDs == [oldest], "equal-date tie uses declared stable model-order adaptation")
        try expect(unseen.next(in: store.state)?.tabIDs == [oldest], "missing dates are distantPast and do not borrow global access history")
        first.record(bulk, in: store.state)
        let retry = first.next(in: store.state)!
        var changed = store.state
        changed.tabs[changed.tabs.firstIndex { $0.id == recent }!].profileID = UUID()
        try expect(!retry.isValid(in: changed), "bulk saved record keeps original Profile identity")
        changed = store.state; changed.tabs.removeAll { $0.id == recent }
        try expect(!retry.isValid(in: changed), "removed bulk winner cannot fall through to a different saved item")
        var expired = first
        try expect(expired.next(in: changed)?.tabIDs == [today], "expired single saved slot resumes existing Today history")
        let before = store.state
        try store.save()
        let file = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("backup.json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var failed = false
        do { _ = try store.restoreClosedItem(retry) } catch { failed = true }
        try expect(failed && store.state == before, "bulk winner save refusal publishes no selection")
        try expect(first.next(in: store.state)?.id == retry.id, "bulk winner remains retryable after failed persistence")
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
        try expect(try store.restoreClosedItem(retry) && first.consume(retry), "bulk saved retry commits original target before consumption")

        let notePath = store.directory.appendingPathComponent("Parc Notes/Shared Note.md")
        try FileManager.default.createDirectory(at: notePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Shared body\n".utf8).write(to: notePath)
        let easels = try EaselStore(directory: store.easelsDirectory(for: profile))
        let easel = try easels.create(title: "Shared Easel")
        let easelPath = easels.directory.appendingPathComponent("documents/" + easel.document.id.uuidString.lowercased() + ".json")
        let noteBytes = try Data(contentsOf: notePath), easelBytes = try Data(contentsOf: easelPath)
        let n = store.openNote(url: notePath, title: "Shared Note")!
        let e = store.openEasel(id: easel.document.id, title: easel.document.title)!
        store.setKind(n, .today); store.setKind(e, .today)
        store.setSplit([n,e]); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3,0.7])
        let todaySplit = store.state.splitLayouts.first { $0.tabIDs == [n,e] }!
        let pinnedRoot = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .pinned)
        try expect(try store.moveSidebarItem(.split(todaySplit.id), to: pinnedRoot, before: nil,
            expected: SidebarHierarchySnapshot(state: store.state, spaceID: store.activeSpaceID, profileID: profile)!),
            "the Note/Easel split moves whole into the pinned section")
        let split = store.state.splitLayouts.first { $0.tabIDs == [n,e] }!
        var splitCache = WindowClosedItems()
        splitCache.recordSelection([oldest], focusedTabID: oldest, state: store.state, at: now)
        splitCache.recordSelection([n,e], focusedTabID: e, state: store.state, at: now + 1)
        let groupIntent = intent([n,e,oldest], focus: e)
        var done: ((Bool) -> Void)?, validate: (() -> Bool)?, committed = false, original = true
        var requested = Set<UUID>()
        store.requestPageRetirement = { ids, check, reply in
            requested = ids; validate = check; done = reply
        }
        store.closeTabs([n,e,oldest], shouldCommit: { original }) { allowed in
            committed = allowed
            if allowed { splitCache.record(groupIntent, in: store.state) }
        }
        try expect(requested == Set([n,e,oldest]), "saved split and other roots share one exact retirement request")
        try expect(splitCache.next(in: store.state) == nil, "pending native/Notes consent cannot publish saved Reopen")
        original = false; try expect(validate?() == false, "intervening original-owner change refuses whole saved collection")
        done?(true)
        try expect(!committed && splitCache.next(in: store.state) == nil, "refused collection creates no saved winner")
        original = true
        store.closeTabs([n,e,oldest], shouldCommit: { original }) { allowed in
            committed = allowed
            if allowed { splitCache.record(groupIntent, in: store.state) }
        }
        try expect(validate?() == true, "original collection passes the actual final retirement validation")
        done?(true); store.requestPageRetirement = nil
        guard let closed = splitCache.next(in: store.state) else {
            throw NSError(domain: "committed original saved split must produce Reopen", code: 1)
        }
        try expect(committed && closed.tabIDs == [n,e] && closed.split == split, "most recent split pane resolves to the exact retained saved group")
        try expect(closed.focusedTabID == e, "saved split keeps original window's focused pane")
        try expect(store.state.splitLayouts.filter { $0.id == split.id } == [split], "saved Close keeps original split identity and geometry")
        var invalid = store.state
        invalid.splitLayouts[invalid.splitLayouts.firstIndex { $0.id == split.id }!].widthFactors = [0.5,0.5]
        try expect(!closed.isValid(in: invalid), "changed retained split expires original saved capability")
        invalid = store.state; invalid.splitLayouts.removeAll { $0.id == split.id }
        try expect(!closed.isValid(in: invalid), "saved Reopen never recreates a dissolved split")
        var noChangedGroup = WindowClosedItems()
        noChangedGroup.recordSelection([n,e], focusedTabID: e, state: store.state, at: now + 1)
        noChangedGroup.record(groupIntent, in: invalid)
        try expect(noChangedGroup.next(in: invalid) == nil, "changed original group cannot degrade into a fabricated singleton")
        var revisit = splitCache; revisit.selected([n])
        try expect(revisit.next(in: store.state) == nil, "visiting any retained group child consumes saved priority")
        try expect(try store.restoreClosedItem(closed), "whole saved split selects through real durable restoration")
        try expect(store.state.selectedTabIDs == [n,e] && store.state.splitLayouts.filter { $0.id == split.id } == [split], "restoration selects original children without appending a duplicate group")
        try expect(splitCache.consume(closed) && splitCache.next(in: store.state) == nil, "whole saved split consumes one saved priority")
        let disk = try BrowserStore(directory: directory)
        try expect(disk.state.splitLayouts.filter { $0.id == split.id } == [split], "saved split restoration survives persistence with one original group")
        try expect(try Data(contentsOf: notePath) == noteBytes && Data(contentsOf: easelPath) == easelBytes,
            "saved typed restoration never changes Note/Easel document bytes")
        try expect((try easels.load(easel.document.id)) === easel, "saved restoration retains the actual shared Easel session")
        try expect(store.state.tabs.first { $0.id == n }?.url == InternalPage.note(notePath).urlString
            && store.state.tabs.first { $0.id == e }?.url == InternalPage.easel(easel.document.id).urlString,
            "typed aliases reopen original document IDs without clones or URL substitutes")
    }
}
