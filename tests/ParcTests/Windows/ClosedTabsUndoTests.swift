import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class Consent {
    var authorize: (() -> Bool)?
    var finish: ((Bool) -> Void)?
    var autoApprove = false
    var usable = true
    var undone = 0
    var errors: [Error] = []
    var redoCurrent: (() -> Bool)?
    var refused = Set<UUID>()
    var lastOperation: ClosedTabsUndoOperation?

    func attach(_ store: BrowserStore) {
        store.requestPageRetirement = { [unowned self] _, canCommit, done in
            if autoApprove { done(canCommit()) } else { authorize = canCommit; finish = done }
        }
    }

    func approve() {
        _ = authorize?()
        finish?(true)
    }

    func register(_ record: ClosedTabsUndo, in manager: FolderUndoManager, on owner: BrowserStore) -> Bool {
        lastOperation = nil
        manager.appendClosedTabs(record, store: owner, canUse: { [unowned self] ids, _ in usable && ids.isDisjoint(with: refused) },
                                 close: { [unowned self] ids, current, done in
            redoCurrent = current
            var next: ClosedTabsUndo?
            owner.closeTabs(ids, reason: .manual, didCommit: { before in
                next = ClosedTabsUndo(prompt: record.prompt, ids: ids, spaceID: record.spaceID, profileID: record.profileID,
                                      focusedTabID: nil, before: before, after: owner.state)
            }, shouldCommit: current) { done($0 ? next : nil) }
        }, didUndo: { [unowned self] _ in undone += 1 }, onError: { [unowned self] in errors.append($0) }) { [unowned self] in lastOperation = $0 }
        return lastOperation != nil
    }
}

private func makeTab(_ title: String, _ space: BrowserSpace, profile: BrowserProfile, kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
    let url = "https://" + title.lowercased().replacingOccurrences(of: " ", with: "-") + ".invalid/"
    return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                 kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                 lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
}

private func writeSeed(_ state: BrowserState, to directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("session.json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(state).write(to: url)
    return url
}

private let storeClock: () -> Date = { Date(timeIntervalSince1970: 1_900_000_000) }

private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-close-undo-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor private final class ClearFixture {
    let consent = Consent()
    let root: URL
    let profile = BrowserProfile(id: UUID(), name: "Original")
    let here: BrowserSpace, there: BrowserSpace
    let folder: BrowserFolder
    let pinned: BrowserTab, filed: BrowserTab, first: BrowserTab, left: BrowserTab, right: BrowserTab, last: BrowserTab
    let elsewhere: BrowserTab, elsewhereToo: BrowserTab, earlier: BrowserTab
    let split: BrowserSplitLayout
    let today: SidebarContainerLocation, thereToday: SidebarContainerLocation, pinnedList: SidebarContainerLocation
    let sessionURL: URL
    let store: BrowserStore
    let initial: BrowserState
    var record: ClosedTabsUndo?
    var committed: Bool?
    var hereIDs: Set<UUID> { [first.id, left.id, right.id, last.id] }

    init() throws {
        root = try temporaryRoot()
        here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        there = BrowserSpace(id: UUID(), name: "There", symbol: "square", color: "123456", profileID: profile.id)
        folder = BrowserFolder(id: UUID(), spaceID: here.id, name: "Pinned folder")
        let profile = profile, here = here, there = there
        pinned = makeTab("Pinned", here, profile: profile, kind: .pinned)
        filed = makeTab("Filed", here, profile: profile, kind: .pinned, folder: folder.id)
        first = makeTab("First", here, profile: profile)
        left = makeTab("Left", here, profile: profile)
        right = makeTab("Right", here, profile: profile)
        last = makeTab("Last", here, profile: profile)
        elsewhere = makeTab("Elsewhere", there, profile: profile)
        elsewhereToo = makeTab("Elsewhere too", there, profile: profile)
        var archived = makeTab("Earlier archive", here, profile: profile)
        archived.archivedAt = Date(timeIntervalSince1970: 1_000)
        earlier = archived
        split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Pair", spaceID: here.id,
                                   tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        var seed = BrowserState(profiles: [profile], spaces: [here, there], activeSpaceID: here.id)
        seed.folders = [folder]
        seed.tabs = [pinned, filed, first, left, right, last, elsewhere, elsewhereToo, earlier]
        seed.splitLayouts = [split]
        today = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
        thereToday = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .today)
        pinnedList = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
        seed.sidebarItemOrder[today.key] = [.tab(last.id), .tab(left.id), .tab(first.id)]
        seed.sidebarItemOrder[pinnedList.key] = [.folder(folder.id), .tab(pinned.id)]
        seed.sidebarItemOrder[thereToday.key] = [.tab(elsewhereToo.id), .tab(elsewhere.id)]
        seed.selectedTabIDs = [first.id]
        seed.selectionBySpace[here.id.uuidString] = [first.id]
        sessionURL = try writeSeed(seed, to: root)
        store = try BrowserStore(directory: root, now: storeClock)
        initial = store.state
        consent.attach(store)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func todayIDs(_ space: BrowserSpace) -> Set<UUID> {
        Set(store.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == space.id && $0.profileID == profile.id }.map(\.id))
    }

    func clear(_ space: BrowserSpace) {
        record = nil
        committed = nil
        let ids = todayIDs(space)
        let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: store.state.activeSpaceID,
            profileID: profile.id, state: store.state, selected: store.state.selectedTabIDs,
            focused: store.state.selectedTabIDs.last, available: { _ in true })
        store.closeTabs(ids, reason: .clearButton, selection: selection, didCommit: { [unowned self] before in
            record = ClosedTabsUndo(prompt: .clear, ids: ids, spaceID: space.id, profileID: profile.id, focusedTabID: nil,
                                    before: before, after: store.state)
        }, shouldCommit: { true }) { [unowned self] in committed = $0 }
    }

    func approvedClear() -> ClosedTabsUndo {
        clear(here)
        _ = consent.authorize?()
        consent.finish?(true)
        return record!
    }

    func register(_ record: ClosedTabsUndo, in manager: FolderUndoManager) -> Bool {
        consent.register(record, in: manager, on: store)
    }

    func goToThere() {
        _ = store.setWindowPresentation(spaceID: there.id, selectedTabIDs: [elsewhere.id])
    }

    func registeredClear() -> (ClosedTabsUndo, FolderUndoManager) {
        let record = approvedClear()
        let window = FolderUndoManager()
        _ = register(record, in: window)
        goToThere()
        return (record, window)
    }

    func autoClear(_ space: BrowserSpace) -> ClosedTabsUndo {
        consent.autoApprove = true
        clear(space)
        return record!
    }
}

@MainActor struct ClosedTabsClearTests {
    @Test func clearWaitsForPageConsentWithoutMutation() throws {
        let f = try ClearFixture()
        f.clear(f.here)
        #expect(f.committed == nil && f.record == nil && f.store.state == f.initial)
    }

    @Test func refusedConsentClearsNothingAndRecordsNoUndo() throws {
        let f = try ClearFixture()
        f.clear(f.here)
        f.consent.finish?(false)
        #expect(f.committed == false && f.record == nil && f.store.state == f.initial)
    }

    @Test func originalPagesAdmitTheClear() throws {
        let f = try ClearFixture()
        f.clear(f.here)
        #expect(f.consent.authorize?() == true)
    }

    @Test func clearArchivesEveryTodayTabWithTheClearButtonReason() throws {
        let f = try ClearFixture()
        _ = f.approvedClear()
        #expect(f.committed == true)
        #expect(f.store.state.tabs.filter { f.hereIDs.contains($0.id) }.allSatisfy {
            $0.archivedAt != nil && $0.archiveProvenance?.reason == .clearButton
        })
    }

    @Test func theSplitArchivesAsOneItemAndLeavesTheSidebar() throws {
        let f = try ClearFixture()
        _ = f.approvedClear()
        let cleared = f.store.state
        let leftProvenance = cleared.tabs.first { $0.id == f.left.id }?.archiveProvenance
        #expect(leftProvenance?.groupID != nil && leftProvenance?.groupID == cleared.tabs.first { $0.id == f.right.id }?.archiveProvenance?.groupID)
        #expect(leftProvenance?.split == f.split && cleared.splitLayouts.isEmpty)
    }

    @Test func clearSelectsTheNextItemHereThePinnedTabAsAnyCloseDoes() throws {
        let f = try ClearFixture()
        _ = f.approvedClear()
        let cleared = f.store.state
        let pinnedNow = try #require(cleared.tabs.first { $0.id == f.pinned.id })
        var stamped = f.pinned
        stamped.lastAccessed = pinnedNow.lastAccessed
        stamped.isUnread = pinnedNow.isUnread
        #expect(cleared.selectedTabIDs == [f.pinned.id] && pinnedNow == stamped)
    }

    @Test func pinnedItemsFoldersTheOtherSpaceAndTheEarlierArchiveAreUntouched() throws {
        let f = try ClearFixture()
        _ = f.approvedClear()
        let cleared = f.store.state
        #expect([f.filed, f.elsewhere, f.elsewhereToo, f.earlier].allSatisfy { cleared.tabs.contains($0) } && cleared.folders == [f.folder])
        #expect(cleared.sidebarItemOrder[f.pinnedList.key] == f.initial.sidebarItemOrder[f.pinnedList.key])
    }

    @Test func theTodayListIsEmptyAfterClear() throws {
        let f = try ClearFixture()
        _ = f.approvedClear()
        #expect(SidebarHierarchy.children(in: f.today, state: f.store.state).isEmpty)
    }

    @Test func theRecordHoldsTheOriginalsTheSplitAndTheTodayOrder() throws {
        let f = try ClearFixture()
        let record = f.approvedClear()
        #expect(record.actionName == "Clear Tabs" && record.tabs.count == 4 && record.groups == [f.split])
        #expect(record.order == SidebarHierarchy.children(in: f.today, state: f.initial))
    }

    @Test func aCloseThatTookNothingOutOfTheSidebarHasNoUndo() throws {
        let f = try ClearFixture()
        #expect(ClosedTabsUndo(prompt: .clear, ids: [f.first.id], spaceID: f.here.id, profileID: f.profile.id, focusedTabID: nil,
                               before: f.initial, after: f.initial) == nil)
    }

    @Test func oneTabNamesClearTab() throws {
        let f = try ClearFixture()
        var lone = f.initial
        lone.tabs.removeAll { $0.id == f.right.id || $0.id == f.left.id || $0.id == f.last.id }
        lone.splitLayouts = []
        var loneCleared = lone
        loneCleared.tabs[loneCleared.tabs.firstIndex { $0.id == f.first.id }!].archivedAt = Date()
        #expect(ClosedTabsUndo(prompt: .clear, ids: [f.first.id], spaceID: f.here.id, profileID: f.profile.id, focusedTabID: nil,
                               before: lone, after: loneCleared)?.actionName == "Clear Tab")
    }

    @Test func theToastReadsClearedTabsUseCommandZToUndo() {
        let content = ParcToastContent.clearedTabs
        #expect(content.body == .shortcut(leading: "Cleared Tabs! Use", shortcut: "⌘Z", trailing: "to undo."))
        #expect(content.accessibilityText == "Cleared Tabs! Use ⌘Z to undo." && content.showsShortcut)
    }

    @Test func clearAlsoLeavesReopenClosedTabSteps() throws {
        let f = try ClearFixture()
        var closedItems = WindowClosedItems()
        let intent = try #require(ClosedItemIntent(ids: f.hereIDs, state: f.initial, spaceID: f.here.id, profileID: f.profile.id, focusedTabID: f.first.id))
        _ = f.approvedClear()
        closedItems.record(intent, in: f.store.state)
        #expect(closedItems.nextStep(in: f.store.state, restorable: { _ in false }) != nil)
    }

    @Test func everyRestoredTabIsARedoTarget() throws {
        let f = try ClearFixture()
        let record = f.approvedClear()
        let window = FolderUndoManager()
        _ = f.register(record, in: window)
        window.undo()
        #expect(record.redoIDs(in: f.store.state) == f.hereIDs)
    }
}

@MainActor struct ClosedTabsUndoWindowTests {
    @Test func aCommittedClearRegistersOnTheWindowsUndoAndTheEditMenuReadsUndoClearTabs() throws {
        let f = try ClearFixture()
        let record = f.approvedClear()
        let window = FolderUndoManager()
        #expect(f.register(record, in: window))
        #expect(window.canUndo && window.undoMenuItemTitle == "Undo Clear Tabs")
    }

    @Test func aBusyWindowOwnerDisablesUndoWithoutDiscardingIt() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        f.consent.usable = false
        #expect(!window.canUndo)
        f.consent.usable = true
        #expect(window.canUndo)
    }

    @Test func undoCommitsAndRestoresTheExactPreClearRecordsAndSplit() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        #expect(f.consent.undone == 1 && !window.isBusy && f.consent.errors.isEmpty)
        #expect(f.initial.tabs.filter { f.hereIDs.contains($0.id) }.allSatisfy { restored.tabs.contains($0) })
        #expect(restored.splitLayouts == [f.split])
        #expect(SidebarHierarchy.children(in: f.today, state: restored) == SidebarHierarchy.children(in: f.today, state: f.initial))
    }

    @Test func undoRestoresIntoTheClearedSpaceWithoutSelecting() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        let beforeUndo = f.store.state
        window.undo()
        let restored = f.store.state
        #expect(restored.activeSpaceID == f.there.id && restored.selectedTabIDs == beforeUndo.selectedTabIDs
                && restored.selectionBySpace == beforeUndo.selectionBySpace)
    }

    @Test func undoTouchesOnlyTheClearedTabs() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        let beforeUndo = f.store.state
        window.undo()
        let restored = f.store.state
        #expect(restored.recentlyClosedIDs.allSatisfy { !f.hereIDs.contains($0) } && restored.tabs.contains(f.earlier))
        #expect(restored.tabs.filter { !f.hereIDs.contains($0.id) } == beforeUndo.tabs.filter { !f.hereIDs.contains($0.id) })
        #expect(restored.folders == beforeUndo.folders)
    }

    @Test func undoIsOnDiskBeforeItPublishes() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let reloaded = try BrowserStore(directory: f.root)
        let restored = f.store.state
        #expect(reloaded.state.tabs == restored.tabs && reloaded.state.splitLayouts == restored.splitLayouts
                && reloaded.state.sidebarItemOrder == restored.sidebarItemOrder)
    }

    @Test func undoExpiresTheClearsReopenSteps() throws {
        let f = try ClearFixture()
        var closedItems = WindowClosedItems()
        let intent = try #require(ClosedItemIntent(ids: f.hereIDs, state: f.initial, spaceID: f.here.id, profileID: f.profile.id, focusedTabID: f.first.id))
        let (_, window) = f.registeredClear()
        closedItems.record(intent, in: f.store.state)
        window.undo()
        #expect(closedItems.nextStep(in: f.store.state, restorable: { _ in false }) == nil)
    }

    @Test func redoClearTabsFollowsUndo() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        #expect(window.canRedo && !window.canUndo && window.redoMenuItemTitle == "Redo Clear Tabs")
    }

    @Test func redoWaitsForFreshPageConsent() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        window.redo()
        #expect(window.isBusy && f.store.state == restored)
    }

    @Test func aRefusedRedoKeepsTheTabsAndTheRedo() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        window.redo()
        f.consent.finish?(false)
        #expect(!window.isBusy && window.canRedo && f.store.state == restored)
        #expect(f.consent.redoCurrent?() == true)
    }

    @Test func redoArchivesAgainAsAManualCloseAndLeavesAnotherSpacesSelectionAlone() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        window.redo()
        f.consent.approve()
        let redone = f.store.state
        #expect(f.hereIDs.allSatisfy { id in redone.tabs.first { $0.id == id }?.archiveProvenance?.reason == .manual })
        #expect(redone.splitLayouts.isEmpty && redone.activeSpaceID == f.there.id && redone.selectedTabIDs == restored.selectedTabIDs)
    }

    @Test func redoReturnsTheGroupToUndo() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        window.redo()
        f.consent.approve()
        #expect(window.canUndo && !window.canRedo && window.undoMenuItemTitle == "Undo Clear Tabs")
    }

    @Test func undoAfterRedoRestoresTheRedoneClose() throws {
        let f = try ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        window.redo()
        f.consent.approve()
        window.undo()
        #expect(f.initial.tabs.filter { f.hereIDs.contains($0.id) }.allSatisfy { f.store.state.tabs.contains($0) })
        #expect(f.store.state.splitLayouts == [f.split])
        #expect(SidebarHierarchy.children(in: f.today, state: f.store.state) == SidebarHierarchy.children(in: f.today, state: f.initial))
    }

    @Test func theLaterClearUndoesFirstAndItsSpacesOrderReturns() throws {
        let f = try ClearFixture()
        let hereRecord = f.autoClear(f.here)
        f.goToThere()
        let thereRecord = f.autoClear(f.there)
        let stack = FolderUndoManager()
        #expect(f.register(hereRecord, in: stack) && f.register(thereRecord, in: stack))
        stack.undo()
        #expect(f.todayIDs(f.there) == [f.elsewhere.id, f.elsewhereToo.id] && f.todayIDs(f.here).isEmpty)
        #expect(SidebarHierarchy.children(in: f.thereToday, state: f.store.state) == SidebarHierarchy.children(in: f.thereToday, state: f.initial))
    }

    @Test func thenTheEarlierClear() throws {
        let f = try ClearFixture()
        let hereRecord = f.autoClear(f.here)
        f.goToThere()
        let thereRecord = f.autoClear(f.there)
        let stack = FolderUndoManager()
        _ = f.register(hereRecord, in: stack)
        _ = f.register(thereRecord, in: stack)
        stack.undo()
        stack.undo()
        #expect(f.todayIDs(f.here) == f.hereIDs && f.store.state.splitLayouts == [f.split])
    }

    @Test func undoInOneWindowLeavesTheOtherWindowsClear() throws {
        let f = try ClearFixture()
        let windowA = f.autoClear(f.here)
        let windowB = f.autoClear(f.there)
        let firstWindow = FolderUndoManager(), secondWindow = FolderUndoManager()
        #expect(f.register(windowA, in: firstWindow) && f.register(windowB, in: secondWindow))
        firstWindow.undo()
        #expect(f.todayIDs(f.here) == f.hereIDs && f.todayIDs(f.there).isEmpty && secondWindow.canUndo && !firstWindow.canUndo)
        secondWindow.undo()
        #expect(f.todayIDs(f.there) == [f.elsewhere.id, f.elsewhereToo.id])
    }
}

@MainActor struct ClosedTabsUndoReopenTests {
    private struct Partial {
        let f: ClearFixture
        let record: ClosedTabsUndo
        let reopened: Set<UUID>
        let deleted: UUID
        let window: FolderUndoManager
    }

    private func partial() throws -> Partial {
        let f = try ClearFixture()
        f.consent.autoApprove = true
        let intent = try #require(ClosedItemIntent(ids: f.hereIDs, state: f.store.state, spaceID: f.here.id, profileID: f.profile.id, focusedTabID: nil))
        f.clear(f.here)
        let record = try #require(f.record)
        var reopen = WindowClosedItems()
        reopen.record(intent, in: f.store.state)
        guard case .items(let step)? = reopen.nextStep(in: f.store.state, restorable: { _ in false }) else {
            throw CloseUndoFailure("Expected Reopen step")
        }
        #expect(try f.store.restoreClosedItem(step))
        let reopened = Set(step.tabIDs)
        let deleted = try #require([f.first.id, f.last.id].first { !reopened.contains($0) })
        f.store.deleteArchivedTabs([deleted])
        let window = FolderUndoManager()
        #expect(f.register(record, in: window) && window.canUndo)
        f.consent.lastOperation?.didReopen(step)
        return Partial(f: f, record: record, reopened: reopened, deleted: deleted, window: window)
    }

    private struct CloseUndoFailure: Error { let message: String; init(_ message: String) { self.message = message } }

    @Test func oneClearedTabIsDeletedFromTheArchive() throws {
        let p = try partial()
        #expect(!p.f.store.state.tabs.contains { $0.id == p.deleted })
    }

    @Test func undoRestoresTheTabsStillArchivedAsClearedAndLeavesReopenedAndDeletedAsTheyWere() throws {
        let p = try partial()
        let reopenedRecords = p.f.store.state.tabs.filter { p.reopened.contains($0.id) }
        p.window.undo()
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(remaining.allSatisfy { id in p.f.store.state.tabs.contains(p.f.initial.tabs.first { $0.id == id }!) })
        #expect(reopenedRecords.allSatisfy { p.f.store.state.tabs.contains($0) } && !p.f.store.state.tabs.contains { $0.id == p.deleted })
    }

    @Test func eachLiveTodayTabAppearsOnce() throws {
        let p = try partial()
        p.window.undo()
        let f = p.f
        let order = SidebarHierarchy.children(in: f.today, state: f.store.state)
        #expect(Set(order).count == order.count)
        #expect(order.flatMap { SidebarHierarchy.tabIDs(in: $0, state: f.store.state, spaceID: f.here.id) }.count == f.todayIDs(f.here).count)
    }

    @Test func redoIsNamedByTheGroupsRemainingItems() throws {
        let p = try partial()
        p.window.undo()
        #expect(p.window.redoMenuItemTitle == "Redo " + ClosedTabsUndo.Prompt.clear.name(count: p.record.itemCount(of: p.f.hereIDs.subtracting(p.reopened))))
    }

    @Test func redoArchivesOnlyWhatUndoRestoredAndTheRedoneCloseIsNamedByItsOwnItems() throws {
        let p = try partial()
        p.window.undo()
        p.window.redo()
        let f = p.f
        let remaining = f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(p.reopened.allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }
                && remaining.allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } })
        #expect(p.window.undoMenuItemTitle == "Undo " + ClosedTabsUndo.Prompt.clear.name(
            count: remaining.count + (remaining.isSuperset(of: [f.left.id, f.right.id]) ? 1 : 0)))
    }

    @Test func undoAfterThatRedoRestoresTheSameTabs() throws {
        let p = try partial()
        p.window.undo()
        p.window.redo()
        p.window.undo()
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(remaining.isSubset(of: p.f.todayIDs(p.f.here)))
    }

    @Test func redoNeverArchivesATabPinnedSince() throws {
        let p = try partial()
        p.window.undo()
        var moved = p.f.store.state
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        if let index = moved.tabs.firstIndex(where: { $0.id == remaining.first }) { moved.tabs[index].kind = .pinned }
        #expect(!p.record.redoIDs(in: moved).contains(remaining.first ?? UUID()))
    }
}

@MainActor struct ClosedTabsPutBackTests {
    private func putBack() throws -> (ClearFixture, FolderUndoManager, Set<UUID>, UUID) {
        let f = try ClearFixture()
        let live = f.todayIDs(f.here)
        let record = f.autoClear(f.here)
        let window = FolderUndoManager()
        #expect(f.register(record, in: window))
        let returned = try #require([f.first.id, f.last.id].first { live.contains($0) })
        #expect(!f.store.restoreArchivedTab(returned, destination: .putBack(currentSpaceID: f.here.id, requestedSpaceID: f.here.id)).isEmpty
                && f.store.state.tabs.contains { $0.id == returned && $0.archivedAt == nil })
        return (f, window, live, returned)
    }

    @Test func undoRestoresTheRestAfterAPutBack() throws {
        let (f, window, live, _) = try putBack()
        window.undo()
        #expect(f.todayIDs(f.here) == live)
    }

    @Test func redoArchivesThePutBackTabAgain() throws {
        let (f, window, live, _) = try putBack()
        window.undo()
        window.redo()
        #expect(live.allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } })
    }

    @Test func undoRestoresThemAllAgain() throws {
        let (f, window, live, _) = try putBack()
        window.undo()
        window.redo()
        window.undo()
        #expect(f.todayIDs(f.here) == live)
    }
}

@MainActor struct ClosedTabsRestoringTests {
    private func cleared() throws -> (ClearFixture, ClosedTabsUndo, BrowserState) {
        let f = try ClearFixture()
        let record = f.approvedClear()
        return (f, record, f.store.state)
    }

    @Test func anArchivedTabEditedSinceComesBackWithItsEdits() throws {
        let (f, record, cleared) = try cleared()
        var edited = cleared
        if let index = edited.tabs.firstIndex(where: { $0.id == f.first.id }) {
            edited.tabs[index].title = "Edited in the Library"
            edited.tabs[index].url = "https://edited.invalid/"
        }
        let editedBack = try #require(record.restoring(edited)?.tabs.first { $0.id == f.first.id })
        #expect(record.restorableIDs(in: edited).contains(f.first.id) && editedBack.title == "Edited in the Library")
        #expect(editedBack.url == "https://edited.invalid/" && editedBack.archivedAt == nil && editedBack.archiveProvenance == nil
                && editedBack.kind == .today)
    }

    @Test func aTabArchivedAgainSinceIsNotThisClears() throws {
        let (f, record, cleared) = try cleared()
        var rearchived = cleared
        if let index = rearchived.tabs.firstIndex(where: { $0.id == f.first.id }) {
            rearchived.tabs[index].archivedAt = Date(timeIntervalSince1970: 2_000_000_000)
        }
        #expect(!record.restorableIDs(in: rearchived).contains(f.first.id))
    }

    @Test func aSplitThatCannotRegroupReturnsItsRemainingPaneAloneInPlace() throws {
        let (f, record, cleared) = try cleared()
        var halfGone = cleared
        halfGone.tabs.removeAll { $0.id == f.right.id }
        let alone = try #require(record.restoring(halfGone))
        #expect(alone.splitLayouts.isEmpty)
        #expect(SidebarHierarchy.children(in: f.today, state: alone) == [.tab(f.last.id), .tab(f.left.id), .tab(f.first.id)])
    }

    @Test func restoredItemsTakeTheirPlacesAroundATabOpenedSince() throws {
        let (f, record, cleared) = try cleared()
        var joined = cleared
        let later = makeTab("Later", f.here, profile: f.profile)
        joined.tabs.append(later)
        joined.sidebarItemOrder[f.today.key] = [.tab(later.id)]
        let survivor = try #require(record.restoring(joined))
        #expect(SidebarHierarchy.children(in: f.today, state: survivor) == [.tab(f.last.id), .split(f.split.id), .tab(f.first.id), .tab(later.id)])
    }
}

@MainActor struct ClosedTabsUndoFailureTests {
    private func failing() throws -> (ClearFixture, FolderUndoManager, Set<UUID>) {
        let f = try ClearFixture()
        let live = f.todayIDs(f.here)
        _ = f.store.setWindowPresentation(spaceID: f.there.id, selectedTabIDs: [])
        let record = f.autoClear(f.here)
        let window = FolderUndoManager()
        #expect(f.register(record, in: window))
        return (f, window, live)
    }

    private func breakDisk(_ f: ClearFixture) throws -> Data {
        let bytes = try Data(contentsOf: f.sessionURL)
        try FileManager.default.removeItem(at: f.sessionURL)
        try FileManager.default.createDirectory(at: f.sessionURL, withIntermediateDirectories: false)
        return bytes
    }

    private func repair(_ f: ClearFixture, _ bytes: Data) throws {
        try FileManager.default.removeItem(at: f.sessionURL)
        try bytes.write(to: f.sessionURL)
    }

    @Test func aFailedWriteKeepsTheClearArchivedAndUndoRetryable() throws {
        let (f, window, _) = try failing()
        _ = try breakDisk(f)
        let archivedBefore = f.store.state
        window.undo()
        #expect(f.consent.errors.count == 1 && f.store.state == archivedBefore && window.canUndo)
    }

    @Test func retryRestores() throws {
        let (f, window, live) = try failing()
        let bytes = try breakDisk(f)
        window.undo()
        try repair(f, bytes)
        window.undo()
        #expect(f.todayIDs(f.here) == live && window.canRedo)
    }

    @Test func archivingTheRestoredTabsByHandRetiresTheRedo() throws {
        let (f, window, live) = try failing()
        window.undo()
        f.store.closeTabs(live, reason: .manual, shouldCommit: { true })
        #expect(!window.canRedo && !window.canUndo)
    }

    @Test func aRedoWaitingForPageConsentFinishesOnApproval() throws {
        let f = try ClearFixture()
        _ = f.store.setWindowPresentation(spaceID: f.there.id, selectedTabIDs: [])
        let record = f.autoClear(f.there)
        let busy = FolderUndoManager()
        #expect(f.register(record, in: busy))
        f.consent.autoApprove = false
        busy.undo()
        busy.redo()
        #expect(busy.isBusy && busy.isRedoing)
        f.consent.approve()
        #expect(!busy.isBusy && busy.canUndo)
    }
}

@MainActor private final class SideFixture {
    let consent = Consent()
    let root: URL
    let profile = BrowserProfile(id: UUID(), name: "Original")
    let side: BrowserSpace
    let sidePinned: BrowserTab, a: BrowserTab, b: BrowserTab, c: BrowserTab, d: BrowserTab, e: BrowserTab
    let trio: BrowserSplitLayout
    let sideToday: SidebarContainerLocation
    let store: BrowserStore
    let initial: BrowserState
    let order: [SidebarItemReference]

    init() throws {
        root = try temporaryRoot()
        side = BrowserSpace(id: UUID(), name: "Side", symbol: "circle", color: "FEDCBA", profileID: profile.id)
        let profile = profile, side = side
        sidePinned = makeTab("Side pinned", side, profile: profile, kind: .pinned)
        a = makeTab("A", side, profile: profile)
        b = makeTab("B", side, profile: profile)
        c = makeTab("C", side, profile: profile)
        d = makeTab("D", side, profile: profile)
        e = makeTab("E", side, profile: profile)
        trio = BrowserSplitLayout(sidebarAnchorID: a.id, customTitle: "Trio", spaceID: side.id,
                                  tabIDs: [a.id, b.id, c.id], orientation: .horizontal, widthFactors: [0.2, 0.3, 0.5])
        var seed = BrowserState(profiles: [profile], spaces: [side], activeSpaceID: side.id)
        seed.tabs = [sidePinned, a, b, c, d, e]
        seed.splitLayouts = [trio]
        sideToday = SidebarContainerLocation(spaceID: side.id, folderID: nil, section: .today)
        seed.sidebarItemOrder[sideToday.key] = [.tab(e.id), .tab(a.id), .tab(d.id)]
        seed.selectedTabIDs = trio.tabIDs
        seed.selectionBySpace[side.id.uuidString] = trio.tabIDs
        _ = try writeSeed(seed, to: root)
        store = try BrowserStore(directory: root, now: storeClock)
        consent.attach(store)
        initial = store.state
        order = SidebarHierarchy.children(in: sideToday, state: initial)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func clear(_ ids: Set<UUID>) -> ClosedTabsUndo? {
        var made: ClosedTabsUndo?
        let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: store.state.activeSpaceID,
            profileID: profile.id, state: store.state, selected: store.state.selectedTabIDs,
            focused: store.state.selectedTabIDs.last, available: { _ in true })
        store.closeTabs(ids, reason: .clearButton, selection: selection, didCommit: { [unowned self] before in
            made = ClosedTabsUndo(prompt: .clear, ids: ids, spaceID: side.id, profileID: profile.id, focusedTabID: nil,
                                  before: before, after: store.state)
        }, shouldCommit: { true })
        return made
    }

    func register(_ record: ClosedTabsUndo) -> FolderUndoManager {
        let manager = FolderUndoManager()
        #expect(consent.register(record, in: manager, on: store))
        return manager
    }
}

@MainActor struct ClosedTabsSplitUndoTests {
    @Test func theTrioIsTheSelectedSplit() throws {
        let f = try SideFixture()
        #expect(f.order == [.tab(f.e.id), .split(f.trio.id), .tab(f.d.id)] && f.initial.selectedTabIDs == f.trio.tabIDs)
    }

    @Test func clearingTheSelectedSplitSelectsThePinnedTab() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        _ = try #require(f.clear([f.a.id, f.b.id, f.c.id, f.d.id, f.e.id]))
        #expect(f.store.state.selectedTabIDs == [f.sidePinned.id] && f.store.state.splitLayouts.isEmpty)
    }

    @Test func undoWithTheClearedSpaceActiveKeepsTheReplacementSelectedAndTheSplitReturnsWhole() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let whole = try #require(f.clear([f.a.id, f.b.id, f.c.id, f.d.id, f.e.id]))
        let replacement = f.store.state.selectedTabIDs
        f.register(whole).undo()
        #expect(f.store.state.activeSpaceID == f.side.id && f.store.state.selectedTabIDs == replacement)
        #expect(f.store.state.splitLayouts == f.initial.splitLayouts)
        #expect(SidebarHierarchy.children(in: f.sideToday, state: f.store.state) == f.order)
    }

    @Test func clearingOnePaneLeavesTheSplitsOtherTwoAndIsOneItem() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let one = try #require(f.clear([f.a.id]))
        #expect(one.actionName == "Clear Tab")
        #expect(f.store.state.splitLayouts.first { $0.id == f.trio.id }?.tabIDs == [f.b.id, f.c.id] && one.memberships[f.a.id]?.dissolved == false)
    }

    @Test func undoPutsAPaneBackIntoItsSplitAtItsPlaceShareAndSidebarSlot() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let one = try #require(f.clear([f.a.id]))
        f.register(one).undo()
        let rejoined = f.store.state.splitLayouts.first { $0.id == f.trio.id }
        #expect(rejoined?.tabIDs == f.trio.tabIDs && rejoined?.sidebarAnchorID == f.trio.sidebarAnchorID)
        #expect(zip(rejoined?.widthFactors ?? [], f.trio.widthFactors).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(SidebarHierarchy.children(in: f.sideToday, state: f.store.state) == f.order)
    }

    @Test func clearingTwoPanesDissolvesTheSplitAndNamesClearTabs() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let pair = try #require(f.clear([f.a.id, f.b.id]))
        #expect(!f.store.state.splitLayouts.contains { $0.id == f.trio.id } && pair.memberships[f.a.id]?.dissolved == true)
        #expect(pair.actionName == "Clear Tabs")
    }

    @Test func undoRegroupsTheSplitTheClearDissolved() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let beforePair = f.store.state.splitLayouts.first { $0.id == f.trio.id }
        let pair = try #require(f.clear([f.a.id, f.b.id]))
        f.register(pair).undo()
        let regrouped = f.store.state.splitLayouts.first { $0.id == f.trio.id }
        #expect(regrouped != nil && regrouped == beforePair)
        #expect(SidebarHierarchy.children(in: f.sideToday, state: f.store.state) == f.order)
    }

    @Test func aRefusedRedoKeepsItsTabsAndCheckAndTheCheckFailsOnceATabIsPinned() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let loose = try #require(f.clear([f.d.id, f.e.id]))
        let window = f.register(loose)
        window.undo()
        f.consent.autoApprove = false
        window.redo()
        f.consent.finish?(false)
        #expect(window.canRedo && f.consent.redoCurrent?() == true)
        f.store.setKind(f.d.id, .pinned)
        #expect(f.consent.redoCurrent?() == false)
    }

    @Test func redoThenArchivesOnlyTheTabStillInToday() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let loose = try #require(f.clear([f.d.id, f.e.id]))
        let window = f.register(loose)
        window.undo()
        f.store.setKind(f.d.id, .pinned)
        window.redo()
        #expect(f.store.state.tabs.first { $0.id == f.d.id }.map { $0.kind == .pinned && $0.archivedAt == nil } == true)
        #expect(f.store.state.tabs.first { $0.id == f.e.id }?.archivedAt != nil)
    }

    @Test func withTheOtherPanesBusyElsewhereThePaneComesBackAloneBesideTheSplit() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        f.consent.refused = [f.b.id, f.c.id]
        let foreign = try #require(f.clear([f.a.id]))
        f.register(foreign).undo()
        #expect(f.store.state.splitLayouts.first { $0.id == f.trio.id }?.tabIDs == [f.b.id, f.c.id])
        #expect(SidebarHierarchy.children(in: f.sideToday, state: f.store.state) == [.split(f.trio.id), .tab(f.a.id)])
    }

    @Test func aPaneThatDissolvesItsSplitNamesTheSplitToo() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        _ = try #require(f.clear([f.a.id]))
        let lastPair = try #require(f.clear([f.b.id]))
        #expect(lastPair.actionName == "Clear Tabs")
    }

    @Test func undoDoesNotRegroupASplitWhoseLastOtherPaneIsBusyElsewhere() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        _ = try #require(f.clear([f.a.id]))
        f.consent.refused = [f.c.id]
        let lastPair = try #require(f.clear([f.b.id]))
        f.register(lastPair).undo()
        #expect(!f.store.state.splitLayouts.contains { $0.id == f.trio.id })
        #expect([f.b.id, f.c.id].allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } })
    }
}

@MainActor private final class ArchiveFixture {
    let consent = Consent()
    let root: URL
    let profile = BrowserProfile(id: UUID(), name: "Original")
    let work: BrowserSpace
    let shelf: BrowserFolder
    let note: BrowserTab, shelved: BrowserTab, keep: BrowserTab
    let t1: BrowserTab, t2: BrowserTab, t3: BrowserTab, s1: BrowserTab, s2: BrowserTab
    let duo: BrowserSplitLayout
    let workToday: SidebarContainerLocation, shelfBox: SidebarContainerLocation
    let store: BrowserStore
    let original: [SidebarItemReference]

    init() throws {
        root = try temporaryRoot()
        work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "FFEEDD", profileID: profile.id)
        shelf = BrowserFolder(id: UUID(), spaceID: work.id, name: "Shelf")
        let profile = profile, work = work, shelf = shelf
        var noteTab = makeTab("Note", work, profile: profile, kind: .pinned, folder: shelf.id)
        noteTab.url = "parc://note/" + UUID().uuidString.lowercased()
        noteTab.savedURL = noteTab.url
        note = noteTab
        shelved = makeTab("Shelved", work, profile: profile, kind: .pinned, folder: shelf.id)
        keep = makeTab("Keep", work, profile: profile, kind: .pinned)
        t1 = makeTab("T1", work, profile: profile)
        t2 = makeTab("T2", work, profile: profile)
        t3 = makeTab("T3", work, profile: profile)
        s1 = makeTab("S1", work, profile: profile)
        s2 = makeTab("S2", work, profile: profile)
        duo = BrowserSplitLayout(sidebarAnchorID: s1.id, customTitle: "Duo", spaceID: work.id,
                                 tabIDs: [s1.id, s2.id], orientation: .horizontal, widthFactors: [0.4, 0.6])
        var seed = BrowserState(profiles: [profile], spaces: [work], activeSpaceID: work.id)
        seed.folders = [shelf]
        seed.tabs = [note, shelved, keep, t1, t2, t3, s1, s2]
        seed.splitLayouts = [duo]
        workToday = SidebarContainerLocation(spaceID: work.id, folderID: nil, section: .today)
        let workPinned = SidebarContainerLocation(spaceID: work.id, folderID: nil, section: .pinned)
        shelfBox = SidebarContainerLocation(spaceID: work.id, folderID: shelf.id, section: .pinned)
        seed.sidebarItemOrder[workToday.key] = [.tab(t1.id), .tab(s1.id), .tab(t2.id), .tab(t3.id)]
        seed.sidebarItemOrder[workPinned.key] = [.folder(shelf.id), .tab(keep.id)]
        seed.sidebarItemOrder[shelfBox.key] = [.tab(note.id), .tab(shelved.id)]
        seed.selectedTabIDs = [t2.id]
        seed.selectionBySpace[work.id.uuidString] = [t2.id]
        _ = try writeSeed(seed, to: root)
        store = try BrowserStore(directory: root, now: storeClock)
        consent.attach(store)
        consent.autoApprove = true
        original = SidebarHierarchy.children(in: workToday, state: store.state)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var order: [SidebarItemReference] { SidebarHierarchy.children(in: workToday, state: store.state) }

    func close(_ ids: Set<UUID>, focused: UUID?, prompt: ClosedTabsUndo.Prompt = .archive) -> ClosedTabsUndo? {
        var made: ClosedTabsUndo?
        let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: store.state.activeSpaceID,
            profileID: profile.id, state: store.state, selected: store.state.selectedTabIDs,
            focused: store.state.selectedTabIDs.last, available: { _ in true })
        store.closeTabs(ids, reason: prompt == .clear ? .clearButton : .manual, selection: selection, didCommit: { [unowned self] before in
            made = ClosedTabsUndo(prompt: prompt, ids: ids, spaceID: work.id, profileID: profile.id,
                                  focusedTabID: focused, before: before, after: store.state)
        }, shouldCommit: { true })
        return made
    }

    func register(_ record: ClosedTabsUndo, in manager: FolderUndoManager = FolderUndoManager()) -> FolderUndoManager {
        #expect(consent.register(record, in: manager, on: store) || consent.lastOperation == nil)
        return manager
    }

    func select(_ ids: [UUID]) {
        _ = store.setWindowPresentation(spaceID: work.id, selectedTabIDs: ids)
    }
}

@MainActor struct ClosedTabsArchiveUndoTests {
    @Test func theFixtureHasASplitBetweenTodayTabs() throws {
        let f = try ArchiveFixture()
        #expect(f.original == [.tab(f.t1.id), .split(f.duo.id), .tab(f.t2.id), .tab(f.t3.id)])
    }

    @Test func commandWOnTheFocusedTabIsOneArchiveTabGroupThatRemembersItsFocus() throws {
        let f = try ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        #expect(focusedClose.prompt == .archive && focusedClose.actionName == "Archive Tab" && focusedClose.focusedTabID == f.t2.id)
        #expect(f.store.state.tabs.first { $0.id == f.t2.id }?.archiveProvenance?.reason == .manual)
        #expect(f.register(focusedClose).undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func undoReturnsTheTabToItsPlaceAndTheStoreLeavesSelectionToTheWindow() throws {
        let f = try ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let window = f.register(focusedClose)
        let selectedAfterClose = f.store.state.selectedTabIDs
        window.undo()
        #expect(f.order == f.original && f.store.state.tabs.contains(f.t2))
        #expect(f.store.state.selectedTabIDs == selectedAfterClose)
    }

    @Test func theWindowSelectsTheTabThatWasFocusedWhenItClosed() throws {
        let f = try ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        var presented = WindowPresentation(state: f.store.state, ready: true)
        f.register(focusedClose).undo()
        let finished = presented.finishClosedTabsUndo(focusedClose, state: f.store.state, available: { _ in true })
        #expect(finished && presented.selectedTabIDs == [f.t2.id])
    }

    @Test func redoArchivesItAgainAndReturnsTheGroupToUndo() throws {
        let f = try ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let window = f.register(focusedClose)
        window.undo()
        #expect(window.redoMenuItemTitle == "Redo Archive Tab")
        window.redo()
        #expect(f.store.state.tabs.first { $0.id == f.t2.id }?.archivedAt != nil && window.undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func aTabThatWasntFocusedRecordsNoFocusAndItsUndoSelectsNothing() throws {
        let f = try ArchiveFixture()
        f.select([f.t1.id])
        let background = try #require(f.close([f.t3.id], focused: f.t1.id))
        var unfocused = WindowPresentation(state: f.store.state, ready: true)
        #expect(background.focusedTabID == nil)
        f.register(background).undo()
        let selected = unfocused.finishClosedTabsUndo(background, state: f.store.state, available: { _ in true })
        #expect(f.order == f.original && !selected && unfocused.selectedTabIDs == [f.t1.id])
    }

    @Test func closingAPinnedTabOnlyUnloadsItSoItRegistersNoUndo() throws {
        let f = try ArchiveFixture()
        #expect(f.close([f.keep.id], focused: f.keep.id) == nil && f.store.state.tabs.contains { $0.id == f.keep.id && $0.archivedAt == nil })
    }

    @Test func aPaneWhoseCloseDissolvesItsSplitNamesTheSplitTooAndTheOtherPaneKeepsTheSlot() throws {
        let f = try ArchiveFixture()
        let paneClose = try #require(f.close([f.s1.id], focused: nil))
        #expect(paneClose.actionName == "Archive Tabs" && !f.store.state.splitLayouts.contains { $0.id == f.duo.id })
        #expect(f.order == [.tab(f.t1.id), .tab(f.s2.id), .tab(f.t2.id), .tab(f.t3.id)])
    }

    @Test func undoRegroupsTheSplitInItsSlot() throws {
        let f = try ArchiveFixture()
        let paneClose = try #require(f.close([f.s1.id], focused: nil))
        f.register(paneClose).undo()
        #expect(f.store.state.splitLayouts == [f.duo] && f.order == f.original)
    }

    @Test func aPinnedNoteOnlyUnloadsInItsFolderSoItRegistersNoUndoEither() throws {
        let f = try ArchiveFixture()
        #expect(f.close([f.note.id], focused: f.note.id) == nil)
        #expect(f.store.state.tabs.contains { $0.id == f.note.id && $0.archivedAt == nil && $0.kind == .pinned })
        #expect(SidebarHierarchy.children(in: f.shelfBox, state: f.store.state) == [.tab(f.note.id), .tab(f.shelved.id)])
    }

    @Test func theLaterCloseIsOnTopAndUndoRestoresItThenOffersTheClear() throws {
        let f = try ArchiveFixture()
        f.select([f.t2.id])
        let clearedAgain = try #require(f.close([f.t1.id, f.t3.id, f.s1.id, f.s2.id], focused: nil, prompt: .clear))
        let lastClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let ordered = f.register(clearedAgain)
        _ = f.register(lastClose, in: ordered)
        #expect(ordered.undoMenuItemTitle == "Undo Archive Tab")
        ordered.undo()
        #expect(f.store.state.tabs.contains { $0.id == f.t2.id && $0.archivedAt == nil }
                && f.store.state.tabs.first { $0.id == f.t1.id }?.archivedAt != nil && ordered.undoMenuItemTitle == "Undo Clear Tabs")
        ordered.undo()
        #expect(f.order == f.original)
    }

    @Test func aMixedCloseArchivesOnlyTheTodayTabAndThePinnedOneUnloadsInPlace() throws {
        let f = try ArchiveFixture()
        let mixedClose = try #require(f.close([f.keep.id, f.t3.id], focused: nil))
        #expect(mixedClose.tabs.map(\.id) == [f.t3.id] && mixedClose.actionName == "Archive Tab")
        #expect(f.store.state.tabs.contains { $0.id == f.keep.id && $0.archivedAt == nil && $0.kind == .pinned })
        f.register(mixedClose).undo()
        #expect(f.store.state.tabs.contains { $0.id == f.t3.id && $0.archivedAt == nil }
                && f.store.state.tabs.contains { $0.id == f.keep.id && $0.archivedAt == nil && $0.kind == .pinned })
    }

    @Test func aClearThatTakesTheFocusedTodayTabRemembersItAndUndoSelectsIt() throws {
        let f = try ArchiveFixture()
        f.select([f.t2.id])
        let todayLive = Set(f.store.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == f.work.id }.map(\.id))
        let focusedClear = try #require(f.close(todayLive, focused: f.t2.id, prompt: .clear))
        #expect(todayLive.contains(f.t2.id) && focusedClear.prompt == .clear && focusedClear.focusedTabID == f.t2.id)
        var afterClear = WindowPresentation(state: f.store.state, ready: true)
        f.register(focusedClear).undo()
        let finished = afterClear.finishClosedTabsUndo(focusedClear, state: f.store.state, available: { _ in true })
        #expect(finished && afterClear.selectedTabIDs == [f.t2.id])
    }

    @Test func aClearRegistersAndUndoRestoresIt() throws {
        let f = try ArchiveFixture()
        let cleanAll = try #require(f.close([f.t1.id, f.t3.id, f.s1.id, f.s2.id, f.t2.id], focused: nil, prompt: .clear))
        f.register(cleanAll).undo()
        #expect(f.order == f.original)
    }

    @Test func aNewGroupWaitsForARedoWithNoToastYetThenJoinsOnceItFinishes() throws {
        let f = try ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        #expect(deferred.isRedoing)
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        #expect(!f.consent.register(meanwhile, in: deferred, on: f.store) && f.consent.lastOperation == nil)
        f.consent.approve()
        #expect(f.consent.lastOperation != nil && !deferred.isBusy)
    }

    @Test func theRedoneCloseCompletedLastSoItIsOnTopAndThenTheCloseThatCommittedDuringTheRedo() throws {
        let f = try ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: deferred, on: f.store)
        f.consent.approve()
        deferred.undo()
        #expect(f.store.state.tabs.contains { $0.id == f.t1.id && $0.archivedAt == nil } && f.store.state.tabs.first { $0.id == f.t3.id }?.archivedAt != nil)
        deferred.undo()
        #expect(f.order == f.original)
    }

    @Test func aRefusedRedoLetsTheWaitingGroupInWhichClearsTheRedo() throws {
        let f = try ArchiveFixture()
        let window = FolderUndoManager()
        let second = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(second, in: window)
        window.undo()
        f.consent.autoApprove = false
        window.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: window, on: f.store)
        f.consent.finish?(false)
        #expect(!window.isBusy && !window.canRedo && window.canUndo)
        window.undo()
        #expect(f.order == f.original)
    }
}

@MainActor struct ClosedTabsPrivateUndoTests {
    private struct Rig {
        let root: URL
        let consent = Consent()
        let store: BrowserStore
        let p1: UUID, p2: UUID, p3: UUID
        let space: UUID, profile: UUID
        let location: SidebarContainerLocation
        let order: [SidebarItemReference]
        let records: [BrowserTab]

        @MainActor init() throws {
            root = try temporaryRoot()
            let parent = BrowserProfile(id: UUID(), name: "Original")
            store = BrowserStore(privateParentProfileID: parent.id, engineProfilePath: root.appendingPathComponent("otr").path,
                                 directory: root, settings: BrowserState.initial().settings)
            consent.attach(store)
            p3 = store.openResolvedURL(URL(string: "https://three.invalid/")!)
            p2 = store.openResolvedURL(URL(string: "https://two.invalid/")!)
            p1 = store.openResolvedURL(URL(string: "https://one.invalid/")!)
            space = store.activeSpaceID
            profile = store.activeSpace.profileID
            location = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            order = SidebarHierarchy.children(in: location, state: store.state)
            records = store.state.tabs
        }

        @MainActor func closeOne() -> ClosedTabsUndo? {
            var record: ClosedTabsUndo?
            store.closeTabs([p2], didCommit: { before in
                record = ClosedTabsUndo(prompt: .archive, ids: [p2], spaceID: space, profileID: profile,
                                        focusedTabID: nil, before: before, after: store.state)
            }, shouldCommit: { true })
            return record
        }
    }

    @Test func theFixtureHasThreePrivateTabs() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        #expect(rig.order == [.tab(rig.p1), .tab(rig.p2), .tab(rig.p3)])
    }

    @Test func aPrivateCloseRemovesTheTabAndRecordsIt() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = rig.closeOne()
        #expect(!rig.store.state.tabs.contains { $0.id == rig.p2 } && record?.actionName == "Archive Tab" && record?.archivedTabs.isEmpty == true)
    }

    @Test func aPrivateWindowsCloseJoinsItsUndoAndUndoPutsTheTabBackInPlace() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = try #require(rig.closeOne())
        let window = FolderUndoManager()
        #expect(rig.consent.register(record, in: window, on: rig.store) && window.undoMenuItemTitle == "Undo Archive Tab")
        window.undo()
        #expect(rig.store.state.tabs.first { $0.id == rig.p2 } == rig.records.first { $0.id == rig.p2 })
        #expect(SidebarHierarchy.children(in: rig.location, state: rig.store.state) == rig.order)
    }

    @Test func redoRemovesItAgain() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = try #require(rig.closeOne())
        let window = FolderUndoManager()
        _ = rig.consent.register(record, in: window, on: rig.store)
        window.undo()
        window.redo()
        #expect(!rig.store.state.tabs.contains { $0.id == rig.p2 } && window.canUndo)
    }

    @Test func aPrivateClearRemovesEveryTabRegistersAndUndoReturnsThemAll() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        var privateClear: ClosedTabsUndo?
        rig.store.closeTabs([rig.p1, rig.p2, rig.p3], reason: .clearButton, didCommit: { before in
            privateClear = ClosedTabsUndo(prompt: .clear, ids: [rig.p1, rig.p2, rig.p3], spaceID: rig.space, profileID: rig.profile,
                                          focusedTabID: nil, before: before, after: rig.store.state)
        }, shouldCommit: { true })
        #expect(rig.store.state.tabs.isEmpty && privateClear?.actionName == "Clear Tabs")
        let window = FolderUndoManager()
        #expect(rig.consent.register(try #require(privateClear), in: window, on: rig.store))
        window.undo()
        #expect(SidebarHierarchy.children(in: rig.location, state: rig.store.state) == rig.order)
    }
}

@MainActor private final class PeekRig {
    let f: ArchiveFixture
    let record: ClosedPeekRecord
    var opened: [ClosedPeekRecord] = []
    var openWorks = false
    var closeRequests: [UUID] = []
    var closeWorks = true
    var livePeeks = Set<UUID>()
    var parentElsewhere = false
    var parentMoves: [() -> Void] = []

    init() throws {
        f = try ArchiveFixture()
        record = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/a")!, parentTabID: f.t1.id, profileID: f.profile.id)
    }

    func append(to manager: FolderUndoManager, appended: @escaping (ClosedPeekUndoOperation) -> Void) {
        manager.appendClosedPeek(record, state: { [unowned self] in f.store.state }, canOpen: { _ in true }, open: { [unowned self] operation, done in
            let openHere = { [unowned self] in
                opened.append(operation.record)
                guard openWorks else { done(false); return }
                let adopted = UUID()
                livePeeks.insert(adopted)
                operation.openedPeek = adopted
                done(true)
            }
            guard parentElsewhere else { openHere(); return }
            parentMoves.append(openHere)
        }, isOpen: { [unowned self] operation in operation.openedPeek.map(livePeeks.contains) == true },
           canClose: { [unowned self] operation in operation.openedPeek.map(livePeeks.contains) == true }, close: { [unowned self] operation, done in
            closeRequests.append(operation.openedPeek!)
            guard closeWorks else { done(nil); return }
            livePeeks.remove(operation.openedPeek!)
            done(ClosedPeekRecord(id: UUID(), url: operation.record.url, parentTabID: operation.record.parentTabID,
                                  profileID: operation.record.profileID))
        }, appended: appended)
    }
}

@MainActor struct ClosedPeekUndoTests {
    @Test func aClosedPeekReadsUndoClosePeek() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        #expect(operation != nil && window.undoMenuItemTitle == "Undo Close Peek")
    }

    @Test func aPeekThatCantOpenKeepsItsUndo() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        window.undo()
        #expect(rig.opened == [rig.record] && window.canUndo && !window.canRedo)
    }

    @Test func undoOpensItAgainAndRemembersThatPeekAndRedoClosePeekFollows() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        #expect(rig.opened.count == 1 && operation?.openedPeek != nil && window.redoMenuItemTitle == "Redo Close Peek")
    }

    @Test func aRefusedCloseKeepsTheRedo() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        let reopenedPeek = try #require(operation?.openedPeek)
        rig.closeWorks = false
        window.redo()
        #expect(rig.closeRequests == [reopenedPeek] && window.canRedo)
    }

    @Test func redoClosesThePeekUndoOpenedNotAnotherOverTheSameParentAndTakesThatClosesRecord() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        let reopenedPeek = try #require(operation?.openedPeek)
        let otherPeek = UUID()
        rig.livePeeks.insert(otherPeek)
        rig.closeWorks = false
        window.redo()
        rig.closeWorks = true
        window.redo()
        #expect(rig.closeRequests == [reopenedPeek, reopenedPeek] && rig.livePeeks == [otherPeek] && window.canUndo)
        #expect(operation?.record.id != rig.record.id && operation?.openedPeek == nil)
    }

    @Test func onceReopenClosedTabTookThePeeksStepUndoHasNothingLeft() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        window.redo()
        let taken = try #require(operation)
        taken.didReopen(taken.record)
        #expect(!window.canUndo)
    }

    @Test func undoForAPeekWhosePageLivesInAnotherWindowWaitsWhileThatPageMovesHere() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.parentElsewhere = true
        rig.openWorks = true
        window.undo()
        #expect(window.isBusy && !window.canUndo && !window.canRedo && rig.parentMoves.count == 1 && rig.opened.isEmpty)
        rig.parentMoves.removeFirst()()
        #expect(!window.isBusy && operation?.openedPeek != nil && window.redoMenuItemTitle == "Redo Close Peek")
    }

    @Test func aMoveOrPeekThatDoesntWorkOutLeavesUndoClosePeekOfferedUntouched() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        rig.parentElsewhere = true
        window.undo()
        #expect(window.isBusy && rig.parentMoves.count == 1)
        rig.parentMoves.removeFirst()()
        #expect(!window.isBusy && window.canUndo && !window.canRedo && window.undoMenuItemTitle == "Undo Close Peek")
    }

    @Test func aReopenedPeekThatLeftSomeOtherWayLeavesNothingToRedo() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        rig.livePeeks.remove(try #require(operation?.openedPeek))
        #expect(!window.canRedo)
    }

    @Test func aPeekWhoseParentLeftTheSidebarCantComeBack() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        _ = rig.f.close([rig.f.t1.id], focused: nil)
        #expect(!window.canUndo)
    }
}

struct ClosedPageHistoryTests {
    private let pageA = UUID(), pageB = UUID(), pageC = UUID()
    private let entriesA = NSObject(), entriesB = NSObject(), entriesC = NSObject()

    @Test func aClosedTabsEntriesWaitForUndoOrReopen() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageA, state: entriesA)
        #expect(history.takeRestored(pageA) == nil)
    }

    @Test func aRestoredTabsFirstPageTakesThemOnce() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageA, state: entriesA)
        history.restore([pageA])
        #expect(history.takeRestored(pageA) === entriesA && history.takeRestored(pageA) == nil)
    }

    @Test func theOldestGoPastTheLimit() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageA, state: entriesA)
        history.closed(pageB, state: entriesB)
        history.closed(pageC, state: entriesC)
        history.restore([pageA, pageB, pageC])
        #expect(history.takeRestored(pageA) == nil && history.takeRestored(pageB) === entriesB)
    }

    @Test func closingAgainWaitsForANewRestoreAndAClosedPeeksAreTakenByItsRecord() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageC, state: entriesA)
        #expect(history.takeRestored(pageC) == nil && history.take(pageC) === entriesA)
    }

    @Test func aReopenThatFailedGivesNoEntries() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageB, state: entriesB)
        history.restore([pageB])
        history.unrestore([pageB])
        #expect(history.takeRestored(pageB) == nil)
    }

    @Test func aPageCreatedForTheTabAnyOtherWayDropsItsRestoredEntries() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageC, state: entriesC)
        history.restore([pageC])
        history.pageCreated(pageC)
        #expect(history.takeRestored(pageC) == nil && history.take(pageC) == nil)
    }

    @MainActor @Test func theStoreKeepsClosedPagesEntriesForEveryWindowOutsideItsSavedState() throws {
        let f = try ArchiveFixture()
        f.store.closedPageHistory.closed(pageA, state: entriesA)
        #expect(!(try JSONEncoder().encode(f.store.state)).isEmpty && f.store.closedPageHistory.take(pageA) === entriesA)
    }

    @Test func aPeekRefusedWhileAnotherUndosPeekWasAdoptedRetriesWhenThatEndsIfItsParentIsSelectedOnce() {
        var waiters = PeekUndoSlotWaiters()
        let shownParent = UUID(), hiddenParent = UUID()
        waiters.refused(shownParent)
        waiters.refused(hiddenParent)
        #expect(waiters.release(selected: [UUID(), shownParent]) == [shownParent] && waiters.release(selected: [hiddenParent]).isEmpty)
    }
}
