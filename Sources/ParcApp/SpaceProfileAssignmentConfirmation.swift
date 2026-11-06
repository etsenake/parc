import AppKit

///
///
/// in its `Dialogs` sheet at the inter-Profile width: "Switch to your <Profile>
///
///
/// illustration is not reproduced.
@MainActor enum SpaceProfileAssignmentConfirmation {
    static func present(on window: NSWindow, store: BrowserStore, space: BrowserSpace, profile: BrowserProfile,
                        ownerValid: @escaping () -> Bool,
                        completion: @escaping (Result<Bool, Error>) -> Void) {
        let ids = Set(store.state.tabs.filter { $0.spaceID == space.id && $0.kind != .favorite && $0.archivedAt == nil }.map(\.id))
        let valid: () -> Bool = {
            ownerValid() && store.state.spaces.contains { $0.id == space.id && $0.profileID == space.profileID }
                && store.state.profiles.contains { $0.id == profile.id }
                && !store.isProfileRemovalPending(profile.id) && !store.isProfileRemovalPending(space.profileID)
                && Set(store.state.tabs.filter { $0.spaceID == space.id && $0.kind != .favorite && $0.archivedAt == nil }.map(\.id)) == ids
        }
        guard space.profileID != profile.id, window.attachedSheet == nil, valid() else { completion(.success(false)); return }
        let dialog = PArcDialog(.init(
            title: [("Switch to your ", false), (profile.name, true), (" Profile?", false)],
            message: [("Each Profile has different browser data, so your ", false), (space.name, true),
                      (" Space might look a little different!\n\nFor example, you might get logged out of some websites, see different Favorites up top, or need to re-install an extension.\n\nThis action cannot be undone.", false)],
            confirm: "Switch", cancel: "Cancel", width: CGFloat(InterProfileMovePrompt.dialogWidth)))
        let began = dialog.begin(for: window) { [weak window] response in
            DispatchQueue.main.async {
                guard response == .confirm, window != nil, valid() else { completion(.success(false)); return }
                store.assignProfile(profile.id, toSpace: space.id, shouldCommit: valid, completion: completion)
            }
        }
        if !began { completion(.success(false)) }
    }
}
