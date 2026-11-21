import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserImportRestartTests {
    struct Fixture {
        let directory: URL
        let store: BrowserStore
        let destination: BrowserImportDestination
        let intent: BrowserImportRestartIntent
        var file: URL { directory.appendingPathComponent("PendingBrowserImportRestart.json") }
    }

    func withFixture(_ body: (Fixture) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let intent = BrowserImportRestartIntent(destination: destination, onboarding: true, sourceBundleID: "com.google.Chrome")
            try body(Fixture(directory: directory, store: store, destination: destination, intent: intent))
        }
    }

    @Test func nothingIsRestoredWhenNothingWasSaved() throws {
        try withFixture { fixture in
            let actual = try BrowserImportRestartIntent.take(from: fixture.directory)
            #expect(actual == nil)
        }
    }

    @Test func aSavedIntentIsRestoredOnce() throws {
        try withFixture { fixture in
            try fixture.intent.save(in: fixture.directory)
            let restored = try BrowserImportRestartIntent.take(from: fixture.directory)
            #expect(restored == fixture.intent && restored?.destination == fixture.destination
                    && restored?.sourceBundleID == "com.google.Chrome")
            let actual = try BrowserImportRestartIntent.take(from: fixture.directory)
            #expect(actual == nil)
        }
    }

    @Test func oldSafariOnlyIntentsKeepSafari() throws {
        try withFixture { fixture in
            try Data("{\"spaceID\":\"\(fixture.destination.spaceID.uuidString)\",\"profileID\":\"\(fixture.destination.profileID.uuidString)\",\"onboarding\":true}".utf8)
                .write(to: fixture.file)
            let actual = try BrowserImportRestartIntent.take(from: fixture.directory)?.sourceBundleID
            #expect(actual == "com.apple.Safari")
        }
    }

    @Test func aRemovedIntentIsGone() throws {
        try withFixture { fixture in
            try fixture.intent.save(in: fixture.directory)
            BrowserImportRestartIntent.remove(from: fixture.directory)
            let actual = try BrowserImportRestartIntent.take(from: fixture.directory)
            #expect(actual == nil)
        }
    }

    @Test func aCorruptIntentFailsAndIsDeleted() throws {
        try withFixture { fixture in
            try Data("invalid".utf8).write(to: fixture.file)
            #expect(throws: (any Error).self) { try BrowserImportRestartIntent.take(from: fixture.directory) }
            #expect(!FileManager.default.fileExists(atPath: fixture.file.path))
        }
    }
}
