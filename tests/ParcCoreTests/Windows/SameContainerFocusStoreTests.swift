import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SameContainerFocusStoreTests {
    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let originalSpace: UUID
        let favorite: UUID
        let destination: UUID
        let actualPrevious: UUID
        var validate: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        var result: Bool?
        var admitted = false

        init() throws {
            store = try BrowserStore(directory: directory)
            originalSpace = store.activeSpaceID
            favorite = store.open("https://favorite.example", kind: .favorite)
            destination = store.createSpace(name: "Destination")
            actualPrevious = store.open("https://previous.example")
            store.selectSpace(originalSpace)
            store.selectTab(favorite)
            store.requestPageRetirement = { [unowned self] _, gate, done in validate = gate; finish = done }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func receipt() throws -> FolderRemovalSelection {
            try #require(FolderRemovalSelection.resolve(removing: [favorite], spaceID: originalSpace,
                profileID: store.activeSpace.profileID, state: store.state, selected: [favorite], focused: favorite,
                previouslySelectedItemID: actualPrevious, available: { _ in true }))
        }

        func close(_ selection: FolderRemovalSelection) {
            store.closeTabs([favorite], selection: selection, shouldCommit: { true }) { [unowned self] in result = $0 }
            admitted = validate?() == true
        }
    }

    @Test func beforeunloadDoesNotSwitchSpaceOrSelectionEarly() throws {
        let f = try Fixture()
        f.close(try f.receipt())
        #expect(f.result == nil && f.store.activeSpaceID == f.originalSpace && f.store.state.selectedTabIDs == [f.favorite])
        #expect(f.admitted)
    }

    @Test func aRefusalPreservesTheOriginalPhysicalContextAndARetryKeepsTheBinding() throws {
        let f = try Fixture()
        let receipt = try f.receipt()
        f.close(receipt)
        f.finish?(false)
        #expect(f.result == false && f.store.activeSpaceID == f.originalSpace)
        f.close(receipt)
        #expect(f.admitted)
    }

    @Test func anApprovedClosePublishesTheDestinationSpaceAndOriginalItemAtomically() throws {
        let f = try Fixture()
        f.close(try f.receipt())
        f.finish?(true)
        #expect(f.result == true && f.store.activeSpaceID == f.destination && f.store.state.selectedTabIDs == [f.actualPrevious])
        #expect(f.store.state.tabs.contains { $0.id == f.favorite && $0.archivedAt == nil })
    }

    @Test func theOriginalPhysicalWindowConsumesTheApprovedDestination() throws {
        let f = try Fixture()
        let receipt = try f.receipt()
        var window = WindowPresentation(state: f.store.state, ready: true)
        f.close(receipt)
        f.finish?(true)
        window.remove(f.favorite)
        let finished = window.finishFolderRemoval(receipt, state: f.store.state, available: { _ in true })
        #expect(finished)
        #expect(window.activeSpaceID == f.destination && window.selectedTabIDs == [f.actualPrevious])
    }

    @Test func theDurableSessionRetainsTheReturnedSpaceAndSelection() throws {
        let f = try Fixture()
        f.close(try f.receipt())
        f.finish?(true)
        try f.store.save()
        let loaded = try BrowserStore(directory: f.directory)
        #expect(loaded.activeSpaceID == f.destination && loaded.state.selectedTabIDs == [f.actualPrevious])
    }

    @Test func aDestinationArchivedDuringNativeConsentRevokesTheReceipt() throws {
        let f = try Fixture()
        f.close(try f.receipt())
        f.finish?(true)
        f.store.selectSpace(f.originalSpace)
        f.store.selectTab(f.favorite)
        f.result = nil
        f.close(try f.receipt())
        #expect(f.admitted)
        f.store.requestPageRetirement = nil
        f.store.closeTab(f.actualPrevious)
        #expect(f.validate?() == false)
        f.finish?(true)
        #expect(f.result == false && f.store.activeSpaceID == f.originalSpace)
    }

    @Test func folderDeleteUsesTheSameOuterContainerReturnAndSurvivesTheSavedSession() throws {
        let f = try Fixture()
        let keptFolder = f.store.createFolder(name: "Keep")
        let kept = f.store.open("https://kept.example", kind: .pinned)
        f.store.moveTab(kept, toSpace: f.originalSpace, folderID: keptFolder)
        let deletedFolder = f.store.createFolder(name: "Delete")
        let doomed = f.store.open("https://doomed.example", kind: .pinned)
        f.store.moveTab(doomed, toSpace: f.originalSpace, folderID: deletedFolder)
        let target = try #require(FolderRemovalTarget(folderID: deletedFolder, spaceID: f.originalSpace,
            profileID: f.store.activeSpace.profileID, state: f.store.state))
        let choice = try #require(FolderRemovalSelection.resolve(target: target, state: f.store.state,
            selected: [doomed], focused: doomed, previouslySelectedItemID: kept, available: { _ in true }))
        #expect(choice.tabIDs == [kept])
        var deletion: Result<Bool, Error>?
        f.store.deleteFolder(target, selection: choice, shouldCommit: { true }) { deletion = $0 }
        #expect(f.validate?() == true && f.store.state.selectedTabIDs == [doomed])
        f.finish?(true)
        let deleted = (try? deletion?.get()) == true
        #expect(deleted && f.store.state.selectedTabIDs == [kept] && !f.store.state.folders.contains { $0.id == deletedFolder })
        try f.store.save()
        let reloaded = try BrowserStore(directory: f.directory)
        #expect(reloaded.state.selectedTabIDs == [kept])
        #expect(reloaded.state.tabs.contains { $0.id == doomed && $0.archivedAt != nil })
    }
}
