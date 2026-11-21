import Foundation
import Testing
@testable import ParcCore

@MainActor
struct FolderMoveStoreTests {
    typealias Fixture = FolderMoveTests.Fixture

    @MainActor struct Persisted {
        let directory = CommandBarFixtures.temporaryDirectory("folder-move")
        let fixture = Fixture()

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(fixture.state).write(to: directory.appendingPathComponent("session.json"))
        }

        func store() throws -> BrowserStore { try BrowserStore(directory: directory) }

        func move(_ id: UUID, in store: BrowserStore) throws -> CommandBarFolderMove {
            let source = try #require(fixture.source([.tab(id)], store.state))
            return try #require(fixture.action(source, fixture.there.id, store.state))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aDurableStoreTransactionAccepts() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let store = try persisted.store()
        #expect(try store.performCommandBarFolderMove(persisted.move(persisted.fixture.first.id, in: store)))
    }

    @Test func theExactFolderPlacementSurvivesAReload() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let store = try persisted.store()
        _ = try store.performCommandBarFolderMove(persisted.move(persisted.fixture.first.id, in: store))
        let reopened = try persisted.store()
        #expect(reopened.state.tabs.first { $0.id == persisted.fixture.first.id }?.folderID == persisted.fixture.there.id)
    }

    @Test func aPersistenceFailurePublishesNoPartialMove() throws {
        let persisted = try Persisted()
        defer { persisted.cleanUp() }
        let failed = try persisted.store()
        let retry = try persisted.move(persisted.fixture.last.id, in: failed)
        let unchanged = failed.state
        try FileManager.default.removeItem(at: persisted.directory)
        try Data("not a directory".utf8).write(to: persisted.directory)
        #expect(throws: (any Error).self) { try failed.performCommandBarFolderMove(retry) }
        #expect(failed.state == unchanged)
    }
}
