import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SpaceHeaderSettingTests {
    @MainActor final class Fixture {
        let directory: URL
        let file: URL
        let store: BrowserStore

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-space-header-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            file = directory.appendingPathComponent("session.json")
            store = try BrowserStore(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aNewSessionTakesTheDefaultOff() throws {
        let f = try Fixture()
        #expect(f.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil)
    }

    @Test func theToggleTurnsItOnAndPublishesAndASecondToggleTurnsItOff() throws {
        let f = try Fixture()
        var published = 0
        let subscription = f.store.statePublisher.dropFirst().sink { _ in published += 1 }
        f.store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        #expect(f.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true)
        #expect(published > 0)
        f.store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        #expect(f.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == false)
        subscription.cancel()
    }

    @Test func theSettingSurvivesARelaunchAndTheSessionStoresItsKey() throws {
        let f = try Fixture()
        f.store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        try f.store.save()
        let relaunched = try BrowserStore(directory: f.directory)
        #expect(relaunched.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.file)) as? [String: Any])
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(settings["showSpaceHeaderOnSingleUnnamedSpaces"] as? Bool == true)
    }

    @Test func anOlderSessionDecodesWithoutItAndTogglingTheUnsetDefaultTurnsItOn() throws {
        let f = try Fixture()
        f.store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        try f.store.save()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.file)) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "showSpaceHeaderOnSingleUnnamedSpaces")
        json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: f.file)
        let older = try BrowserStore(directory: f.directory)
        #expect(older.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil)
        older.toggleSpaceHeaderOnSingleUnnamedSpaces()
        #expect(older.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true)
    }
}
