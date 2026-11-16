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
        var target: String { "import " + destination.profileID.uuidString + " " + identifier }
        var failure: ImportedExtensionFailures.Failure {
            .init(name: name, profile: profile, target: target, reason: reason)
        }
    }
    private static var installs: [UUID: PCNativeImportSession] = [:]

    static func record(_ item: Item, retryable: Bool = true, store: BrowserStore) {
        guard retryable else { ImportedExtensionFailures.record(item.failure); return }
        ImportedExtensionFailures.record(item.failure) { [weak store] in
            guard let store else { return }
            retry(item, store: store)
        }
    }

    static func retry(_ item: Item, store: BrowserStore) {
        guard !SetupExtensionChanges.removableProfiles([item.destination.profileID], in: store.state).isEmpty else { return }
        let request = PCNativeImportExtensionRequest(source: item.source,
            profilePath: store.independentEngineProfilePath(for: item.destination.profileID), extensionIDs: [item.identifier])
        let id = UUID()
        let failed = { [weak store] (failures: [PCNativeImportExtensionFailure], late: Bool) in
            if late { ImportedExtensionFailures.recordFailed(failures.map(\.identifier)) }
            guard let store else { return }
            for failure in failures where failure.identifier == item.identifier {
                var again = item
                again.reason = .init(failure.restriction)
                record(again, store: store)
            }
        }
        let install = PCNativeBrowserApplication.installImportedExtensions([request], completion: { result in
            installs[id] = nil
            ImportedExtensionFailures.clearFailed(result.installedIdentifiers)
            failed(result.failures, false)
        }, backgroundFailures: { failed($0, true) })
        guard let install else { record(item, store: store); return }
        installs[id] = install
    }
}
