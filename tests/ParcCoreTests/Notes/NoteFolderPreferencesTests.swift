import Combine
import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor struct NoteFolderPreferencesTests {
    @Test func foldersAreChosenPerSpaceAndStoredStandardized() throws {
        let suite = "parc.tests.note-folder." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite), "a private defaults suite opens")
        defer { defaults.removePersistentDomain(forName: suite) }
        NoteFolderPreferences.defaults = defaults
        var announced: [UUID] = []
        let subscription = NoteFolderPreferences.changes.sink { announced.append($0) }
        defer { subscription.cancel() }

        let first = UUID(), second = UUID()
        let standard = NoteLibrary.defaultFolder.standardizedFileURL
        #expect(standard.lastPathComponent == "Parc Notes"
               && standard.deletingLastPathComponent().lastPathComponent == "Documents", "the default folder is Documents/Parc Notes")
        #expect(NoteFolderPreferences.folder(for: first) == standard, "a fresh Space keeps notes in the default folder")
        #expect(NoteFolderPreferences.customFolder(for: first) == nil, "a fresh Space has no custom folder")

        let custom = URL(fileURLWithPath: "/Volumes/Archive/Thoughts/../Notes", isDirectory: true)
        NoteFolderPreferences.setFolder(custom, for: first)
        #expect(NoteFolderPreferences.folder(for: first).path == "/Volumes/Archive/Notes", "the chosen folder is stored standardized")
        #expect(NoteFolderPreferences.folder(for: second) == standard, "another Space keeps its own folder")
        #expect(announced == [first], "choosing a folder announces that Space once")

        NoteFolderPreferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Notes/"), for: first)
        #expect(announced == [first], "choosing the same folder again is quiet")

        NoteFolderPreferences.setFolder(URL(string: "https://example.com/notes")!, for: first)
        #expect(NoteFolderPreferences.folder(for: first).path == "/Volumes/Archive/Notes" && announced == [first], "a web address is never a Notes folder")

        NoteFolderPreferences.setFolder(standard, for: second)
        #expect(announced == [first] && defaults.object(forKey: "Parc.Notes.Folder." + second.uuidString) == nil, "choosing the default for a Space already using it stores nothing")

        NoteFolderPreferences.setFolder(standard, for: first)
        #expect(NoteFolderPreferences.customFolder(for: first) == nil && NoteFolderPreferences.folder(for: first) == standard, "choosing the default folder clears the custom one")
        #expect(announced == [first, first], "going back to the default announces the change")

        defaults.set("relative/notes", forKey: "Parc.Notes.Folder." + second.uuidString)
        #expect(NoteFolderPreferences.folder(for: second) == standard, "a stored path that isn't absolute falls back to the default")
        NoteFolderPreferences.setFolder(standard, for: second)
        #expect(defaults.object(forKey: "Parc.Notes.Folder." + second.uuidString) == nil && announced.last == second, "choosing the default sweeps out a broken stored path")

        announced.removeAll()
        NoteFolderPreferences.setFolder(URL(fileURLWithPath: "/Users/parc-sample/Writing", isDirectory: true), for: second)
        #expect(NoteFolderPreferences.library(for: second) === NoteLibrary.shared(folder: URL(fileURLWithPath: "/Users/parc-sample/Writing")), "the Space's library is the shared library for its folder")
        NoteFolderPreferences.removeProfile(second)
        #expect(NoteFolderPreferences.folder(for: second) == standard, "removing a Space's data forgets its folder")
        #expect(announced == [second, second], "forgetting a folder announces it")
        NoteFolderPreferences.removeProfile(second)
        #expect(announced == [second, second], "forgetting nothing is quiet")
    }
}
}
