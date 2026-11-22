import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreSessionTests {
    @Test static func corruptFileIsPreserved() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            #expect(files.count == 1, "The model must have one identifiable JSON state file")
            guard let file = files.first else { return }
            let corrupt = Data("{\"intentionally incomplete session\":".utf8)
            try corrupt.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) }
            catch { rejected = true }
            #expect(rejected, "A corrupt session must surface an error instead of silently resetting")
            let after = try Data(contentsOf: file)
            #expect(after == corrupt, "Opening a corrupt session must preserve its original bytes")
        }
    }

    @Test static func aSessionRestoresItsStateAndKeepsTheSavedPinDestination() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let firstSpace = store.activeSpaceID
            let saved = store.open("https://example.org/start", kind: .pinned)
            let parent = store.createFolder(name: "Research")
            let child = store.createFolder(name: "Articles", parentID: parent)
            store.moveTab(saved, toSpace: firstSpace, folderID: child)
            store.toggleFolder(parent)
            store.updateTab(saved, title: "Current article", url: "https://example.org/article")
            let secondSpace = store.createSpace(name: "Work", color: "AACCEE")
            let profile = store.createProfile(name: "Work profile")
            store.assignProfile(profile, toSpace: secondSpace)
            let first = store.open("https://work.example.org/one")
            let second = store.open("https://work.example.org/two")
            store.setSplit([first, second])
            store.updateSettings { $0.sidebarWidth = 278 }
            store.setAutoArchiveInterval(.sevenDays, for: store.activeSpace.profileID)
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory, now: { date })
            #expect(reopened.state == expected, "A saved session must preserve profiles, Spaces, folders, tabs, ordering, settings, and split selection")
            #expect(try BrowserStoreTestsSupport.tab(saved, in: reopened).savedURL == "https://example.org/start", "Navigating a pinned tab must preserve its saved destination across a restart")
            try BrowserStoreTestsSupport.expectValidSelection(reopened)
        }
    }

    @Test static func theSessionFileIsPrivateToTheCurrentUser() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            try store.save()
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("session.json").path)
            #expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Session data must be saved with owner-only permissions")
        }
    }

    @Test static func theSessionFileRoundTripsThePersistedState() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tab = store.open("https://example.org/start", kind: .pinned)
            store.updateTab(tab, title: "Article", url: "https://example.org/article")
            try store.save()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: directory.appendingPathComponent("session.json"))
            var expected = store.state
            expected.windows = store.windowRecords
            expected.history = []
            #expect(try decoder.decode(BrowserState.self, from: data) == expected)
        }
    }

    @Test static func compactSessionFilesLoadAndSaveTheSameState() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            _ = store.open("https://example.org/start", kind: .pinned)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let expected = try decoder.decode(BrowserState.self, from: Data(contentsOf: file))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(expected).write(to: file)

            let reopened = try BrowserStore(directory: directory, now: { date })
            try reopened.save()

            let restored = try decoder.decode(BrowserState.self, from: Data(contentsOf: file))
            #expect(restored == expected)
        }
    }

    @Test static func deferredSavingWritesTheMostRecentTitle() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let scheduler = DataFixtures.DeferredSave(store)
            let tab = store.open("https://example.org/start", kind: .pinned)
            store.updateTab(tab, title: "Live title")
            store.updateTab(tab, title: "Final title")

            scheduler.run(on: store)

            let reopened = try BrowserStore(directory: directory, now: { date })
            #expect(reopened.state.tabs.first { $0.id == tab }?.title == "Final title")
        }
    }

    @Test static func aFailedSettingsCommitKeepsAnAlreadyScheduledSessionSave() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let scheduler = DataFixtures.DeferredSave(store)
            let url = "https://pending-save.example.org"
            _ = store.open(url)
            let file = directory.appendingPathComponent("session.json")
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

            #expect(throws: (any Error).self) { try store.createProfilePersisted(name: "Work") }
            #expect(store.persistenceError != nil)
            #expect(store.state.profiles.count == 1)
            try FileManager.default.removeItem(at: file)
            scheduler.run(on: store)

            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.tabs.contains { $0.url == url })
        }
    }
}
