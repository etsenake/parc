import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserImportStoreTests {
    let importedAt = Date(timeIntervalSince1970: 1_793_000_000)

    let one = BrowserImportBookmark(id: "one", title: "Same title", url: "https://example.test/one", children: [])
    let loose = BrowserImportBookmark(id: "loose", title: "Loose", url: "https://example.test/loose", children: [])

    struct Fixture {
        let directory: URL
        let store: BrowserStore
        let original: BrowserSpace
        let target: BrowserImportDestination
        let otherSpace: UUID
        let selection: BrowserImportSelection
        var session: URL { directory.appendingPathComponent("session.json") }
        var backup: URL { directory.appendingPathComponent("prior-session.json") }

        func refuseWrites() throws {
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        }

        func allowWrites() throws {
            try FileManager.default.removeItem(at: session)
            try FileManager.default.moveItem(at: backup, to: session)
        }
    }

    func withFixture(_ body: (Fixture) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let importedAt = importedAt
            let store = try BrowserStore(directory: directory, now: { importedAt })
            let original = store.activeSpace
            let target = BrowserImportDestination(spaceID: original.id, profileID: original.profileID)
            let two = BrowserImportBookmark(id: "two", title: "Same title", url: "https://example.test/one", children: [])
            let nested = BrowserImportBookmark(id: "nested", title: "Nested", url: nil, children: [two])
            let folder = BrowserImportBookmark(id: "folder", title: "Work", url: nil, children: [one, nested])
            var selection = try BrowserImportSelection(roots: [folder, loose])
            selection.toggle("folder")
            selection.toggle("two")
            let otherSpace = store.createSpace(name: "Other")
            try store.save()
            try body(Fixture(directory: directory, store: store, original: original, target: target,
                             otherSpace: otherSpace, selection: selection))
        }
    }

    func withCommitted(_ body: (Fixture) throws -> Void) throws {
        try withFixture { fixture in
            try fixture.store.commitImportedBookmarks(fixture.selection.includedRoots, destination: fixture.target)
            try body(fixture)
        }
    }

    @Test func importDoesNotChangeTheActiveSpaceAndInsertsOnlySelectedOriginals() throws {
        try withCommitted { fixture in
            let state = fixture.store.state
            #expect(state.activeSpaceID == fixture.otherSpace)
            #expect(state.tabs.filter { $0.spaceID == fixture.original.id && $0.kind == .pinned }.count == 2)
            #expect(!state.tabs.contains { $0.spaceID == fixture.otherSpace && $0.kind == .pinned })
        }
    }

    @Test func theOriginalAncestorHierarchyIsRetained() throws {
        try withCommitted { fixture in
            let folders = fixture.store.state.folders.filter { $0.spaceID == fixture.original.id }
            #expect(folders.count == 2)
            let outer = try #require(folders.first { $0.name == "Work" })
            let inner = try #require(folders.first { $0.name == "Nested" })
            #expect(inner.parentID == outer.id)
            let pages = fixture.store.state.tabs.filter { $0.spaceID == fixture.original.id && $0.kind == .pinned }
            #expect(pages.first { $0.title == "Same title" }?.folderID == inner.id)
        }
    }

    @Test func mixedRootOrderBeginsWithTheFolderAndEndsWithTheLoosePage() throws {
        try withCommitted { fixture in
            let state = fixture.store.state
            let outer = try #require(state.folders.first { $0.name == "Work" })
            let pages = state.tabs.filter { $0.spaceID == fixture.original.id && $0.kind == .pinned }
            let loosePage = try #require(pages.first { $0.title == "Loose" })
            let order = SidebarHierarchy.children(in: .init(spaceID: fixture.original.id, folderID: nil, section: .pinned),
                                                  state: state)
            #expect(order.first == .folder(outer.id))
            #expect(order.last == .tab(loosePage.id))
        }
    }

    @Test func aGenuineSessionReloadPreservesTheImportedHierarchyAndPages() throws {
        try withCommitted { fixture in
            let reloaded = try BrowserStore(directory: fixture.directory)
            #expect(reloaded.state.folders == fixture.store.state.folders)
            #expect(reloaded.state.tabs == fixture.store.state.tabs)
        }
    }

    @Test func importedBrowserPagesUseParcsPublicNamespaceImmediately() throws {
        try withCommitted { fixture in
            let bookmark = BrowserImportBookmark(id: "settings", title: "Settings", url: "chrome://settings", children: [])
            try fixture.store.commitImportedBookmarks([bookmark], destination: fixture.target)
            #expect(fixture.store.state.tabs.last?.url == "parc://settings"
                    && fixture.store.state.tabs.last?.savedURL == "parc://settings")
        }
    }

    @Test func anArcOnlySchemeDoesNotBecomeAParcShortcut() throws {
        try withCommitted { fixture in
            #expect(throws: (any Error).self) {
                try fixture.store.commitImportedBookmarks(
                    [.init(id: "excluded", title: "Arc", url: "arc://settings", children: [])], destination: fixture.target)
            }
        }
    }

    @Test func aRefusedDiskWritePropagatesAndLeavesNoHalfInsertedBookmarks() throws {
        try withCommitted { fixture in
            let before = fixture.store.state
            try fixture.refuseWrites()
            #expect(throws: (any Error).self) {
                try fixture.store.commitImportedBookmarks([one], destination: fixture.target)
            }
            #expect(fixture.store.state.tabs == before.tabs && fixture.store.state.folders == before.folders)
        }
    }

    @Test func retryingAfterAFailureCommitsOneNewOriginal() throws {
        try withCommitted { fixture in
            let before = fixture.store.state
            try fixture.refuseWrites()
            _ = try? fixture.store.commitImportedBookmarks([one], destination: fixture.target)
            try fixture.allowWrites()
            try fixture.store.commitImportedBookmarks([one], destination: fixture.target)
            #expect(fixture.store.state.tabs.count == before.tabs.count + 1)
        }
    }

    @Test func aSeparateSourceProfileGetsAnIsolatedIdentityCommittedTogether() throws {
        try withCommitted { fixture in
            let count = fixture.store.state.profiles.count
            let separate = try fixture.store.createImportDestination(name: "Imported Work", basedOn: fixture.target)
            #expect(separate.profileID != fixture.target.profileID && separate.spaceID != fixture.target.spaceID)
            #expect(fixture.store.state.profiles.count == count + 1 && separate.isCurrent(in: fixture.store.state))
            #expect(fixture.store.activeSpaceID == fixture.otherSpace)
            #expect(fixture.store.state.spaces.first { $0.id == separate.spaceID }?.theme == fixture.original.theme)
        }
    }

    @Test func aNativeDestinationIsDurableBeforeContextAcquisition() throws {
        try withCommitted { fixture in
            let separate = try fixture.store.createImportDestination(name: "Imported Work", basedOn: fixture.target)
            let saved = try BrowserStore(directory: fixture.directory)
            #expect(separate.isCurrent(in: saved.state))
        }
    }

    @Test func theWrongOriginalProfileIsRefused() throws {
        try withCommitted { fixture in
            let separate = try fixture.store.createImportDestination(name: "Imported Work", basedOn: fixture.target)
            let stale = BrowserImportDestination(spaceID: fixture.original.id, profileID: separate.profileID)
            #expect(throws: (any Error).self) { try fixture.store.commitImportedBookmarks([loose], destination: stale) }
        }
    }

    @Test func anExistingOriginalProfileKeepsTheCapturedSpaceAndCreatesNothing() throws {
        try withCommitted { fixture in
            let originalTarget = BrowserImportProfileTarget(profileID: fixture.target.profileID, spaceID: fixture.target.spaceID)
            let unchanged = fixture.store.state
            let existing = try fixture.store.prepareImportDestination(originalTarget, basedOn: fixture.target)
            #expect(existing == fixture.target)
            #expect(fixture.store.state.spaces == unchanged.spaces && fixture.store.state.profiles == unchanged.profiles)
            #expect(fixture.store.activeSpaceID == fixture.otherSpace)
        }
    }

    @Test func choicesKeepTheInvocationSpaceAndReachOtherProfilesThroughTheirOwnSpace() throws {
        try withCommitted { fixture in
            let originalTarget = BrowserImportProfileTarget(profileID: fixture.target.profileID, spaceID: fixture.target.spaceID)
            let separate = try fixture.store.createImportDestination(name: "Imported Work", basedOn: fixture.target)
            let separateTarget = BrowserImportProfileTarget(profileID: separate.profileID, spaceID: separate.spaceID)
            let choices = BrowserImportProfileTarget.choices(in: fixture.store.state, original: fixture.target)
            #expect(choices.first { $0.profileID == fixture.target.profileID } == originalTarget)
            #expect(choices.contains(separateTarget))
            let resolved = try fixture.store.prepareImportDestination(separateTarget, basedOn: fixture.target)
            #expect(resolved == separate)
        }
    }

    struct Unused {
        let id: UUID
        let target: BrowserImportProfileTarget
    }

    func withUnused(_ body: (Fixture, Unused) throws -> Void) throws {
        try withCommitted { fixture in
            let id = fixture.store.createProfile(name: "Unused")
            try body(fixture, Unused(id: id, target: BrowserImportProfileTarget(profileID: id, spaceID: nil)))
        }
    }

    @Test func anUnusedProfileIsATargetWithoutCreatingASpaceEarly() throws {
        try withUnused { fixture, unused in
            #expect(BrowserImportProfileTarget.choices(in: fixture.store.state, original: fixture.target).contains(unused.target))
        }
    }

    @Test func preparingAnUnusedDestinationAddsOnlyItsBookmarkSpaceWithoutFocusingIt() throws {
        try withUnused { fixture, unused in
            let profileCount = fixture.store.state.profiles.count
            let spacesBefore = fixture.store.state.spaces.count
            let destination = try fixture.store.prepareImportDestination(unused.target, basedOn: fixture.target)
            #expect(destination.profileID == unused.id)
            #expect(fixture.store.state.profiles.count == profileCount && fixture.store.state.spaces.count == spacesBefore + 1)
            #expect(fixture.store.activeSpaceID == fixture.otherSpace)
            #expect(!unused.target.isCurrent(in: fixture.store.state))
        }
    }

    @Test func aStaleUnusedTargetDoesNotCreateDuplicateSpaces() throws {
        try withUnused { fixture, unused in
            _ = try fixture.store.prepareImportDestination(unused.target, basedOn: fixture.target)
            #expect(throws: (any Error).self) {
                try fixture.store.prepareImportDestination(unused.target, basedOn: fixture.target)
            }
        }
    }

    @Test func anUnusedProfileDestinationPersistsBeforeNativeAdmission() throws {
        try withUnused { fixture, unused in
            let destination = try fixture.store.prepareImportDestination(unused.target, basedOn: fixture.target)
            let reloaded = try BrowserStore(directory: fixture.directory)
            #expect(destination.isCurrent(in: reloaded.state))
        }
    }

    @Test func profileRetirementInvalidatesAnIssuedTargetAndRemovesItFromChoices() throws {
        try withCommitted { fixture in
            let separate = try fixture.store.createImportDestination(name: "Imported Work", basedOn: fixture.target)
            let separateTarget = BrowserImportProfileTarget(profileID: separate.profileID, spaceID: separate.spaceID)
            var retired = fixture.store.state
            retired.profileRemovals.append(.init(id: UUID(), profileID: separate.profileID, profileName: "Imported Work"))
            #expect(!separateTarget.isCurrent(in: retired))
            #expect(!BrowserImportProfileTarget.choices(in: retired, original: fixture.target).contains(separateTarget))
        }
    }

    @Test func aReassignedSpaceNeverSilentlyRetargetsNativeData() throws {
        try withCommitted { fixture in
            let separate = try fixture.store.createImportDestination(name: "Imported Work", basedOn: fixture.target)
            let separateTarget = BrowserImportProfileTarget(profileID: separate.profileID, spaceID: separate.spaceID)
            var reassigned = fixture.store.state
            let index = try #require(reassigned.spaces.firstIndex { $0.id == separate.spaceID })
            reassigned.spaces[index].profileID = fixture.target.profileID
            #expect(!separateTarget.isCurrent(in: reassigned))
        }
    }

    @Test func aFailedUnusedDestinationSavePreservesBothCollections() throws {
        try withCommitted { fixture in
            let failureProfile = fixture.store.createProfile(name: "Unused failure")
            try fixture.store.save()
            let before = fixture.store.state
            try fixture.refuseWrites()
            #expect(throws: (any Error).self) {
                try fixture.store.prepareImportDestination(.init(profileID: failureProfile, spaceID: nil), basedOn: fixture.target)
            }
            #expect(fixture.store.state.spaces == before.spaces && fixture.store.state.profiles == before.profiles)
        }
    }

    @Test func aFailedNewDestinationSaveLeavesNoHalfCreatedProfileOrSpace() throws {
        try withCommitted { fixture in
            let before = fixture.store.state
            try fixture.refuseWrites()
            #expect(throws: (any Error).self) {
                try fixture.store.createImportDestination(name: "Personal", basedOn: fixture.target)
            }
            #expect(fixture.store.state.spaces == before.spaces && fixture.store.state.profiles == before.profiles)
        }
    }
}
