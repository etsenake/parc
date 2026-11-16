import Foundation

@MainActor
enum SetupExtensionChanges {
    static func addICloudPasswords(to destination: BrowserImportDestination, store: BrowserStore,
                                   connects: @escaping @MainActor () -> Bool = { ICloudPasswordsSupport.connects() }) {
        let failure = ImportedExtensionFailures.Failure(name: "iCloud Passwords", target: "setup " + destination.profileID.uuidString)
        guard connects() else { ImportedExtensionFailures.record(failure); return }
        PCNativeBrowserApplication.installICloudPasswordsExtension(
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID)) { [weak store] error in
                guard let error else { return }
                NSLog("Parc could not install the selected iCloud Passwords extension: %@", error.localizedDescription)
                MainActor.assumeIsolated {
                    var failure = failure
                    failure.reason = .init(PCImportedExtensions.restriction(for: error))
                    ImportedExtensionFailures.record(failure) { [weak store] in
                        guard let store, !removableProfiles([destination.profileID], in: store.state).isEmpty else { return }
                        addICloudPasswords(to: destination, store: store, connects: connects)
                    }
                }
            }
    }

    static func addAdBlocker(to destination: BrowserImportDestination, store: BrowserStore) {
        PCNativeBrowserApplication.installSetupAdBlocker(
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID)) { [weak store] error in
                guard let error else { return }
                NSLog("Parc could not install uBlock Origin: %@", error.localizedDescription)
                MainActor.assumeIsolated {
                    let target = "setup " + destination.profileID.uuidString
                    let reason = ImportedExtensionFailures.Failure.Reason(PCImportedExtensions.restriction(for: error))
                    ImportedExtensionFailures.record(.init(name: "uBlock Origin Lite", target: target, reason: reason)) { [weak store] in
                        guard let store, !removableProfiles([destination.profileID], in: store.state).isEmpty else { return }
                        addAdBlocker(to: destination, store: store)
                    }
                }
            }
    }

    private(set) static var setupRun = UUID()
    private static var adBlockerChoices: [UUID: OnboardingDraft.AdBlockerChoice] = [:]

    static func beginSetupRun() { setupRun = UUID() }

    static func apply(_ choice: OnboardingDraft.AdBlockerChoice, to blockers: [OnboardingDraft.ImportedAdBlocker],
                      in destination: BrowserImportDestination, store: BrowserStore) {
        adBlockerChoices[setupRun] = choice
        ImportedExtensionRetries.discardDeclined()
        let plan = choice.plan(for: blockers, setupProfileID: destination.profileID)
        let names = Dictionary(blockers.map { ($0.identifier, $0.displayName) }) { first, _ in first }
        removeAdBlockers(plan.removals, names: names, store: store)
        if let profileID = plan.installProfileID,
           case let target = BrowserImportDestination(spaceID: destination.spaceID, profileID: profileID),
           target.isCurrent(in: store.state) {
            addAdBlocker(to: target, store: store)
        }
    }

    static func declines(_ identifier: String, in run: UUID) -> Bool {
        guard OnboardingAdBlocker.isKnown(identifier) else { return false }
        switch adBlockerChoices[run] {
        case .some(.keep(let kept)): return identifier != kept
        case .some(.uBlock): return identifier != OnboardingAdBlocker.uBlockOrigin
        case .some(.none): return true
        case .some(.keepAll), nil: return false
        }
    }

    static func removableProfiles(_ profiles: [UUID], in state: BrowserState) -> [UUID] {
        profiles.filter { id in
            state.profiles.contains { $0.id == id } && !state.profileRemovals.contains { $0.profileID == id }
        }
    }

    static func removeAdBlockers(_ removals: [UUID: Set<String>], names: [String: String], store: BrowserStore) {
        let profiles = removableProfiles(store.state.profiles.map(\.id).filter { removals[$0] != nil }, in: store.state)
        var reach: [String: Set<UUID>] = [:]
        for profileID in profiles {
            for identifier in removals[profileID] ?? [] { reach[names[identifier] ?? identifier, default: []].insert(profileID) }
        }
        for profileID in profiles {
            for identifier in (removals[profileID] ?? []).sorted() {
                let name = names[identifier] ?? identifier
                removeAdBlocker(identifier, named: name, from: profileID,
                                namingProfile: reach[name, default: []].count > 1, store: store)
            }
        }
    }

    static func removeAdBlocker(_ identifier: String, named name: String, from profileID: UUID,
                                namingProfile: Bool, store: BrowserStore) {
        guard !removableProfiles([profileID], in: store.state).isEmpty else { return }
        PCNativeBrowserApplication.removeSetupAdBlockers([identifier],
            fromProfilePath: store.independentEngineProfilePath(for: profileID)) { [weak store] error in
                guard let error else { return }
                NSLog("Parc could not remove %@: %@", name, error.localizedDescription)
                MainActor.assumeIsolated {
                    let profile = namingProfile ? store?.state.profiles.first { $0.id == profileID }?.name : nil
                    let failure = ImportedExtensionFailures.Failure(change: .removal, name: name, profile: profile,
                        target: identifier + " " + profileID.uuidString,
                        reason: .init(PCImportedExtensions.restriction(for: error)))
                    ImportedExtensionFailures.record(failure) { [weak store] in
                        guard let store else { return }
                        removeAdBlocker(identifier, named: name, from: profileID, namingProfile: namingProfile, store: store)
                    }
                }
            }
    }
}
