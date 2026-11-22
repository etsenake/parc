import Foundation
import Testing
@testable import ParcCore

extension SpaceDeletionTestsSupport {
    @MainActor
    struct SpaceDeletionUndoAndRenameTests {
        func scratchDirectory(writing state: BrowserState) throws -> URL {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
            return directory
        }

        @Test func aMissingDocumentDisablesUndoWithoutConsumingHistory() throws {
            let fixture = try Fixture()
            let undo = fixture.deleteSource()
            fixture.documentAvailable = false
            #expect(try !fixture.store.undoSpaceDeletion(undo, shouldCommit: { true }))
            fixture.documentAvailable = true
            #expect(try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true }))
        }

        @Test func undoRestoresTheOriginalSpacePositionAndFolders() throws {
            let fixture = try Fixture()
            let undo = fixture.deleteSource()
            fixture.store.updateTab(fixture.favorite1.id, title: "Live favorite title")
            #expect(try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true }))
            #expect(fixture.store.state.spaces.map(\.id) == [fixture.source.id, fixture.other.id])
            #expect(fixture.store.state.folders == [fixture.folder])
        }

        @Test func undoDoesNotRewindLiveFavorites() throws {
            let fixture = try Fixture()
            let undo = fixture.deleteSource()
            fixture.store.updateTab(fixture.favorite1.id, title: "Live favorite title")
            _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
            #expect(fixture.store.state.tabs.first { $0.id == fixture.favorite1.id }?.title == "Live favorite title")
        }

        @Test func aTypedAliasRetainsItsDocumentIdentityAfterUndo() throws {
            let fixture = try Fixture()
            let undo = fixture.deleteSource()
            _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
            #expect(fixture.store.state.tabs.first { $0.id == fixture.note.id }?.savedURL == fixture.page.urlString)
        }

        @Test func undoRestoresTheOriginalFavoriteStorageAnchor() throws {
            let fixture = try Fixture()
            let undo = fixture.deleteSource()
            _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
            #expect(fixture.store.state.splitLayouts.first?.spaceID == fixture.source.id)
        }

        @Test func redoBindsOriginalMembershipUntilANewChildAppears() throws {
            let fixture = try Fixture()
            let undo = fixture.deleteSource()
            _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
            #expect(undo.redoTarget(in: fixture.store.state) != nil)
            fixture.store.selectSpace(fixture.source.id)
            _ = fixture.store.openResolvedURL(URL(string: "https://new.test")!)
            #expect(undo.redoTarget(in: fixture.store.state) == nil)
        }

        @Test func reorderingSpacesAcceptsTheCurrentOrder() throws {
            let fixture = try Fixture()
            let originalOrder = fixture.store.state.spaces.map(\.id)
            #expect(try fixture.store.reorderSpace(fixture.other.id, before: fixture.source.id, expectedOrder: originalOrder))
        }

        @Test func reorderingSpacesRefusesAStaleOrder() throws {
            let fixture = try Fixture()
            let originalOrder = fixture.store.state.spaces.map(\.id)
            _ = try fixture.store.reorderSpace(fixture.other.id, before: fixture.source.id, expectedOrder: originalOrder)
            #expect(try !fixture.store.reorderSpace(fixture.source.id, before: fixture.other.id, expectedOrder: originalOrder))
        }

        @Test func aFolderRenameSavesImmediately() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let expected = initial.folders[0], profile = initial.spaces[0].profileID
            #expect(try store.renameFolder(expected, profileID: profile, name: "Renamed"))
            #expect(try BrowserStore(directory: directory).state.folders[0].name == "Renamed")
        }

        @Test func aFolderRenameRefusesAStaleName() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let expected = initial.folders[0], profile = initial.spaces[0].profileID
            _ = try store.renameFolder(expected, profileID: profile, name: "Renamed")
            #expect(try !store.renameFolder(expected, profileID: profile, name: "Stale"))
        }

        @Test func aFolderRenameRefusesAMovedTarget() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let current = store.state.folders[0]
            var moved = current
            moved.spaceID = initial.spaces[1].id
            #expect(try !store.renameFolder(moved, profileID: initial.spaces[1].profileID, name: "Stale"))
        }

        @Test func aFolderRenameRefusesAReparentedTarget() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let profile = initial.spaces[0].profileID
            let current = store.state.folders[0]
            var reparented = current
            reparented.parentID = UUID()
            #expect(try !store.renameFolder(reparented, profileID: profile, name: "Stale"))
        }

        @Test func aFolderRenameRefusesAReassignedTarget() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let current = store.state.folders[0]
            #expect(try !store.renameFolder(current, profileID: initial.profiles.last!.id, name: "Stale"))
        }

        @Test func folderRenamesPreserveIndependentDisclosure() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let profile = initial.spaces[0].profileID
            let current = store.state.folders[0]
            store.toggleFolder(current.id)
            #expect(try store.renameFolder(current, profileID: profile, name: "Disclosure kept"))
            #expect(store.state.folders[0].isExpanded != current.isExpanded)
        }

        @Test func aFolderRenameWriteFailurePreservesPublishedState() throws {
            let initial = try Fixture().initial
            let directory = try scratchDirectory(writing: initial)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let before = store.state
            try FileManager.default.removeItem(at: directory)
            try Data().write(to: directory)
            #expect(throws: (any Error).self) {
                try store.renameFolder(before.folders[0], profileID: initial.spaces[0].profileID, name: "Not saved")
            }
            #expect(store.state == before)
            try FileManager.default.removeItem(at: directory)
        }
    }
}
