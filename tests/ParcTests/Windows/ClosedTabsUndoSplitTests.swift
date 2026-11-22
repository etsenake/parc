import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct ClosedTabsUndoSplitTests {
    @MainActor private final class SideFixture {
        let consent = ClosedTabsUndoSupport.Consent()
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
            root = try ClosedTabsUndoSupport.temporaryRoot()
            side = BrowserSpace(id: UUID(), name: "Side", symbol: "circle", color: "FEDCBA", profileID: profile.id)
            let profile = profile, side = side
            sidePinned = ClosedTabsUndoSupport.makeTab("Side pinned", side, profile: profile, kind: .pinned)
            a = ClosedTabsUndoSupport.makeTab("A", side, profile: profile)
            b = ClosedTabsUndoSupport.makeTab("B", side, profile: profile)
            c = ClosedTabsUndoSupport.makeTab("C", side, profile: profile)
            d = ClosedTabsUndoSupport.makeTab("D", side, profile: profile)
            e = ClosedTabsUndoSupport.makeTab("E", side, profile: profile)
            trio = BrowserSplitLayout(sidebarAnchorID: a.id, customTitle: "Trio", spaceID: side.id,
                                      tabIDs: [a.id, b.id, c.id], orientation: .horizontal, widthFactors: [0.2, 0.3, 0.5])
            var seed = BrowserState(profiles: [profile], spaces: [side], activeSpaceID: side.id)
            seed.tabs = [sidePinned, a, b, c, d, e]
            seed.splitLayouts = [trio]
            sideToday = SidebarContainerLocation(spaceID: side.id, folderID: nil, section: .today)
            seed.sidebarItemOrder[sideToday.key] = [.tab(e.id), .tab(a.id), .tab(d.id)]
            seed.selectedTabIDs = trio.tabIDs
            seed.selectionBySpace[side.id.uuidString] = trio.tabIDs
            _ = try ClosedTabsUndoSupport.writeSeed(seed, to: root)
            store = try BrowserStore(directory: root, now: ClosedTabsUndoSupport.storeClock)
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

    @Test func aRefusedRedoKeepsItsRedoAndItsValidation() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let loose = try #require(f.clear([f.d.id, f.e.id]))
        let window = f.register(loose)
        window.undo()
        f.consent.autoApprove = false
        window.redo()
        f.consent.finish?(false)
        #expect(window.canRedo && f.consent.redoCurrent?() == true)
    }

    @Test func pinningATabInvalidatesThePendingRedoCheck() throws {
        let f = try SideFixture()
        f.consent.autoApprove = true
        let loose = try #require(f.clear([f.d.id, f.e.id]))
        let window = f.register(loose)
        window.undo()
        f.consent.autoApprove = false
        window.redo()
        f.consent.finish?(false)
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
        _ = try #require(f.clear([f.d.id, f.e.id]))
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
