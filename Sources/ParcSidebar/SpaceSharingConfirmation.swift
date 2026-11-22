import AppKit
import ParcCore
import ParcKit

@MainActor package enum SpaceSharingConfirmation {
    package static func present(on window: NSWindow, store: BrowserStore, spaceID: UUID, sharing: SpaceDataSharing,
                        ownerValid: @escaping () -> Bool,
                        explain: @escaping (InterProfileDocumentBlock) -> Void,
                        completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let space = store.state.spaces.first(where: { $0.id == spaceID }) else { completion(.success(false)); return }
        let target = sharing.partner.flatMap { id in store.state.spaces.first { $0.id == id } }
        func openTabs() -> Set<UUID> {
            Set(store.state.openTabs(where: { $0.spaceID == spaceID && $0.kind != .favorite }).map(\.id))
        }
        let ids = openTabs()
        let valid: () -> Bool = {
            guard ownerValid(),
                  store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == space.profileID }),
                  !store.isProfileRemovalPending(space.profileID), openTabs() == ids else { return false }
            guard let target else { return sharing == .separate }
            return store.state.spaces.contains { $0.id == target.id && $0.profileID == target.profileID }
                && !store.isProfileRemovalPending(target.profileID)
        }
        guard window.attachedSheet == nil, valid() else { completion(.success(false)); return }
        if let block = store.sharingDocumentBlock(forSpace: spaceID, to: sharing) {
            explain(block); completion(.success(false)); return
        }
        guard let warning = store.sharingWarning(forSpace: spaceID, to: sharing) else { completion(.success(false)); return }
        let stillWarned: () -> Bool = { valid() && store.sharingWarning(forSpace: spaceID, to: sharing) == warning }
        let dialog = ParcDialog(.init(
            title: [(warning.title, false)], message: [(warning.message, false)],
            confirm: warning.confirm, cancel: "Cancel", width: CGFloat(InterProfileMovePrompt.dialogWidth),
            destructive: warning.destructive))
        let began = dialog.begin(for: window) { [weak window] response in
            DispatchQueue.main.async {
                guard response == .confirm, window != nil, stillWarned() else { completion(.success(false)); return }
                store.changeSharing(ofSpace: spaceID, to: sharing, shouldCommit: stillWarned) { result in
                    switch result {
                    case .success(let change):
                        if let unused = change?.unusedProfile { handOff(unused) }
                        if change == nil, let block = store.sharingDocumentBlock(forSpace: spaceID, to: sharing) { explain(block) }
                        completion(.success(change != nil))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
        if !began { completion(.success(false)) }
    }

    package static func handOff(_ unused: UnusedProfile) {
        ProfileRemovalController.shared.remove(profileID: unused.id, expectedName: unused.name)
    }
}

extension SpaceDataSharing {
    var partner: UUID? {
        if case .share(let id) = self { return id }
        return nil
    }
}
