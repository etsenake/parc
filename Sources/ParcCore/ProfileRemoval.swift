import Foundation

package struct ProfileRemovalRecord: Codable, Equatable, Identifiable {
    package let id: UUID
    package let profileID: UUID
    package let profileName: String
    package var fallbackProfileID: UUID?

    package init(id: UUID, profileID: UUID, profileName: String, fallbackProfileID: UUID? = nil) {
        self.id = id
        self.profileID = profileID
        self.profileName = profileName
        self.fallbackProfileID = fallbackProfileID
    }
}

struct ProfileRemovalSummary: Equatable {
    let profile: BrowserProfile
    let savedTabCount: Int
    let historyEntryCount: Int
}

package enum ProfileRemovalError: LocalizedError, Equatable {
    case unavailable, assignedToSpaces, alreadyRemoving, nameChanged
    case incompleteOperation, invalidSelection, activeDocumentWrite
    package var errorDescription: String? {
        switch self {
        case .unavailable: return "This profile is no longer available."
        case .assignedToSpaces: return "Only Profiles not assigned to any Spaces can be deleted."
        case .alreadyRemoving: return "This profile has a removal operation in progress."
        case .nameChanged: return "This profile was renamed. Select it again to delete it."
        case .incompleteOperation: return "Profile removal needs to finish before this profile can be used again."
        case .invalidSelection: return "The profile selection changed. Review the unused Profiles again."
        case .activeDocumentWrite: return "Wait for this profile’s Library changes to finish, then try again."
        }
    }
}

extension BrowserStore {
    var unusedProfilesForRemoval: [BrowserProfile] {
        state.profiles.filter { (try? profileRemovalSummary($0.id)) != nil }
    }

    func validateUnusedProfileRemoval(_ profiles: [BrowserProfile]) throws {
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count else {
            throw ProfileRemovalError.invalidSelection
        }
        for profile in profiles {
            let current = try profileRemovalSummary(profile.id)
            guard current.profile.name == profile.name else { throw ProfileRemovalError.nameChanged }
        }
    }

    var defaultProfileID: UUID { state.settings.defaultProfileID ?? state.profiles[0].id }

    package func fallbackProfileID(for record: ProfileRemovalRecord) -> UUID {
        record.fallbackProfileID ?? defaultProfileID
    }

    func survivingProfileID(excluding removed: Set<UUID>) -> UUID? {
        let used = state.spaces.map(\.profileID).filter { !removed.contains($0) && !isProfileRemovalPending($0) }
        if let current = state.settings.defaultProfileID ?? state.profiles.first?.id, used.contains(current) { return current }
        if let active = state.spaces.first(where: { $0.id == state.activeSpaceID })?.profileID, used.contains(active) { return active }
        return used.first
    }

    package func isProfileRemovalPending(_ profileID: UUID) -> Bool {
        state.profileRemovals.contains { $0.profileID == profileID }
    }

    func profileRemovalSummary(_ profileID: UUID) throws -> ProfileRemovalSummary {
        guard let profile = state.profiles.first(where: { $0.id == profileID }) else {
            throw ProfileRemovalError.unavailable
        }
        guard !state.spaces.contains(where: { $0.profileID == profileID }) else {
            throw ProfileRemovalError.assignedToSpaces
        }
        guard !isProfileRemovalPending(profileID) else { throw ProfileRemovalError.alreadyRemoving }
        return ProfileRemovalSummary(profile: profile,
            savedTabCount: state.tabs.filter { $0.profileID == profileID }.count,
            historyEntryCount: state.history.filter { $0.profileID == profileID }.count)
    }

    func validateProfileRemoval(_ profileID: UUID, expectedName: String) throws -> ProfileRemovalSummary {
        let summary = try profileRemovalSummary(profileID)
        guard summary.profile.name == expectedName else { throw ProfileRemovalError.nameChanged }
        return summary
    }
}

@MainActor package final class ProfileWriteReservation {
    private var release: (() -> Void)?
    package init(release: @escaping () -> Void) { self.release = release }
    package func perform<T>(_ operation: () async throws -> T) async rethrows -> T {
        defer { finish() }
        return try await operation()
    }
    package func finish() { let action = release; release = nil; action?() }
}
