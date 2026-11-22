import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeFolderDeletionTests {
    private struct DeletionFixture {
        let directory: URL
        let store: BrowserStore
        let date: Date
        let space: UUID
        let profile: UUID
        let sibling: UUID
        let parent: UUID
        let nested: UUID
        let empty: UUID
        let outside: UUID
        let first: UUID
        let a: UUID
        let b: UUID
        let split: BrowserSplitLayout
        let root: SidebarContainerLocation
        let before: BrowserState
        let rootBefore: [SidebarItemReference]
        let target: FolderRemovalTarget
    }

    @MainActor
    private static func withDeletionFixture(_ body: (DeletionFixture) throws -> Void) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let sibling = store.createFolder(name: "Keep")
            let parent = store.createFolder(name: "Delete")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let outside = store.open("https://keep.example", kind: .pinned)
            let first = store.open("https://one.example", kind: .pinned)
            let a = store.open("https://a.example")
            let b = store.open("https://b.example")
            store.moveTab(first, toSpace: space, folderID: parent)
            try BrowserStoreTestsSupport.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let split = store.activeSplitLayout!
            store.toggleFolder(nested)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first),
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
            let before = store.state
            let rootBefore = SidebarHierarchy.children(in: root, state: before)
            let target = FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: before)!
            try body(DeletionFixture(directory: directory, store: store, date: date, space: space, profile: profile,
                                     sibling: sibling, parent: parent, nested: nested, empty: empty, outside: outside,
                                     first: first, a: a, b: b, split: split, root: root, before: before, rootBefore: rootBefore,
                                     target: target))
        }
    }

    @Test @MainActor static func deletionTargetsIncludeCollapsedAndEmptyDescendants() throws {
        try withDeletionFixture { fixture in
            let target = fixture.target
            let parent = fixture.parent
            let nested = fixture.nested
            let empty = fixture.empty
            let first = fixture.first
            let a = fixture.a
            let b = fixture.b
            #expect(target.folderIDs == [parent, nested, empty] && Set(target.tabs.map(\.id)) == [first, a, b], "Deletion binds collapsed and empty descendants in original mixed order")
        }
    }

    @Test @MainActor static func aForeignProfileCannotPrepareFolderDeletion() throws {
        try withDeletionFixture { fixture in
            let parent = fixture.parent
            let space = fixture.space
            let before = fixture.before
            #expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: UUID(), state: before) == nil, "Foreign profile cannot prepare deletion")
        }
    }

    @Test @MainActor static func aCyclicFolderCannotPrepareDeletion() throws {
        try withDeletionFixture { fixture in
            let before = fixture.before
            let parent = fixture.parent
            let empty = fixture.empty
            let space = fixture.space
            let profile = fixture.profile
            var malformed = before
            malformed.folders[malformed.folders.firstIndex { $0.id == parent }!].parentID = empty
            #expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: malformed) == nil, "Hierarchy cycles refuse before consent")
        }
    }

    @Test @MainActor static func aSplitCannotBorrowAPageOutsideTheDeletedSubtree() throws {
        try withDeletionFixture { fixture in
            let before = fixture.before
            let outside = fixture.outside
            let parent = fixture.parent
            let space = fixture.space
            let profile = fixture.profile
            var crossSplit = before
            crossSplit.splitLayouts[0].tabIDs[1] = outside
            #expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: crossSplit) == nil, "A cross-subtree split cannot borrow an outside page")
        }
    }

    @Test @MainActor static func anOriginatingWindowCanRefuseToDeleteTheWholeSubtree() throws {
        try withDeletionFixture { fixture in
            let store = fixture.store
            let target = fixture.target
            let first = fixture.first
            let a = fixture.a
            let b = fixture.b
            let before = fixture.before
            var requested = Set<UUID>(), validate: (() -> Bool)?, finish: ((Bool) -> Void)?
            store.requestPageRetirement = { ids, gate, done in requested = ids; validate = gate; finish = done }
            var results: [Result<Bool, Error>] = []
            store.deleteFolder(target, shouldCommit: { false }) { results.append($0) }
            #expect(requested == [first, a, b] && store.state == before, "Every original descendant page joins retirement before metadata changes")
            #expect(validate?() == false, "Originating-window refusal cancels the whole operation")
            finish?(false)
            let outcome = try results.last?.get()
            #expect(outcome == false && store.state == before, "Refusal preserves folder tree, tabs, selection and order")
        }
    }

    @Test @MainActor static func aNativeRefusalLeavesEveryFolderAndPageInPlace() throws {
        try withDeletionFixture { fixture in
            let store = fixture.store
            let target = fixture.target
            let before = fixture.before
            var finish: ((Bool) -> Void)?
            store.requestPageRetirement = { _, _, done in finish = done }
            var results: [Result<Bool, Error>] = []
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            finish?(false)
            let outcome = try results.last?.get()
            #expect(store.state == before && outcome == false, "Native beforeunload refusal does not archive any sibling")
        }
    }

    @Test @MainActor static func approvalCanBeUsedOnceAndWaitsForNativeCompletion() throws {
        try withDeletionFixture { fixture in
            let store = fixture.store
            let target = fixture.target
            let before = fixture.before
            var validate: (() -> Bool)?
            store.requestPageRetirement = { _, gate, _ in validate = gate }
            store.deleteFolder(target, shouldCommit: { true }) { _ in }
            #expect(validate?() == true && validate?() == false, "Consent authorization is one-shot")
            #expect(store.state == before, "Approved pages must actually finish retiring before saved deletion")
        }
    }

    @Test @MainActor static func completingFolderDeletionPublishesACompleteDurableArchive() throws {
        try withDeletionFixture { fixture in
            let store = fixture.store
            let target = fixture.target
            let parent = fixture.parent
            let nested = fixture.nested
            let empty = fixture.empty
            let sibling = fixture.sibling
            let date = fixture.date
            let profile = fixture.profile
            let outside = fixture.outside
            let before = fixture.before
            let root = fixture.root
            let rootBefore = fixture.rootBefore
            let split = fixture.split
            let space = fixture.space
            let directory = fixture.directory
            var results: [Result<Bool, Error>] = []
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            var validate: (() -> Bool)?
            var finish: ((Bool) -> Void)?
            store.requestPageRetirement = { _, gate, done in validate = gate; finish = done }
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            try #require(validate?() == true)
            let done = try #require(finish)
            done(true)
            #expect((try results.last?.get()) == true && publications == 1, "Complete deletion publishes once after durable save")
            #expect(!store.state.folders.contains { [parent, nested, empty].contains($0.id) } && store.state.folders.contains { $0.id == sibling }, "Only the original subtree folder records are deleted")
            #expect(target.tabs.allSatisfy { original in store.state.tabs.contains { $0.id == original.id && $0.archivedAt == date && $0.folderID == nil && $0.profileID == profile && $0.kind == original.kind && $0.savedURL == original.savedURL } }, "Original saved identities and destinations become archived tabs without fabricated folder archives")
            #expect(store.state.tabs.first { $0.id == outside } == before.tabs.first { $0.id == outside }, "Outside saved tab is byte-for-byte untouched")
            #expect(SidebarHierarchy.children(in: root, state: store.state) == rootBefore.filter { $0 != .folder(parent) }, "Mixed sibling order survives removal without reparenting children")
            #expect(store.state.splitLayouts.isEmpty && store.state.selectedTabIDs.isEmpty, "Retired original split cannot remain visibly selected")
            let archived = store.archivedItems(profileID: profile)
            #expect(archived.count == 2 && archived.contains { $0.tabs.map(\.id) == split.tabIDs && $0.provenance?.split == split }, "Complete split children stay one restorable archive item with original geometry")
            #expect(archived.allSatisfy { $0.provenance?.reason == .manual && $0.provenance?.spaceID == space }, "Archive uses the genuine original Space and manual source")
            #expect(store.state.history == before.history && store.state.downloads == before.downloads, "Folder deletion leaves history/download records intact")
            let loaded = try BrowserStore(directory: directory)
            #expect(loaded.state.tabs == store.state.tabs && loaded.state.folders == store.state.folders && loaded.state.sidebarItemOrder == store.state.sidebarItemOrder, "Durable reload contains the complete archive and hierarchy result")
            observation.cancel()
        }
    }

    @Test @MainActor static func aRepeatedNativeDeletionCompletionCannotCommitAgain() throws {
        try withDeletionFixture { fixture in
            let store = fixture.store
            let target = fixture.target
            var results: [Result<Bool, Error>] = []
            var validate: (() -> Bool)?
            var finish: ((Bool) -> Void)?
            store.requestPageRetirement = { _, gate, done in validate = gate; finish = done }
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            try #require(validate?() == true)
            let done = try #require(finish)
            done(true)
            let after = store.state, resultCount = results.count
            done(true)
            #expect(store.state == after && results.count == resultCount, "Repeated native completion cannot duplicate archives or commits")
        }
    }

    @Test @MainActor static func puttingBackADeletedSplitRebuildsOnlyItsFolderPathAndRestoresItsSlot() throws {
        try withDeletionFixture { fixture in
            let store = fixture.store
            let target = fixture.target
            let a = fixture.a
            let profile = fixture.profile
            let space = fixture.space
            let split = fixture.split
            let parent = fixture.parent
            let nested = fixture.nested
            let empty = fixture.empty
            let root = fixture.root
            let rootBefore = fixture.rootBefore
            var validate: (() -> Bool)?
            var finish: ((Bool) -> Void)?
            store.requestPageRetirement = { _, gate, done in validate = gate; finish = done }
            store.deleteFolder(target, shouldCommit: { true }) { _ in }
            try #require(validate?() == true)
            let done = try #require(finish)
            done(true)
            _ = store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space))
            #expect(store.state.selectedTabIDs == split.tabIDs && store.activeSplitLayout?.orientation == .vertical && store.activeSplitLayout?.widthFactors == [0.3, 0.7], "Restoring the archived split preserves original page IDs/order and geometry")
            #expect(store.state.folders.first { $0.id == parent }?.parentID == nil
                && store.state.folders.first { $0.id == nested }?.parentID == parent
                && !store.state.folders.contains { $0.id == empty }, "Restoring the split rebuilds only the deleted folders on its path")
            #expect(split.tabIDs.allSatisfy { id in store.state.tabs.first { $0.id == id }?.folderID == nested }
                && SidebarHierarchy.children(in: .init(spaceID: space, folderID: nested, section: .pinned), state: store.state) == [.split(split.id)], "The restored split sits inside its rebuilt folder")
            #expect(SidebarHierarchy.children(in: root, state: store.state) == rootBefore, "The rebuilt folder returns to its original Pinned position")
        }
    }

    @Test @MainActor static func changingAFolderDuringNativeConsentPreventsDeletion() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validate, completion in gate = validate; done = completion }
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            var result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { true }) { result = $0 }
            store.renameFolder(folder, name: "Changed")
            #expect(gate?() == false, "Renamed or structurally changed target invalidates original confirmation")
            done?(false)
            #expect((try result?.get()) == false && store.state.tabs.first { $0.id == tabID }?.archivedAt == nil, "Stale cancellation retains original page and saved tab")
        }
    }

    @Test @MainActor static func aReentrantWindowValidatorCannotDeleteAnEditedFolder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validate, completion in gate = validate; done = completion }
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(target, shouldCommit: { store.renameFolder(folder, name: "Reentered"); return true }) { _ in }
            #expect(gate?() == false, "Reentrant validator cannot authorize a changed subtree")
            done?(false)
        }
    }

    @Test @MainActor static func deletingAnEmptyFolderStillRequiresWindowConsent() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            var result: Result<Bool, Error>?
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderRemovalTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(emptyTarget, shouldCommit: { false }) { result = $0 }
            #expect(store.state.folders.contains { $0.id == empty }, "Empty-folder removal still honors original-window cancellation")
            store.deleteFolder(emptyTarget, shouldCommit: { true }) { result = $0 }
            #expect((try result?.get()) == true && !store.state.folders.contains { $0.id == empty }, "Confirmed empty folder uses the same durable transaction")
        }
    }

    @Test @MainActor static func aFailedSaveCannotPublishAPartialFolderDeletion() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var result: Result<Bool, Error>?
            let failureTarget = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let original = store.state
            try store.save()
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("session.json"), withIntermediateDirectories: false)
            store.deleteFolder(failureTarget, shouldCommit: { true }) { result = $0 }
            if case .failure = result {} else { throw BrowserStoreTestsSupport.Failure(description: "Save failure must report an error") }
            #expect(store.state == original && store.persistenceError != nil, "Failed durable save cannot publish a partial deletion")
        }
    }
}
