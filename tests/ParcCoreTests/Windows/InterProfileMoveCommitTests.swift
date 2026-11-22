import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveCommitTests {
    private typealias Store = InterProfileMoveTestsSupport.Store
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @MainActor private final class Transaction {
        let f = Fixture()
        let s: Store
        let store: BrowserStore
        let proposal: (BrowserState) -> BrowserState?
        var result: Result<Bool, Error>?
        var pending: (() -> Bool, (Bool) -> Void)?

        init() throws {
            let f = f
            s = try Store("inter-profile")
            store = try s.open(f.state)
            let r = f.request(f.today)
            proposal = { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) }
        }

        func move() { result = nil; store.moveAcrossProfiles([f.today.id], proposal: proposal) { [unowned self] in result = $0 } }
        var succeeded: Bool? { try? result?.get() }
    }

    @MainActor @Test func theDialogPreferenceDefaultsOff() throws {
        let t = try Transaction()
        #expect(!t.store.bypassesInterProfileMoveConfirmation)
    }

    @MainActor @Test func refusedPageConsentPublishesNothing() throws {
        let t = try Transaction()
        var asked: Set<UUID> = []
        t.store.requestPageRetirement = { ids, _, completion in asked = ids; completion(false) }
        t.move()
        #expect(asked == [t.f.today.id])
        #expect(t.succeeded == false)
        #expect(t.store.state == t.f.state)
    }

    @MainActor @Test func theMovedTabIsReservedWhilePagesRetire() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in t.pending = (shouldCommit, completion) }
        t.move()
        #expect(t.store.retiringTabIDs == [t.f.today.id])
        #expect(t.result == nil)
    }

    @MainActor @Test func approvalDoesNotPublishBeforeEveryPageCloses() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in t.pending = (shouldCommit, completion) }
        t.move()
        #expect(t.pending?.0() == true)
        #expect(t.store.state == t.f.state)
    }

    @MainActor @Test func theMoveCommitsAfterRetirement() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in t.pending = (shouldCommit, completion) }
        t.move()
        _ = t.pending?.0()
        t.pending?.1(true)
        #expect(t.succeeded == true)
        #expect(t.store.state.tabs.first { $0.id == t.f.today.id }?.profileID == t.f.q.id)
        #expect(t.store.retiringTabIDs.isEmpty)
    }

    @MainActor @Test func theMovePersistsAtomically() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        t.move()
        #expect(try BrowserStore(directory: t.s.directory).state.tabs.first { $0.id == t.f.today.id }?.profileID == t.f.q.id)
    }

    @MainActor @Test func aChangedOriginalAfterTheGestureRefuses() throws {
        let t = try Transaction()
        var edited = t.f.state
        edited.tabs[0].customTitle = "Renamed"
        let stale = try t.s.open(edited)
        stale.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        var result: Result<Bool, Error>?
        stale.moveAcrossProfiles([t.f.today.id], proposal: t.proposal) { result = $0 }
        #expect((try? result?.get()) == false)
        #expect(stale.state == edited)
    }

    @MainActor @Test func aFailedSavePublishesNothing() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        try t.s.breakWrites()
        t.move()
        var failed = false
        if case .failure? = t.result { failed = true }
        #expect(failed)
        #expect(t.store.state == t.f.state)
    }

    @MainActor private func emptyFolderMove(_ f: Fixture) -> (state: BrowserState, folder: BrowserFolder, move: SidebarSpaceMove) {
        var state = f.state
        let folder = BrowserFolder(id: UUID(), spaceID: f.s.id, name: "Empty")
        state.folders.append(folder)
        state.sidebarItemOrder[f.root.key]?.append(.folder(folder.id))
        let move = SidebarSpaceMove(items: [.folder(folder.id)],
            from: SidebarHierarchySnapshot(state: state, spaceID: f.s.id, profileID: f.p.id)!,
            to: SidebarHierarchySnapshot(state: state, spaceID: f.d.id, profileID: f.q.id)!, state: state)!
        return (state, folder, move)
    }

    @MainActor @Test func anEmptyFolderNeedsNoDecision() throws {
        let f = Fixture()
        let e = emptyFolderMove(f)
        #expect(e.move.tabIDs.isEmpty)
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [], destination: f.q.id, decision: nil, bypass: false) == .proceed(remembersChoice: false))
    }

    @MainActor @Test func anEmptyFolderMovesAtOnce() throws {
        let f = Fixture()
        let e = emptyFolderMove(f)
        let s = try Store("empty-folder")
        let store = try s.open(e.state)
        var retired = false
        store.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        var result: Result<Bool, Error>?
        store.moveAcrossProfiles([], proposal: { e.move.applying(to: $0) }) { result = $0 }
        #expect((try? result?.get()) == true)
        #expect(!retired)
        #expect(store.state.folders.first { $0.id == e.folder.id }?.spaceID == f.d.id)
    }

    @MainActor @Test func anOrdinaryRelocationCannotSkipThePageReload() throws {
        let f = Fixture()
        let s = try Store("plain")
        let plain = try s.open(f.state)
        let from = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let move = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state))
        #expect(try plain.moveSidebarItemsAcrossSpaces(move) == false)
        #expect(plain.state == f.state)
    }

    @MainActor @Test func dontAskAgainStoresThePreference() throws {
        let f = Fixture()
        let s = try Store("remember")
        let plain = try s.open(f.state)
        plain.rememberInterProfileMoveChoice()
        #expect(plain.bypassesInterProfileMoveConfirmation)
    }
}
