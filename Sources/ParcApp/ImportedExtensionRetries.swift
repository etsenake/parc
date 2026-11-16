import Foundation

@MainActor
enum ImportedExtensionRetries {
    struct Item {
        let source: PCNativeImportProfile
        let identifier: String
        let name: String
        let destination: BrowserImportDestination
        var profile: String? = nil
        var reason: ImportedExtensionFailures.Failure.Reason? = nil
        var retryable = true
        var setup = false
        var target: String { "import " + destination.profileID.uuidString + " " + identifier }
        var failure: ImportedExtensionFailures.Failure {
            .init(name: name, profile: profile, target: target, reason: reason)
        }
        @MainActor func reported(by failure: PCImportedExtensionFailure) -> Item {
            var item = self
            guard failure.identifier != nil else { item.profile = nil; item.retryable = false; return item }
            item.reason = .init(failure.restriction)
            return item
        }
    }
    private static var installs: [UUID: PCNativeImportSession] = [:]
    private static var setupBlockers: [String: String] = [:]

    private static func declined(_ item: Item) -> Bool { item.setup && SetupExtensionChanges.declines(item.identifier) }

    static func discardDeclined() {
        ImportedExtensionFailures.discard { failure in
            failure.target.flatMap { setupBlockers[$0] }.map(SetupExtensionChanges.declines) ?? false
        }
    }

    static func record(_ item: Item, store: BrowserStore) {
        guard !declined(item) else { return }
        setupBlockers[item.target] = item.setup && OnboardingAdBlocker.isKnown(item.identifier) ? item.identifier : nil
        guard item.retryable else { ImportedExtensionFailures.record(item.failure); return }
        ImportedExtensionFailures.record(item.failure) { [weak store] in
            guard let store else { return }
            retry(item, store: store)
        }
    }

    static func retry(_ item: Item, store: BrowserStore) {
        guard !declined(item),
              !SetupExtensionChanges.removableProfiles([item.destination.profileID], in: store.state).isEmpty else { return }
        let request = PCNativeImportExtensionRequest(source: item.source,
            profilePath: store.independentEngineProfilePath(for: item.destination.profileID), extensionIDs: [item.identifier])
        let id = UUID()
        let failed = { [weak store] (failures: [PCImportedExtensionFailure], late: Bool) in
            let mine = failures.filter { ($0.identifier ?? item.identifier) == item.identifier }
            if late, !mine.isEmpty { ImportedExtensionFailures.recordFailed([item.identifier]) }
            guard let store else { return }
            for failure in mine { record(item.reported(by: failure), store: store) }
        }
        let install = PCImportedExtensions.install([request], completion: { result, failures in
            installs[id] = nil
            ImportedExtensionFailures.clearFailed(result.installedIdentifiers)
            failed(failures, false)
        }, backgroundFailures: { failed($0, true) })
        guard let install else { record(item, store: store); return }
        installs[id] = install
    }
}
