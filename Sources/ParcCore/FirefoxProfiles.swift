import Foundation

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
        for section in sections where section.name.hasPrefix("Profile") {
            guard let path = section.values["Path"], !path.isEmpty else { continue }
            let url = section.values["IsRelative"] == "0" ? URL(fileURLWithPath: path, isDirectory: true)
                : root.appendingPathComponent(path, isDirectory: true)
            let isDefault = installDefault.map { $0 == path } ?? (section.values["Default"] == "1")
            result.append(Entry(path: url, name: section.values["Name"] ?? url.lastPathComponent, isDefault: isDefault))
        }
        return result
    }

    package static func paths(root: URL) -> [URL] { entries(root: root).map(\.path) }
}
