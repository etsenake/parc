import Foundation
import Testing
@testable import ParcCore

@MainActor
struct FavoriteActionStoreTests {
    typealias Fixture = FavoriteActionTests.Fixture

    @MainActor struct Persisted {
        let directory = CommandBarFixtures.temporaryDirectory("favorite-actions")
        let fixture = Fixture()
        let file: URL
        let encoder = JSONEncoder()

        init() throws {
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("session.json")
            try writeSession()
        }

        func writeSession() throws { try encoder.encode(fixture.state).write(to: file) }

        func store() throws -> BrowserStore { try BrowserStore(directory: directory) }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aDurableStoreTransactionSucceeds() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let store = try persisted.store()
        let action = try #require(persisted.fixture.action([persisted.fixture.first.id, persisted.fixture.second.id], store.state))
        #expect(try store.performFavoriteAction(action))
    }

    @Test func exactOrderAndMembershipSurviveAReload() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let fixture = persisted.fixture
        let store = try persisted.store()
        _ = try store.performFavoriteAction(try #require(fixture.action([fixture.first.id, fixture.second.id], store.state)))
        let reopened = try persisted.store()
        #expect(reopened.state.tabs.filter { $0.kind == .favorite }.map(\.id) == [fixture.existing.id, fixture.first.id, fixture.second.id])
    }

    @Test func aPinnedHomeSurvivesAReload() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let fixture = persisted.fixture
        let store = try persisted.store()
        _ = try store.performFavoriteAction(try #require(fixture.action([fixture.first.id, fixture.second.id], store.state)))
        #expect(try persisted.store().state.tabs.first { $0.id == fixture.second.id }?.savedURL == fixture.second.savedURL)
    }

    @Test func theRealStoreRefusesConsumedMembership() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let fixture = persisted.fixture
        let store = try persisted.store()
        let action = try #require(fixture.action([fixture.first.id, fixture.second.id], store.state))
        _ = try store.performFavoriteAction(action)
        #expect(try !store.performFavoriteAction(action))
    }

    @Test func aFailedAtomicWritePublishesNoPartialMembership() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let fixture = persisted.fixture
        let failing = try persisted.store()
        let before = failing.state
        let action = try #require(fixture.action([fixture.first.id, fixture.second.id], before))
        try FileManager.default.removeItem(at: persisted.file)
        try FileManager.default.createDirectory(at: persisted.file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try failing.performFavoriteAction(action) }
        #expect(failing.state == before)
    }
}
