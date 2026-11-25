import Foundation

package struct ChromiumSavedTabGroup: Equatable {
    package struct Tab: Equatable {
        package let url: String
        package let title: String
        package let position: Int

        package init(url: String, title: String, position: Int) {
            self.url = url
            self.title = title
            self.position = position
        }
    }

    package let guid: String
    package let title: String
    package let color: Int
    package let position: Int
    package let tabs: [Tab]

    package init(guid: String, title: String, color: Int, position: Int, tabs: [Tab]) {
        self.guid = guid
        self.title = title
        self.color = color
        self.position = position
        self.tabs = tabs
    }
}

package enum ChromiumSavedTabGroups {
    static let dataPrefix = Array("saved_tab_group-dt-".utf8)
    static let maximumRecords = 50_000

    package static func read(profileDirectory: URL) throws -> [ChromiumSavedTabGroup] {
        let store = profileDirectory.appendingPathComponent("Sync Data", isDirectory: true)
            .appendingPathComponent("LevelDB", isDirectory: true)
        return groups(from: try LevelDBReader.read(directory: store, keyPrefix: dataPrefix))
    }

    struct GroupRecord {
        let guid: String
        let title: String
        let color: Int
        let pinnedPosition: Int64?
        let updated: Int64
    }

    struct TabRecord {
        let tab: ChromiumSavedTabGroup.Tab
        let created: Int64
    }

    static func groups(from records: [[UInt8]: [UInt8]], maximumRecords: Int = Self.maximumRecords) -> [ChromiumSavedTabGroup] {
        var groups: [String: GroupRecord] = [:]
        var tabs: [String: [TabRecord]] = [:]
        let kept = records.sorted { $0.key.lexicographicallyPrecedes($1.key) }.prefix(maximumRecords)
        for (key, value) in kept {
            guard let data = ProtobufReader(value), let specifics = data.message(2) else { continue }
            let named = specifics.string(1) ?? ""
            let guid = (named.isEmpty ? String(decoding: key.dropFirst(dataPrefix.count), as: UTF8.self) : named).lowercased()
            guard !guid.isEmpty else { continue }
            let created = specifics.int64(2) ?? 0
            if let group = specifics.message(4) {
                guard data.message(3)?.bool(7) != true else { continue }
                let color = group.varint(3).map { Int(clamping: $0) } ?? 0
                groups[guid] = GroupRecord(guid: guid, title: group.string(2) ?? "", color: (0...9).contains(color) ? color : 0,
                                           pinnedPosition: group.int64(4), updated: specifics.int64(3) ?? created)
            } else if let tab = specifics.message(5), let owner = tab.string(1)?.lowercased(), !owner.isEmpty,
                      let url = tab.string(3), !url.isEmpty {
                let entry = ChromiumSavedTabGroup.Tab(url: url, title: tab.string(4) ?? "", position: Int(clamping: tab.int64(2) ?? 0))
                tabs[owner, default: []].append(TabRecord(tab: entry, created: created))
            }
        }
        let ordered = groups.values.filter { tabs[$0.guid]?.isEmpty == false }.sorted { first, second in
            if let a = first.pinnedPosition, let b = second.pinnedPosition, a != b { return a < b }
            if (first.pinnedPosition == nil) != (second.pinnedPosition == nil) { return first.pinnedPosition != nil }
            if first.updated != second.updated { return first.updated > second.updated }
            return first.guid < second.guid
        }
        return ordered.enumerated().map { index, group in
            let members = (tabs[group.guid] ?? []).sorted { first, second in
                if first.tab.position != second.tab.position { return first.tab.position < second.tab.position }
                if first.created != second.created { return first.created < second.created }
                return first.tab.url < second.tab.url
            }
            return ChromiumSavedTabGroup(guid: group.guid, title: group.title, color: group.color, position: index,
                                         tabs: members.map(\.tab))
        }
    }
}
