import Foundation
import SQLite3
import Testing
@testable import ParcCore

struct FirefoxProfilesTests {
    private static let ini = """
    [Install4F96D1932A9F858E]
    Default=Profiles/abcd1234.default-release
    Locked=1

    [Profile1]
    Name=default
    IsRelative=1
    Path=Profiles/efgh5678.default
    Default=1

    [Profile0]
    Name=default-release
    IsRelative=1
    Path=Profiles/abcd1234.default-release
    StoreID=a1b2c3d4

    [General]
    StartWithLastProfile=1
    Version=2
    """

    private static func withRoot<T>(ini: String, _ body: (URL) throws -> T) throws -> T {
        try DataFixtures.withTemporaryDirectory { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(ini.utf8).write(to: root.appendingPathComponent("profiles.ini"))
            return try body(root)
        }
    }

    private static func openGroup(root: URL, storeID: String, rows: [(Int, String, String)]) throws -> OpaquePointer? {
        let folder = root.appendingPathComponent("Profile Groups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var database: OpaquePointer?
        try #require(sqlite3_open(folder.appendingPathComponent("\(storeID).sqlite").path, &database) == SQLITE_OK)
        var sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE Profiles (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, avatar TEXT NOT NULL,
          themeId TEXT NOT NULL, themeFg TEXT NOT NULL, themeBg TEXT NOT NULL);
        """
        for (id, path, name) in rows {
            sql += "INSERT INTO Profiles VALUES (\(id), '\(path)', '\(name)', 'book', 'default', '', '');\n"
        }
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        return database
    }

    private static func paths(_ root: URL, _ relative: [String]) -> [String] {
        relative.map { root.appendingPathComponent($0, isDirectory: true).standardizedFileURL.path }
    }

    @Test func profileGroupsAddEveryProfileWithItsRealName() throws {
        try Self.withRoot(ini: Self.ini) { root in
            let database = try Self.openGroup(root: root, storeID: "a1b2c3d4", rows: [
                (1, "Profiles/abcd1234.default-release", "Personal"),
                (2, "Profiles/ijkl9012.Profile 2", "Work"),
                (3, "Profiles/mnop3456.Profile 3", "  "),
            ])
            defer { sqlite3_close(database) }
            let entries = FirefoxProfiles.entries(root: root)
            #expect(entries.map(\.name) == ["default", "Personal", "Work", "mnop3456.Profile 3"])
            #expect(entries.map(\.isDefault) == [false, true, false, false])
            #expect(entries.map { $0.path.standardizedFileURL.path } == Self.paths(root, [
                "Profiles/efgh5678.default", "Profiles/abcd1234.default-release",
                "Profiles/ijkl9012.Profile 2", "Profiles/mnop3456.Profile 3",
            ]))
        }
    }

    @Test func withoutAStoreIDOnlyTheIniProfilesAreListed() throws {
        let ini = Self.ini.replacingOccurrences(of: "StoreID=a1b2c3d4\n", with: "")
        try Self.withRoot(ini: ini) { root in
            let database = try Self.openGroup(root: root, storeID: "a1b2c3d4",
                                              rows: [(2, "Profiles/ijkl9012.Profile 2", "Work")])
            defer { sqlite3_close(database) }
            let entries = FirefoxProfiles.entries(root: root)
            #expect(entries.map(\.name) == ["default", "default-release"])
            #expect(entries.map(\.isDefault) == [false, true])
        }
    }

    @Test func aMissingGroupDatabaseKeepsTheIniProfiles() throws {
        try Self.withRoot(ini: Self.ini) { root in
            let entries = FirefoxProfiles.entries(root: root)
            #expect(entries.map(\.name) == ["default", "default-release"])
            #expect(FirefoxProfiles.paths(root: root).map { $0.standardizedFileURL.path }
                    == Self.paths(root, ["Profiles/efgh5678.default", "Profiles/abcd1234.default-release"]))
        }
    }

    @Test func withoutAnInstallSectionTheDefaultFlagDecides() throws {
        let ini = Self.ini.replacingOccurrences(of: "Default=Profiles/abcd1234.default-release\n", with: "")
            .replacingOccurrences(of: "[Install4F96D1932A9F858E]\n", with: "")
        try Self.withRoot(ini: ini) { root in
            let database = try Self.openGroup(root: root, storeID: "a1b2c3d4",
                                              rows: [(1, "Profiles/abcd1234.default-release", "Personal")])
            defer { sqlite3_close(database) }
            let entries = FirefoxProfiles.entries(root: root)
            #expect(entries.map(\.name) == ["default", "Personal"])
            #expect(entries.map(\.isDefault) == [true, false])
        }
    }
}
