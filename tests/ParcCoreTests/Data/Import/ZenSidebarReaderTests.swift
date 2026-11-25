import Foundation
import Testing
@testable import ParcCore

enum ZenSidebarFixture {
    typealias Item = SidebarImport.Item

    static let personal = "{aaaaaaaa-0000-4000-8000-000000000001}"
    static let work = "{bbbbbbbb-0000-4000-8000-000000000002}"
    static let profileFolder = "x1y2z3.Default (release)"
    static let key = SidebarImport.profileKey(directory: profileFolder)
    static let workKey = SidebarImport.ProfileKey.extra("zen:\(profileFolder):2")
    static let clientsKey = SidebarImport.ProfileKey.extra("zen:\(profileFolder):5")
    static let importedAt = Date(timeIntervalSince1970: 1_793_000_000)

    static let session = #"""
        {
          "lastCollected": 1764000000000,
          "spaces": [
            { "uuid": "{aaaaaaaa-0000-4000-8000-000000000001}", "name": "Personal", "icon": "🏠",
              "containerTabId": 0, "hasCollapsedPinnedTabs": false,
              "theme": { "type": "gradient", "gradientColors": [], "opacity": 0.5, "texture": 0 } },
            { "uuid": "{bbbbbbbb-0000-4000-8000-000000000002}", "name": "Work", "icon": "",
              "containerTabId": 2, "hasCollapsedPinnedTabs": true,
              "theme": { "type": "gradient", "opacity": 0.5, "texture": 0.5, "gradientColors": [
                { "c": [0, 0, 255], "isPrimary": false, "isCustom": false },
                { "c": [255, 128, 0], "isPrimary": true, "isCustom": false } ] } }
          ],
          "tabs": [
            { "zenSyncId": "1-e1", "zenEssential": true, "pinned": true, "userContextId": 0,
              "zenWorkspace": null, "groupId": null, "zenIsEmpty": false, "zenIsGlance": false,
              "entries": [{ "url": "https://github.com/", "title": "GitHub" }], "index": 1,
              "_zenPinnedInitialState": { "entry": { "url": "https://github.com/", "title": "GitHub" } } },
            { "zenSyncId": "1-e2", "zenEssential": true, "pinned": true, "userContextId": 2,
              "zenWorkspace": "{bbbbbbbb-0000-4000-8000-000000000002}", "zenIsEmpty": false, "zenIsGlance": false,
              "entries": [{ "url": "https://mail.example.com/", "title": "Mail" }], "index": 1 },
            { "zenSyncId": "1-e3", "zenEssential": true, "pinned": true, "userContextId": 5, "zenWorkspace": null,
              "entries": [{ "url": "https://calendar.example.com/", "title": "Calendar" }], "index": 1 },

            { "zenSyncId": "1-p1", "pinned": true, "zenEssential": false, "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}", "zenStaticLabel": "Inbox",
              "zenIsEmpty": false, "zenIsGlance": false,
              "entries": [{ "url": "https://news.example.com/item/42", "title": "Item 42" }], "index": 1,
              "_zenPinnedInitialState": { "entry": { "url": "https://news.example.com/", "title": "News" } } },
            { "zenSyncId": "1-f1e", "pinned": true, "zenIsEmpty": true, "groupId": "100-1", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}", "entries": [{ "url": "about:blank" }], "index": 1 },
            { "zenSyncId": "1-f1t1", "pinned": true, "groupId": "100-1", "userContextId": 0, "zenIsEmpty": false,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://blog.example.com/", "title": "Blog" }], "index": 1 },
            { "zenSyncId": "1-s1", "pinned": true, "groupId": "500-split", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://left.example/", "title": "Left" }], "index": 1 },
            { "zenSyncId": "1-s2", "pinned": true, "groupId": "500-split", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://right.example/", "title": "Right" }], "index": 1 },
            { "zenSyncId": "1-f2e", "pinned": true, "zenIsEmpty": true, "groupId": "200-2", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}", "entries": [{ "url": "about:blank" }], "index": 1 },
            { "zenSyncId": "1-f2t1", "pinned": true, "groupId": "200-2", "userContextId": 0, "zenIsEmpty": false,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://arxiv.org/abs/1", "title": "Paper" }], "index": 1 },
            { "zenSyncId": "1-f4e", "pinned": true, "zenIsEmpty": true, "groupId": "400-live", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}", "entries": [{ "url": "about:blank" }], "index": 1 },
            { "zenSyncId": "1-l1", "pinned": true, "groupId": "400-live", "userContextId": 0, "zenLiveFolderItemId": "item-1",
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://feed.example/1", "title": "Feed item" }], "index": 1 },

            { "zenSyncId": "1-p2", "pinned": true, "zenEssential": false, "userContextId": 2,
              "zenWorkspace": "{bbbbbbbb-0000-4000-8000-000000000002}", "zenIsEmpty": false,
              "entries": [{ "url": "https://jira.example.com/", "title": "Jira" }], "index": 1 },

            { "zenSyncId": "1-u1", "pinned": false, "groupId": "300-split", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://a.example/", "title": "A" }], "index": 1 },
            { "zenSyncId": "1-u2", "pinned": false, "groupId": "300-split", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://b.example/", "title": "B" }], "index": 1 },
            { "zenSyncId": "1-u5", "pinned": false, "groupId": "300-split", "userContextId": 0,
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://c.example/", "title": "C" }], "index": 1 },
            { "zenSyncId": "1-u3", "pinned": false, "userContextId": 0, "zenGlanceId": "g1",
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://d.example/", "title": "D" }, { "url": "https://d.example/2", "title": "D2" }], "index": 2 },
            { "zenSyncId": "1-g3", "pinned": false, "userContextId": 0, "zenIsGlance": true, "zenGlanceId": "g1",
              "zenWorkspace": "{aaaaaaaa-0000-4000-8000-000000000001}",
              "entries": [{ "url": "https://preview.example/", "title": "Preview" }], "index": 1 },
            { "zenSyncId": "1-u4", "pinned": false, "userContextId": 2, "zenDefaultUserContextId": "true",
              "zenWorkspace": "{bbbbbbbb-0000-4000-8000-000000000002}",
              "entries": [{ "url": "https://wiki.example.com/", "title": "Wiki" }], "index": 1 },
            { "zenSyncId": "1-u6", "pinned": false, "userContextId": 2,
              "zenWorkspace": "{bbbbbbbb-0000-4000-8000-000000000002}",
              "entries": [{ "url": "about:preferences", "title": "Settings" }], "index": 1 }
          ],
          "folders": [
            { "id": "100-1", "name": "Reading", "collapsed": false, "parentId": null, "pinned": true,
              "essential": false, "splitViewGroup": false, "isLiveFolder": false, "saveOnWindowClose": false,
              "prevSiblingInfo": { "type": "tab", "id": "1-p1" }, "emptyTabIds": ["1-f1e", "1-f2e"],
              "workspaceId": "{aaaaaaaa-0000-4000-8000-000000000001}" },
            { "id": "500-split", "name": "", "collapsed": false, "parentId": "100-1", "pinned": true,
              "essential": false, "splitViewGroup": true, "isLiveFolder": false,
              "prevSiblingInfo": { "type": "tab", "id": "1-f1t1" }, "emptyTabIds": [],
              "workspaceId": "{aaaaaaaa-0000-4000-8000-000000000001}" },
            { "id": "200-2", "name": "Papers", "collapsed": true, "parentId": "100-1", "pinned": true,
              "essential": false, "splitViewGroup": false, "isLiveFolder": false, "saveOnWindowClose": false,
              "prevSiblingInfo": { "type": "group", "id": "500-split" }, "emptyTabIds": ["1-f2e"],
              "userIcon": "chrome://browser/skin/zen-icons/selectable/book.svg",
              "workspaceId": "{aaaaaaaa-0000-4000-8000-000000000001}" },
            { "id": "400-live", "name": "Feed", "collapsed": false, "parentId": null, "pinned": true,
              "essential": false, "splitViewGroup": false, "isLiveFolder": true,
              "prevSiblingInfo": { "type": "group", "id": "100-1" }, "emptyTabIds": ["1-f4e"],
              "workspaceId": "{aaaaaaaa-0000-4000-8000-000000000001}" },
            { "id": "600-6", "name": "Later", "collapsed": false, "parentId": null, "pinned": true,
              "essential": false, "splitViewGroup": false, "isLiveFolder": false,
              "prevSiblingInfo": { "type": "group", "id": "100-1" }, "emptyTabIds": [],
              "workspaceId": "{aaaaaaaa-0000-4000-8000-000000000001}" }
          ],
          "splitViewData": [
            { "groupId": "300-split", "gridType": "grid", "tabs": ["1-u1", "1-u2", "1-u5"],
              "layoutTree": { "type": "splitter", "direction": "row", "children": [
                { "type": "splitter", "direction": "column", "sizeInParent": 60, "children": [
                  { "type": "leaf", "tabId": "1-u1", "sizeInParent": 50 },
                  { "type": "leaf", "tabId": "1-u2", "sizeInParent": 50 } ] },
                { "type": "leaf", "tabId": "1-u5", "sizeInParent": 40 } ] } },
            { "groupId": "500-split", "gridType": "vsep", "tabs": ["1-s1", "1-s2"],
              "layoutTree": { "type": "splitter", "direction": "row", "children": [
                { "type": "leaf", "tabId": "1-s1", "sizeInParent": 30 },
                { "type": "leaf", "tabId": "1-s2", "sizeInParent": 70 } ] } }
          ],
          "groups": [
            { "id": "100-1", "name": "Reading", "pinned": true, "essential": false, "splitView": false, "collapsed": false },
            { "id": "200-2", "name": "Papers", "pinned": true, "essential": false, "splitView": false, "collapsed": true },
            { "id": "300-split", "name": "", "pinned": false, "essential": false, "splitView": true, "collapsed": false }
          ]
        }
        """#

    static let routing = #"""
        { "routes": [
            { "id": "r1", "reference": "jira.example.com", "openIn": "{bbbbbbbb-0000-4000-8000-000000000002}", "matchType": "contains" },
            { "id": "r2", "reference": "^https://(docs|sheets)\\.example\\.com/", "openIn": "{bbbbbbbb-0000-4000-8000-000000000002}", "matchType": "regex" },
            { "id": "r3", "reference": "news.example.com", "openIn": "most-recent-space", "matchType": "equal-to" },
            { "id": "r4", "reference": "gone.example.com", "openIn": "{cccccccc-0000-4000-8000-000000000003}", "matchType": "contains" } ],
          "defaultRouteExternal": "little-window" }
        """#

    static let containers = #"""
        { "version": 8, "lastUserContextId": 6,
          "identities": [
            { "userContextId": 2, "public": true, "icon": "briefcase", "color": "orange" },
            { "userContextId": 5, "public": true, "icon": "circle", "color": "red", "name": "Clients" },
            { "userContextId": 6, "public": false, "icon": "", "color": "", "name": "userContextIdInternal.thumbnail", "accessKey": "" } ],
          "siteAssociations": { "calendar.example.com": 5 } }
        """#

    static func minimalSession(title: String, uuid: String = "{dddddddd-0000-4000-8000-000000000004}",
                               container: Int = 0) -> String {
        """
        { "spaces": [ { "uuid": "\(uuid)", "name": "\(title)", "icon": "", "containerTabId": \(container) } ],
          "tabs": [ { "zenSyncId": "m-1", "pinned": true, "zenWorkspace": "\(uuid)",
                      "entries": [ { "url": "https://\(title.lowercased()).example/", "title": "\(title)" } ], "index": 1 } ],
          "folders": [], "splitViewData": [], "groups": [] }
        """
    }

    static func writeMozLz4(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MozLz4.encode(Data(json.utf8)).write(to: url)
    }

    static func makeProfile(in root: URL, folder name: String = profileFolder, session: String? = session,
                            routing: String? = routing, prefs: String? = nil) throws -> SidebarImportProfile {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let session { try writeMozLz4(session, to: directory.appendingPathComponent("zen-sessions.jsonlz4")) }
        if let routing { try writeMozLz4(routing, to: directory.appendingPathComponent("zen-space-routing.jsonlz4")) }
        try Data(containers.utf8).write(to: directory.appendingPathComponent("containers.json"))
        if let prefs { try Data(prefs.utf8).write(to: directory.appendingPathComponent("prefs.js")) }
        return SidebarImportProfile(key: SidebarImport.profileKey(directory: name), directory: directory, name: "Zen")
    }

    static func withRead(prefs: String? = nil, _ body: (SidebarImport) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try makeProfile(in: root, prefs: prefs)
            try body(ZenSidebarReader.read(profiles: [profile]))
        }
    }

    static func rounded(_ items: [Item]) -> [Item] {
        items.map { item in
            switch item {
            case let .split(title, icon, tabs, orientation, factors):
                return .split(title: title, icon: icon, tabs: tabs, orientation: orientation,
                              widthFactors: factors.map { ($0 * 1e6).rounded() / 1e6 })
            case let .folder(title, icon, children, isExpanded):
                return .folder(title: title, icon: icon, children: rounded(children), isExpanded: isExpanded)
            case .tab, .stackedSplit: return item
            }
        }
    }

    static func close(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    static func urls(_ items: [Item]) -> [String] {
        items.flatMap { item -> [String] in
            switch item {
            case .tab(let tab): return [tab.url]
            case .folder(_, _, let children, _): return urls(children)
            case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs.map(\.url)
            }
        }
    }
}

struct ZenSidebarReaderTests {
    private typealias Fixture = ZenSidebarFixture
    private typealias Tab = SidebarImport.Tab

    @Test func spacesKeepZensOrderTitleEmojiAndId() throws {
        try Fixture.withRead { zen in
            #expect(zen.spaces.map(\.title) == ["Personal", "Work"])
            #expect(zen.spaces.map(\.icon) == [.emoji("🏠"), nil])
            #expect(zen.spaces.map(\.id) == ["zen:\(Fixture.personal)", "zen:\(Fixture.work)"])
            #expect(zen.spaces.map(\.pinnedCollapsed) == [false, true])
            #expect(zen.spaces.allSatisfy { $0.placement == .new })
        }
    }

    @Test func aSpaceInAContainerGetsTheContainersProfile() throws {
        try Fixture.withRead { zen in
            #expect(zen.spaces.map(\.profile) == [Fixture.key, Fixture.workKey])
            #expect(zen.extraProfiles == [SidebarImport.ExtraProfile(key: Fixture.workKey, name: "Work"),
                                          SidebarImport.ExtraProfile(key: Fixture.clientsKey, name: "Clients")])
            #expect(zen.profiles == [Fixture.key, Fixture.workKey, Fixture.clientsKey])
        }
    }

    @Test func theSpaceThemeTakesThePrimaryGradientColor() throws {
        try Fixture.withRead { zen in
            #expect(zen.spaces[0].theme == nil)
            let color = try #require(ThemeColor(red: 1, green: 128.0 / 255, blue: 0))
            #expect(zen.spaces[1].theme == SpaceTheme(primaryColor: color, colorCount: 2, noise: 0.5))
        }
    }

    @Test func thePinnedTreeKeepsZensNestingOrderRenamesAndSplit() throws {
        try Fixture.withRead { zen in
            let expected: [SidebarImport.Item] = [
                .tab(Tab(title: "News", url: "https://news.example.com/", customTitle: "Inbox")),
                .folder(title: "Reading", icon: nil, children: [
                    .tab(Tab(title: "Blog", url: "https://blog.example.com/")),
                    .split(title: nil, icon: nil, tabs: [Tab(title: "Left", url: "https://left.example/"),
                           Tab(title: "Right", url: "https://right.example/")], orientation: .horizontal, widthFactors: [0.3, 0.7]),
                    .folder(title: "Papers", icon: nil, children: [.tab(Tab(title: "Paper", url: "https://arxiv.org/abs/1"))],
                            isExpanded: false),
                ], isExpanded: true),
                .folder(title: "Later", icon: nil, children: [], isExpanded: true),
            ]
            #expect(Fixture.rounded(zen.spaces[0].pinned) == expected)
            #expect(zen.spaces[1].pinned == [.tab(Tab(title: "Jira", url: "https://jira.example.com/"))])
        }
    }

    @Test func todayHoldsTheStackedSplitAndTheCurrentPageOfEachTab() throws {
        try Fixture.withRead { zen in
            let today = zen.spaces[0].today
            #expect(today.count == 2)
            guard case let .stackedSplit(title, icon, tabs, orientation, stacks) = today.first else {
                Issue.record("Today starts with a stacked split")
                return
            }
            #expect(title == nil && icon == nil && orientation == .horizontal)
            #expect(tabs.map(\.url) == ["https://a.example/", "https://b.example/", "https://c.example/"])
            #expect(stacks.slotSizes == [2, 1])
            #expect(Fixture.close(stacks.slotFactors, [0.6, 0.4]))
            #expect(stacks.stackFactors.count == 2 && Fixture.close(stacks.stackFactors[0], [0.5, 0.5]))
            #expect(Fixture.close(stacks.flattenedFactors, [0.3, 0.3, 0.4]))
            #expect(today.last == .tab(Tab(title: "D2", url: "https://d.example/2")))
            #expect(zen.spaces[1].today == [.tab(Tab(title: "Wiki", url: "https://wiki.example.com/"))])
        }
    }

    @Test func essentialsBecomeFavoritesOfTheirContainersProfile() throws {
        try Fixture.withRead { zen in
            #expect(zen.favorites[Fixture.key] == [.tab(Tab(title: "GitHub", url: "https://github.com/"))])
            #expect(zen.favorites[Fixture.workKey] == [.tab(Tab(title: "Mail", url: "https://mail.example.com/"))])
            #expect(zen.favorites[Fixture.clientsKey] == [.tab(Tab(title: "Calendar", url: "https://calendar.example.com/"))])
        }
    }

    @Test func sharedEssentialsAllGoToTheZenProfile() throws {
        try Fixture.withRead(prefs: #"user_pref("zen.workspaces.separate-essentials", false);"#) { zen in
            #expect(zen.favorites.count == 1)
            #expect(Fixture.urls(zen.favorites[Fixture.key] ?? [])
                    == ["https://github.com/", "https://mail.example.com/", "https://calendar.example.com/"])
            #expect(zen.extraProfiles == [SidebarImport.ExtraProfile(key: Fixture.workKey, name: "Work")])
        }
    }

    @Test func routesComeOverExceptRegexAndUnknownSpaces() throws {
        try Fixture.withRead { zen in
            #expect(zen.routes == [
                SidebarImport.Route(conditions: [.init(style: .contains, pattern: "jira.example.com")],
                                    destination: .space("zen:\(Fixture.work)")),
                SidebarImport.Route(conditions: [.init(style: .matches, pattern: "news.example.com")], destination: .mostRecent),
            ])
            #expect(zen.warnings.count == 1)
            #expect(zen.warnings.first?.contains("regular expression") == true)
        }
    }

    @Test func glancesLiveFolderItemsEmptyLiveFoldersAndNonWebTabsAreSkipped() throws {
        try Fixture.withRead { zen in
            #expect(zen.skippedItemCount == 4)
            let all = zen.spaces.flatMap { Fixture.urls($0.pinned) + Fixture.urls($0.today) }
            #expect(!all.contains("https://preview.example/") && !all.contains("https://feed.example/1")
                    && !all.contains("about:blank") && !all.contains("about:preferences"))
            #expect(!zen.spaces[0].pinned.contains { item in
                if case .folder(let title, _, _, _) = item { return title == "Feed" }
                return false
            })
        }
    }
}
