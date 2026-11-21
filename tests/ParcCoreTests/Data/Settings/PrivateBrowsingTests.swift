import Foundation
import Testing
@testable import ParcCore

@MainActor
struct PrivateBrowsingTests {
    @MainActor final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParcPrivateChecks-\(UUID().uuidString)")
        let normal: BrowserStore
        let originalState: BrowserState
        let originalBytes: Data
        let parent: UUID
        let enginePath: String
        let privateStore: BrowserStore
        var session: URL { root.appendingPathComponent("session.json") }
        var absent: URL { root.appendingPathComponent("must-not-be-created") }

        init() throws {
            normal = try BrowserStore(directory: root)
            let normalID = normal.openResolvedURL(URL(string: "https://normal.example.test/")!)
            normal.updateTab(normalID, title: "Normal", url: "https://normal.example.test/visited")
            try normal.save()
            originalState = normal.state
            originalBytes = try Data(contentsOf: root.appendingPathComponent("session.json"))
            parent = normal.activeSpace.profileID
            enginePath = normal.independentEngineProfilePath(for: parent)
            privateStore = BrowserStore(privateParentProfileID: parent, engineProfilePath: enginePath,
                                        directory: root, settings: normal.state.settings)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func openPrivateTab() -> UUID {
            let id = privateStore.openResolvedURL(URL(string: "https://private.example.test/")!)
            privateStore.updateTab(id, title: "Private", url: "https://private.example.test/visited")
            return id
        }

        func privateStore(parent: UUID, path: String, directory: URL) -> BrowserStore {
            BrowserStore(privateParentProfileID: parent, engineProfilePath: path, directory: directory,
                         settings: normal.state.settings)
        }
    }

    @Test func thePrivateModelHasAnExplicitOriginalParentIdentity() throws {
        let fixture = try Fixture()
        #expect(fixture.privateStore.isEphemeral && fixture.privateStore.privateParentProfileID == fixture.parent)
    }

    @Test func normalDataIsNotImportedIntoThePrivateModel() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        #expect(store.state.tabs.isEmpty && store.state.history.isEmpty && store.state.downloads.isEmpty)
    }

    @Test func privateAppIdentitiesAreDistinctFromNormalPersistedObjects() throws {
        let fixture = try Fixture()
        #expect(fixture.privateStore.activeSpace.profileID != fixture.parent
                && fixture.privateStore.activeSpaceID != fixture.normal.activeSpaceID)
    }

    @Test func theExplicitContextPathIdentifiesTheParentWithoutInventingAnOTRDiskProfile() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        #expect(store.independentEngineProfilePath(for: store.activeSpace.profileID) == fixture.enginePath)
    }

    @Test func privateNavigationIsAnInMemoryTabWithoutAHistoryEntry() throws {
        let fixture = try Fixture()
        _ = fixture.openPrivateTab()
        #expect(fixture.privateStore.state.tabs.count == 1 && fixture.privateStore.state.history.isEmpty)
    }

    @Test func closePreservesThePrivateTabWhileNativeApprovalIsPendingAndARefusalRetainsIt() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        let id = fixture.openPrivateTab()
        var finish: ((Bool) -> Void)?
        var retired: Set<UUID> = []
        store.requestPageRetirement = { ids, _, completion in
            retired = ids
            finish = completion
        }
        var closed: Bool?
        store.closeTabs([id], completion: { closed = $0 })
        #expect(retired == [id])
        #expect(closed == nil && store.state.tabs.contains { $0.id == id })
        finish?(false)
        #expect(closed == false && store.state.tabs.contains { $0.id == id })
    }

    @Test func nativeApprovalRevalidatesThePendingTransactionAndAnApprovedCloseDiscardsThePrivateObject() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        let id = fixture.openPrivateTab()
        var approve: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        store.requestPageRetirement = { _, shouldCommit, completion in
            approve = shouldCommit
            finish = completion
        }
        var closed: Bool?
        store.closeTabs([id], completion: { closed = $0 })
        #expect(approve?() == true)
        finish?(true)
        #expect(closed == true && store.state.tabs.isEmpty)
        #expect(store.archivedTabs.isEmpty && store.state.recentlyClosedIDs.isEmpty)
    }

    @Test func explicitAndDelayedSavesPreserveTheNormalSessionBytesAndState() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        _ = fixture.openPrivateTab()
        try store.saveSettingsSelection(pane: "general", profileID: nil)
        try store.saveProfileName(store.activeSpace.profileID, expectedName: "Incognito", name: "Memory only")
        try store.save()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        #expect(try Data(contentsOf: fixture.session) == fixture.originalBytes)
        #expect(fixture.normal.state == fixture.originalState)
    }

    @Test func aNativeCreatedPageAdoptsTheExactPrivateModelProfile() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        let adopted = store.adoptNativePage(url: URL(string: "https://private.example.test/popup"), title: "Original popup",
                                            profilePath: fixture.enginePath, preferredSpaceID: store.activeSpaceID, select: false)
        #expect(adopted != nil && store.state.tabs.last?.profileID == store.activeSpace.profileID)
    }

    @Test func aForeignNativeParentPathCannotBeAdopted() throws {
        let fixture = try Fixture()
        let store = fixture.privateStore
        #expect(store.adoptNativePage(url: nil, title: "", profilePath: fixture.enginePath + "-different",
                                      preferredSpaceID: store.activeSpaceID, select: false) == nil)
    }

    @Test func ephemeralInitializationAndSaveCreateNoStorage() throws {
        let fixture = try Fixture()
        let second = fixture.privateStore(parent: fixture.parent, path: fixture.enginePath, directory: fixture.absent)
        _ = second.openResolvedURL(URL(string: "https://private.example.test/second")!)
        try second.save()
        #expect(!FileManager.default.fileExists(atPath: fixture.absent.path))
    }

    @Test func physicalPrivateWindowsHaveDistinctAppModelIdentities() throws {
        let fixture = try Fixture()
        let second = fixture.privateStore(parent: fixture.parent, path: fixture.enginePath, directory: fixture.absent)
        #expect(second.activeSpaceID != fixture.privateStore.activeSpaceID
                && second.activeSpace.profileID != fixture.privateStore.activeSpace.profileID)
    }

    @Test func applicationCommandsResolveTheNormalParentAndAnActualNormalSpace() throws {
        let fixture = try Fixture()
        let context = fixture.normal.applicationContext(from: fixture.privateStore, spaceID: fixture.privateStore.activeSpaceID)
        #expect(context?.profileID == fixture.parent && context?.spaceID == fixture.normal.activeSpaceID)
        #expect(context?.profileID != fixture.privateStore.activeSpace.profileID)
    }

    @Test func anEphemeralStoreCannotBecomeTheApplicationPreferenceOwner() throws {
        let fixture = try Fixture()
        #expect(fixture.privateStore.applicationContext(from: fixture.normal, spaceID: fixture.normal.activeSpaceID) == nil)
    }

    @Test func anotherPersistentStoreIsNotSilentlySubstituted() throws {
        let fixture = try Fixture()
        let foreign = try BrowserStore(directory: fixture.root.appendingPathComponent("foreign"))
        #expect(fixture.normal.applicationContext(from: foreign, spaceID: foreign.activeSpaceID) == nil)
    }

    @Test func aMissingOriginalParentDoesNotFallBackToDefault() throws {
        let fixture = try Fixture()
        let stale = fixture.privateStore(parent: UUID(), path: fixture.enginePath, directory: fixture.absent)
        #expect(fixture.normal.applicationContext(from: stale, spaceID: stale.activeSpaceID) == nil)
    }

    @Test func anUnassignedRealProfileRemainsASettingsOwnerWithoutInventingASpace() throws {
        let fixture = try Fixture()
        let unassigned = fixture.normal.createProfile(name: "Unassigned")
        let unassignedPrivate = fixture.privateStore(parent: unassigned,
            path: fixture.normal.independentEngineProfilePath(for: unassigned), directory: fixture.absent)
        let context = fixture.normal.applicationContext(from: unassignedPrivate, spaceID: unassignedPrivate.activeSpaceID)
        #expect(context?.profileID == unassigned && context?.spaceID == nil)
    }

    @Test func aRetiringOriginalParentIsRejectedBeforeApplicationCommandDispatch() throws {
        let fixture = try Fixture()
        let unassigned = fixture.normal.createProfile(name: "Unassigned")
        let unassignedPrivate = fixture.privateStore(parent: unassigned,
            path: fixture.normal.independentEngineProfilePath(for: unassigned), directory: fixture.absent)
        let pending = try fixture.normal.stageProfileRemoval(unassigned, expectedName: "Unassigned")
        #expect(fixture.normal.applicationContext(from: unassignedPrivate, spaceID: unassignedPrivate.activeSpaceID) == nil)
        try fixture.normal.cancelProfileRemoval(pending)
    }

    @Test func applicationSettingsWritesDoNotMutateTheEphemeralSessionAndPersistInTheNormalStore() throws {
        let fixture = try Fixture()
        let snapshot = fixture.privateStore.state
        try fixture.normal.saveSettingsSelection(pane: "Profiles", profileID: fixture.parent)
        #expect(fixture.privateStore.state == snapshot)
        let reloaded = try BrowserStore(directory: fixture.root)
        #expect(reloaded.state.settings.settingsProfileID == fixture.parent)
    }
}
