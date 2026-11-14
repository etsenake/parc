import Foundation

enum SpaceSharing {
    static let version = 1
}

enum SpaceDataSharing: Equatable {
    case share(withSpace: UUID)
    case separate
}

struct UnusedProfile: Equatable {
    let id: UUID
    let name: String
}

struct SpaceSharingChange: Equatable {
    let spaceID: UUID
    let profileID: UUID
    let previousProfileID: UUID
    let unusedProfile: UnusedProfile?
}

enum SpaceSharingWarning: Equatable {
    case share(target: String, space: String, discardsOwnData: Bool)
    case keepSeparate(space: String)

    static let deletionNote = "This also deletes its logins, saved passwords and history. This can’t be undone."

    static func choose(_ sharing: SpaceDataSharing, space: String, target: String?, joinsOtherData: Bool,
                       spaceSharesData: Bool, discardsOwnData: Bool) -> SpaceSharingWarning? {
        switch sharing {
        case .share:
            guard joinsOtherData, let target else { return nil }
            return .share(target: target, space: space, discardsOwnData: discardsOwnData)
        case .separate:
            return spaceSharesData ? .keepSeparate(space: space) : nil
        }
    }

    var title: String {
        switch self {
        case .share(let target, let space, _): return "Share \(target)’s data with \(space)?"
        case .keepSeparate(let space): return "Keep \(space) separate?"
        }
    }

    var message: String {
        switch self {
        case .share(let target, let space, true):
            return "\(space)’s pages will reload signed in as \(target). \(space)’s own logins, saved passwords and history will be deleted. This can’t be undone."
        case .share(let target, let space, false):
            return "\(space)’s pages will reload with \(target)’s logins, history, extensions and Favorites."
        case .keepSeparate:
            return "It starts fresh: signed out of every site, with no history, extensions or Favorites."
        }
    }

    var confirm: String {
        switch self {
        case .share: return "Share Data"
        case .keepSeparate: return "Keep Separate"
        }
    }

    var destructive: Bool {
        if case .share(_, _, true) = self { return true }
        return false
    }
}

extension BrowserState {
    func resolvedAutoArchiveHours(forSpace id: UUID) -> Double {
        guard let space = spaces.first(where: { $0.id == id }) else { return autoArchiveDefaultHours }
        return space.autoArchiveHours ?? profiles.first { $0.id == space.profileID }?.autoArchiveHours ?? autoArchiveDefaultHours
    }

    var profilesWithoutSpaces: [BrowserProfile] {
        profiles.filter { profile in
            !spaces.contains { $0.profileID == profile.id } && !profileRemovals.contains { $0.profileID == profile.id }
        }
    }

    @discardableResult
    mutating func upgradeSpaceSharing() -> Bool {
        guard spaceSharingVersion < SpaceSharing.version, !spaces.isEmpty else { return false }
        let template = spaces.first { $0.id == activeSpaceID } ?? spaces[0]
        for profile in profilesWithoutSpaces {
            var space = BrowserSpace(id: UUID(), name: profile.name, symbol: "circle.fill", color: "B9B5D4", profileID: profile.id)
            space.theme = template.theme
            spaces.append(space)
        }
        for index in spaces.indices {
            if spaces[index].autoArchiveHours == nil {
                spaces[index].autoArchiveHours = profiles.first { $0.id == spaces[index].profileID }?.autoArchiveHours
            }
            spaces[index].updateDisplayName(position: index)
        }
        spaceSharingVersion = SpaceSharing.version
        return true
    }
}

extension BrowserStore {
    func autoArchiveInterval(forSpace spaceID: UUID) -> AutoArchiveInterval? {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return nil }
        return space.autoArchiveHours.flatMap(AutoArchiveInterval.init(rawValue:)) ?? autoArchiveInterval(for: space.profileID)
    }

    @discardableResult
    func setAutoArchiveInterval(_ interval: AutoArchiveInterval, forSpace spaceID: UUID) throws -> Bool {
        guard let index = state.spaces.firstIndex(where: { $0.id == spaceID }),
              !isProfileRemovalPending(state.spaces[index].profileID) else { throw ProfileSettingsError.unavailable }
        guard state.spaces[index].autoArchiveHours != interval.rawValue else { return false }
        var next = state
        next.spaces[index].autoArchiveHours = interval.rawValue
        next.autoArchiveEducationEligible = false
        try commitProfileSettings(next)
        return true
    }

    func unusedProfile(_ profileID: UUID) -> UnusedProfile? {
        guard let profile = state.profiles.first(where: { $0.id == profileID }),
              !state.spaces.contains(where: { $0.profileID == profileID }),
              !isProfileRemovalPending(profileID) else { return nil }
        return UnusedProfile(id: profileID, name: profile.name)
    }

    private func soleProfile(of spaceID: UUID) -> UnusedProfile? {
        guard let space = state.spaces.first(where: { $0.id == spaceID }),
              let profile = state.profiles.first(where: { $0.id == space.profileID }),
              !isProfileRemovalPending(profile.id),
              !state.spaces.contains(where: { $0.id != spaceID && $0.profileID == space.profileID }) else { return nil }
        return UnusedProfile(id: profile.id, name: profile.name)
    }

    func unusedProfile(ifSpace spaceID: UUID, joins sharing: SpaceDataSharing) -> UnusedProfile? {
        guard case .share(let otherID) = sharing,
              let space = state.spaces.first(where: { $0.id == spaceID }),
              let other = state.spaces.first(where: { $0.id == otherID }),
              other.profileID != space.profileID else { return nil }
        return soleProfile(of: spaceID)
    }

    func sharingWarning(forSpace spaceID: UUID, to sharing: SpaceDataSharing) -> SpaceSharingWarning? {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return nil }
        var target: BrowserSpace?
        if case .share(let otherID) = sharing { target = state.spaces.first { $0.id == otherID && $0.id != spaceID } }
        return SpaceSharingWarning.choose(sharing, space: space.name, target: target?.name,
                                          joinsOtherData: target.map { $0.profileID != space.profileID } ?? false,
                                          spaceSharesData: !spaceSharing(of: spaceID).isEmpty,
                                          discardsOwnData: unusedProfile(ifSpace: spaceID, joins: sharing) != nil)
    }

    func wouldOrphanProfile(ifSpace spaceID: UUID, joins sharing: SpaceDataSharing) -> Bool {
        unusedProfile(ifSpace: spaceID, joins: sharing) != nil
    }

    func unusedProfile(ifDeletingSpace spaceID: UUID) -> UnusedProfile? { soleProfile(of: spaceID) }

    func wouldOrphanProfile(ifDeletingSpace spaceID: UUID) -> Bool { unusedProfile(ifDeletingSpace: spaceID) != nil }

    func stageRemoval(of unused: UnusedProfile) throws -> ProfileRemovalRecord {
        guard unusedProfile(unused.id) == unused else { throw ProfileRemovalError.unavailable }
        return try stageProfileRemoval(unused.id, expectedName: unused.name)
    }

    func spaceSharing(of spaceID: UUID) -> [BrowserSpace] {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return [] }
        return state.spaces.filter { $0.id != spaceID && $0.profileID == space.profileID }
    }

    func createSpace(_ draft: SidebarNewSpaceDraft, completion: @escaping (Result<UUID?, Error>) -> Void) {
        guard !isEphemeral, !draft.tabIDs.contains(where: { retiringTabIDs.contains($0) }) else { completion(.success(nil)); return }
        guard draft.movesItemsAcrossProfiles else {
            completion(Result { try createSpaceAndMoveSidebarItems(draft) })
            return
        }
        moveAcrossProfiles(Set(draft.tabIDs), proposal: { draft.applying(to: $0) }) { result in
            completion(result.map { $0 ? draft.spaceID : nil })
        }
    }

    func changeSharing(ofSpace spaceID: UUID, to sharing: SpaceDataSharing, newProfileID: UUID = UUID(),
                       shouldCommit: @escaping () -> Bool = { true },
                       completion: @escaping (Result<SpaceSharingChange?, Error>) -> Void) {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { completion(.success(nil)); return }
        let previous = space.profileID
        let target: UUID
        var created: BrowserProfile?
        switch sharing {
        case .share(let otherID):
            guard otherID != spaceID, let other = state.spaces.first(where: { $0.id == otherID }),
                  other.profileID != previous else { completion(.success(nil)); return }
            target = other.profileID
        case .separate:
            guard !spaceSharing(of: spaceID).isEmpty else { completion(.success(nil)); return }
            let name = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
            created = BrowserProfile(id: newProfileID, name: name.isEmpty ? "Profile" : name,
                                     autoArchiveHours: state.resolvedAutoArchiveHours(forSpace: spaceID))
            target = newProfileID
        }
        assignProfile(target, toSpace: spaceID, creating: created, shouldCommit: shouldCommit) { [weak self] result in
            completion(result.map { moved in
                guard moved, let self else { return nil }
                return SpaceSharingChange(spaceID: spaceID, profileID: target, previousProfileID: previous,
                                          unusedProfile: self.unusedProfile(previous))
            })
        }
    }
}
