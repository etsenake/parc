import Foundation
import SQLite3

struct SafariTabsDatabase {
    struct Attributes {
        var localURL: String?
        var localTitle: String?
        var pinnedAddress: String?
        var pinnedTitle: String?
        var symbol: String?
        var favoritesFolder: String?
        var isPinned = false
        var isUnnamed = false
    }

    struct Row {
        let id: Int64
        let parent: Int64?
        let type: Int64
        let subtype: Int64
        let special: Int64
        let title: String?
        let url: String?
        let uuid: String
        let syncable: Bool
        let hidden: Bool
        let deleted: Bool
        let closed: Bool
        let attributes: Attributes
    }

    struct Window {
        let id: Int64
        let profile: Int64?
        let local: Int64?
        let live: Bool
    }

    var rows: [Int64: Row] = [:]
    var children: [Int64: [Int64]] = [:]
    var windows: [Window] = []
    var unnamed: [Int64: [Int64]] = [:]
    var localGroups = Set<Int64>()
    var privateGroups = Set<Int64>()
    var unnamedGroups = Set<Int64>()

    static let maximumBytes: Int64 = 2 << 30
    static let maximumRows = 250_000

    private enum Failure: Error { case torn }

    static func read(_ file: URL) throws -> SafariTabsDatabase? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do { return try copied(file) } catch Failure.torn {}
        do { return try copied(file) } catch Failure.torn { throw CocoaError(.fileReadCorruptFile) }
    }

    private static func copied(_ file: URL) throws -> SafariTabsDatabase {
        let files = FileManager.default
        let sides = ["-wal", "-shm"].map { (URL(fileURLWithPath: file.path + $0), $0) }.filter { files.fileExists(atPath: $0.0.path) }
        for source in [file] + sides.map({ $0.0 }) {
            let size = (try files.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        }
        let folder = files.temporaryDirectory.appendingPathComponent("ParcSafariTabs-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("SafariTabs.db")
        try files.copyItem(at: file, to: copy)
        for (source, suffix) in sides {
            try files.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
        }
        return try load(copy)
    }

    private static func load(_ file: URL) throws -> SafariTabsDatabase {
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let db = handle else {
            _ = sqlite3_close(handle)
            throw failure(opened)
        }
        defer { _ = sqlite3_close(db) }
        _ = sqlite3_exec(db, "BEGIN", nil, nil, nil)
        defer { _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        let tables = try names(db, "SELECT name FROM sqlite_master WHERE type = 'table'", column: 0)
        guard tables.contains("bookmarks") else { throw CocoaError(.fileReadCorruptFile) }
        let columns = try names(db, "PRAGMA table_info(bookmarks)", column: 1)
        func column(_ name: String, _ fallback: String) -> String { columns.contains(name) ? name : fallback }
        let sql = """
            SELECT id, parent, type, \(column("subtype", "0")), \(column("special_id", "0")), \(column("title", "NULL")), \
            \(column("url", "NULL")), \(column("external_uuid", "NULL")), \(column("syncable", "1")), \(column("hidden", "0")), \
            \(column("deleted", "0")), (\(column("date_closed", "NULL")) IS NOT NULL), \(column("extra_attributes", "NULL")), \
            CASE WHEN type = 0 THEN \(column("local_attributes", "NULL")) END \
            FROM bookmarks ORDER BY parent, \(column("order_index", "0")), id
            """
        var result = SafariTabsDatabase()
        try query(db, sql) { statement in
            guard result.rows.count < maximumRows else { return false }
            let id = sqlite3_column_int64(statement, 0)
            let row = Row(id: id, parent: integer(statement, 1), type: sqlite3_column_int64(statement, 2),
                          subtype: sqlite3_column_int64(statement, 3), special: sqlite3_column_int64(statement, 4),
                          title: text(statement, 5), url: text(statement, 6), uuid: text(statement, 7) ?? "",
                          syncable: sqlite3_column_int64(statement, 8) != 0, hidden: sqlite3_column_int64(statement, 9) != 0,
                          deleted: sqlite3_column_int64(statement, 10) != 0, closed: sqlite3_column_int64(statement, 11) != 0,
                          attributes: attributes(extra: blob(statement, 12), local: blob(statement, 13)))
            result.rows[id] = row
            if let parent = row.parent, parent != id { result.children[parent, default: []].append(id) }
            return true
        }
        if tables.contains("windows") {
            let windowColumns = try names(db, "PRAGMA table_info(windows)", column: 1)
            func window(_ name: String, _ fallback: String) -> String { windowColumns.contains(name) ? name : fallback }
            let sql = """
                SELECT id, \(window("active_profile_id", "NULL")), \(window("local_tab_group_id", "NULL")), \
                \(window("private_tab_group_id", "NULL")), \
                (\(window("is_last_session", "1")) = 1 AND \(window("date_closed", "NULL")) IS NULL) \
                FROM windows ORDER BY id
                """
            try query(db, sql) { statement in
                let item = Window(id: sqlite3_column_int64(statement, 0), profile: integer(statement, 1),
                                  local: integer(statement, 2), live: sqlite3_column_int64(statement, 4) != 0)
                result.windows.append(item)
                if let local = item.local { result.localGroups.insert(local) }
                if let hidden = integer(statement, 3) { result.privateGroups.insert(hidden) }
                return result.windows.count < maximumRows
            }
        }
        if tables.contains("windows_unnamed_tab_groups") {
            try query(db, "SELECT window_id, tab_group_id FROM windows_unnamed_tab_groups ORDER BY id") { statement in
                let window = sqlite3_column_int64(statement, 0), group = sqlite3_column_int64(statement, 1)
                result.unnamed[window, default: []].append(group)
                result.unnamedGroups.insert(group)
                return result.unnamedGroups.count < maximumRows
            }
        }
        return result
    }

    private static func attributes(extra: Data?, local: Data?) -> Attributes {
        let extra = dictionary(extra), local = dictionary(local)
        func string(_ values: [String: Any], _ key: String) -> String? {
            (values[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        var result = Attributes()
        result.localURL = string(extra, "LocalURL")
        result.localTitle = string(extra, "LocalTitle")
        result.pinnedAddress = string(extra, "PinnedAddress") ?? string(local, "PinnedPageURL")
        result.pinnedTitle = string(extra, "PinnedTitle") ?? string(local, "PinnedPageTitle")
        result.symbol = string(extra, "SymbolImageName")
        result.favoritesFolder = string(extra, "CustomFavoritesFolderServerID")
        result.isPinned = extra["IsPinned"] as? Bool == true || local["IsPinned"] as? Bool == true
        result.isUnnamed = extra["IsUnnamed"] as? Bool == true
        return result
    }

    private static func dictionary(_ data: Data?) -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }

    private static func query(_ db: OpaquePointer, _ sql: String, _ row: (OpaquePointer) throws -> Bool) throws {
        var handle: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &handle, nil)
        guard prepared == SQLITE_OK, let statement = handle else {
            _ = sqlite3_finalize(handle)
            throw failure(prepared)
        }
        defer { _ = sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else { throw failure(step) }
            guard try row(statement) else { return }
        }
    }

    private static func names(_ db: OpaquePointer, _ sql: String, column: Int32) throws -> Set<String> {
        var result = Set<String>()
        try query(db, sql) { statement in
            if let value = text(statement, column) { result.insert(value) }
            return true
        }
        return result
    }

    private static func failure(_ code: Int32) -> any Error {
        let primary = code & 0xff
        return primary == SQLITE_CORRUPT || primary == SQLITE_NOTADB ? Failure.torn : CocoaError(.fileReadCorruptFile)
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private static func integer(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private static func blob(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }
}
