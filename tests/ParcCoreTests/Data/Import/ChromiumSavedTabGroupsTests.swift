import Foundation
import Testing
@testable import ParcCore

struct ChromiumSavedTabGroupsTests {
    typealias F = LevelDBFixture

    static func tag(_ field: Int, _ wire: Int) -> [UInt8] { F.varint(field << 3 | wire) }
    static func number(_ field: Int, _ value: Int64) -> [UInt8] { tag(field, 0) + F.varint(UInt64(bitPattern: value)) }
    static func bytes(_ field: Int, _ value: [UInt8]) -> [UInt8] { tag(field, 2) + F.lengthPrefixed(value) }
    static func string(_ field: Int, _ value: String) -> [UInt8] { bytes(field, Array(value.utf8)) }

    static func group(_ guid: String, title: String, color: Int64, pinned: Int64? = nil, created: Int64, hidden: Bool = false) -> [UInt8] {
        var group = string(2, title) + number(3, color)
        if let pinned { group += number(4, pinned) }
        let specifics = string(1, guid) + number(2, created) + number(3, created) + bytes(4, group) + number(7, 2)
        let local = string(1, "local-token") + (hidden ? number(7, 1) : [])
        return number(1, 1) + bytes(2, specifics) + bytes(3, local)
    }

    static func tab(_ guid: String, group: String, position: Int64, url: String, title: String, created: Int64 = 1) -> [UInt8] {
        let tab = string(1, group) + number(2, position) + string(3, url) + string(4, title)
        return number(1, 1) + bytes(2, string(1, guid) + number(2, created) + bytes(5, tab))
    }

    static func data(_ guid: String) -> String { "saved_tab_group-dt-\(guid)" }

    func store(in profile: URL) -> URL {
        profile.appendingPathComponent("Sync Data").appendingPathComponent("LevelDB")
    }

    @Test func aSavedGroupComesBackWithItsTabsInOrder() throws {
        try DataFixtures.withTemporaryDirectory { profile in
            let trip = "1b4e28ba-2fa1-11d2-883f-0016d3cca427"
            let hidden = "2c5f39cb-3fb2-22e3-994f-1127e4ddb538"
            let maps = "a0000000-0000-4000-8000-000000000001"
            let hotels = "a0000000-0000-4000-8000-000000000002"
            let entries: [F.Entry] = [
                (F.internalKey("bookmarks-dt-something", 1), Self.string(1, "not a group")),
                (F.internalKey(Self.data(trip), 2), Self.group(trip, title: "Weekend trip", color: 5, pinned: 0, created: 100)),
                (F.internalKey(Self.data(hidden), 3), Self.group(hidden, title: "Old copy", color: 2, created: 90, hidden: true)),
                (F.internalKey(Self.data(maps), 4),
                 Self.tab(maps, group: trip, position: 1, url: "https://maps.example/", title: "Maps")),
                (F.internalKey(Self.data("b0000000-0000-4000-8000-000000000003"), 5),
                 Self.tab("b0000000-0000-4000-8000-000000000003", group: hidden, position: 0, url: "https://old.example/", title: "Old")),
                (F.internalKey(Self.data("c0000000-0000-4000-8000-000000000004"), 6),
                 Self.tab("c0000000-0000-4000-8000-000000000004", group: "nobody", position: 0, url: "https://orphan.example/", title: "Orphan")),
                (F.internalKey(Self.data("ffffffff-0000-4000-8000-000000000005"), 7), [0xff]),
                (F.internalKey("saved_tab_group-md-\(trip)", 8), [0x0a, 0x7f]),
                (F.internalKey("saved_tab_group-GlobalMetadata", 9), [0x12, 0x00]),
            ]
            let table = F.table([F.TableBlock(entries: Array(entries[0..<4])), F.TableBlock(entries: Array(entries[4...]), compressed: true)])
            let log = F.log([
                F.batch(sequence: 10, [(Self.data(hotels), Self.tab(hotels, group: trip, position: 0, url: "https://hotels.example/", title: "Hotels"))]),
                F.batch(sequence: 11, [(Self.data(maps), Self.tab(maps, group: trip, position: 1, url: "https://maps.example/route", title: "Maps route"))]),
            ])
            try F.write(to: store(in: profile), edits: [F.edit(logNumber: 4, added: [(0, 3)])], tables: [3: table], logs: [4: log])

            let groups = try ChromiumSavedTabGroups.read(profileDirectory: profile)

            #expect(groups == [
                ChromiumSavedTabGroup(guid: trip, title: "Weekend trip", color: 5, position: 0, tabs: [
                    .init(url: "https://hotels.example/", title: "Hotels", position: 0),
                    .init(url: "https://maps.example/route", title: "Maps route", position: 1),
                ]),
            ])
        }
    }

    @Test func pinnedGroupsComeFirstThenNewestAndDeletedGroupsStayGone() throws {
        try DataFixtures.withTemporaryDirectory { profile in
            let guids = ["10000000-0000-4000-8000-000000000000", "20000000-0000-4000-8000-000000000000",
                         "30000000-0000-4000-8000-000000000000", "40000000-0000-4000-8000-000000000000"]
            let created: [Int64] = [100, 300, 200, 400]
            var operations: [(key: String, value: [UInt8]?)] = []
            for (index, guid) in guids.enumerated() {
                operations.append((Self.data(guid), Self.group(guid, title: "Group \(index)", color: Int64(index + 1),
                                                               pinned: index == 0 ? 3 : nil, created: created[index])))
                let tabGUID = "e000000\(index)-0000-4000-8000-000000000000"
                operations.append((Self.data(tabGUID), Self.tab(tabGUID, group: guid, position: 0, url: "https://\(index).example/", title: "Tab \(index)")))
            }
            let log = F.log([F.batch(sequence: 1, operations), F.batch(sequence: 100, [(Self.data(guids[3]), nil)])])
            try F.write(to: store(in: profile), edits: [F.edit(logNumber: 5)], logs: [5: log])

            let groups = try ChromiumSavedTabGroups.read(profileDirectory: profile)

            #expect(groups.map(\.guid) == [guids[0], guids[1], guids[2]])
            #expect(groups.map(\.position) == [0, 1, 2])
            #expect(groups.map(\.color) == [1, 2, 3])
            #expect(groups.map(\.title) == ["Group 0", "Group 1", "Group 2"])
            #expect(groups.map { $0.tabs.map(\.url) } == [["https://0.example/"], ["https://1.example/"], ["https://2.example/"]])
        }
    }

    @Test func aProfileWithoutSyncDataHasNoSavedGroups() throws {
        try DataFixtures.withTemporaryDirectory { profile in
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            #expect(try ChromiumSavedTabGroups.read(profileDirectory: profile).isEmpty)
        }
    }
}
