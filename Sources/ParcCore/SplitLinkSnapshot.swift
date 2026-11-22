import Foundation

package struct SplitLinkSnapshot: Equatable {
    let spaceID: UUID
    let profileID: UUID
    package let selection: [UUID]
    package let focusedID: UUID
    let sourceURL: URL?
    let generation: UInt64

    package init(spaceID: UUID, profileID: UUID, selection: [UUID], focusedID: UUID, sourceURL: URL?, generation: UInt64) {
        self.spaceID = spaceID
        self.profileID = profileID
        self.selection = selection
        self.focusedID = focusedID
        self.sourceURL = sourceURL
        self.generation = generation
    }

    package func accepts(spaceID: UUID, profileID: UUID, selection: [UUID],
                 focusedID: UUID?, sourceURL: URL?, generation: UInt64) -> Bool {
        self.spaceID == spaceID && self.profileID == profileID &&
            self.selection == selection && self.focusedID == focusedID &&
            self.sourceURL == sourceURL && self.generation == generation &&
            selection.contains(self.focusedID)
    }
}

package enum LinkClickPane {
    package static func id(selection: [UUID], current: UUID?, rendered: [UUID],
                   covered: (UUID) -> Bool, shows: (UUID) -> Bool) -> UUID? {
        selection.first { ($0 == current || rendered.contains($0)) && !covered($0) && shows($0) }
    }
}
