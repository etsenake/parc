import Foundation
import Testing
@testable import ParcCore

struct ArcSidebarExtrasTests {
    private typealias Support = ArcSidebarImportTestsSupport
    private typealias Tab = SidebarImport.Tab

    private static let clock = Date(timeIntervalSinceReferenceDate: 815_100_000)

    private static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    private static func work(_ items: [Any]) throws -> Data {
        try json(["sidebar": ["containers": [["global": [:]], [
            "spaces": ["S1", ["id": "S1", "title": "Work", "profile": ["default": true],
                              "containerIDs": ["pinned", "P1", "unpinned", "U1"]]],
            "items": items, "topAppsContainerIDs": []]]]])
    }

    private static func container(_ id: String, _ children: [String]) -> [Any] {
        [id, ["id": id, "childrenIds": children, "data": ["itemContainer": ["containerType": ["spaceItems": ["_0": "S1"]]]]]]
    }

    private static func tab(_ id: String, parent: String, url: String, title: String, extra: [String: Any] = [:]) -> [Any] {
        var item: [String: Any] = ["id": id, "parentID": parent, "childrenIds": [],
                                   "data": ["tab": ["savedURL": url, "savedTitle": title]]]
        item.merge(extra) { _, new in new }
        return [id, item]
    }

    private static func folder(_ id: String, title: String, parent: String, children: [String]) -> [Any] {
        [id, ["id": id, "title": title, "parentID": parent, "childrenIds": children, "data": ["list": [:]]]]
    }

    private static func group(_ id: String, title: String?, name: String, parent: String, children: [String]) -> [Any] {
        let item: [String: Any] = ["id": id, "title": title ?? NSNull(), "parentID": parent, "childrenIds": children,
                                   "data": ["tabGroup": ["title": name]]]
        return [id, item]
    }

    private static var groupItems: [Any] {
        let parts: [[Any]] = [
            container("P1", ["G2"]), container("U1", ["G1", "T3"]),
            group("G1", title: nil, name: "Shopping", parent: "U1", children: ["T1", "T2"]),
            tab("T1", parent: "G1", url: "https://shop.example.test/1", title: "One"),
            tab("T2", parent: "G1", url: "https://shop.example.test/2", title: "Two"),
            tab("T3", parent: "U1", url: "https://example.test/3", title: "Three"),
            group("G2", title: "Renamed group", name: "Reading", parent: "P1", children: ["T4"]),
            tab("T4", parent: "G2", url: "https://example.test/4", title: "Four")]
        return parts.flatMap { $0 }
    }

    private static var folderItems: [Any] {
        let parts: [[Any]] = [
            container("P1", ["F1", "F2", "U"]), container("U1", []),
            folder("F1", title: "Open one", parent: "P1", children: ["T1"]),
            folder("F2", title: "Closed one", parent: "P1", children: ["F3"]),
            folder("F3", title: "Nested open", parent: "F2", children: []),
            tab("T1", parent: "F1", url: "https://example.test/a", title: "A"),
            tab("U", parent: "P1", url: "https://example.test/u", title: "U", extra: ["isUnread": true])]
        return parts.flatMap { $0 }
    }

    private static var windows: [String: Any] {
        ["version": 1, "windows": [
            ["id": "W1", "focusedSpaceID": "S1", "expandedItems": ["F1"], "spacesWithCollapsedPinnedSections": []],
            ["id": "W2", "focusedSpaceID": "S1", "expandedItems": ["F3"],
             "spacesWithCollapsedPinnedSections": [["id": "S1", "peekedItemID": NSNull()]]]],
         "sidebarViewPreferences": ["sidebarWidth": 254, "sidebarMode": "anchored"]]
    }

    private static func archiveEntry(_ id: String, at seconds: Double, reason: String, source: [String: Any],
                                     url: String, title: String, extra: [String: Any] = [:]) -> [Any] {
        var item: [String: Any] = ["id": id, "childrenIds": [], "data": ["tab": ["savedURL": url, "savedTitle": title]]]
        item.merge(extra) { _, new in new }
        return [id, ["archivedAt": seconds, "reason": reason, "source": source, "sidebarItem": item]]
    }

    private static var archive: [String: Any] {
        let work: [String: Any] = ["space": ["_0": "S1"]]
        let renamed: [String: Any] = ["title": "Renamed", "data": ["tab": ["savedURL": "https://example.test/manual",
                                                                           "savedTitle": "Manual page", "savedMuteStatus": "mute"]]]
        let parts: [[Any]] = [
            archiveEntry("A1", at: 815_000_000, reason: "auto", source: work, url: "https://example.test/auto", title: "Auto page"),
            archiveEntry("A2", at: 815_000_100, reason: "manual", source: work, url: "https://example.test/manual",
                         title: "Manual page", extra: renamed),
            archiveEntry("A3", at: 815_000_200, reason: "clearButton", source: ["littleArc": [String: Any]()],
                         url: "https://example.test/little", title: "Little"),
            archiveEntry("A4", at: 815_000_300, reason: "clearTabGroup", source: ["space": ["_0": "GONE"]],
                         url: "arc://boosts", title: "Refused"),
            archiveEntry("A5", at: 100, reason: "auto", source: work, url: "https://example.test/old", title: "Too old")]
        return ["version": 1, "items": parts.flatMap { $0 }]
    }

    private static func urlMatch(_ style: String, _ text: String) -> [String: Any] {
        ["componentType": ["urlMatch": ["_0": [style: [:]], "_1": text]]]
    }

    private static var routing: [String: Any] {
        let toWork: [String: Any] = ["space": ["_0": ["space": ["_0": "S1"]]]]
        return ["rules": [
            ["id": "R1", "sourceComponents": [urlMatch("contains", " figma.com ")], "destination": toWork],
            ["id": "R2", "sourceComponents": [urlMatch("matches", "https://docs.example.test/team"), urlMatch("contains", "edit")],
             "destination": ["space": ["_0": ["mostRecent": [:]]]]],
            ["id": "R3", "sourceComponents": [urlMatch("contains", "youtube.com")],
             "destination": ["littleArc": ["_0": ["mostRecent": [:]]]]],
            ["id": "R4", "sourceComponents": [urlMatch("contains", "jira")],
             "destination": ["space": ["_0": ["space": ["_0": "NOT-IMPORTED"]]]]],
            ["id": "R5", "sourceComponents": [["componentType": ["somethingNew": ["_0": "x"]]]], "destination": toWork]],
            "defaultDestination": ["littleArc": ["_0": ["mostRecent": [:]]]]]
    }

    private static func expansion(_ items: [SidebarImport.Item]) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for item in items {
            guard case let .folder(title, _, children, isExpanded) = item else { continue }
            result[title] = isExpanded
            result.merge(expansion(children)) { current, _ in current }
        }
        return result
    }

    @Test func tidyTabsGroupsBecomeTodayTabsAndAPinnedFolder() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.groupItems))
        let space = try #require(arc.spaces.first)
        #expect(space.today == [.tab(Tab(title: "One", url: "https://shop.example.test/1")),
                                .tab(Tab(title: "Two", url: "https://shop.example.test/2")),
                                .tab(Tab(title: "Three", url: "https://example.test/3"))])
        #expect(space.pinned == [.folder(title: "Renamed group", icon: nil,
                                         children: [.tab(Tab(title: "Four", url: "https://example.test/4"))])])
        #expect(arc.skippedItemCount == 0)
    }

    @Test func foldersOpenOnlyWhereSomeArcWindowHadThemOpen() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.folderItems), windows: Self.json(Self.windows))
        #expect(Self.expansion(arc.spaces[0].pinned) == ["Open one": true, "Closed one": false, "Nested open": true])
    }

    @Test func withoutAWindowsFileEveryFolderStaysOpenAndPinnedStaysShown() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.folderItems))
        #expect(Self.expansion(arc.spaces[0].pinned) == ["Open one": true, "Closed one": true, "Nested open": true])
        #expect(arc.spaces[0].pinnedCollapsed == false)
    }

    @Test func aCollapsedPinnedSectionComesOverInEitherSpelling() throws {
        let objects = try SidebarImport(arcData: Self.work(Self.folderItems), windows: Self.json(Self.windows))
        let strings = try SidebarImport(arcData: Self.work(Self.folderItems), windows: Self.json(
            ["windows": [["id": "W1", "expandedItems": [], "spacesWithCollapsedPinnedSection": ["S1"]]]]))
        let topLevel = try SidebarImport(arcData: Self.work(Self.folderItems), windows: Self.json(
            ["windows": [], "spacesWithCollapsedPinnedSections": [["id": "S1"]]]))
        #expect(objects.spaces[0].pinnedCollapsed && strings.spaces[0].pinnedCollapsed && topLevel.spaces[0].pinnedCollapsed)
    }

    @Test func unreadPinnedTabsKeepTheirDot() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.folderItems))
        #expect(arc.spaces[0].pinned.last == SidebarImport.Item.tab(Tab(title: "U", url: "https://example.test/u", isUnread: true)))
    }

    @Test func anEmptyWindowsListLeavesEveryFolderOpen() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.folderItems), windows: Self.json(["version": 1, "windows": []]))
        #expect(Self.expansion(arc.spaces[0].pinned) == ["Open one": true, "Closed one": true, "Nested open": true])
    }

    @Test func archivedTabsWithoutAKnownSpaceAreSkippedAndCounted() throws {
        let entries: [[Any]] = [
            Self.archiveEntry("B1", at: 815_000_000, reason: "auto", source: ["space": ["_0": "S1"]],
                              url: "https://example.test/kept", title: "Kept"),
            Self.archiveEntry("B2", at: 815_000_100, reason: "auto", source: ["littleArc": [String: Any]()],
                              url: "https://example.test/little", title: "Little"),
            Self.archiveEntry("B3", at: 815_000_200, reason: "auto", source: ["standaloneSidebar": [String: Any]()],
                              url: "https://example.test/standalone", title: "Standalone"),
            Self.archiveEntry("B4", at: 815_000_300, reason: "auto", source: ["unknown": [String: Any]()],
                              url: "https://example.test/unknown", title: "Unknown"),
            Self.archiveEntry("B5", at: 815_000_400, reason: "auto", source: ["space": ["_0": "GONE"]],
                              url: "https://example.test/gone", title: "Gone")]
        let arc = try SidebarImport(arcData: Self.work(Self.container("P1", []) + Self.container("U1", [])),
                                    archive: Self.json(["version": 1, "items": entries.flatMap { $0 }]))
        #expect(arc.archive.map(\.tab.url) == ["https://example.test/kept"])
        #expect(arc.skippedItemCount == 4)
    }

    @Test func archivedTabsKeepTheirReasonSpaceTitleAndMute() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.container("P1", []) + Self.container("U1", [])),
                                    archive: Self.json(Self.archive))
        #expect(arc.archive == [
            SidebarImport.ArchivedTab(tab: Tab(title: "Auto page", url: "https://example.test/auto"),
                                      archivedAt: Date(timeIntervalSinceReferenceDate: 815_000_000),
                                      reason: .automatic, spaceID: "S1", profile: .standard),
            SidebarImport.ArchivedTab(tab: Tab(title: "Manual page", url: "https://example.test/manual", customTitle: "Renamed",
                                               isMuted: true),
                                      archivedAt: Date(timeIntervalSinceReferenceDate: 815_000_100),
                                      reason: .manual, spaceID: "S1", profile: .standard),
            SidebarImport.ArchivedTab(tab: Tab(title: "Too old", url: "https://example.test/old"),
                                      archivedAt: Date(timeIntervalSinceReferenceDate: 100),
                                      reason: .automatic, spaceID: "S1", profile: .standard)])
    }

    @Test func airTrafficControlRulesBecomeRoutesAndLittleArcWarnsOnce() throws {
        let arc = try SidebarImport(arcData: Self.work(Self.container("P1", []) + Self.container("U1", [])),
                                    routing: Self.json(Self.routing))
        #expect(arc.routes == [
            SidebarImport.Route(conditions: [.init(style: .contains, pattern: "figma.com")], destination: .space("S1")),
            SidebarImport.Route(conditions: [.init(style: .matches, pattern: "https://docs.example.test/team"),
                                             .init(style: .contains, pattern: "edit")], destination: .mostRecent)])
        #expect(arc.warnings.count == 1)
    }

    @Test func theMainSidebarWinsOverALittleArcContainerListedFirst() throws {
        let arc = try SidebarImport(arcData: Self.json(["sidebar": ["containers": [
            ["littleBrowser": ["_0": "LW"]],
            ["spaces": ["L", ["id": "L", "title": NSNull(), "profile": ["default": true], "containerIDs": ["unpinned", "LU"]]],
             "items": ["LU", ["id": "LU", "childrenIds": [], "data": ["itemContainer": [:]]]], "topAppsContainerIDs": []],
            ["global": [:]],
            ["spaces": ["S1", ["id": "S1", "title": "Work", "profile": ["default": true], "containerIDs": ["pinned", "P1"]]],
             "items": ["P1", ["id": "P1", "childrenIds": [], "data": ["itemContainer": [:]]]], "topAppsContainerIDs": []]]]]))
        #expect(arc.spaces.map(\.title) == ["Work"])
    }

    @Test func theSnapshotReadsArcsExtraFilesAndToleratesMissingOnes() throws {
        try DataFixtures.withTemporaryDirectory { home in
            let sidebar = ArcSidebarSnapshot.sidebarURL(home: home)
            try FileManager.default.createDirectory(at: sidebar.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.work(Self.folderItems).write(to: sidebar)
            let bare = try ArcSidebarSnapshot.read(home: home).0
            #expect(Self.expansion(bare.spaces[0].pinned).values.allSatisfy { $0 } && bare.archive.isEmpty && bare.routes.isEmpty)
            try Self.json(Self.windows).write(to: ArcSidebarSnapshot.windowsURL(home: home))
            try Self.json(Self.archive).write(to: ArcSidebarSnapshot.archiveURL(home: home))
            try Self.json(Self.routing).write(to: ArcSidebarSnapshot.routingURL(home: home))
            let full = try ArcSidebarSnapshot.read(home: home).0
            #expect(Self.expansion(full.spaces[0].pinned)["Closed one"] == false && full.spaces[0].pinnedCollapsed)
            #expect(full.archive.count == 3 && full.routes.count == 2)
        }
    }

    @MainActor @Test func aFreshStoreGetsTheArchiveFolderStatePinnedStateUnreadDotAndRoutes() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Self.clock })
            let standardID = store.state.profiles[0].id
            let arc = try SidebarImport(arcData: Self.work(Self.folderItems), windows: Self.json(Self.windows),
                                        archive: Self.json(Self.archive), routing: Self.json(Self.routing))
            _ = try store.importSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: standardID)
            let workID = try #require(store.state.arcImportedSpaces["S1"])
            let archived = store.state.tabs.filter { $0.archivedAt != nil }
            #expect(archived.map(\.savedURL) == ["https://example.test/auto", "https://example.test/manual"])
            #expect(archived.compactMap { $0.archiveProvenance?.reason } == [.automatic, .manual])
            #expect(archived.allSatisfy { $0.spaceID == workID && $0.archiveProvenance?.spaceID == workID })
            #expect(archived.last?.customTitle == "Renamed" && archived.last?.isMuted == true)
            let folders = store.state.folders.filter { $0.spaceID == workID }
            #expect(Dictionary(uniqueKeysWithValues: folders.map { ($0.name, $0.isExpanded) })
                    == ["Open one": true, "Closed one": false, "Nested open": true])
            #expect(store.state.spaces.first { $0.id == workID }?.pinnedCollapsed == true)
            #expect(store.state.tabs.first { $0.savedURL == "https://example.test/u" }?.isUnread == true)
            let rules = store.linkRouting.state.rules
            #expect(rules.map(\.destination) == [.space(workID), .mostRecent])
            #expect(rules.map { $0.conditions.map(\.pattern) } == [["figma.com"], ["https://docs.example.test/team", "edit"]])
            #expect(rules.map { $0.conditions.map(\.style) } == [[.contains], [.matches, .contains]])

            let tabCount = store.state.tabs.count
            _ = try store.importSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: standardID)
            #expect(store.state.tabs.count == tabCount && store.linkRouting.state.rules.count == 2)
        }
    }
}
