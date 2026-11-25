import Foundation

package struct FirefoxSession {
    package struct ClosedTab: Equatable {
        package let tab: SidebarImport.Tab
        package let closedAt: Date
        package let window: Int?
    }

    package let state: [String: Any]
    package let windows: [[String: Any]]
    package let closedWindows: [[String: Any]]
    package let savedGroups: [[String: Any]]
    package let closedTabs: [ClosedTab]

    package static func files(profile directory: URL) -> [URL] {
        let backups = directory.appendingPathComponent("sessionstore-backups", isDirectory: true)
        let upgrades = ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? [])
            .filter { $0.hasPrefix("upgrade.jsonlz4-") }.sorted(by: >)
        return [directory.appendingPathComponent("sessionstore.jsonlz4"),
                backups.appendingPathComponent("recovery.jsonlz4"),
                backups.appendingPathComponent("recovery.baklz4"),
                backups.appendingPathComponent("previous.jsonlz4")]
            + upgrades.map { backups.appendingPathComponent($0) }
    }

    package static func read(profile directory: URL) throws -> FirefoxSession? {
        var encrypted = false
        for file in files(profile: directory) {
            do {
                guard let state = try MozLz4.json(at: file) as? [String: Any], supported(state) else { continue }
                return FirefoxSession(state: state)
            } catch MozLz4.Failure.encrypted {
                encrypted = true
            } catch {}
        }
        if encrypted { throw MozLz4.Failure.encrypted }
        return nil
    }

    package init(state: [String: Any]) {
        func normal(_ window: [String: Any]) -> Bool {
            !["isPrivate", "isPopup", "isTaskbarTab", "isMiniWindow"].contains { window[$0] as? Bool == true }
        }
        func hasTabs(_ windows: [[String: Any]], unpinnedOnly: Bool) -> Bool {
            windows.contains { window in Self.list(window["tabs"]).contains { !unpinnedOnly || $0["pinned"] as? Bool != true } }
        }
        var current = Self.list(state["windows"]).filter(normal)
        var closed = Self.list(state["_closedWindows"]).filter(normal)
        var discarded: [[String: Any]] = []
        let last = state["lastSessionState"] as? [String: Any]
        let lastWindows = Self.list(last?["windows"]).filter(normal)
        if !hasTabs(current, unpinnedOnly: true), hasTabs(lastWindows, unpinnedOnly: false) {
            discarded = current
            current = lastWindows
            closed += Self.list(last?["_closedWindows"]).filter(normal)
        }
        if !hasTabs(current, unpinnedOnly: false), !closed.isEmpty {
            discarded += current
            current = [closed.removeFirst()]
        }
        let openGroups = Set(current.flatMap { Self.list($0["groups"]).compactMap { Self.key($0["id"]) } })
        var closedTabs: [ClosedTab] = []
        func append(_ tabState: Any?, _ closedAt: Any?, _ window: Int?) {
            guard let tabState = tabState as? [String: Any], let milliseconds = closedAt as? Double,
                  milliseconds.isFinite, milliseconds > 0, let tab = Self.tab(tabState) else { return }
            closedTabs.append(ClosedTab(tab: tab, closedAt: Date(timeIntervalSince1970: milliseconds / 1000), window: window))
        }
        func appendClosed(in window: [String: Any], index: Int?) {
            for record in Self.list(window["_closedTabs"]) { append(record["state"], record["closedAt"], index) }
            for group in Self.list(window["closedGroups"]) {
                for record in Self.list(group["tabs"]) { append(record["state"], record["closedAt"] ?? group["closedAt"], index) }
            }
        }
        for (index, window) in current.enumerated() { appendClosed(in: window, index: index) }
        for window in closed {
            for tab in Self.list(window["tabs"]) { append(tab, window["closedAt"], nil) }
            appendClosed(in: window, index: nil)
        }
        for window in discarded { appendClosed(in: window, index: nil) }
        self.state = state
        windows = current
        closedWindows = closed
        savedGroups = Self.list(state["savedGroups"]).filter { group in
            !(group["removeAfterRestore"] as? Bool == true && Self.key(group["id"]).map { openGroups.contains($0) } == true)
        }
        self.closedTabs = closedTabs
    }

    package static func tab(_ state: [String: Any]) -> SidebarImport.Tab? {
        guard let entry = currentEntry(state), let url = entry["url"] as? String else { return nil }
        return SidebarImport.Tab.web(url: url, title: entry["title"] as? String)
    }

    package static func currentEntry(_ state: [String: Any]) -> [String: Any]? {
        guard let entries = state["entries"] as? [Any], !entries.isEmpty else { return nil }
        let index = (state["index"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? entries.count
        return entries[min(index, entries.count) - 1] as? [String: Any]
    }

    package static func key(_ value: Any?) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        return (value as? NSNumber).map(\.stringValue)
    }

    package static func list(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    static func supported(_ state: [String: Any]) -> Bool {
        guard let version = state["version"] as? [Any], version.count >= 2, version[0] as? String == "sessionrestore",
              let number = version[1] as? Int else { return false }
        return number <= 1
    }
}
