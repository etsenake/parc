import Foundation
import ParcCore

extension EaselTabIcons {
    package func configure(store browser: BrowserStore) {
        directory = { [weak browser] profile in browser?.easelsDirectory(for: profile) }
        let availability = EaselStoreAvailability()
        store = { directory in
            guard availability.contains(directory) else { return nil }
            return try? EaselEditorViewController.sharedStore(directory: directory)
        }
        notesFolder = { [weak browser] directory in
            guard let browser else { return nil }
            let path = directory.standardizedFileURL.path
            return browser.state.profiles
                .first { browser.easelsDirectory(for: $0.id).standardizedFileURL.path == path }
                .map { NoteFolderPreferences.folder(for: $0.id) }
        }
    }
}
