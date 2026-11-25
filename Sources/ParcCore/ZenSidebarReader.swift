import Foundation

package enum ZenSidebarReader {
    static let defaultContainerNames = [1: "Personal", 2: "Work", 3: "Banking", 4: "Shopping"]
    static let maximumPlainFileSize = 16 * 1024 * 1024

    package static func read(profiles: [SidebarImportProfile]) throws -> SidebarImport {
        var parts: [SidebarImport] = [], regexRoutes = 0
        for profile in profiles {
            let part = read(profile: profile)
            parts.append(part.sidebar)
            regexRoutes += part.regexRoutes
        }
        var result = SidebarImport.merged(parts)
        if regexRoutes == 1 {
            result.warnings.append("1 Zen routing rule uses a regular expression, which Parc can't match, so it was left out.")
        } else if regexRoutes > 1 {
            result.warnings.append("\(regexRoutes) Zen routing rules use regular expressions, which Parc can't match, so they were left out.")
        }
        return result
    }

    static func read(profile: SidebarImportProfile) -> (sidebar: SidebarImport, regexRoutes: Int) {
        let directory = profile.directory
        let loaded = session(in: directory)
        guard let root = loaded.root else {
            var empty = SidebarImport(spaces: [])
            if loaded.unreadable { empty.warnings.append("Parc couldn't read the Zen sidebar of \(profile.name).") }
            return (empty, 0)
        }
        var session = ZenSidebarSession(root: root, profile: profile.key, profileFolder: directory.lastPathComponent,
                                        containers: containers(in: directory),
                                        separateEssentials: separateEssentials(in: directory))
        let routing = routes(in: directory, spaces: Set(session.spaceUUIDs))
        var sidebar = session.sidebar()
        sidebar.routes = routing.routes + siteRoutes(in: directory, folder: directory.lastPathComponent)
        if let closed = try? FirefoxSession.read(profile: directory)?.closedTabs {
            sidebar.archive = closed.map { SidebarImport.ArchivedTab(tab: $0.tab, archivedAt: $0.closedAt, reason: .manual,
                                                                     spaceID: nil, profile: profile.key) }
        }
        return (sidebar, routing.regex)
    }

    static func siteRoutes(in directory: URL, folder: String) -> [SidebarImport.Route] {
        guard let data = plainData(directory.appendingPathComponent("containers.json")),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let associations = root["siteAssociations"] as? [String: Any] else { return [] }
        let known = containers(in: directory)
        return associations.keys.sorted().compactMap { host in
            guard let id = (associations[host] as? NSNumber)?.intValue, known[id] != nil,
                  !host.isEmpty, !host.contains("/"), !host.contains(" ") else { return nil }
            return SidebarImport.Route(conditions: [.init(style: .contains, pattern: host.lowercased())],
                                       destination: .profile(.extra("zen:\(folder):\(id)")))
        }
    }

    static func sessionCandidates(in directory: URL) -> [URL] {
        let backups = directory.appendingPathComponent("zen-sessions-backup", isDirectory: true)
        let dated = ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? [])
            .filter { $0.hasPrefix("zen-sessions-") && $0.hasSuffix(".jsonlz4") }
            .sorted(by: >)
        return [directory.appendingPathComponent("zen-sessions.jsonlz4"),
                backups.appendingPathComponent("clean.jsonlz4"),
                backups.appendingPathComponent("recovery.baklz4")] + dated.map { backups.appendingPathComponent($0) }
    }

    static func session(in directory: URL) -> (root: [String: Any]?, unreadable: Bool) {
        var unreadable = false
        for url in sessionCandidates(in: directory) where FileManager.default.fileExists(atPath: url.path) {
            guard let root = (try? MozLz4.json(at: url)) as? [String: Any] else { unreadable = true; continue }
            if let spaces = root["spaces"] as? [Any], !spaces.isEmpty { return (root, false) }
        }
        return (nil, unreadable)
    }

    static func plainData(_ url: URL) -> Data? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= maximumPlainFileSize else { return nil }
        return try? Data(contentsOf: url)
    }

    static func containers(in directory: URL) -> [Int: String] {
        guard let data = plainData(directory.appendingPathComponent("containers.json")),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var result: [Int: String] = [:]
        for case let identity as [String: Any] in root["identities"] as? [Any] ?? [] {
            guard identity["public"] as? Bool == true, let id = (identity["userContextId"] as? NSNumber)?.intValue, id > 0,
                  result[id] == nil else { continue }
            let name = (identity["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result[id] = name.isEmpty ? defaultContainerNames[id] ?? "Container \(id)" : name
        }
        return result
    }

    static func separateEssentials(in directory: URL) -> Bool {
        guard let data = plainData(directory.appendingPathComponent("prefs.js")),
              let text = String(data: data, encoding: .utf8) else { return true }
        let pattern = #"user_pref\(\s*"zen\.workspaces\.separate-essentials"\s*,\s*(true|false)\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text) else { return true }
        return text[range] == "true"
    }

    static func routes(in directory: URL, spaces: Set<String>) -> (routes: [SidebarImport.Route], regex: Int) {
        let url = directory.appendingPathComponent("zen-space-routing.jsonlz4")
        guard FileManager.default.fileExists(atPath: url.path),
              let root = (try? MozLz4.json(at: url)) as? [String: Any] else { return ([], 0) }
        var routes: [SidebarImport.Route] = [], regex = 0
        for case let route as [String: Any] in root["routes"] as? [Any] ?? [] {
            guard let reference = (route["reference"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reference.isEmpty, let openIn = route["openIn"] as? String else { continue }
            let destination: SidebarImport.Route.Destination
            if openIn == "most-recent-space" { destination = .mostRecent }
            else if spaces.contains(openIn) { destination = .space(ZenSidebarSession.spaceID(openIn)) }
            else { continue }
            let style: LinkMatchStyle
            switch route["matchType"] as? String {
            case "contains": style = .contains
            case "equal-to": style = .matches
            case "regex": regex += 1; continue
            default: continue
            }
            routes.append(SidebarImport.Route(conditions: [.init(style: style, pattern: reference)], destination: destination))
        }
        return (routes, regex)
    }
}
