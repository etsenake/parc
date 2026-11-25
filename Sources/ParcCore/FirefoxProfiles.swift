import Foundation
import SQLite3

package enum FirefoxProfiles {
    package struct Entry: Equatable {
        package let path: URL
        package let name: String
        package let isDefault: Bool
    }

    package static func entries(root: URL) -> [Entry] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }
        var sections: [(name: String, values: [String: String])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") { sections.append((String(line.dropFirst().dropLast()), [:])); continue }
            guard !line.hasPrefix(";"), !line.hasPrefix("#"), let equals = line.firstIndex(of: "="), !sections.isEmpty else { continue }
            sections[sections.count - 1].values[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        let installDefault = sections.first { $0.name.hasPrefix("Install") }?.values["Default"]
        var result: [Entry] = []
        var stores: [String] = []
        for section in sections where section.name.hasPrefix("Profile") {
            guard let path = section.values["Path"], !path.isEmpty else { continue }
            let url = section.values["IsRelative"] == "0" ? URL(fileURLWithPath: path, isDirectory: true)
                : root.appendingPathComponent(path, isDirectory: true)
            let isDefault = installDefault.map { $0 == path } ?? (section.values["Default"] == "1")
            result.append(Entry(path: url, name: section.values["Name"] ?? url.lastPathComponent, isDefault: isDefault))
            if let store = section.values["StoreID"], !store.isEmpty, !stores.contains(store) { stores.append(store) }
        }
        for store in stores {
            for profile in groupProfiles(root: root, storeID: store) {
                let url = profile.path.hasPrefix("/") ? URL(fileURLWithPath: profile.path, isDirectory: true)
                    : root.appendingPathComponent(profile.path, isDirectory: true)
                let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = result.firstIndex(where: { $0.path.standardizedFileURL.path == url.standardizedFileURL.path }) {
                    let entry = result[index]
                    result[index] = Entry(path: entry.path, name: name.isEmpty ? entry.name : name, isDefault: entry.isDefault)
                } else {
                    result.append(Entry(path: url, name: name.isEmpty ? url.lastPathComponent : name, isDefault: false))
                }
            }
        }
        return result
    }

    package static func paths(root: URL) -> [URL] { entries(root: root).map(\.path) }

    static func groupProfiles(root: URL, storeID: String) -> [(path: String, name: String)] {
        guard storeID.utf8.count <= 255, !storeID.hasPrefix("."), !storeID.contains("/"),
              !storeID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return [] }
        let files = FileManager.default
        let source = root.appendingPathComponent("Profile Groups", isDirectory: true).appendingPathComponent("\(storeID).sqlite")
        guard files.fileExists(atPath: source.path),
              ((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max) <= 64 * 1024 * 1024 else { return [] }
        let folder = files.temporaryDirectory.appendingPathComponent("parc-firefox-\(UUID().uuidString)", isDirectory: true)
        guard (try? files.createDirectory(at: folder, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o700])) != nil else { return [] }
        defer { try? files.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("profiles.sqlite")
        guard (try? files.copyItem(at: source, to: copy)) != nil else { return [] }
        for suffix in ["-wal", "-shm"] where files.fileExists(atPath: source.path + suffix) {
            try? files.copyItem(at: URL(fileURLWithPath: source.path + suffix), to: URL(fileURLWithPath: copy.path + suffix))
        }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(copy.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT path, name FROM Profiles ORDER BY id", -1, &statement, nil) == SQLITE_OK
        else { return [] }
        var result: [(path: String, name: String)] = []
        while result.count < 1_000, sqlite3_step(statement) == SQLITE_ROW {
            guard let path = sqlite3_column_text(statement, 0).map({ String(cString: $0) }), !path.isEmpty else { continue }
            result.append((path, sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""))
        }
        return result
    }
}
