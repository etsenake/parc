import Combine
import Foundation

@MainActor
enum NoteFolderPreferences {
    static var defaults: UserDefaults = .standard
    static let changes = PassthroughSubject<UUID, Never>()

    private static func key(_ profileID: UUID) -> String { "Parc.Notes.Folder." + profileID.uuidString }

    static func folder(for profileID: UUID) -> URL {
        if let path = defaults.string(forKey: key(profileID)), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return NoteLibrary.defaultFolder
    }

    static func setFolder(_ url: URL, for profileID: UUID) {
        defaults.set(url.standardizedFileURL.path, forKey: key(profileID))
        changes.send(profileID)
    }

    static func removeProfile(_ profileID: UUID) {
        defaults.removeObject(forKey: key(profileID))
    }
}
