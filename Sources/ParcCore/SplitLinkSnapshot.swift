import Foundation

/// Window-local presentation state captured before an original split request.
/// Native separately owns the exact source document and BrowserContext lease.
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
