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
        let step: ClosedItemStep
        let reopened: Set<UUID>
        let deleted: UUID
        let window = FolderUndoManager()
        let operation: ClosedTabsUndoOperation?
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
        return Partial(f: f, record: record, step: step, reopened: reopened, deleted: deleted, operation: f.consent.lastOperation)
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
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(p.window.redoMenuItemTitle == "Redo " + ClosedTabsUndo.Prompt.clear.name(count: p.record.itemCount(of: p.f.hereIDs.subtracting(p.reopened))))
        _ = remaining
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
