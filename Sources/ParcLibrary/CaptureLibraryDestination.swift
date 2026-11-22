import Foundation
import ParcCore

@MainActor
package struct CaptureLibraryDestination {
    let store: BrowserStore
    let profileID: UUID
    let spaceID: UUID
    let spaceName: String
    package let allowsEasels: Bool
    package let library: CaptureLibraryStore

    package static func make(store: BrowserStore, parent: BrowserStore?, profileID: UUID,
                     spaceID: UUID) -> CaptureLibraryDestination? {
        guard store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return nil }
        let owner: BrowserStore, targetProfile: UUID, targetSpace: UUID, name: String
        if store.isEphemeral {
            guard let parent, !parent.isEphemeral, let original = store.privateParentProfileID,
                  parent.state.profiles.contains(where: { $0.id == original }),
                  !parent.isProfileRemovalPending(original) else { return nil }
            owner = parent; targetProfile = original
            targetSpace = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            name = "Incognito"
        } else {
            guard store.state.profiles.contains(where: { $0.id == profileID }),
                  !store.isProfileRemovalPending(profileID),
                  let space = store.state.spaces.first(where: { $0.id == spaceID && $0.profileID == profileID }) else { return nil }
            owner = store; targetProfile = profileID; targetSpace = space.id; name = space.name
        }
        return .init(store: owner, profileID: targetProfile, spaceID: targetSpace,
                     spaceName: name, allowsEasels: !store.isEphemeral,
                     library: CaptureLibraryStore.shared(directory: owner.capturesDirectory(for: targetProfile), profileID: targetProfile))
    }

    package func reserve() -> ProfileWriteReservation? { store.reserveProfileWrite(profileID) }
    package func input(id: UUID, expectedRevision: UUID?, capturedAt: Date, title: String,
               sourceURL: String, kind: SavedCapture.Kind, pngData: Data) -> CaptureLibraryInput {
        .init(id: id, expectedRevision: expectedRevision, capturedAt: capturedAt,
              profileID: profileID, spaceID: spaceID, spaceName: spaceName,
              title: title, sourceURL: sourceURL, kind: kind, pngData: pngData)
    }
    package func easels(_ provider: () throws -> [CaptureEaselDestination]) rethrows -> [CaptureEaselDestination] {
        allowsEasels ? try provider() : []
    }
}
