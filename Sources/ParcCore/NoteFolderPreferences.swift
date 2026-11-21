import Combine
import Foundation

@MainActor
package enum NoteFolderPreferences {
    package static var defaults: UserDefaults = .standard
    package static let changes = PassthroughSubject<UUID, Never>()

    private static let keyPrefix = "Parc.Notes.Folder."
    private static func key(_ profileID: UUID) -> String { keyPrefix + profileID.uuidString }

    package static func folder(for profileID: UUID) -> URL {
        customFolder(for: profileID) ?? NoteLibrary.defaultFolder.standardizedFileURL
    }

    package static func customFolder(for profileID: UUID) -> URL? {
        guard let path = defaults.string(forKey: key(profileID)), path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    package static var allFolders: [URL] {
        var folders = [NoteLibrary.defaultFolder.standardizedFileURL]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(keyPrefix) {
            guard let path = value as? String, path.hasPrefix("/") else { continue }
            folders.append(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
        }
        return folders
    }

    package static func library(for profileID: UUID) -> NoteLibrary {
        NoteLibrary.shared(folder: folder(for: profileID))
    }

    package static func setFolder(_ url: URL, for profileID: UUID) {
        guard url.isFileURL else { return }
        let chosen = URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true).standardizedFileURL
        if chosen.path == NoteLibrary.defaultFolder.standardizedFileURL.path {
            guard defaults.object(forKey: key(profileID)) != nil else { return }
            defaults.removeObject(forKey: key(profileID))
        } else {
            guard customFolder(for: profileID)?.path != chosen.path else { return }
            defaults.set(chosen.path, forKey: key(profileID))
        }
        changes.send(profileID)
    }

    package static func removeProfile(_ profileID: UUID) {
        guard defaults.object(forKey: key(profileID)) != nil else { return }
        defaults.removeObject(forKey: key(profileID))
        changes.send(profileID)
    }
}
