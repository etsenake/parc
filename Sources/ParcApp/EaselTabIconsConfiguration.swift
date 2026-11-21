import Foundation

extension EaselTabIcons {
    func configure(store browser: BrowserStore) {
        directory = { [weak browser] profile in browser?.easelsDirectory(for: profile) }
        store = { directory in
            guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
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
