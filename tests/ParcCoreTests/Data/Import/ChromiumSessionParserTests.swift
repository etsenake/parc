import Foundation
import Testing
@testable import ParcCore

struct ChromiumSessionParserTests {
    private typealias Fixture = ChromiumSessionFixture

    private func parse(_ commands: [[UInt8]], flavor: ChromiumFlavor = .chrome) throws -> ChromiumSession {
        try #require(ChromiumSessionParser.session(Fixture.file(commands), flavor: flavor))
    }

    @Test func theNormalWindowKeepsItsTabsInStripOrderAndThePopupIsGone() throws {
        let session = try parse(Fixture.standard())
        #expect(session.windows.map(\.id) == [1])
        #expect(session.windows[0].tabs.map(\.id) == [10, 11, 12, 13, 14, 15])
        #expect(session.windows[0].tabs.map(\.url) == ["https://pinned.example/", "https://a.example/", "https://b.example/",
                                                       "https://left.example/", "https://right.example/", "https://plain.example/"])
        #expect(session.windows[0].tabs.map(\.title) == ["Pinned", "Group A", "Group B", "Split Left", "Split Right", "Plain"])
        #expect(session.windows[0].selectedIndex == 3)
    }

    @Test func pinnedGroupAndSplitMembershipComeThrough() throws {
        let session = try parse(Fixture.standard())
        let tabs = session.windows[0].tabs
        #expect(tabs.map(\.pinned) == [true, false, false, false, false, false])
        #expect(tabs.map(\.group) == [nil, Fixture.group, Fixture.group, nil, nil, nil])
        #expect(tabs.map(\.split) == [nil, nil, nil, Fixture.split, Fixture.split, nil])
        #expect(session.groups == [Fixture.group: ChromiumSession.Group(title: "Work", color: 1, collapsed: false)])
        #expect(session.splits == [Fixture.split: ChromiumSession.Split(ratio: 0.6, sideBySide: true)])
    }

    @Test func aTabClosedAfterTheMarkerIsGone() throws {
        let session = try parse(Fixture.standard())
        #expect(!session.windows.flatMap(\.tabs).contains { $0.id == 16 || $0.url.contains("closed") })
    }

    @Test func aClosedWindowDisappearsWithItsTabs() throws {
        let session = try parse(Fixture.standard() + Fixture.tabCommands(window: 3, tab: 30, visual: 0, url: "https://gone.example/",
                                                                         title: "Gone") + [Fixture.windowType(3, 0), Fixture.closed(17, 3)])
        #expect(session.windows.map(\.id) == [1])
    }

    @Test func collapsedSavedGroupMetadataAndStackedSplitLayoutAreRead() throws {
        let commands = Fixture.standard() + [Fixture.groupMetadata(Fixture.group, title: "Later", color: 4, collapsed: true,
                                                                   savedGUID: "0a1b2c3d-0000-4000-8000-000000000001"),
                                             Fixture.splitData(Fixture.split, ratio: 0.25, layout: "Horizontal")]
        let session = try parse(commands)
        #expect(session.groups[Fixture.group] == ChromiumSession.Group(title: "Later", color: 4, collapsed: true,
                                                                       savedGUID: "0a1b2c3d-0000-4000-8000-000000000001"))
        #expect(session.splits[Fixture.split] == ChromiumSession.Split(ratio: 0.25, sideBySide: false))
    }

    @Test func metadataCutAfterTheColourMeansExpanded() throws {
        let pickle = Fixture.Pickle().token(Fixture.group).string16("Old").uint32(2)
        let session = try parse(Fixture.standard() + [Fixture.command(27, pickle.bytes)])
        #expect(session.groups[Fixture.group] == ChromiumSession.Group(title: "Old", color: 2, collapsed: false))
    }

    @Test func aGroupWithoutMetadataStillExistsAndUnreferencedMetadataIsDropped() throws {
        let other = ChromiumToken(high: 7, low: 8), loose = ChromiumToken(high: 9, low: 9)
        let commands = Fixture.standard() + [Fixture.tokenAssignment(25, tab: 15, other),
                                             Fixture.groupMetadata(loose, title: "Orphan", color: 0, collapsed: false)]
        let session = try parse(commands)
        #expect(session.groups[other] == ChromiumSession.Group(title: "", color: 0, collapsed: false))
        #expect(session.groups[loose] == nil)
    }

    @Test func theWindowTitleAndExtraDataArePickedUp() throws {
        let commands = Fixture.standard() + [Fixture.windowTitle(1, "Research"),
                                             Fixture.extraData(33, id: 15, key: "helium.pinned_tab_id", value: "pin-1"),
                                             Fixture.extraData(34, id: 1, key: "vertical_tab_strip_collapsed", value: "true")]
        let session = try parse(commands)
        #expect(session.windows[0].userTitle == "Research")
        #expect(session.windows[0].tabs.last?.extraData == ["helium.pinned_tab_id": "pin-1"])
        #expect(session.windows[0].extraData == ["vertical_tab_strip_collapsed": "true"])
    }

    @Test func theCurrentEntryFollowsTheSelectedIndexAcrossAPrune() throws {
        let commands = Fixture.standard() + [
            Fixture.navigation(tab: 15, index: 1, url: "https://plain.example/one", title: "One"),
            Fixture.navigation(tab: 15, index: 2, url: "https://plain.example/two", title: "Two"),
            Fixture.navigation(tab: 15, index: 3, url: "https://plain.example/three", title: "Three"),
            Fixture.idIndex(7, 15, 3),
            Fixture.prune(tab: 15, index: 1, count: 2),
        ]
        let tab = try #require(try parse(commands).windows[0].tabs.last)
        #expect(tab.url == "https://plain.example/three" && tab.title == "Three")
    }

    @Test func pruningTheSelectedEntryFallsBackToTheEntryBeforeIt() throws {
        let commands = Fixture.standard() + [
            Fixture.navigation(tab: 15, index: 1, url: "https://plain.example/one", title: "One"),
            Fixture.navigation(tab: 15, index: 2, url: "https://plain.example/two", title: "Two"),
            Fixture.idIndex(7, 15, 2),
            Fixture.prune(tab: 15, index: 2, count: 1),
        ]
        let tab = try #require(try parse(commands).windows[0].tabs.last)
        #expect(tab.url == "https://plain.example/one")
    }

    @Test func aLaterNavigationForTheSameIndexReplacesTheEarlierOne() throws {
        let commands = Fixture.standard() + [Fixture.navigation(tab: 15, index: 0, url: "https://plain.example/new", title: "New")]
        #expect(try parse(commands).windows[0].tabs.last?.url == "https://plain.example/new")
    }

    @Test func aSelectedIndexPastTheLastEntryUsesTheLastEntry() throws {
        let commands = Fixture.standard() + [Fixture.navigation(tab: 15, index: 1, url: "https://plain.example/one", title: "One"),
                                             Fixture.idIndex(7, 15, 9)]
        #expect(try parse(commands).windows[0].tabs.last?.url == "https://plain.example/one")
    }

    @Test func aTruncatedTailKeepsEverythingBeforeIt() throws {
        var data = Fixture.file(Fixture.standard() + [Fixture.windowTitle(1, "Kept"), Fixture.idIndex(0, 1, 17),
                                                      Fixture.navigation(tab: 17, index: 0, url: "https://late.example/", title: "Late")])
        data.removeLast(3)
        let session = try #require(ChromiumSessionParser.session(data, flavor: .chrome))
        #expect(session.windows[0].userTitle == "Kept")
        #expect(session.windows[0].tabs.count == 6)
    }

    @Test func anUnknownCommandStopsTheReplayButKeepsWhatCameBefore() throws {
        let commands = Fixture.standard() + [Fixture.command(99, [1, 2, 3])] + [Fixture.windowTitle(1, "Never")]
        let session = try parse(commands)
        #expect(session.windows[0].tabs.count == 6 && session.windows[0].userTitle == nil)
    }

    @Test func aWrongSizedStructStopsTheReplay() throws {
        let commands = Fixture.standard() + [Fixture.command(12, [15, 0, 0, 0, 1])] + [Fixture.windowTitle(1, "Never")]
        let session = try parse(commands)
        #expect(session.windows[0].userTitle == nil && session.windows[0].tabs.last?.pinned == false)
    }

    @Test func aFileWithoutTheMarkerOrWithTheWrongHeaderIsNotASession() {
        let unmarked = Fixture.standard().filter { $0 != Fixture.marker }
        #expect(ChromiumSessionParser.session(Fixture.file(unmarked), flavor: .chrome) == nil)
        #expect(ChromiumSessionParser.session(Fixture.file(Fixture.standard(), version: 5), flavor: .chrome) == nil)
        #expect(ChromiumSessionParser.session(Data([0x53, 0x4E]), flavor: .chrome) == nil)
    }

    @Test func vivaldiShiftedIdsCarryGroupsSplitsExtraDataAndExtensionJSON() throws {
        let session = try parse(Fixture.standard(vivaldi: true) + [
            Fixture.vivaldiExtension(21, id: 15, json: #"{"workspaceId":1.0}"#),
            Fixture.vivaldiExtension(21, id: 15, json: #"{"workspaceId":2.0,"fixedTitle":"Mine"}"#),
            Fixture.vivaldiExtension(22, id: 1, json: #"{"groupTitles":{}}"#),
            Fixture.extraData(35, id: 14, key: "k", value: "v"),
            Fixture.command(200, [0, 1]),
        ], flavor: .vivaldi)
        let tabs = session.windows[0].tabs
        #expect(tabs.map(\.id) == [10, 11, 12, 13, 14, 15])
        #expect(tabs.map(\.group) == [nil, Fixture.group, Fixture.group, nil, nil, nil])
        #expect(session.groups[Fixture.group]?.title == "Work")
        #expect(session.splits[Fixture.split] == ChromiumSession.Split(ratio: 0.6, sideBySide: true))
        #expect(tabs[5].extraData == ["vivaldi.ext": #"{"workspaceId":2.0,"fixedTitle":"Mine"}"#])
        #expect(tabs[4].extraData == ["k": "v"])
        #expect(session.windows[0].extraData == ["vivaldi.ext": #"{"groupTitles":{}}"#])
    }

    @Test func operaWorkspaceRecordsSurviveBecauseItsMarkerIs252() throws {
        let data = try #require(Fixture.hex(Fixture.operaFixtureHex))
        let session = try #require(ChromiumSessionParser.session(data, flavor: .opera))
        #expect(session.windows.map(\.id) == [1])
        #expect(session.windows[0].extraData == ["workspaces_state": "2"])
        #expect(session.windows[0].tabs.map(\.url) == ["https://ws2.example/"])
        #expect(session.windows[0].tabs[0].title == "In workspace 2")
        #expect(session.windows[0].tabs[0].extraData == ["workspaces_state": "2"])
        #expect(ChromiumSessionParser.session(data, flavor: .operaGX)?.windows[0].tabs[0].extraData == ["workspaces_state": "2"])
    }

    @Test func operaSkipsItsOwnFlagCommandsAndIgnoresOtherTabDataKeys() throws {
        var commands = Fixture.standard().filter { $0 != Fixture.marker }
        commands.insert(Fixture.command(253, Fixture.i32(15) + [1, 0, 0, 0]), at: 8)
        commands.insert(Fixture.command(251, [4, 0, 0, 0, 9, 9, 9, 9]), at: 8)
        commands += [Fixture.operaData(255, id: 15, key: "tab_thumbnail", value: "blob"),
                     Fixture.operaData(255, id: 15, key: "workspaces_state", value: "0"),
                     Fixture.operaData(255, id: 15, key: "workspaces_state", value: "3"),
                     Fixture.operaData(254, id: 1, key: "workspaces_state", value: "3"),
                     Fixture.command(252, [])]
        let session = try #require(ChromiumSessionParser.session(Fixture.file(commands), flavor: .opera))
        #expect(session.windows[0].tabs.count == 6)
        #expect(session.windows[0].tabs.last?.extraData == ["workspaces_state": "3"])
        #expect(session.windows[0].extraData == ["workspaces_state": "3"])
    }

    @Test func anOperaFileReadAsStockChromeLosesTheWorkspace() throws {
        let data = try #require(Fixture.hex(Fixture.operaFixtureHex))
        #expect(ChromiumSessionParser.session(data, flavor: .chrome)?.windows.first?.tabs.first?.extraData.isEmpty != false)
    }

    @Test func aVivaldiFileReadAsStockChromeStopsAtTheFirstShiftedCommand() throws {
        let session = try parse(Fixture.standard(vivaldi: true), flavor: .chrome)
        #expect(session.groups.isEmpty && session.splits.isEmpty)
    }
}

enum ChromiumSessionFixture {
    static let group = ChromiumToken(high: 0x1111_1111_1111_1111, low: 0x2222_2222_2222_2222)
    static let split = ChromiumToken(high: 0x3333_3333_3333_3333, low: 0x4444_4444_4444_4444)
    static let timestamp: Int64 = 13_350_000_000_000_000
    static let marker = command(255, [])

    struct Pickle {
        var payload: [UInt8] = []

        var bytes: [UInt8] { ChromiumSessionFixture.le(UInt32(payload.count)) + payload }

        private func appending(_ data: [UInt8], aligned: Bool = false) -> Pickle {
            Pickle(payload: payload + data + (aligned ? Array(repeating: 0, count: (4 - data.count % 4) % 4) : []))
        }

        func int(_ value: Int32) -> Pickle { appending(le(UInt32(bitPattern: value))) }
        func uint32(_ value: UInt32) -> Pickle { appending(le(value)) }
        func int64(_ value: Int64) -> Pickle { appending(le(UInt64(bitPattern: value))) }
        func uint64(_ value: UInt64) -> Pickle { appending(le(value)) }
        func double(_ value: Double) -> Pickle { appending(le(value.bitPattern)) }
        func bool(_ value: Bool) -> Pickle { int(value ? 1 : 0) }
        func token(_ token: ChromiumToken) -> Pickle { uint64(token.high).uint64(token.low) }

        func string(_ value: String) -> Pickle {
            let data = Array(value.utf8)
            return appending(le(UInt32(data.count))).appending(data, aligned: true)
        }

        func string16(_ value: String) -> Pickle {
            let units = Array(value.utf16)
            return appending(le(UInt32(units.count))).appending(units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }, aligned: true)
        }

        private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { ChromiumSessionFixture.le(value) }
    }

    static func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    static func i32(_ values: Int32...) -> [UInt8] { values.flatMap { le(UInt32(bitPattern: $0)) } }

    static func command(_ id: UInt8, _ payload: [UInt8]) -> [UInt8] {
        le(UInt16(payload.count + 1)) + [id] + payload
    }

    static func file(_ commands: [[UInt8]], version: Int32 = 3) -> Data {
        Data(i32(0x5353_4E53, version) + commands.flatMap { $0 })
    }

    static func shifted(_ id: UInt8, vivaldi: Bool) -> UInt8 { vivaldi && id >= 21 && id < 255 ? id + 2 : id }

    static func idIndex(_ id: UInt8, _ first: Int32, _ second: Int32) -> [UInt8] { command(id, i32(first, second)) }

    static func windowType(_ window: Int32, _ type: Int32) -> [UInt8] { idIndex(9, window, type) }

    static func windowBounds(_ window: Int32) -> [UInt8] { command(14, i32(window, 0, 25, 1440, 875, 1)) }

    static func pinned(_ tab: Int32) -> [UInt8] { command(12, i32(tab) + [1, 0, 0, 0]) }

    static func lastActive(_ tab: Int32, vivaldi: Bool = false) -> [UInt8] {
        command(shifted(21, vivaldi: vivaldi), i32(tab, 0) + le(UInt64(bitPattern: timestamp)))
    }

    static func closed(_ id: UInt8, _ target: Int32) -> [UInt8] { command(id, i32(target, 0) + le(UInt64(0))) }

    static func prune(tab: Int32, index: Int32, count: Int32, vivaldi: Bool = false) -> [UInt8] {
        command(shifted(24, vivaldi: vivaldi), i32(tab, index, count))
    }

    static func tokenAssignment(_ id: UInt8, tab: Int32, _ token: ChromiumToken, vivaldi: Bool = false) -> [UInt8] {
        command(shifted(id, vivaldi: vivaldi), i32(tab, 0) + le(token.high) + le(token.low) + [1] + Array(repeating: 0, count: 7))
    }

    static func groupMetadata(_ token: ChromiumToken, title: String, color: UInt32, collapsed: Bool, savedGUID: String? = nil,
                              vivaldi: Bool = false) -> [UInt8] {
        var pickle = Pickle().token(token).string16(title).uint32(color).bool(collapsed).bool(savedGUID != nil)
        if let savedGUID { pickle = pickle.string(savedGUID) }
        return command(shifted(27, vivaldi: vivaldi), pickle.bytes)
    }

    static func splitData(_ token: ChromiumToken, ratio: Double, layout: String = "Vertical", vivaldi: Bool = false) -> [UInt8] {
        let pickle = Pickle().token(token).double(ratio).string(layout)
        return command(shifted(37, vivaldi: vivaldi), pickle.bytes)
    }

    static func windowTitle(_ window: Int32, _ title: String, vivaldi: Bool = false) -> [UInt8] {
        let pickle = Pickle().int(window).string(title)
        return command(shifted(31, vivaldi: vivaldi), pickle.bytes)
    }

    static func extraData(_ id: UInt8, id target: Int32, key: String, value: String) -> [UInt8] {
        let pickle = Pickle().int(target).string(key).string(value)
        return command(id, pickle.bytes)
    }

    static func vivaldiExtension(_ id: UInt8, id target: Int32, json: String) -> [UInt8] {
        let pickle = Pickle().int(target).string(json)
        return command(id, pickle.bytes)
    }

    static func navigationPickle(index: Int32, url: String, title: String) -> Pickle {
        Pickle().int(index).string(url).string16(title).string("")
            .int(1).int(0).string("").int(0).string("").bool(false)
            .int64(timestamp).string16("").int(200).int(0).int(0)
            .int64(-1).int64(-1).int64(-1).int(0)
    }

    static func navigation(tab: Int32, index: Int32, url: String, title: String) -> [UInt8] {
        let pickle = Pickle().int(tab)
        return command(6, (pickle.payload + navigationPickle(index: index, url: url, title: title).payload).pickled)
    }

    static func activeWindow(_ window: Int32) -> [UInt8] { command(20, i32(window)) }

    static func tabCommands(window: Int32, tab: Int32, visual: Int32, url: String, title: String, pin: Bool = false,
                            group: ChromiumToken? = nil, split: ChromiumToken? = nil, vivaldi: Bool = false) -> [[UInt8]] {
        var out = [idIndex(0, window, tab), lastActive(tab, vivaldi: vivaldi), navigation(tab: tab, index: 0, url: url, title: title),
                   idIndex(7, tab, 0), idIndex(2, tab, visual)]
        if pin { out.append(pinned(tab)) }
        if let group { out.append(tokenAssignment(25, tab: tab, group, vivaldi: vivaldi)) }
        if let split { out.append(tokenAssignment(36, tab: tab, split, vivaldi: vivaldi)) }
        return out
    }

    static func standard(vivaldi: Bool = false) -> [[UInt8]] {
        let window: Int32 = 1
        var out = [windowBounds(window), windowType(window, 0), idIndex(8, window, 3),
                   groupMetadata(group, title: "Work", color: 1, collapsed: false, vivaldi: vivaldi),
                   splitData(split, ratio: 0.6, vivaldi: vivaldi)]
        out += tabCommands(window: window, tab: 10, visual: 0, url: "https://pinned.example/", title: "Pinned", pin: true, vivaldi: vivaldi)
        out += tabCommands(window: window, tab: 11, visual: 1, url: "https://a.example/", title: "Group A", group: group, vivaldi: vivaldi)
        out += tabCommands(window: window, tab: 12, visual: 2, url: "https://b.example/", title: "Group B", group: group, vivaldi: vivaldi)
        out += tabCommands(window: window, tab: 13, visual: 3, url: "https://left.example/", title: "Split Left", split: split,
                           vivaldi: vivaldi)
        out += tabCommands(window: window, tab: 14, visual: 4, url: "https://right.example/", title: "Split Right", split: split,
                           vivaldi: vivaldi)
        out += tabCommands(window: window, tab: 15, visual: 5, url: "https://plain.example/", title: "Plain", vivaldi: vivaldi)
        let popup: Int32 = 2
        out += [windowType(popup, 1), idIndex(8, popup, 0)]
        out += tabCommands(window: popup, tab: 20, visual: 0, url: "https://popup.example/", title: "Popup", vivaldi: vivaldi)
        out += [activeWindow(window), marker]
        out += tabCommands(window: window, tab: 16, visual: 6, url: "https://closed.example/", title: "Closed", vivaldi: vivaldi)
        out += [closed(16, 16)]
        return out
    }

    static func restoreNavigation(index: Int32, url: String, title: String) -> [UInt8] {
        let pickle = Pickle().int(0)
        return command(1, (pickle.payload + navigationPickle(index: index, url: url, title: title).payload).pickled)
    }

    static func restoreTab(id: Int32, url: String, title: String, closedAt: Int64) -> [[UInt8]] {
        [command(4, i32(id, 0) + le(UInt64(bitPattern: closedAt))), restoreNavigation(index: 0, url: url, title: title)]
    }

    static func restoreWindow(id: Int32, tabs: Int32, closedAt: Int64, type: Int32 = 0) -> [UInt8] {
        let pickle = Pickle().int(id).int(0).int(tabs).int64(closedAt).int(0).int(0).int(800).int(600).int(1).string("").int(type)
        return command(9, pickle.bytes)
    }

    static func restoreGroup(session: Int32, tabs: Int32, closedAt: Int64) -> [UInt8] {
        let pickle = Pickle().token(group).int(session).int(tabs).int(1).string16("Gone group").uint32(3).bool(false).int64(closedAt)
        return command(13, pickle.bytes)
    }

    static func operaData(_ id: UInt8, id target: Int32, key: String, value: String) -> [UInt8] {
        extraData(id, id: target, key: key, value: value)
    }

    static let operaFixtureHex = """
        534e53530300000019000e010000000000000019000000a00500006b0300000100000009000901000000000000002500\
        fe200000000100000010000000776f726b7370616365735f737461746501000000320000000900080100000000000000\
        090000010000000a0000001100150a000000000000000060c017c16d2f00950006900000000a00000000000000140000\
        0068747470733a2f2f7773322e6578616d706c652f0e00000049006e00200077006f0072006b00730070006100630065\
        0020003200000000000100000000000000000000000000000000000000000000000060c017c16d2f0000000000c80000\
        000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff000000000900070a00000000000000\
        0900020a000000000000002500ff200000000a00000010000000776f726b7370616365735f7374617465010000003200\
        0000050014010000000100fc
        """

    static func hex(_ text: String) -> Data? {
        let digits = Array(text.utf8)
        guard digits.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(decoding: digits[index...index + 1], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    static func windowsMicroseconds(_ date: Date) -> Int64 {
        Int64(((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000).rounded())
    }
}

private extension Array where Element == UInt8 {
    var pickled: [UInt8] { ChromiumSessionFixture.le(UInt32(count)) + self }
}
