import Foundation
import Testing
@testable import ParcCore

enum FirefoxSidebarFixture {
    typealias Item = SidebarImport.Item
    typealias Tab = SidebarImport.Tab

    static let folder = "abcd1234.default-release"
    static let profileKey = SidebarImport.ProfileKey.custom(directory: folder)
    static let importedAt = Date(timeIntervalSince1970: 1_764_100_000)

    static let session = #"""
    {
      "version": ["sessionrestore", 1],
      "selectedWindow": 1,
      "maxSplitViewId": 1,
      "session": {"lastUpdate": 1764000000000, "startTime": 1763990000000, "recentCrashes": 0},
      "windows": [
        {
          "selected": 3,
          "zIndex": 1,
          "tabs": [
            {"pinned": true, "hidden": false, "lastAccessed": 1763999000000, "userContextId": 0,
             "index": 1, "entries": [{"url": "https://mail.example.com/", "title": "Mail"}]},
            {"hidden": false, "lastAccessed": 1763999100000, "userContextId": 0, "groupId": "1763990000000-1",
             "index": 2, "entries": [
               {"url": "https://docs.example.com/a", "title": "Doc A (old)"},
               {"url": "https://docs.example.com/b", "title": "Doc B"}]},
            {"hidden": false, "lastAccessed": 1763999200000, "userContextId": 0, "groupId": "1763990000000-1",
             "entries": [{"url": "https://docs.example.com/c", "title": "Doc C"}]},
            {"hidden": false, "lastAccessed": 1763999300000, "userContextId": 0, "splitViewId": 1,
             "index": 1, "entries": [{"url": "https://left.example.com/", "title": "Left"}]},
            {"hidden": false, "lastAccessed": 1763999300001, "userContextId": 0, "splitViewId": 1,
             "index": 1, "entries": [{"url": "https://right.example.com/", "title": "Right"}]},
            {"hidden": false, "lastAccessed": 1763999400000, "userContextId": 0,
             "index": 1, "entries": [{"url": "https://news.example.com/", "title": "News"}]}
          ],
          "groups": [
            {"id": "1763990000000-1", "name": "Research", "color": "blue", "collapsed": true, "saveOnWindowClose": true}
          ],
          "splitViews": [{"id": 1, "numberOfTabs": 2}],
          "_closedTabs": [
            {"closedId": 7, "closedAt": 1763999500000, "title": "Closed one", "pos": 6,
             "sourceWindowId": "window0",
             "state": {"lastAccessed": 1763999450000, "index": 1,
                       "entries": [{"url": "https://closed.example.com/", "title": "Closed one"}]}}
          ],
          "closedGroups": []
        },
        {
          "selected": 1,
          "zIndex": 2,
          "tabs": [
            {"hidden": false, "lastAccessed": 1763998000000, "userContextId": 0,
             "index": 1, "entries": [{"url": "https://shop.example.com/", "title": "Shop"}]},
            {"hidden": false, "lastAccessed": 1763998100000, "userContextId": 0,
             "index": 1, "entries": [{"url": "https://maps.example.com/", "title": "Maps"}]}
          ],
          "groups": [],
          "splitViews": [],
          "_closedTabs": [],
          "closedGroups": []
        }
      ],
      "_closedWindows": [],
      "savedGroups": [
        {"id": "1763980000000-9", "name": "Trip", "color": "green", "collapsed": false,
         "saved": true, "closedAt": 1763985000000, "sourceWindowId": "window0",
         "tabs": [
           {"closedId": 3, "closedAt": 1763985000000, "title": "Flights",
            "state": {"lastAccessed": 1763984000000, "index": 1,
                      "entries": [{"url": "https://flights.example.com/", "title": "Flights"}]}},
           {"closedId": 4, "closedAt": 1763985000000, "title": "Hotel",
            "state": {"lastAccessed": 1763984100000, "index": 1,
                      "entries": [{"url": "https://hotel.example.com/", "title": "Hotel"}]}}
         ],
         "splitViews": []}
      ]
    }
    """#

    static let prefs = #"""
    user_pref("browser.startup.homepage_override.mstone", "146.0");
    user_pref("browser.newtabpage.pinned", "[{\"url\":\"https://wiki.example.com/\",\"label\":\"Wiki\"},null,{\"url\":\"about:robots\",\"label\":\"Robots\"},{\"url\":\"https://calendar.example.com/\"}]");
    user_pref("browser.startup.page", 3);
    """#

    static func compressed(_ json: String) -> Data { MozLz4.encode(Data(json.utf8)) }

    static let encrypted = Data("mozEnc0\0".utf8) + Data((0..<64).map { UInt8($0) })

    static func tab(_ title: String, _ url: String) -> Tab { Tab(title: title, url: url) }

    static func withProfile<T>(_ files: [String: Data], _ body: (SidebarImportProfile) throws -> T) throws -> T {
        try DataFixtures.withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (path, data) in files {
                let file = directory.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file)
            }
            return try body(SidebarImportProfile(key: profileKey, directory: directory, name: "Personal"))
        }
    }

    static func read(_ files: [String: Data]) throws -> SidebarImport {
        try withProfile(files) { try FirefoxSidebarReader.read(profiles: [$0]) }
    }

    static func standard() throws -> SidebarImport {
        try read(["sessionstore.jsonlz4": compressed(session), "prefs.js": Data(prefs.utf8)])
    }

    static var firstPinned: [Item] { [
        .tab(tab("Mail", "https://mail.example.com/")),
        .folder(title: "Research", icon: nil, children: [
            .tab(tab("Doc B", "https://docs.example.com/b")),
            .tab(tab("Doc C", "https://docs.example.com/c")),
        ], isExpanded: false),
        .folder(title: "Trip", icon: nil, children: [
            .tab(tab("Flights", "https://flights.example.com/")),
            .tab(tab("Hotel", "https://hotel.example.com/")),
        ], isExpanded: false),
    ] }

    static var firstToday: [Item] { [
        .split(title: nil, icon: nil, tabs: [tab("Left", "https://left.example.com/"), tab("Right", "https://right.example.com/")],
               orientation: .horizontal, widthFactors: [0.5, 0.5]),
        .tab(tab("News", "https://news.example.com/")),
    ] }
}

struct FirefoxSidebarReaderTests {
    private typealias Fixture = FirefoxSidebarFixture

    @Test func everyWindowBecomesASpaceWithTheFirstOneHeadingHome() throws {
        let sidebar = try Fixture.standard()
        #expect(sidebar.spaces.count == 2)
        #expect(sidebar.spaces.map(\.placement) == [.profileHome, .new])
        #expect(sidebar.spaces.allSatisfy { $0.title == nil && $0.profile == Fixture.profileKey })
        let ids = sidebar.spaces.compactMap(\.id)
        #expect(ids.count == 2 && Set(ids).count == 2 && ids.allSatisfy { $0.hasPrefix("firefox:\(Fixture.folder):") })
    }

    @Test func pinnedTabsGroupsAndSavedGroupsFillPinnedInOrder() throws {
        let sidebar = try Fixture.standard()
        #expect(sidebar.spaces[0].pinned == Fixture.firstPinned)
        #expect(sidebar.spaces[1].pinned.isEmpty)
    }

    @Test func splitViewsAndLooseTabsFillToday() throws {
        let sidebar = try Fixture.standard()
        #expect(sidebar.spaces[0].today == Fixture.firstToday)
        #expect(sidebar.spaces[1].today == [.tab(Fixture.tab("Shop", "https://shop.example.com/")),
                                            .tab(Fixture.tab("Maps", "https://maps.example.com/"))])
    }

    @Test func closedTabsGoToTheArchiveOfTheirWindowsSpace() throws {
        let sidebar = try Fixture.standard()
        #expect(sidebar.archive == [SidebarImport.ArchivedTab(tab: Fixture.tab("Closed one", "https://closed.example.com/"),
            archivedAt: Date(timeIntervalSince1970: 1_763_999_500), reason: .manual, spaceID: sidebar.spaces[0].id,
            profile: Fixture.profileKey)])
    }

    @Test func newTabShortcutsBecomeFavoritesSkippingEmptySlots() throws {
        let sidebar = try Fixture.standard()
        let favorites = try #require(sidebar.favorites[Fixture.profileKey])
        #expect(favorites == [.tab(Fixture.tab("Wiki", "https://wiki.example.com/")),
                              .tab(Fixture.tab("calendar.example.com", "https://calendar.example.com/"))])
        #expect(sidebar.warnings.isEmpty && sidebar.skippedItemCount == 0)
    }

    @Test func favoritesStopAtTwelve() throws {
        let slots = (1...14).map { ["url": "https://site\($0).example.com/", "label": "Site \($0)"] }
        let array = String(decoding: try JSONSerialization.data(withJSONObject: slots), as: UTF8.self)
        let literal = "\"" + array.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        let sidebar = try Fixture.read(["prefs.js": Data("user_pref(\"browser.newtabpage.pinned\", \(literal));\n".utf8)])
        let favorites = try #require(sidebar.favorites[Fixture.profileKey])
        #expect(favorites == (1...12).map { Fixture.Item.tab(Fixture.tab("Site \($0)", "https://site\($0).example.com/")) })
        #expect(sidebar.spaces.isEmpty)
    }

    @Test func anEncryptedSessionFileFallsBackToRecovery() throws {
        let sidebar = try Fixture.read(["sessionstore.jsonlz4": Fixture.encrypted,
                                        "sessionstore-backups/recovery.jsonlz4": Fixture.compressed(Fixture.session)])
        #expect(sidebar.spaces.map(\.pinned) == [Fixture.firstPinned, []])
        #expect(sidebar.spaces[0].today == Fixture.firstToday)
        #expect(sidebar.warnings.isEmpty)
    }

    @Test func aBrokenRecoveryFileFallsBackToItsBackup() throws {
        let sidebar = try Fixture.read([
            "sessionstore-backups/recovery.jsonlz4": Fixture.compressed("{\"version\": "),
            "sessionstore-backups/recovery.baklz4": Fixture.compressed(Fixture.session),
            "sessionstore-backups/previous.jsonlz4": Fixture.compressed(#"{"version": ["sessionrestore", 1], "windows": []}"#),
        ])
        #expect(sidebar.spaces.count == 2 && sidebar.spaces[0].today == Fixture.firstToday)
    }

    @Test func aNewerSessionFormatIsSkipped() throws {
        let future = Fixture.session.replacingOccurrences(of: #"["sessionrestore", 1]"#, with: #"["sessionrestore", 2]"#)
        let sidebar = try Fixture.read(["sessionstore.jsonlz4": Fixture.compressed(future),
                                        "sessionstore-backups/upgrade.jsonlz4-20261101000000": Fixture.compressed(Fixture.session)])
        #expect(sidebar.spaces.count == 2 && sidebar.spaces[0].pinned == Fixture.firstPinned)
    }

    @Test func onlyEncryptedSessionsWarnAndStillBringFavorites() throws {
        let sidebar = try Fixture.read(["sessionstore.jsonlz4": Fixture.encrypted,
                                        "sessionstore-backups/recovery.jsonlz4": Fixture.encrypted,
                                        "prefs.js": Data(Fixture.prefs.utf8)])
        #expect(sidebar.spaces.isEmpty && sidebar.archive.isEmpty)
        #expect(sidebar.warnings.count == 1 && sidebar.warnings[0].contains("Personal"))
        #expect(sidebar.favorites[Fixture.profileKey]?.count == 2)
    }

    @Test func aMissingProfileFolderImportsNothing() throws {
        let sidebar = try FirefoxSidebarReader.read(profiles: [SidebarImportProfile(key: Fixture.profileKey,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), name: "Gone")])
        #expect(sidebar.spaces.isEmpty && sidebar.favorites.isEmpty && sidebar.archive.isEmpty && sidebar.warnings.isEmpty)
    }

    @Test func unnamedGroupsHoldTheirSplitsAndNumericIdsMatch() throws {
        let json = #"""
        {"version": ["sessionrestore", 1], "windows": [{"tabs": [
          {"groupId": 5, "splitViewId": "old-split", "entries": [{"url": "https://one.example.com/", "title": "One"}]},
          {"groupId": 5, "splitViewId": "old-split", "entries": [{"url": "https://two.example.com/", "title": "Two"}]},
          {"groupId": 5, "entries": [{"url": "https://three.example.com/", "title": "Three"}]},
          {"entries": [{"url": "about:blank"}]},
          {"groupId": "missing", "entries": [{"url": "https://loose.example.com/", "title": "Loose"}]}
        ], "groups": [{"id": 5, "name": "  ", "collapsed": false}], "splitViews": [{"id": "old-split", "numberOfTabs": 2}]}]}
        """#
        let sidebar = try Fixture.read(["sessionstore.jsonlz4": Fixture.compressed(json)])
        #expect(sidebar.spaces.count == 1)
        #expect(sidebar.spaces[0].pinned == [.folder(title: "Tab Group", icon: nil, children: [
            .split(title: nil, icon: nil, tabs: [Fixture.tab("One", "https://one.example.com/"),
                                                 Fixture.tab("Two", "https://two.example.com/")],
                   orientation: .horizontal, widthFactors: [0.5, 0.5]),
            .tab(Fixture.tab("Three", "https://three.example.com/")),
        ], isExpanded: true)])
        #expect(sidebar.spaces[0].today == [.tab(Fixture.tab("Loose", "https://loose.example.com/"))])
        #expect(sidebar.skippedItemCount == 1)
    }

    @Test func aDeferredSessionImportsTheLastSessionAndDropsItsParkedGroups() throws {
        let json = #"""
        {"version": ["sessionrestore", 1],
         "windows": [{"tabs": [{"pinned": true, "entries": [{"url": "https://mail.example.com/", "title": "Mail"}]}],
           "groups": [],
           "_closedTabs": [
             {"closedAt": 1764000100000, "state": {"entries": [{"url": "https://news.example.com/", "title": "News"}]}},
             {"closedAt": 1764000200000, "state": {"entries": [{"url": "https://old.example.com/", "title": "Old"}]}}]}],
         "lastSessionState": {"windows": [{"tabs": [
             {"pinned": true, "entries": [{"url": "https://mail.example.com/", "title": "Mail"}]},
             {"groupId": "g1", "entries": [{"url": "https://docs.example.com/c", "title": "Doc C"}]},
             {"entries": [{"url": "https://news.example.com/", "title": "News"}]}],
           "groups": [{"id": "g1", "name": "Research", "collapsed": false}]}]},
         "savedGroups": [
           {"id": "g1", "name": "Research", "collapsed": false, "removeAfterRestore": true, "closedAt": 1764000000000,
            "tabs": [{"closedAt": 1764000000000,
                      "state": {"entries": [{"url": "https://docs.example.com/c", "title": "Doc C"}]}}]},
           {"id": "g2", "name": "", "collapsed": false, "removeAfterRestore": true, "closedAt": 1764000000000,
            "tabs": [{"closedAt": 1764000000000,
                      "state": {"entries": [{"url": "https://later.example.com/", "title": "Later"}]}}]}]}
        """#
        let sidebar = try Fixture.read(["sessionstore.jsonlz4": Fixture.compressed(json)])
        #expect(sidebar.spaces.count == 1)
        #expect(sidebar.spaces[0].pinned == [
            .tab(Fixture.tab("Mail", "https://mail.example.com/")),
            .folder(title: "Research", icon: nil, children: [.tab(Fixture.tab("Doc C", "https://docs.example.com/c"))],
                    isExpanded: true),
            .folder(title: "Tab Group", icon: nil, children: [.tab(Fixture.tab("Later", "https://later.example.com/"))],
                    isExpanded: false),
        ])
        #expect(sidebar.spaces[0].today == [.tab(Fixture.tab("News", "https://news.example.com/"))])
        #expect(sidebar.archive == [SidebarImport.ArchivedTab(tab: Fixture.tab("Old", "https://old.example.com/"),
            archivedAt: Date(timeIntervalSince1970: 1_764_000_200), reason: .manual, spaceID: nil, profile: Fixture.profileKey)])
    }

    @Test func afterTheLastWindowClosesTheMostRecentClosedWindowComesBack() throws {
        let json = #"""
        {"version": ["sessionrestore", 1],
         "windows": [{"isPopup": true, "tabs": [{"entries": [{"url": "https://popup.example.com/"}]}]}],
         "_closedWindows": [
           {"closedAt": 1764000300000, "tabs": [
             {"entries": [{"url": "https://a.example.com/", "title": "A"}]},
             {"entries": [{"url": "https://b.example.com/", "title": "B"}]}],
            "_closedTabs": [{"closedAt": 1764000250000,
                             "state": {"entries": [{"url": "https://gone.example.com/", "title": "Gone"}]}}]},
           {"closedAt": 1764000100000, "tabs": [{"entries": [{"url": "https://c.example.com/", "title": "C"}]}]}]}
        """#
        let sidebar = try Fixture.read(["sessionstore.jsonlz4": Fixture.compressed(json)])
        #expect(sidebar.spaces.count == 1 && sidebar.spaces[0].placement == .profileHome && sidebar.spaces[0].pinned.isEmpty)
        #expect(sidebar.spaces[0].today == [.tab(Fixture.tab("A", "https://a.example.com/")),
                                            .tab(Fixture.tab("B", "https://b.example.com/"))])
        #expect(sidebar.archive == [
            SidebarImport.ArchivedTab(tab: Fixture.tab("Gone", "https://gone.example.com/"),
                archivedAt: Date(timeIntervalSince1970: 1_764_000_250), reason: .manual, spaceID: sidebar.spaces[0].id,
                profile: Fixture.profileKey),
            SidebarImport.ArchivedTab(tab: Fixture.tab("C", "https://c.example.com/"),
                archivedAt: Date(timeIntervalSince1970: 1_764_000_100), reason: .manual, spaceID: nil,
                profile: Fixture.profileKey),
        ])
    }

    @Test func theSessionReaderExposesWindowsAndClosedTabsForOtherForks() throws {
        try Fixture.withProfile(["sessionstore.jsonlz4": Fixture.compressed(Fixture.session)]) { profile in
            let session = try #require(try FirefoxSession.read(profile: profile.directory))
            #expect(session.windows.count == 2 && session.closedWindows.isEmpty && session.savedGroups.count == 1)
            #expect(session.closedTabs == [FirefoxSession.ClosedTab(tab: Fixture.tab("Closed one", "https://closed.example.com/"),
                closedAt: Date(timeIntervalSince1970: 1_763_999_500), window: 0)])
        }
    }
}
