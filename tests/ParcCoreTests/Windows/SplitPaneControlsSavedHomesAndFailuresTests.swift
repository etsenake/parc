import Foundation
import Testing
@testable import ParcCore

struct SplitPaneControlsSavedHomesAndFailuresTests {
    private typealias Fixture = SplitPaneControlsTestsSupport.Fixture

    @MainActor @Test func aSavedOriginalNeedsARealSavedHomeReceipt() throws {
        let f = try Fixture()
        f.store.selectTab(f.saved)
        let pinned = try #require(SplitPaneInsertion(paneID: f.saved, operation: .addAfter, state: f.store.state))
        #expect(!f.store.insertSplitPane(pinned, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func aMissingHomeLeaksNoPartialTab() throws {
        let f = try Fixture()
        f.store.selectTab(f.saved)
        let pinned = try #require(SplitPaneInsertion(paneID: f.saved, operation: .addAfter, state: f.store.state))
        let before = f.store.state
        _ = f.store.insertSplitPane(pinned, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:])
        #expect(f.store.state == before)
    }

    @MainActor @Test func aPinnedOriginalMovesWithAFreshSavedHome() throws {
        let f = try Fixture()
        f.store.selectTab(f.saved)
        let pinned = try #require(SplitPaneInsertion(paneID: f.saved, operation: .addAfter, state: f.store.state))
        #expect(f.store.insertSplitPane(pinned, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [f.saved: UUID()], documents: [:]))
    }

    @MainActor @Test func theSavedHomeKeepsTheExactParentSection() throws {
        let f = try Fixture()
        let inserted = try f.insertPinned()
        let home = f.store.state.tabs.first { $0.id == inserted.home }
        #expect(home?.folderID == f.folder)
        #expect(home?.kind == .pinned)
    }

    @MainActor @Test func theLiveOriginalBecomesThePaneAndTheHomeNeverReplacesItsPage() throws {
        let f = try Fixture()
        let inserted = try f.insertPinned()
        #expect(f.store.state.tabs.first { $0.id == f.saved }?.kind == .today)
        #expect(f.store.state.selectedTabIDs == [f.saved, inserted.newID])
    }

    @MainActor private func pendingDraft(_ f: Fixture) throws -> SplitPaneInsertion {
        _ = try f.insertPinned()
        return try #require(SplitPaneInsertion(paneID: f.saved, operation: .addBelow, state: f.store.state))
    }

    @MainActor @Test func aDestinationProfileChangeInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var foreign = f.store.state
        foreign.spaces[0].profileID = UUID()
        #expect(!pending.isCurrent(in: foreign))
    }

    @MainActor @Test func aRemovedProfileInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var removed = f.store.state
        removed.profiles.removeAll { $0.id == pending.profileID }
        #expect(!pending.isCurrent(in: removed))
    }

    @MainActor @Test func aRetiredOriginalInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var archived = f.store.state
        archived.tabs[archived.tabs.firstIndex { $0.id == f.saved }!].archivedAt = f.now
        #expect(!pending.isCurrent(in: archived))
    }

    @MainActor @Test func changedGroupGeometryInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var changed = f.store.state
        changed.splitLayouts[changed.splitLayouts.firstIndex { $0.id == pending.layout?.id }!].widthFactors = [0.75, 0.25]
        #expect(!pending.isCurrent(in: changed))
    }

    @MainActor @Test func aStorageFailureRefusesPaneMaterialization() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        try f.breakStorage()
        #expect(!f.store.insertSplitPane(pending, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func aFailedSaveLeavesOriginalsAndNoOrphanTab() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        let failureState = f.store.state
        try f.breakStorage()
        _ = f.store.insertSplitPane(pending, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:])
        #expect(f.store.state == failureState)
        #expect(f.store.persistenceError != nil)
    }

    @MainActor @Test func aStorageFailureAlsoRefusesAReorder() throws {
        let f = try Fixture()
        _ = try pendingDraft(f)
        let failureState = f.store.state
        try f.breakStorage()
        #expect(!f.store.moveSplitPane(f.saved, offset: 1, expected: f.store.activeSplitLayout!))
        #expect(f.store.state == failureState)
    }

    @MainActor @Test func theSameReceiptRetriesAfterStorageRecovers() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        let failureID = UUID()
        try f.breakStorage()
        _ = f.store.insertSplitPane(pending, tabID: failureID, navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:])
        try f.restoreStorage()
        #expect(f.store.insertSplitPane(pending, tabID: failureID, navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
        #expect(f.store.persistenceError == nil)
    }
}
