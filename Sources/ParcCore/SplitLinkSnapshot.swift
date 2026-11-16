import Foundation

struct SplitLinkSnapshot: Equatable {
    let spaceID: UUID
    let profileID: UUID
    let selection: [UUID]
    let focusedID: UUID
    let sourceURL: URL?
    let generation: UInt64

    func accepts(spaceID: UUID, profileID: UUID, selection: [UUID],
                 focusedID: UUID?, sourceURL: URL?, generation: UInt64) -> Bool {
        self.spaceID == spaceID && self.profileID == profileID &&
            self.selection == selection && self.focusedID == focusedID &&
            self.sourceURL == sourceURL && self.generation == generation &&
            selection.contains(self.focusedID)
    }
}

enum LinkClickPane {
    static func id(selection: [UUID], current: UUID?, rendered: [UUID],
                   covered: (UUID) -> Bool, shows: (UUID) -> Bool) -> UUID? {
        selection.first { ($0 == current || rendered.contains($0)) && !covered($0) && shows($0) }
    }
}
