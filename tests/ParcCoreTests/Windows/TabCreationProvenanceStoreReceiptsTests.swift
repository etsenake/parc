import Foundation
import Testing
@testable import ParcCore

@MainActor
struct TabCreationProvenanceStoreReceiptsTests {
    @MainActor final class StoreFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let original: UUID
        let adjacent: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            original = store.open("https://original.example", kind: .pinned)
            adjacent = store.open("https://adjacent.example")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var profile: UUID { store.activeSpace.profileID }
    }

    @Test func actualCreationWritesItsSourceReceipt() throws {
        let s = try StoreFixture()
        let created = s.store.open("https://new.example", creation: TabCreationProvenance(referrerID: s.original,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        #expect(s.store.state.tabs.first { $0.id == created }?.referrerID == s.original)
    }

    @MainActor private final class CloseAttempt {
        let fixture: StoreFixture
        let created: UUID
        let decision: FolderRemovalSelection
        var origin: WindowPresentation
        var validator: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        var closed: Bool?

        init() throws {
            let fixture = try StoreFixture()
            self.fixture = fixture
            let store = fixture.store
            let created = store.open("https://new.example", creation: TabCreationProvenance(referrerID: fixture.original,
                activeTabID: fixture.adjacent, profileID: fixture.profile, state: store.state))
            self.created = created
            var origin = WindowPresentation(state: store.state, ready: true)
            origin.recordCreation(created, state: store.state)
            self.origin = origin
            decision = try #require(FolderRemovalSelection.resolve(removing: [created], spaceID: store.activeSpaceID,
                profileID: fixture.profile, state: store.state, selected: [created], focused: created,
                referrerPool: origin.referrerPool, available: { _ in true }))
            store.requestPageRetirement = { [weak self] _, validate, complete in
                self?.validator = validate
                self?.finish = complete
            }
        }

        func request() {
            fixture.store.closeTabs([created], selection: decision, shouldCommit: { true }) { [weak self] in self?.closed = $0 }
        }

        func refuseFirstAttempt() throws {
            request()
            try #require(validator?() == true)
            finish?(false)
        }

        func finishSecondAttempt() throws {
            try refuseFirstAttempt()
            request()
            try #require(validator?() == true)
            finish?(true)
        }
    }

    @Test func closingAChildChoosesItsOriginalSource() throws {
        let attempt = try CloseAttempt()
        #expect(attempt.decision.tabIDs == [attempt.fixture.original])
    }

    @Test func thePendingCloseKeepsItsSelectionAndCanCommit() throws {
        let attempt = try CloseAttempt()
        attempt.request()
        #expect(attempt.fixture.store.state.selectedTabIDs == [attempt.created] && attempt.closed == nil)
        #expect(attempt.validator?() == true)
    }

    @Test func refusingPageConsentLeavesTheTabUnarchived() throws {
        let attempt = try CloseAttempt()
        try attempt.refuseFirstAttempt()
        #expect(attempt.closed == false && attempt.fixture.store.state.tabs.first { $0.id == attempt.created }?.archivedAt == nil)
    }

    @Test func aSecondAttemptCanCommitAfterPageConsentWasRefused() throws {
        let attempt = try CloseAttempt()
        try attempt.refuseFirstAttempt()
        attempt.request()
        #expect(attempt.validator?() == true)
        attempt.finish?(true)
        let state = attempt.fixture.store.state
        #expect(attempt.closed == true && state.selectedTabIDs == [attempt.fixture.original])
        #expect(state.tabs.first { $0.id == attempt.created }?.archivedAt != nil)
    }

    @Test func theOriginalWindowCanApplyTheRetriedCloseSelection() throws {
        let attempt = try CloseAttempt()
        try attempt.finishSecondAttempt()
        let state = attempt.fixture.store.state
        attempt.origin.reconcile(state) { _ in true }
        let peer = WindowPresentation(state: state, ready: false)
        let consumed = attempt.origin.finishFolderRemoval(attempt.decision, state: state, available: { _ in true })
        #expect(consumed)
        #expect(attempt.origin.selectedTabIDs == [attempt.fixture.original] && !peer.isReady)
    }

    @Test func theRetriedClosePersistsTheSourceReceiptAndSelection() throws {
        let attempt = try CloseAttempt()
        try attempt.finishSecondAttempt()
        try attempt.fixture.store.save()
        let reload = try BrowserStore(directory: attempt.fixture.directory)
        #expect(reload.state.tabs.first { $0.id == attempt.created }?.activeTabBeforeCreationID == attempt.fixture.original)
        #expect(reload.state.selectedTabIDs == [attempt.fixture.original])
    }

    @Test func duplicatesCaptureTheExactOriginsActiveItemWithoutInheritingTheSourcesReferrer() throws {
        let s = try StoreFixture()
        let source = s.store.open("https://copy-source.example", creation: TabCreationProvenance(referrerID: s.adjacent,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        s.store.selectTab(s.original)
        let copyReceipt = TabCreationProvenance(referrerID: nil, activeTabID: s.original, profileID: s.profile, state: s.store.state)
        let target = try #require(SidebarDuplicateTarget(items: [.tab(source)], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state))
        let result = try #require(try s.store.duplicateSidebarItems(target, destinations: [source: "https://copy-source.example"],
            creation: copyReceipt))
        let copied = try #require(s.store.state.tabs.first { $0.id == result.tabIDs[0] })
        #expect(copied.referrerID == nil)
        #expect(copied.activeTabBeforeCreationID == s.original)
        #expect(s.store.state.selectedTabIDs == [s.original])
        #expect(s.store.state.tabs.first { $0.id == source }?.referrerID == s.adjacent)
    }

    @Test func aContextualCopyUsesAFreshOriginReceiptForEveryOriginalRoot() throws {
        let s = try StoreFixture()
        let source = s.store.open("https://copy-source.example")
        s.store.selectTab(s.original)
        let copyReceipt = TabCreationProvenance(referrerID: nil, activeTabID: s.original, profileID: s.profile, state: s.store.state)
        let folder = s.store.createFolder(name: "Target")
        let copySource = try #require(CommandBarFolderMoveSource(items: [.tab(source)], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state))
        let move = try #require(CommandBarFolderMove.snapshot(source: copySource, state: s.store.state).first { $0.folder.folderID == folder })
        let copyResult = try #require(try s.store.copyCommandBarItemsToFolder(move, destinations: [source: "https://copy-source.example"],
            creation: copyReceipt))
        #expect(copyResult.tabs.allSatisfy { $0.referrerID == nil && $0.activeTabBeforeCreationID == s.original })
    }

    @Test func aCallerWithoutAWindowCannotInventCopiedProvenance() throws {
        let s = try StoreFixture()
        let source = s.store.open("https://copy-source.example", creation: TabCreationProvenance(referrerID: s.adjacent,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        let target = try #require(SidebarDuplicateTarget(items: [.tab(source)], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state))
        let ownerless = try #require(try s.store.duplicateSidebarItems(target, destinations: [source: "https://copy-source.example"]))
        #expect(ownerless.tabIDs.allSatisfy { id in s.store.state.tabs.contains {
            $0.id == id && $0.referrerID == nil && $0.activeTabBeforeCreationID == nil } })
    }
}
