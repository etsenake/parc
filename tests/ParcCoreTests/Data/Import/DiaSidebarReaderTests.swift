import Foundation
import Testing
@testable import ParcCore

struct DiaSidebarReaderTests {
    private typealias Fixture = DiaSidebarReaderFixture
    private typealias Item = SidebarImport.Item

    private func withRead(_ sql: String = Fixture.sql, _ body: (SidebarImport) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try body(try Fixture.read(sql, in: directory))
        }
    }

    private func spaces(_ sql: String = Fixture.sql) throws -> [SidebarImport.Space] {
        try DataFixtures.withTemporaryDirectory { directory in try Fixture.read(sql, in: directory).spaces }
    }

    @Test func eachSpaceRowBecomesANewSpaceInCreationOrderWithAPrefixedID() throws {
        try withRead { imported in
            #expect(imported.spaces.map(\.title) == ["Work", "Play"])
            #expect(imported.spaces.map(\.id) == ["dia:Default:sp-work", "dia:Default:sp-play"])
            #expect(imported.spaces.allSatisfy { $0.placement == .new && $0.profile == .standard && $0.icon == nil })
            #expect(imported.warnings.isEmpty && imported.skippedItemCount == 0)
        }
    }

    @Test func spaceThemesFollowDiasColourNames() throws {
        let blue = try #require(ThemeColor(hex: "4C8DF6"))
        var expected = SpaceTheme.singleColor(blue)
        expected.intensity = 0.4
        let found = try spaces()
        #expect(found[0].theme == expected)
        #expect(found[1].theme == SpaceTheme())
    }

    @Test func pinnedKeepsNestedFoldersCustomTitlesAndSplitsInOrder() throws {
        let work = try spaces()[0]
        let spec = Item.tab(.init(title: "Spec page", url: "https://spec.example.com/", customTitle: "My Spec"))
        let expected: [Item] = [
            .folder(title: "Docs", icon: nil, children: [
                .folder(title: "Specs", icon: nil, children: [spec], isExpanded: true)
            ], isExpanded: true),
            .split(title: nil, icon: nil,
                   tabs: [.init(title: "A", url: "https://a.example.com/"), .init(title: "B", url: "https://b.example.com/")],
                   orientation: .horizontal, widthFactors: [0.35, 0.65])
        ]
        #expect(Fixture.rounded(work.pinned) == Fixture.rounded(expected))
    }

    @Test func aDeletedPinnedTabIsLeftOutEvenWhenItStillHasContent() throws {
        let sql = Fixture.sql + """

        INSERT INTO nodes VALUES (90, 'tab', 't-gone', 2, 3, '2026-03-01 00:00:00.000', '');
        INSERT INTO nodes VALUES (91, 'content_pane', 'p-gone', 90, 0, NULL, '');
        INSERT INTO content_panes VALUES ('p-gone', NULL, 'web_content');
        INSERT INTO web_contents VALUES (40, 'p-gone', 'https://gone.example.com/', 'Gone');
        """
        let baseline = try spaces()[0].pinned
        let work = try spaces(sql)[0]
        #expect(work.pinned.count == 2 && work.pinned == baseline)
    }

    @Test func todayHoldsTheOpenWindowsTabsAndSkipsClosedWindowsAndNewTabPages() throws {
        let found = try spaces()
        #expect(found[0].today == [Fixture.tab("https://today.example.com/", "Today")])
        #expect(found[1].today.isEmpty)
        #expect(found[1].pinned == [Fixture.tab("https://play.example.com/", "Play")])
    }

    @Test func favoritesComeFromTheFavoritesRoots() throws {
        try withRead { imported in
            #expect(imported.favorites == [.standard: [Fixture.tab("https://mail.example.com/", "Mail")]])
        }
    }

    @Test func decryptReceivesTheTabsFileAndTheProfileFolder() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let calls = DiaDecryptCalls()
            _ = try Fixture.read(in: directory, calls: calls)
            let entries = calls.entries
            #expect(entries.count == 1)
            #expect(entries.first?.url.lastPathComponent == "tabs.db")
            #expect(entries.first?.url.deletingLastPathComponent().lastPathComponent == "Default")
            #expect(entries.first?.format == .diaTabs(profileFolder: "Default"))
        }
    }

    @Test func eachProfileKeepsItsOwnSpacesAndIDs() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let plain = try Fixture.plainDatabase(Fixture.sql, in: directory.appendingPathComponent("plain"))
            let first = try Fixture.profile(in: directory)
            let second = try Fixture.profile(folder: "Profile 1", key: .custom(directory: "Profile 1"), in: directory)
            let empty = try Fixture.profile(folder: "Profile 2", key: .custom(directory: "Profile 2"), in: directory,
                                            withTabs: false)
            let imported = try DiaSidebarReader.read(profiles: [first, second, empty], decrypt: { _, _ in plain })
            #expect(imported.spaces.map(\.id) == ["dia:Default:sp-work", "dia:Default:sp-play",
                                                  "dia:Profile 1:sp-work", "dia:Profile 1:sp-play"])
            #expect(imported.spaces.map(\.profile) == [.standard, .standard, .custom(directory: "Profile 1"),
                                                       .custom(directory: "Profile 1")])
            #expect(Set(imported.favorites.keys) == [.standard, .custom(directory: "Profile 1")])
            #expect(imported.warnings.isEmpty)
        }
    }

    @Test func aFolderIconIsKeptWhenItIsAValidEmoji() throws {
        let sql = Fixture.sql.replacingOccurrences(of: #"{"emoji":"D"}"#, with: #"{"emoji":"📁"}"#)
        let work = try spaces(sql)[0]
        guard case .folder(_, let icon, _, _) = work.pinned[0] else {
            Issue.record("The first pinned item is a folder")
            return
        }
        #expect(icon == .emoji("📁"))
    }

    @Test func aTabWithThreePanesNormalisesItsWidths() throws {
        let sql = Fixture.sql + """

        INSERT INTO nodes VALUES (70, 'tab', 't-three', 5, 1, NULL, '');
        INSERT INTO nodes VALUES (71, 'content_pane', 'p-t1', 70, 0, NULL, '');
        INSERT INTO nodes VALUES (72, 'content_pane', 'p-t2', 70, 1, NULL, '');
        INSERT INTO nodes VALUES (73, 'content_pane', 'p-t3', 70, 2, NULL, '');
        INSERT INTO tabs VALUES ('t-three', '2026-02-03 09:00:00.000', '[1,2,1]');
        INSERT INTO content_panes VALUES ('p-t1', NULL, 'web_content');
        INSERT INTO content_panes VALUES ('p-t2', NULL, 'web_content');
        INSERT INTO content_panes VALUES ('p-t3', NULL, 'web_content');
        INSERT INTO web_contents VALUES (20, 'p-t1', 'https://one.example.com/', 'One');
        INSERT INTO web_contents VALUES (21, 'p-t2', 'https://two.example.com/', 'Two');
        INSERT INTO web_contents VALUES (22, 'p-t3', 'https://three.example.com/', 'Three');
        """
        let play = try spaces(sql)[1]
        let expected = Item.split(title: nil, icon: nil,
            tabs: [.init(title: "One", url: "https://one.example.com/"), .init(title: "Two", url: "https://two.example.com/"),
                   .init(title: "Three", url: "https://three.example.com/")],
            orientation: .horizontal, widthFactors: [0.25, 0.5, 0.25])
        #expect(Fixture.rounded(Array(play.pinned.dropFirst())) == Fixture.rounded([expected]))
    }

    @Test func aSplitWithoutUsableWidthsGetsEqualPanes() throws {
        let sql = Fixture.sql.replacingOccurrences(of: "'[0.35,0.65]'", with: "NULL")
        let work = try spaces(sql)[0]
        guard case .split(_, _, _, _, let factors) = work.pinned[1] else {
            Issue.record("The second pinned item is a split")
            return
        }
        #expect(factors == [0.5, 0.5])
    }

    @Test func favoritesAreCappedAtTwelveAndDuplicateAddressesAreDropped() throws {
        var extra = ""
        for index in 0..<15 {
            let node = 100 + index * 3
            extra += """

            INSERT INTO nodes VALUES (\(node), 'tab', 'f-\(index)', 1, \(index + 1), NULL, '');
            INSERT INTO nodes VALUES (\(node + 1), 'content_pane', 'fp-\(index)', \(node), 0, NULL, '');
            INSERT INTO tabs VALUES ('f-\(index)', '2026-01-02 08:00:00.000', NULL);
            INSERT INTO content_panes VALUES ('fp-\(index)', NULL, 'web_content');
            INSERT INTO web_contents VALUES (\(100 + index), 'fp-\(index)', 'https://fav\(index % 14).example.com/', 'Fav \(index)');
            """
        }
        try withRead(Fixture.sql + extra) { imported in
            let urls = (imported.favorites[.standard] ?? []).compactMap { item -> String? in
                if case .tab(let tab) = item { return tab.url }
                return nil
            }
            #expect(urls.count == 12 && Set(urls).count == 12)
            #expect(urls.first == "https://mail.example.com/")
            #expect(urls.last == "https://fav10.example.com/")
            #expect(Array(imported.spaces[0].pinned.prefix(3)) == [
                Fixture.tab("https://fav11.example.com/", "Fav 11"), Fixture.tab("https://fav12.example.com/", "Fav 12"),
                Fixture.tab("https://fav13.example.com/", "Fav 13")])
            #expect(imported.spaces[0].pinned.count == 5)
        }
    }

    @Test func tablesLinkedByNodeIDInsteadOfEntityIDStillResolve() throws {
        let sql = """
        CREATE TABLE spaces (id TEXT PRIMARY KEY, title TEXT, creation_date DATE);
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, entity_id TEXT, parent_id INTEGER, "order" INTEGER, deleted_at DATETIME, space_id TEXT);
        CREATE TABLE tabs (node_id INTEGER, split_view_widths TEXT);
        CREATE TABLE tab_groups (node_id INTEGER, title TEXT, icon TEXT);
        CREATE TABLE content_panes (node_id INTEGER, custom_title TEXT, variant TEXT);
        CREATE TABLE web_contents (id INTEGER PRIMARY KEY, content_pane_id TEXT, url TEXT, title TEXT);
        INSERT INTO spaces VALUES ('s', 'Only', '2026-01-01 10:00:00.000');
        INSERT INTO nodes VALUES (1, 'pinned_container', NULL, NULL, 0, NULL, 's');
        INSERT INTO nodes VALUES (2, 'group', NULL, 1, 0, NULL, '');
        INSERT INTO tab_groups VALUES (2, 'Linked', NULL);
        INSERT INTO nodes VALUES (3, 'tab', NULL, 2, 0, NULL, '');
        INSERT INTO nodes VALUES (4, 'content_pane', NULL, 3, 0, NULL, '');
        INSERT INTO content_panes VALUES (4, 'Renamed', 'web_content');
        INSERT INTO web_contents VALUES (1, '4', 'https://linked.example.com/', 'Linked page');
        """
        let only = try spaces(sql)[0]
        #expect(only.pinned == [.folder(title: "Linked", icon: nil,
            children: [Fixture.tab("https://linked.example.com/", "Linked page", custom: "Renamed")], isExpanded: true)])
    }

    @Test func aPaneKeepsItsLatestPageAndNonWebPanesAreSkipped() throws {
        let sql = Fixture.sql + """

        INSERT INTO web_contents VALUES (30, 'p-play', 'https://play.example.com/later', 'Later');
        INSERT INTO nodes VALUES (80, 'tab', 't-chrome', 5, 1, NULL, '');
        INSERT INTO nodes VALUES (81, 'content_pane', 'p-chrome', 80, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-chrome', '2026-02-03 09:00:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-chrome', NULL, 'web_content');
        INSERT INTO web_contents VALUES (31, 'p-chrome', 'about:blank', 'Blank');
        """
        try withRead(sql) { imported in
            #expect(imported.spaces[1].pinned == [Fixture.tab("https://play.example.com/later", "Later")])
            #expect(imported.skippedItemCount == 1)
        }
    }

    @Test func noDecryptorMeansAnEmptyImportAndOneWarning() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let first = try Fixture.profile(in: directory)
            let second = try Fixture.profile(folder: "Profile 1", key: .custom(directory: "Profile 1"), in: directory)
            let imported = try DiaSidebarReader.read(profiles: [first, second], decrypt: nil)
            #expect(imported.spaces.isEmpty && imported.favorites.isEmpty)
            #expect(imported.warnings.count == 1 && imported.warnings[0].hasPrefix("Parc couldn’t unlock Dia’s tabs"))
        }
    }

    @Test func aDecryptorThatThrowsMeansAnEmptyImportAndOneWarning() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let profile = try Fixture.profile(in: directory)
            let imported = try DiaSidebarReader.read(profiles: [profile], decrypt: { _, _ in throw CocoaError(.userCancelled) })
            #expect(imported.spaces.isEmpty && imported.favorites.isEmpty)
            #expect(imported.warnings.count == 1 && imported.warnings[0].hasPrefix("Parc couldn’t unlock Dia’s tabs"))
        }
    }

    @Test func aProfileWithoutATabsDatabaseIsQuietlyEmpty() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let profile = try Fixture.profile(in: directory, withTabs: false)
            let imported = try DiaSidebarReader.read(profiles: [profile], decrypt: nil)
            #expect(imported.spaces.isEmpty && imported.warnings.isEmpty)
        }
    }

    @Test func bytesThatAreNotADatabaseGiveAWarningInsteadOfAFailure() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let profile = try Fixture.profile(in: directory)
            let garbage = Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 31) })
            let imported = try DiaSidebarReader.read(profiles: [profile], decrypt: { _, _ in garbage })
            #expect(imported.spaces.isEmpty && imported.warnings.count == 1)
        }
    }
}
