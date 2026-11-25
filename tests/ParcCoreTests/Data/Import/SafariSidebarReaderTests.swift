import Foundation
import SQLite3
import Testing
@testable import ParcCore

enum SafariSidebarReaderFixture {
    typealias Tab = SidebarImport.Tab
    typealias Item = SidebarImport.Item
    typealias ProfileKey = SidebarImport.ProfileKey

    static let work = ProfileKey.extra("safari:6F1C2B9E-0A4D-4C55-9E21-3B7D8A1F0C42")
    static let school = ProfileKey.extra("safari:A1B2C3D4-0000-4000-8000-000000000048")
    static let importedAt = Date(timeIntervalSince1970: 1_793_000_000)

    static func profiles(_ home: URL, key: ProfileKey = .standard) -> [SidebarImportProfile] {
        [SidebarImportProfile(key: key, directory: home.appendingPathComponent("Library/Safari", isDirectory: true), name: "Safari")]
    }

    static func database(_ home: URL) -> URL {
        home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db")
    }

    static func read(_ home: URL, key: ProfileKey = .standard) throws -> SidebarImport {
        try SafariSidebarReader.read(home: home, profiles: profiles(home, key: key))
    }

    static func withHome<T>(extra: String = "", _ body: (URL) throws -> T) throws -> T {
        try withHome(extra: extra, bookmarks: bookmarks, body)
    }

    static func withHome<T>(extra: String = "", bookmarks: [String: Any]?, _ body: (URL) throws -> T) throws -> T {
        try DataFixtures.withTemporaryDirectory { home in
            let file = database(home)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let db = try open(file)
            do {
                try execute(db, sql + "\n" + extra)
                _ = sqlite3_close(db)
            } catch {
                _ = sqlite3_close(db)
                throw error
            }
            if let bookmarks { try write(bookmarks: bookmarks, home: home) }
            return try body(home)
        }
    }

    static func write(bookmarks: [String: Any], home: URL) throws {
        let file = home.appendingPathComponent("Library/Safari/Bookmarks.plist")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: bookmarks, format: .binary, options: 0).write(to: file)
    }

    static func open(_ file: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db = handle else {
            _ = sqlite3_close(handle)
            throw CocoaError(.fileWriteUnknown)
        }
        return db
    }

    static func execute(_ db: OpaquePointer, _ statements: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, statements, nil, nil, &message)
        let detail = message.map { String(cString: $0) } ?? ""
        sqlite3_free(message)
        guard status == SQLITE_OK else { throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: detail]) }
    }

    static func blob(_ values: [String: Any]) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        return "X'" + data.map { String(format: "%02X", $0) }.joined() + "'"
    }

    static func leaf(_ url: String, _ title: String) -> [String: Any] {
        ["WebBookmarkType": "WebBookmarkTypeLeaf", "WebBookmarkUUID": UUID().uuidString, "URLString": url,
         "URIDictionary": ["title": title]]
    }

    static func list(_ title: String, _ children: [[String: Any]], uuid: String = UUID().uuidString,
                     server: String? = nil) -> [String: Any] {
        var node: [String: Any] = ["WebBookmarkType": "WebBookmarkTypeList", "Title": title, "WebBookmarkUUID": uuid,
                                   "Children": children]
        if let server { node["Sync"] = ["ServerID": server] }
        return node
    }

    static var bookmarks: [String: Any] {
        let bar = [leaf("javascript:alert(1)", "Bookmarklet"), list("Nested", [leaf("https://nested.example.com/", "Nested")])]
            + (1...14).map { leaf("https://bar\($0).example.com/", "Bar \($0)") }
        let work = list("Work Favorites", [leaf("https://jira.example.com/", "Jira"), leaf("https://wiki.work.example.com/", "Work Wiki")],
                        server: "FAV-FOLDER-0001")
        let children: [[String: Any]] = [
            ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
            list("BookmarksBar", bar),
            list("BookmarksMenu", [work]),
            list("School Favorites", [leaf("https://homework.example.com/", "Homework")], uuid: "SCHOOL-LIST"),
        ]
        return ["WebBookmarkFileVersion": 1, "Children": children]
    }

    static func tab(_ title: String, _ url: String, custom: String? = nil) -> Item {
        .tab(Tab(title: title, url: url, customTitle: custom))
    }

    static var expected: SidebarImport {
        SidebarImport(spaces: [
            .init(title: nil, icon: nil, theme: nil, profile: .standard,
                  pinned: [tab("Mail", "https://mail.example.com/"), tab("Calendar", "https://cal.example.com/")],
                  id: "safari:loose:DefaultProfile",
                  today: [tab("Notes (local file)", "file:///Users/example/notes.html"), tab("Weather", "https://weather.example.com/")],
                  placement: .profileHome),
            .init(title: "Research", icon: nil, theme: nil, profile: .standard,
                  pinned: [tab("Search results", "https://papers.example.org/", custom: "Paper index"),
                           .folder(title: "Favorites", icon: nil, children: [tab("Group favorite", "https://wiki.example.org/")],
                                   isExpanded: false)],
                  id: "safari:B0000000-0000-4000-8000-000000000005", today: [tab("Article A", "https://news.example.net/a")]),
            .init(title: "Work", icon: .symbol("briefcase"), theme: nil, profile: work,
                  pinned: [tab("Work Chat", "https://chat.example.com/")],
                  id: "safari:loose:6F1C2B9E-0A4D-4C55-9E21-3B7D8A1F0C42", today: [tab("Work loose tab", "https://docs.example.com/w")]),
            .init(title: "Client X", icon: nil, theme: nil, profile: work, pinned: [],
                  id: "safari:B0000000-0000-4000-8000-000000000007",
                  today: [tab("Client dashboard", "https://clientx.example.com/"),
                          tab("Client invoices", "https://clientx.example.com/invoices")]),
        ], favorites: [
            (key: .standard, items: (1...12).map { tab("Bar \($0)", "https://bar\($0).example.com/") }),
            (key: work, items: [tab("Jira", "https://jira.example.com/"), tab("Work Wiki", "https://wiki.work.example.com/")]),
        ], extraProfiles: [.init(key: work, name: "Work")])
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

    static let sql = #"""
        PRAGMA foreign_keys = OFF;

        CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, special_id INTEGER DEFAULT 0, parent INTEGER, type INTEGER, title TEXT, url TEXT COLLATE NOCASE, num_children INTEGER DEFAULT 0, editable INTEGER DEFAULT 1, deletable INTEGER DEFAULT 1, hidden INTEGER DEFAULT 0, hidden_ancestor_count INTEGER DEFAULT 0, order_index INTEGER NOT NULL, external_uuid TEXT UNIQUE, read INTEGER DEFAULT NULL, last_modified REAL DEFAULT NULL, server_id TEXT, sync_key TEXT, sync_data BLOB, added INTEGER DEFAULT 1, deleted INTEGER DEFAULT 0, extra_attributes BLOB DEFAULT NULL, local_attributes BLOB DEFAULT NULL, fetched_icon BOOL DEFAULT 0, icon BLOB DEFAULT NULL, dav_generation INTEGER DEFAULT 0, locally_added BOOL DEFAULT 0, archive_status INTEGER DEFAULT 0, syncable BOOL DEFAULT 1, web_filter_status INTEGER DEFAULT 0, modified_attributes UNSIGNED BIG INT DEFAULT 0, date_closed REAL DEFAULT NULL, last_selected_child INTEGER DEFAULT NULL, subtype INTEGER DEFAULT 0, topic_title TEXT DEFAULT NULL, FOREIGN KEY (last_selected_child) REFERENCES bookmarks (id) ON DELETE SET NULL);
        CREATE INDEX folder_list_index ON bookmarks (parent, type, order_index);
        CREATE INDEX group_index ON bookmarks (parent, order_index);

        CREATE TABLE windows (id INTEGER PRIMARY KEY, active_tab_group_id INTEGER DEFAULT NULL, active_profile_id INTEGER DEFAULT NULL, date_closed REAL DEFAULT NULL, extra_attributes BLOB DEFAULT NULL, is_last_session INTEGER DEFAULT 0, local_tab_group_id INTEGER DEFAULT NULL, private_tab_group_id INTEGER DEFAULT NULL, scene_id TEXT DEFAULT NULL, uuid TEXT NOT NULL UNIQUE, restoration_archive BLOB DEFAULT NULL);
        CREATE TABLE windows_tab_groups (id INTEGER PRIMARY KEY, active_tab_id INTEGER DEFAULT NULL, tab_group_id INTEGER NOT NULL, window_id INTEGER NOT NULL, UNIQUE (tab_group_id, window_id));
        CREATE TABLE windows_profiles (id INTEGER PRIMARY KEY, active_tab_group_id INTEGER DEFAULT NULL, profile_id INTEGER NOT NULL, window_id INTEGER NOT NULL, UNIQUE (profile_id, window_id));
        CREATE TABLE windows_unnamed_tab_groups (id INTEGER PRIMARY KEY, tab_group_id INTEGER NOT NULL, window_id INTEGER NOT NULL, UNIQUE (tab_group_id, window_id));
        CREATE TABLE settings (id INTEGER PRIMARY KEY, key TEXT NOT NULL, value NUMERIC NOT NULL, generation INTEGER NOT NULL, device_identifier TEXT NOT NULL, parent INTEGER, sync_data BLOB, modified INTEGER NOT NULL, deleted INTEGER NOT NULL, server_id TEXT, UNIQUE (key, parent));

        INSERT INTO bookmarks (id, parent, type, subtype, special_id, title, url, order_index, external_uuid, server_id, syncable, hidden, deleted, date_closed, extra_attributes) VALUES
        (0,  NULL, 1, 0, 0, NULL,                    NULL, 0, 'Root', NULL, 0, 0, 0, NULL, NULL),
        (1,  0, 1, 2, 0, 'Personal',                 '',   0, 'DefaultProfile', 'DefaultProfile', 1, 0, 0, NULL, NULL),
        (2,  0, 1, 2, 0, 'Work',                     '',   1, '6F1C2B9E-0A4D-4C55-9E21-3B7D8A1F0C42', 'PROFILE-WORK-SERVER-ID', 1, 0, 0, NULL, X'62706C6973743030D2010203045F101D437573746F6D4661766F7269746573466F6C64657253657276657249445F100F53796D626F6C496D6167654E616D655F100F4641562D464F4C4445522D3030303159627269656663617365080D2D3F51000000000000010100000000000000050000000000000000000000000000005B'),
        (3,  0, 1, 0, 0, 'pinned',                   NULL, 2, 'pinned', NULL, 0, 0, 0, NULL, X'62706C6973743030D101025F101E636F6D2E6170706C652E626F6F6B6D61726B732E4F6D697446726F6D554909080B2C000000000000010100000000000000030000000000000000000000000000002D'),
        (4,  2, 1, 0, 0, 'pinned-6F1C2B9E-0A4D-4C55-9E21-3B7D8A1F0C42', NULL, 0, 'pinned-6F1C2B9E-0A4D-4C55-9E21-3B7D8A1F0C42', NULL, 0, 0, 0, NULL, X'62706C6973743030D101025F101E636F6D2E6170706C652E626F6F6B6D61726B732E4F6D697446726F6D554909080B2C000000000000010100000000000000030000000000000000000000000000002D'),
        (5,  0, 1, 0, 0, 'Research',                 NULL, 3, 'B0000000-0000-4000-8000-000000000005', 'TG-RESEARCH', 1, 0, 0, NULL, NULL),
        (6,  5, 1, 1, 0, 'TopScopedBookmarkList',    NULL, 0, 'B0000000-0000-4000-8000-000000000006', 'TopScopedBookmarkList_TG-RESEARCH', 1, 0, 0, NULL, NULL),
        (7,  2, 1, 0, 0, 'Client X',                 NULL, 2, 'B0000000-0000-4000-8000-000000000007', 'TG-CLIENTX', 1, 0, 0, NULL, NULL),
        (8,  0, 1, 0, 0, 'Local',                    NULL, 4, 'B0000000-0000-4000-8000-000000000008', NULL, 0, 1, 0, NULL, NULL),
        (9,  0, 1, 0, 0, 'Private',                  NULL, 5, 'B0000000-0000-4000-8000-000000000009', NULL, 0, 1, 0, NULL, NULL),
        (23, 0, 1, 0, 0, 'recentlyClosed',           NULL, 6, 'recentlyClosed', NULL, 0, 0, 0, NULL, X'62706C6973743030D101025F101E636F6D2E6170706C652E626F6F6B6D61726B732E4F6D697446726F6D554909080B2C000000000000010100000000000000030000000000000000000000000000002D'),
        (25, 2, 1, 3, 0, 'Example MacBook',          NULL, 3, 'B0000000-0000-4000-8000-000000000025', 'DEVICE-THIS-MAC', 1, 0, 0, NULL, NULL),
        (26, 25, 1, 0, 0, 'Unnamed',                 NULL, 0, 'B0000000-0000-4000-8000-000000000026', 'TG-UNNAMED-1', 1, 0, 0, NULL, X'62706C6973743030D10102594973556E6E616D656409080B150000000000000101000000000000000300000000000000000000000000000016'),
        (28, 0, 1, 0, 0, 'privatePinned',            NULL, 7, 'privatePinned', NULL, 0, 0, 0, NULL, X'62706C6973743030D101025F101E636F6D2E6170706C652E626F6F6B6D61726B732E4F6D697446726F6D554909080B2C000000000000010100000000000000030000000000000000000000000000002D'),
        (29, 0, 1, 0, 0, 'Old Trip',                 NULL, 8, 'B0000000-0000-4000-8000-000000000029', 'TG-OLD', 1, 0, 1, NULL, NULL),
        (31, 0, 1, 0, 0, 'Local',                    NULL, 9, 'B0000000-0000-4000-8000-000000000031', NULL, 0, 1, 0, NULL, NULL),
        (32, 0, 1, 0, 0, 'Private',                  NULL, 10, 'B0000000-0000-4000-8000-000000000032', NULL, 0, 1, 0, NULL, NULL),
        (10, 3, 0, 0, 0, 'Mail',                     'https://mail.example.com/', 0, 'C0000000-0000-4000-8000-000000000010', NULL, 0, 0, 0, NULL, NULL),
        (11, 3, 0, 0, 0, 'Calendar',                 'https://cal.example.com/',  1, 'C0000000-0000-4000-8000-000000000011', NULL, 0, 0, 0, NULL, NULL),
        (12, 4, 0, 0, 0, 'Work Chat',                'https://chat.example.com/', 0, 'C0000000-0000-4000-8000-000000000012', NULL, 0, 0, 0, NULL, NULL),
        (13, 5, 0, 0, 0, 'Search results',           'https://papers.example.org/search?q=x', 0, 'C0000000-0000-4000-8000-000000000013', 'T13', 1, 0, 0, NULL, X'62706C6973743030D301020304050658497350696E6E65645D50696E6E6564416464726573735B50696E6E65645469746C65095F101B68747470733A2F2F7061706572732E6578616D706C652E6F72672F5B506170657220696E646578080F1826323351000000000000010100000000000000070000000000000000000000000000005D'),
        (14, 5, 0, 0, 0, 'Article A',                'https://news.example.net/a', 1, 'C0000000-0000-4000-8000-000000000014', 'T14', 1, 0, 0, NULL, NULL),
        (15, 5, 0, 0, 0, 'Deleted tab',              'https://gone.example.net/', 2, 'C0000000-0000-4000-8000-000000000015', 'T15', 1, 0, 1, NULL, NULL),
        (16, 5, 0, 0, 0, 'Closed tab',               'https://closed.example.net/', 3, 'C0000000-0000-4000-8000-000000000016', 'T16', 1, 0, 0, 785000000.0, NULL),
        (17, 6, 0, 0, 0, 'Group favorite',           'https://wiki.example.org/', 0, 'C0000000-0000-4000-8000-000000000017', 'T17', 1, 0, 0, NULL, NULL),
        (18, 7, 0, 0, 0, 'Client dashboard',         'https://clientx.example.com/', 0, 'C0000000-0000-4000-8000-000000000018', 'T18', 1, 0, 0, NULL, NULL),
        (19, 7, 0, 0, 0, 'Client invoices',          'https://clientx.example.com/invoices', 1, 'C0000000-0000-4000-8000-000000000019', 'T19', 1, 0, 0, NULL, NULL),
        (20, 8, 0, 0, 0, 'Notes',                    NULL, 0, 'C0000000-0000-4000-8000-000000000020', NULL, 0, 0, 0, NULL, X'62706C6973743030D2010203045A4C6F63616C5469746C65584C6F63616C55524C5F10124E6F74657320286C6F63616C2066696C65295F102066696C653A2F2F2F55736572732F6578616D706C652F6E6F7465732E68746D6C080D1821360000000000000101000000000000000500000000000000000000000000000059'),
        (21, 8, 0, 0, 0, 'Start Page',               NULL, 1, 'C0000000-0000-4000-8000-000000000021', NULL, 0, 0, 0, NULL, NULL),
        (33, 8, 0, 0, 0, 'Weather',                  'https://weather.example.com/', 2, 'C0000000-0000-4000-8000-000000000033', NULL, 0, 0, 0, NULL, NULL),
        (22, 9, 0, 0, 0, 'Secret',                   'https://private.example.com/', 0, 'C0000000-0000-4000-8000-000000000022', NULL, 0, 0, 0, NULL, NULL),
        (24, 23, 0, 0, 0, 'Recently closed',         'https://recent.example.com/', 0, 'C0000000-0000-4000-8000-000000000024', NULL, 0, 0, 0, 784000000.0, NULL),
        (27, 26, 0, 0, 0, 'Work loose tab',          'https://docs.example.com/w', 0, 'C0000000-0000-4000-8000-000000000027', 'T27', 1, 0, 0, NULL, NULL),
        (30, 29, 0, 0, 0, 'Old booking',             'https://trip.example.com/', 0, 'C0000000-0000-4000-8000-000000000030', 'T30', 1, 0, 1, NULL, NULL);

        UPDATE bookmarks SET last_selected_child = 14 WHERE id = 5;

        INSERT INTO windows (id, uuid, active_tab_group_id, active_profile_id, local_tab_group_id, private_tab_group_id, is_last_session, date_closed) VALUES
        (1, 'D0000000-0000-4000-8000-000000000001', 5,  1, 8,  9,  1, NULL),
        (2, 'D0000000-0000-4000-8000-000000000002', 26, 2, 31, 32, 1, NULL),
        (3, 'D0000000-0000-4000-8000-000000000003', 8,  1, 8,  9,  0, 783000000.0);

        INSERT INTO windows_tab_groups (window_id, tab_group_id, active_tab_id) VALUES
        (1, 5, 14), (1, 8, 33), (2, 7, 18), (2, 26, 27);
        INSERT INTO windows_profiles (window_id, profile_id, active_tab_group_id) VALUES
        (1, 1, 5), (2, 2, 26);
        INSERT INTO windows_unnamed_tab_groups (window_id, tab_group_id) VALUES
        (2, 26);
        """#
}

struct SafariSidebarReaderTests {
    private typealias Fixture = SafariSidebarReaderFixture

    @Test func theFixtureBecomesItsSpacesProfilesPinnedTodayAndFavorites() throws {
        try Fixture.withHome { home in
            let imported = try Fixture.read(home)
            #expect(imported == Fixture.expected)
        }
    }

    @Test func deletedClosedPrivateAndRecentlyClosedRowsStayInSafari() throws {
        try Fixture.withHome { home in
            let sidebar = try Fixture.read(home)
            let urls = sidebar.spaces.flatMap { Fixture.urls($0.pinned) + Fixture.urls($0.today) }
                + sidebar.favorites.values.flatMap { Fixture.urls($0) }
            for gone in ["gone.example.net", "closed.example.net", "private.example.com", "recent.example.com", "trip.example.com"] {
                #expect(!urls.contains { $0.contains(gone) })
            }
            #expect(!sidebar.spaces.contains { ["Old Trip", "Private", "Local", "Unnamed", "recentlyClosed"].contains($0.title ?? "") })
            #expect(urls.count == Set(urls).count)
        }
    }

    @Test func theChosenProfileStandsInForSafarisDefaultProfile() throws {
        try Fixture.withHome { home in
            let chosen = SidebarImport.ProfileKey.custom(directory: "Safari")
            let sidebar = try Fixture.read(home, key: chosen)
            #expect(sidebar.spaces.map(\.profile) == [chosen, chosen, Fixture.work, Fixture.work])
            #expect(sidebar.favorites[chosen]?.count == 12 && sidebar.favorites[.standard] == nil)
            #expect(sidebar.extraProfiles == [.init(key: Fixture.work, name: "Work")])
        }
    }

    @Test func groupsInsideADeviceFolderImportAndRemoteOrDeletedOnesDoNot() throws {
        let school = try Fixture.blob(["CustomFavoritesFolderServerID": "SCHOOL-LIST", "SymbolImageName": "not-a-symbol"])
        let extra = """
            INSERT INTO bookmarks (id, parent, type, subtype, title, url, order_index, external_uuid, syncable, hidden, deleted, \
            extra_attributes) VALUES
            (40, 25, 1, 0, 'Side quest', NULL, 1, 'B0000000-0000-4000-8000-000000000040', 1, 0, 0, NULL),
            (41, 40, 0, 0, 'Quest map', 'https://quest.example.com/', 0, 'C0000000-0000-4000-8000-000000000041', 1, 0, 0, NULL),
            (42, 2, 1, 4, 'Other Mac', NULL, 4, 'B0000000-0000-4000-8000-000000000042', 1, 0, 0, NULL),
            (43, 42, 1, 0, 'Remote group', NULL, 0, 'B0000000-0000-4000-8000-000000000043', 1, 0, 0, NULL),
            (44, 43, 0, 0, 'Remote tab', 'https://remote.example.com/', 0, 'C0000000-0000-4000-8000-000000000044', 1, 0, 0, NULL),
            (45, 0, 1, 2, 'Gone', '', 11, 'GONE-PROFILE', 1, 0, 1, NULL),
            (46, 45, 1, 0, 'Gone group', NULL, 0, 'B0000000-0000-4000-8000-000000000046', 1, 0, 0, NULL),
            (47, 46, 0, 0, 'Gone tab', 'https://gone-profile.example.com/', 0, 'C0000000-0000-4000-8000-000000000047', 1, 0, 0, NULL),
            (48, 0, 1, 2, 'School', '', 12, 'A1B2C3D4-0000-4000-8000-000000000048', 1, 0, 0, \(school));
            """
        try Fixture.withHome(extra: extra) { home in
            let sidebar = try Fixture.read(home)
            let work = sidebar.spaces.filter { $0.profile == Fixture.work }
            #expect(work.map(\.title) == ["Work", "Client X", "Side quest"])
            #expect(work.last == SidebarImport.Space(title: "Side quest", icon: nil, theme: nil, profile: Fixture.work, pinned: [],
                                                           id: "safari:B0000000-0000-4000-8000-000000000040",
                                                           today: [Fixture.tab("Quest map", "https://quest.example.com/")]))
            #expect(!sidebar.spaces.contains { ["Remote group", "Gone group", "Gone", "School"].contains($0.title ?? "") })
            #expect(sidebar.extraProfiles == [.init(key: Fixture.work, name: "Work"), .init(key: Fixture.school, name: "School")])
            #expect(sidebar.favorites[Fixture.school] == [Fixture.tab("Homework", "https://homework.example.com/")])
        }
    }

    @Test func tabsStillWaitingInSafarisWriteAheadLogAreRead() throws {
        try Fixture.withHome { home in
            let db = try Fixture.open(Fixture.database(home))
            defer { _ = sqlite3_close(db) }
            try Fixture.execute(db, """
                PRAGMA journal_mode = WAL;
                PRAGMA wal_autocheckpoint = 0;
                INSERT INTO bookmarks (id, parent, type, title, url, order_index, external_uuid)
                VALUES (50, 5, 0, 'Fresh', 'https://fresh.example.com/', 9, 'C0000000-0000-4000-8000-000000000050');
                """)
            #expect(FileManager.default.fileExists(atPath: Fixture.database(home).path + "-wal"))
            let research = try #require(try Fixture.read(home).spaces.first { $0.title == "Research" })
            #expect(research.today == [Fixture.tab("Article A", "https://news.example.net/a"),
                                       Fixture.tab("Fresh", "https://fresh.example.com/")])
        }
    }

    @Test func missingSafariFilesImportNothingAndABookmarksFileAloneStillBringsFavorites() throws {
        try DataFixtures.withTemporaryDirectory { home in
            #expect(try Fixture.read(home) == SidebarImport(spaces: []))
            try Fixture.write(bookmarks: Fixture.bookmarks, home: home)
            let sidebar = try Fixture.read(home)
            #expect(sidebar.spaces.isEmpty && sidebar.extraProfiles.isEmpty)
            #expect(sidebar.favorites[.standard]?.count == 12)
        }
    }

    @Test func noChosenProfileImportsNothing() throws {
        try Fixture.withHome { home in
            let imported = try SafariSidebarReader.read(home: home, profiles: [])
            #expect(imported == SidebarImport(spaces: []))
        }
    }
}
