import Combine
import Foundation
import ParcTestSupport
import Testing
@testable import ParcCore

@MainActor final class NoteFolderPreferencesTests {
    let defaults: UserDefaults
    let preferences: NoteFolderPreferences
    let first = UUID(), second = UUID()
    let standard: URL
    var announced: [UUID] = []
    var subscription: AnyCancellable?

    init() throws {
        let suite = "parc.tests.note-folder." + UUID().uuidString
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true).standardizedFileURL
        standard = folder
        defaults = try #require(TestDefaults("parc.tests.note-folder."))
        preferences = NoteFolderPreferences(defaults: defaults, defaultFolder: { folder })
        subscription = preferences.changes.sink { [unowned self] in self.announced.append($0) }
    }

    func key(_ profile: UUID) -> String { "Parc.Notes.Folder." + profile.uuidString }

    @Test func aFreshSpaceKeepsNotesInTheDefaultFolder() {
        #expect(preferences.folder(for: first) == standard)
        #expect(preferences.customFolder(for: first) == nil)
    }

    @Test func theChosenFolderIsStoredStandardizedForThatSpaceOnly() {
        preferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Thoughts/../Notes", isDirectory: true), for: first)
        #expect(preferences.folder(for: first).path == "/Volumes/Archive/Notes")
        #expect(preferences.folder(for: second) == standard)
    }

    @Test func choosingAFolderAnnouncesThatSpaceOnce() {
        preferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Notes", isDirectory: true), for: first)
        #expect(announced == [first])
    }

    @Test func choosingTheSameFolderAgainIsQuiet() {
        preferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Notes", isDirectory: true), for: first)
        preferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Notes/"), for: first)
        #expect(announced == [first])
    }

    @Test func aWebAddressIsNeverANotesFolder() {
        preferences.setFolder(URL(string: "https://example.com/notes")!, for: first)
        #expect(preferences.folder(for: first) == standard)
        #expect(announced.isEmpty)
    }

    @Test func choosingTheDefaultForASpaceAlreadyUsingItStoresNothing() {
        preferences.setFolder(standard, for: second)
        #expect(announced.isEmpty)
        #expect(defaults.object(forKey: key(second)) == nil)
    }

    @Test func goingBackToTheDefaultClearsTheCustomFolderAndAnnouncesIt() {
        preferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Notes", isDirectory: true), for: first)
        preferences.setFolder(standard, for: first)
        #expect(preferences.customFolder(for: first) == nil && preferences.folder(for: first) == standard)
        #expect(announced == [first, first])
    }

    @Test func aStoredPathThatIsNotAbsoluteFallsBackToTheDefault() {
        defaults.set("relative/notes", forKey: key(second))
        #expect(preferences.folder(for: second) == standard)
    }

    @Test func choosingTheDefaultSweepsOutABrokenStoredPath() {
        defaults.set("relative/notes", forKey: key(second))
        preferences.setFolder(standard, for: second)
        #expect(defaults.object(forKey: key(second)) == nil && announced.last == second)
    }

    @Test func allFoldersListTheDefaultAndEveryChosenFolder() {
        preferences.setFolder(URL(fileURLWithPath: "/Volumes/Archive/Notes", isDirectory: true), for: first)
        #expect(Set(preferences.allFolders.map(\.path)) == [standard.path, "/Volumes/Archive/Notes"])
    }

    @Test func removingASpaceForgetsItsFolderAndAnnouncesIt() {
        preferences.setFolder(URL(fileURLWithPath: "/Users/parc-sample/Writing", isDirectory: true), for: second)
        announced.removeAll()
        preferences.removeProfile(second)
        #expect(preferences.folder(for: second) == standard)
        #expect(announced == [second])
    }

    @Test func forgettingNothingIsQuiet() {
        preferences.removeProfile(second)
        #expect(announced.isEmpty)
    }

    @Test func aSpacesLibraryIsTheSharedLibraryForItsFolder() {
        let defaultFolder = standard
        var settings = NoteFileSettings(clock: NoteManualClock(), worker: .inline, hopToMain: { _ in }, defaults: defaults)
        settings.defaultFolder = { defaultFolder }
        let files = NoteFiles(settings: settings)
        files.folders.setFolder(URL(fileURLWithPath: "/Users/parc-sample/Writing", isDirectory: true), for: second)
        #expect(files.library(forProfile: second) === files.library(folder: URL(fileURLWithPath: "/Users/parc-sample/Writing")))
    }
}
