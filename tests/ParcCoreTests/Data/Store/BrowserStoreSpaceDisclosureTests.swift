import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceDisclosureTests {
    @MainActor
    private struct DisclosureFixture {
        let store: BrowserStore
        let space: UUID
        let profile: UUID
        let origin: [BrowserFolder]
        let other: UUID

        func collapse() throws {
            try #require(try store.setFoldersExpanded(false, in: space, profileID: profile, expectedFolders: origin))
        }
    }

    @MainActor
    private static func disclosure(in directory: URL) throws -> DisclosureFixture {
        let store = try BrowserStore(directory: directory)
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        let parent = store.createFolder(name: "Parent")
        let child = store.createFolder(name: "Child", parentID: parent)
        let saved = store.open("https://folder.example.org/selected")
        store.moveTab(saved, toSpace: space, folderID: child)
        store.toggleFolder(parent)
        let origin = store.state.folders.filter { $0.spaceID == space }
        let other = store.createSpace(name: "Other window")
        _ = store.createFolder(name: "Leave expanded")
        _ = store.open("https://other.example.org/current")
        return DisclosureFixture(store: store, space: space, profile: profile, origin: origin, other: other)
    }

    @Test @MainActor static func bulkCollapseIncludesHiddenDescendantsAndPublishesOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try disclosure(in: directory)
            let store = fixture.store
            let space = fixture.space
            let profile = fixture.profile
            let origin = fixture.origin
            let other = fixture.other
            let before = store.state
            var publications: [BrowserState] = []
            let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
            #expect(try store.setFoldersExpanded(false, in: space, profileID: profile,
                                                    expectedFolders: origin), "Original Space remains an eligible disclosure owner")
            var expected = before
            for index in expected.folders.indices where expected.folders[index].spaceID == space {
                expected.folders[index].isExpanded = false
            }
            #expect(store.state == expected, "Collapse includes hidden descendants and changes no browsing state or foreign folder")
            #expect(publications == [expected], "Bulk collapse publishes only the complete folder change")
            #expect(store.activeSpaceID == other, "A folder command cannot steal another window's shared store context")
            observation.cancel()
        }
    }

    @Test @MainActor static func repeatingBulkCollapseDoesNotPublishAgain() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try disclosure(in: directory)
            let store = fixture.store
            let space = fixture.space
            let profile = fixture.profile
            var publications: [BrowserState] = []
            let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
            try fixture.collapse()
            let collapsed = store.state.folders.filter { $0.spaceID == space }
            #expect(try store.setFoldersExpanded(false, in: space, profileID: profile,
                                                    expectedFolders: collapsed), "Repeated matching disclosure is an idempotent success")
            #expect(publications.count == 1, "No-op disclosure does not publish again")
            observation.cancel()
        }
    }

    @Test @MainActor static func bulkExpansionRejectsStaleFolderSnapshotsAndForeignProfiles() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try disclosure(in: directory)
            let store = fixture.store
            let space = fixture.space
            let profile = fixture.profile
            let origin = fixture.origin
            try fixture.collapse()
            let expected = store.state
            let collapsed = store.state.folders.filter { $0.spaceID == space }
            #expect(!(try store.setFoldersExpanded(true, in: space, profileID: profile,
                                                       expectedFolders: origin)), "A stale folder snapshot cannot overwrite later disclosure")
            #expect(!(try store.setFoldersExpanded(true, in: space, profileID: UUID(),
                                                       expectedFolders: collapsed)), "Changed Profile ownership rejects before mutation")
            #expect(store.state == expected, "Rejected commands preserve the exact session")
        }
    }

    @Test @MainActor static func bulkExpansionRestoresEveryDescendantAndPersistsDisclosure() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try disclosure(in: directory)
            let store = fixture.store
            let space = fixture.space
            let profile = fixture.profile
            try fixture.collapse()
            var expected = store.state
            let collapsed = store.state.folders.filter { $0.spaceID == space }
            #expect(try store.setFoldersExpanded(true, in: space, profileID: profile,
                                                    expectedFolders: collapsed), "Expand restores all nested folder disclosure")
            for index in expected.folders.indices where expected.folders[index].spaceID == space {
                expected.folders[index].isExpanded = true
            }
            #expect(store.state == expected, "Expand leaves original tabs, selection, profiles and URL metadata unchanged")
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.folders == expected.folders, "Bulk disclosure is durably saved before success")
        }
    }

    @Test @MainActor static func failedFolderDisclosureSaveLeavesEveryFolderUntouched() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let saved = store.open("https://folder.example.org/selected")
            store.moveTab(saved, toSpace: space, folderID: child)
            store.toggleFolder(parent)
            let origin = store.state.folders.filter { $0.spaceID == space }
            let expected = store.state
            try store.save()
            let session = directory.appendingPathComponent("session.json")
            let backup = directory.appendingPathComponent("saved-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            var writeFailed = false
            do {
                _ = try store.setFoldersExpanded(false, in: space, profileID: profile,
                    expectedFolders: origin)
            } catch { writeFailed = true }
            #expect(writeFailed && store.persistenceError != nil, "A refused atomic save reports the real failure")
            #expect(store.state == expected, "Failed persistence never publishes a folder change")
            try FileManager.default.removeItem(at: session)
            try FileManager.default.moveItem(at: backup, to: session)
        }
    }

    @Test @MainActor static func favoriteSelectionAfterProfileReassignment() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let sameProfileSpace = store.createSpace(name: "Same profile")
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: originalSpace)
            store.selectSpace(originalSpace)
            store.selectTab(favorite)
            #expect(store.activeSpaceID == sameProfileSpace, "Selecting a favorite after its origin Space changes profile must choose a Space using the favorite's profile")
            try BrowserStoreTestsSupport.expectValidSelection(store)
        }
    }

    enum RelationshipDamage: CaseIterable { case cycle, missingFolder, wrongProfile }

    @Test(arguments: RelationshipDamage.allCases)
    @MainActor static func invalidRelationshipsAreRejectedWithoutRewritingTheSession(_ damage: RelationshipDamage) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            _ = store.open("https://example.org")
            let folder = store.createFolder(name: "Folder")
            let otherProfile = store.createProfile(name: "Other")
            var valid = store.state
            valid.settings.restoreSession = false
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let file = directory.appendingPathComponent("session.json")
            switch damage {
            case .cycle: valid.folders[0].parentID = folder
            case .missingFolder: valid.tabs[0].folderID = UUID()
            case .wrongProfile: valid.tabs[0].profileID = otherProfile
            }
            let data = try encoder.encode(valid)
            try data.write(to: file)
            #expect(throws: (any Error).self) { try BrowserStore(directory: directory) }
            #expect(try Data(contentsOf: file) == data)
        }
    }
}
