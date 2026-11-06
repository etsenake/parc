import Foundation

struct ProfileRemovalRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let profileName: String
}

struct ProfileRemovalSummary: Equatable {
    let profile: BrowserProfile
    let savedTabCount: Int
    let historyEntryCount: Int
}

enum ProfileRemovalError: LocalizedError, Equatable {
    case unavailable, defaultProfile, assignedToSpaces, alreadyRemoving, nameChanged, nameDoesNotMatch
    case incompleteOperation, confirmationDoesNotMatch, invalidSelection, activeDocumentWrite
    var errorDescription: String? {
        switch self {
        case .unavailable: return "This profile is no longer available."
        case .defaultProfile: return "The Default Profile cannot be deleted."
        case .assignedToSpaces: return "Only Profiles not assigned to any Spaces can be deleted."
        case .alreadyRemoving: return "This profile has a removal operation in progress."
        case .nameChanged: return "This profile was renamed. Close this dialog and select it again."
        case .nameDoesNotMatch: return "Enter the name of this profile to continue."
        case .incompleteOperation: return "Profile removal needs to finish before this profile can be used again."
        case .confirmationDoesNotMatch: return "Type CONFIRM to delete the listed unused Profiles."
        case .invalidSelection: return "The profile selection changed. Close this dialog and review the unused Profiles again."
        case .activeDocumentWrite: return "Wait for this profile’s Library changes to finish, then try again."
        }
    }
}

extension BrowserStore {
    /// An unused profile has no assigned Space, even if it retains saved tabs
    /// or history. Never substitute the currently selected Settings profile.
    var unusedProfilesForRemoval: [BrowserProfile] {
        state.profiles.filter { (try? profileRemovalSummary($0.id)) != nil }
    }

    static func confirmsUnusedProfileRemoval(_ text: String) -> Bool {
        text.caseInsensitiveCompare("CONFIRM") == .orderedSame
    }

    func validateUnusedProfileRemoval(_ profiles: [BrowserProfile], confirmation: String) throws {
        guard Self.confirmsUnusedProfileRemoval(confirmation) else {
            throw ProfileRemovalError.confirmationDoesNotMatch
        }
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count else {
            throw ProfileRemovalError.invalidSelection
        }
        for profile in profiles {
            let current = try profileRemovalSummary(profile.id)
            guard current.profile.name == profile.name else { throw ProfileRemovalError.nameChanged }
        }
    }

    /// Existing sessions preserve the original first profile as Default.
    /// Display names remain editable and are never used as deletion identity.
    var defaultProfileID: UUID { state.settings.defaultProfileID ?? state.profiles[0].id }

    func isProfileRemovalPending(_ profileID: UUID) -> Bool {
        state.profileRemovals.contains { $0.profileID == profileID }
    }

    func profileRemovalSummary(_ profileID: UUID) throws -> ProfileRemovalSummary {
        guard let profile = state.profiles.first(where: { $0.id == profileID }) else {
            throw ProfileRemovalError.unavailable
        }
        guard profileID != defaultProfileID else { throw ProfileRemovalError.defaultProfile }
        guard !state.spaces.contains(where: { $0.profileID == profileID }) else {
            throw ProfileRemovalError.assignedToSpaces
        }
        guard !isProfileRemovalPending(profileID) else { throw ProfileRemovalError.alreadyRemoving }
        return ProfileRemovalSummary(profile: profile,
            savedTabCount: state.tabs.filter { $0.profileID == profileID }.count,
            historyEntryCount: state.history.filter { $0.profileID == profileID }.count)
    }

    func validateProfileRemoval(_ profileID: UUID, expectedName: String, confirmation: String) throws -> ProfileRemovalSummary {
        let summary = try profileRemovalSummary(profileID)
        guard summary.profile.name == expectedName else { throw ProfileRemovalError.nameChanged }
        guard confirmation.caseInsensitiveCompare(expectedName) == .orderedSame else {
            throw ProfileRemovalError.nameDoesNotMatch
        }
        return summary
    }
}

/// Retains the original store until the asynchronous disk operation finishes.
/// Ending or replacing the window cannot release this admission early.
@MainActor final class ProfileWriteReservation {
    private var release: (() -> Void)?
    init(release: @escaping () -> Void) { self.release = release }
    func perform<T>(_ operation: () async throws -> T) async rethrows -> T {
        defer { finish() }
        return try await operation()
    }
    func finish() { let action = release; release = nil; action?() }
}
