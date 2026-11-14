import AppKit

@MainActor
final class AppWidePreferenceController {
    static let shared = AppWidePreferenceController()

    struct Locks: Equatable {
        var search = false
        var suggestions = false
        var downloads = false
        var any: Bool { search || suggestions || downloads }
    }

    @MainActor
    private struct Snapshot {
        let search: PCNativeSearchPreferences
        let download: PCNativeDownloadPreferences

        var state: AppWideProfileState {
            let engines = search.engines.map {
                AppWideSearchEngine(identifier: $0.identifier, keyword: $0.keyword, canMakeDefault: $0.canMakeDefault)
            }
            return AppWideProfileState(
                engines: engines,
                defaultKeyword: engines.first { $0.identifier == search.defaultIdentifier }?.keyword,
                defaultEditable: search.defaultEditable,
                suggestionsEnabled: search.suggestionsEnabled, suggestionsEditable: search.suggestionsEditable,
                downloadDirectory: download.directoryURL.path, directoryEditable: !download.directoryManaged,
                promptForDownload: download.promptForDownload, promptEditable: !download.promptManaged)
        }
    }

    private weak var store: BrowserStore?
    private var seenPaths: Set<String> = []
    private var waitingPaths: Set<String> = []
    private var upgradeStarted = false

    func start(store: BrowserStore) {
        guard self.store == nil, !store.isEphemeral else { return }
        self.store = store
        upgradeIfNeeded()
    }

    func profileAvailable(path: String) {
        guard let store else { return }
        if store.state.settings.appWidePreferences == nil {
            waitingPaths.insert(path)
            upgradeIfNeeded()
            return
        }
        guard seenPaths.insert(path).inserted else { return }
        apply(toPath: path)
    }

    func update(_ change: (inout AppWidePreferences) -> Void) throws {
        guard let store else { return }
        var next = store.state.settings.appWidePreferences ?? AppWidePreferences()
        change(&next)
        try store.saveAppWidePreferences(next)
        var failure: Error?
        for path in loadedProfilePaths() {
            seenPaths.insert(path)
            apply(toPath: path) { failure = failure ?? $0 }
        }
        if let failure { throw failure }
    }

    func locks(completion: @escaping (Locks) -> Void) {
        var result = Locks()
        let paths = loadedProfilePaths()
        guard !paths.isEmpty else { completion(result); return }
        var remaining = paths.count
        for path in paths {
            read(path: path) { snapshot in
                if let snapshot {
                    result.search = result.search || snapshot.search.defaultManaged || snapshot.search.defaultExtensionControlled
                    result.suggestions = result.suggestions || snapshot.search.suggestionsManaged
                    result.downloads = result.downloads || snapshot.download.directoryManaged || snapshot.download.promptManaged
                }
                remaining -= 1
                if remaining == 0 { completion(result) }
            }
        }
    }

    private func profilePaths() -> [String] {
        guard let store else { return [] }
        return store.state.profiles.filter { !store.isProfileRemovalPending($0.id) }
            .map { store.independentEngineProfilePath(for: $0.id) }
    }

    private func loadedProfilePaths() -> [String] {
        profilePaths().filter { PCNativeBrowserApplication.downloadPreferences(profilePath: $0) != nil }
    }

    private func upgradeIfNeeded() {
        guard let store, !upgradeStarted, store.state.settings.appWidePreferences == nil,
              let profileID = store.state.spaces.first?.profileID ?? store.state.profiles.first?.id,
              store.state.profiles.contains(where: { $0.id == profileID }) else { return }
        upgradeStarted = true
        let path = store.independentEngineProfilePath(for: profileID)
        read(path: path) { [weak self] snapshot in
            guard let self, let store = self.store else { return }
            guard let snapshot else { self.upgradeStarted = false; return }
            do { try store.recordAppWidePreferencesIfMissing(AppWidePreferences.recorded(from: snapshot.state)) }
            catch { self.upgradeStarted = false; return }
            self.seenPaths.insert(path)
            let others = Set(self.loadedProfilePaths()).union(self.waitingPaths)
            self.waitingPaths.removeAll()
            for other in others where self.seenPaths.insert(other).inserted { self.apply(toPath: other) }
        }
    }

    private func apply(toPath path: String, completion: ((Error?) -> Void)? = nil) {
        guard let wanted = store?.state.settings.appWidePreferences else { completion?(nil); return }
        read(path: path) { snapshot in
            guard let snapshot else { completion?(nil); return }
            let changes = wanted.changes(for: snapshot.state)
            guard !changes.isEmpty else { completion?(nil); return }
            do {
                var search = snapshot.search
                var download = snapshot.download
                if let identifier = changes.engineIdentifier {
                    search = try PCNativeBrowserApplication.setDefaultSearchEngine(identifier, for: search)
                }
                if let suggestions = changes.suggestions {
                    search = try PCNativeBrowserApplication.setSearchSuggestionsEnabled(suggestions, for: search)
                }
                if let directory = changes.downloadDirectory {
                    download = try PCNativeBrowserApplication.setDownloadDirectory(
                        URL(fileURLWithPath: directory, isDirectory: true), for: download)
                }
                if let prompt = changes.promptForDownload {
                    _ = try PCNativeBrowserApplication.setPromptForDownload(prompt, for: download)
                }
                completion?(nil)
            } catch { completion?(error) }
        }
    }

    private func read(path: String, completion: @escaping (Snapshot?) -> Void) {
        PCNativeBrowserApplication.searchPreferences(profilePath: path) { search, _ in
            MainActor.assumeIsolated {
                guard let search, search.profilePath == path else { completion(nil); return }
                PCNativeBrowserApplication.downloadPreferences(profilePath: path) { download, _ in
                    MainActor.assumeIsolated {
                        guard let download, download.profilePath == path else { completion(nil); return }
                        completion(Snapshot(search: search, download: download))
                    }
                }
            }
        }
    }
}
