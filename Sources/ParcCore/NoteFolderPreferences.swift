import Combine
import Foundation

@MainActor
package final class NoteFolderPreferences {
    package let defaults: UserDefaults
    package let changes = PassthroughSubject<UUID, Never>()

    private static let keyPrefix = "Parc.Notes.Folder."
    private static func key(_ profileID: UUID) -> String { keyPrefix + profileID.uuidString }

    package init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    package func folder(for profileID: UUID) -> URL {
        customFolder(for: profileID) ?? NoteLibrary.defaultFolder.standardizedFileURL
    }

    package func customFolder(for profileID: UUID) -> URL? {
        guard let path = defaults.string(forKey: Self.key(profileID)), path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    package var allFolders: [URL] {
        var folders = [NoteLibrary.defaultFolder.standardizedFileURL]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.keyPrefix) {
            guard let path = value as? String, path.hasPrefix("/") else { continue }
            folders.append(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
        }
        return folders
    }

    package func setFolder(_ url: URL, for profileID: UUID) {
        guard url.isFileURL else { return }
        let chosen = URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true).standardizedFileURL
        if chosen.path == NoteLibrary.defaultFolder.standardizedFileURL.path {
            guard defaults.object(forKey: Self.key(profileID)) != nil else { return }
            defaults.removeObject(forKey: Self.key(profileID))
        } else {
            guard customFolder(for: profileID)?.path != chosen.path else { return }
            defaults.set(chosen.path, forKey: Self.key(profileID))
        }
        changes.send(profileID)
    }

    package func removeProfile(_ profileID: UUID) {
        guard defaults.object(forKey: Self.key(profileID)) != nil else { return }
        defaults.removeObject(forKey: Self.key(profileID))
        changes.send(profileID)
    }
}

extension NoteFiles {
    package func library(forProfile profileID: UUID) -> NoteLibrary {
        library(folder: folders.folder(for: profileID))
    }
}

extension NoteFolderPreferences {
    package static var shared: NoteFolderPreferences { NoteFiles.shared.folders }
    package static var changes: PassthroughSubject<UUID, Never> { shared.changes }
    package static var allFolders: [URL] { shared.allFolders }
    package static func folder(for profileID: UUID) -> URL { shared.folder(for: profileID) }
    package static func customFolder(for profileID: UUID) -> URL? { shared.customFolder(for: profileID) }
    package static func library(for profileID: UUID) -> NoteLibrary { NoteFiles.shared.library(forProfile: profileID) }
    package static func setFolder(_ url: URL, for profileID: UUID) { shared.setFolder(url, for: profileID) }
    package static func removeProfile(_ profileID: UUID) { shared.removeProfile(profileID) }
}
