import Foundation
import Testing
@testable import ParcCore

extension SpaceDeletionTestsSupport {
    @MainActor
    struct SpaceDeletionRetirementTests {
        @Test func deletionRequiresATypedDocumentCapabilityBeforeClosing() throws {
            let fixture = try Fixture()
            fixture.remove(fixture.target(), documents: [:])
            #expect(fixture.completed == false)
            #expect(fixture.requests.isEmpty)
        }

        @Test func onlyOriginalNonFavoriteContentsRetireAndNothingMutatesBeforeConsent() throws {
            let fixture = try Fixture()
            fixture.remove(fixture.target())
            #expect(fixture.requests.count == 1)
            #expect(fixture.requests[0].0 == [fixture.saved.id, fixture.today.id, fixture.note.id])
            #expect(fixture.completed == nil)
            #expect(fixture.store.state.spaces.count == 2)
        }

        @Test func refusalPreservesTheWholeSpace() throws {
            let fixture = try Fixture()
            fixture.remove(fixture.target())
            fixture.requests.removeFirst().2(false)
            #expect(fixture.completed == false)
            #expect(fixture.store.state.spaces.count == 2)
        }

        @Test func oneDurableDeletionCommitsAfterConsent() throws {
            let fixture = try Fixture()
            fixture.remove(fixture.target())
            #expect(fixture.requests[0].1())
            fixture.requests.removeFirst().2(true)
            #expect(fixture.completed == true)
            #expect(fixture.failure == nil)
            #expect(fixture.record != nil)
        }

        @Test func onlyTheOriginalSpaceAndItsFoldersAreRemoved() throws {
            let fixture = try Fixture()
            _ = fixture.deleteSource()
            #expect(fixture.store.state.spaces.map(\.id) == [fixture.other.id])
            #expect(fixture.store.state.folders.isEmpty)
        }

        @Test func theArchiveRetainsOriginalProvenance() throws {
            let fixture = try Fixture()
            let target = fixture.target()
            _ = fixture.deleteSource()
            let archived = fixture.store.state.tabs.filter { target.tabIDs.contains($0.id) }
            #expect(!archived.isEmpty)
            #expect(archived.allSatisfy { $0.archivedAt != nil && $0.archiveProvenance?.spaceID == fixture.source.id })
        }

        @Test func profileFavoritesAreRetained() throws {
            let fixture = try Fixture()
            _ = fixture.deleteSource()
            let favorites = fixture.store.state.tabs.filter { $0.kind == .favorite }
            #expect(favorites.count == 2)
            #expect(favorites.allSatisfy { $0.archivedAt == nil && $0.profileID == fixture.profile })
        }

        @Test func theFavoriteSplitStaysIntactAndSurvivesPersistence() throws {
            let fixture = try Fixture()
            _ = fixture.deleteSource()
            #expect(fixture.store.state.splitLayouts.first?.id == fixture.favorites.id)
            #expect(fixture.store.state.splitLayouts.first?.widthFactors == [0.4, 0.6])
            let reload = try BrowserStore(directory: fixture.directory)
            #expect(reload.state.splitLayouts.first?.id == fixture.favorites.id)
        }

        @Test func theLastSpaceCannotBeDeleted() throws {
            let fixture = try Fixture()
            _ = fixture.deleteSource()
            #expect(SpaceDeletionTarget(spaceID: fixture.other.id, state: fixture.store.state) == nil)
        }

        @Test func aForeignProfileFavoriteAnchorDoesNotPreventSubsequentDeletion() throws {
            let fixture = try Fixture()
            _ = fixture.deleteSource()
            var parked = fixture.store.state
            let third = BrowserSpace(id: UUID(), name: "Third", symbol: "circle", color: "AABBCC", profileID: fixture.otherProfile.id)
            parked.spaces.append(third)
            let parkedTarget = SpaceDeletionTarget(spaceID: fixture.other.id, state: parked)
            #expect(parkedTarget != nil)
            let parkedDeletion = parkedTarget.flatMap { SpaceDeletionUndo.make(target: $0, state: parked, now: fixture.now, documents: [:]) }
            #expect(parkedDeletion?.1.splitLayouts.first?.spaceID == third.id)
        }

        @Test func aDiskFailurePublishesNoPartialDeletionOrNewProfile() throws {
            let fixture = try Fixture()
            let beforeFailure = fixture.store.state
            fixture.remove(fixture.target())
            #expect(fixture.requests[0].1())
            try FileManager.default.removeItem(at: fixture.directory)
            try Data().write(to: fixture.directory)
            fixture.requests.removeFirst().2(true)
            #expect(fixture.failure != nil)
            #expect(fixture.store.state == beforeFailure)
            #expect(throws: (any Error).self) { try fixture.store.createProfilePersisted(name: "Not saved") }
            #expect(fixture.store.state == beforeFailure)
        }
    }
}
