import Foundation

struct ArcWindowLayout {
    var expanded: Set<String>? = nil
    var collapsedPinned: Set<String> = []

    init(_ data: Data?) {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        func ids(_ value: Any?) -> [String] {
            (value as? [Any] ?? []).compactMap { entry in
                let id = entry as? String ?? (entry as? [String: Any])?["id"] as? String
                return id.flatMap { $0.isEmpty ? nil : $0 }
            }
        }
        let keys = ["spacesWithCollapsedPinnedSections", "spacesWithCollapsedPinnedSection"]
        let windows = (root["windows"] as? [Any])?.compactMap { $0 as? [String: Any] }
        var collapsed = Set(keys.flatMap { ids(root[$0]) })
        for window in windows ?? [] { collapsed.formUnion(keys.flatMap { ids(window[$0]) }) }
        collapsedPinned = collapsed
        expanded = windows.flatMap { list in list.isEmpty ? nil : Set(list.flatMap { ids($0["expandedItems"]) }) }
    }
}

extension SidebarImport {
    static func arcPairs(_ value: Any?) -> [(Any, Any)] {
        guard let array = value as? [Any] else { return [] }
        return stride(from: 0, to: array.count - 1, by: 2).map { (array[$0], array[$0 + 1]) }
    }

    static func arcMainContainer(_ containers: [Any]) -> [String: Any]? {
        let entries = containers.map { $0 as? [String: Any] ?? [:] }
        func holdsSpaces(_ index: Int) -> Bool { entries.indices.contains(index) && entries[index]["spaces"] is [Any] }
        func marker(_ index: Int, _ key: String) -> Bool {
            entries.indices.contains(index) && entries[index][key] != nil && !holdsSpaces(index)
        }
        if let global = entries.indices.first(where: { marker($0, "global") }), holdsSpaces(global + 1) {
            return entries[global + 1]
        }
        let main = entries.indices.first { holdsSpaces($0) && !marker($0 - 1, "littleBrowser") }
            ?? entries.indices.first(where: holdsSpaces)
        return main.map { entries[$0] }
    }

    static func arcTab(_ item: [String: Any]) -> Tab? {
        guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
        return Tab.web(url: tab["savedURL"] as? String ?? "", title: tab["savedTitle"] as? String,
                       customTitle: item["title"] as? String, isMuted: tab["savedMuteStatus"] as? String == "mute",
                       isUnread: item["isUnread"] as? Bool == true)
    }

    static func arcArchive(_ data: Data?, spaces: [String: ProfileKey]) -> (tabs: [ArchivedTab], skipped: Int) {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], 0) }
        var result: [ArchivedTab] = [], skipped = 0
        for (_, value) in arcPairs(root["items"]).prefix(maximumItems) {
            guard let entry = value as? [String: Any], let item = entry["sidebarItem"] as? [String: Any], let tab = arcTab(item),
                  let seconds = entry["archivedAt"] as? Double, seconds.isFinite else { continue }
            guard let source = ((entry["source"] as? [String: Any])?["space"] as? [String: Any])?["_0"] as? String,
                  let profile = spaces[source] else { skipped += 1; continue }
            result.append(ArchivedTab(tab: tab, archivedAt: Date(timeIntervalSinceReferenceDate: seconds),
                                      reason: arcArchiveReason(entry["reason"]), spaceID: source, profile: profile))
        }
        return (result, skipped)
    }

    static func arcRoutes(_ data: Data?, spaces: Set<String>) -> (routes: [Route], warnings: [String]) {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], []) }
        func littleArc(_ value: Any?) -> Bool { (value as? [String: Any])?["littleArc"] != nil }
        var routes: [Route] = [], sendsToLittleArc = littleArc(root["defaultDestination"])
        for case let rule as [String: Any] in (root["rules"] as? [Any] ?? []).prefix(maximumItems) {
            if littleArc(rule["destination"]) { sendsToLittleArc = true; continue }
            guard let destination = arcRouteDestination(rule["destination"], spaces: spaces),
                  let components = rule["sourceComponents"] as? [Any], !components.isEmpty else { continue }
            let conditions = components.compactMap(arcRouteCondition)
            guard conditions.count == components.count else { continue }
            routes.append(Route(conditions: conditions, destination: destination))
        }
        guard sendsToLittleArc else { return (routes, []) }
        return (routes, ["Air Traffic Control sent some links to Little Arc. Parc has no Little Arc, "
                         + "so those links open in your most recent Space."])
    }

    private static func arcCase(_ value: Any?) -> String? {
        value as? String ?? (value as? [String: Any]).flatMap { $0.count == 1 ? $0.keys.first : nil }
    }

    private static func arcArchiveReason(_ value: Any?) -> ArchiveReason {
        switch arcCase(value) {
        case "auto": return .automatic
        case "clearButton": return .clearButton
        case "clearTabGroup": return .clearTabGroup
        default: return .manual
        }
    }

    private static func arcRouteDestination(_ value: Any?, spaces: Set<String>) -> Route.Destination? {
        guard let target = ((value as? [String: Any])?["space"] as? [String: Any])?["_0"] else { return nil }
        if arcCase(target) == "mostRecent" { return .mostRecent }
        guard let id = (((target as? [String: Any])?["space"] as? [String: Any])?["_0"] as? String),
              spaces.contains(id) else { return nil }
        return .space(id)
    }

    private static func arcRouteCondition(_ value: Any) -> Route.Condition? {
        guard let match = ((value as? [String: Any])?["componentType"] as? [String: Any])?["urlMatch"] as? [String: Any],
              let pattern = (match["_1"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty
        else { return nil }
        switch arcCase(match["_0"]) {
        case "contains": return Route.Condition(style: .contains, pattern: pattern)
        case "matches": return Route.Condition(style: .matches, pattern: pattern)
        default: return nil
        }
    }
}
