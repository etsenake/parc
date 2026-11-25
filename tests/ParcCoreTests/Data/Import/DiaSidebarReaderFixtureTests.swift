import Foundation
import SQLite3
import Testing
@testable import ParcCore

final class DiaDecryptCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(url: URL, format: SidebarEncryptedFormat)] = []

    func record(_ url: URL, _ format: SidebarEncryptedFormat) {
        lock.lock(); defer { lock.unlock() }
        recorded.append((url, format))
    }

    var entries: [(url: URL, format: SidebarEncryptedFormat)] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}

enum DiaSidebarReaderFixture {
    typealias Item = SidebarImport.Item
    typealias Tab = SidebarImport.Tab

    static let sql = """
        CREATE TABLE spaces (id TEXT PRIMARY KEY, title TEXT, creation_date DATE, theme TEXT, theme_intensity DOUBLE);
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, entity_id TEXT, parent_id INTEGER, "order" INTEGER, deleted_at DATETIME, space_id TEXT DEFAULT '');
        CREATE TABLE tabs (id TEXT PRIMARY KEY, creation_date DATE, split_view_widths TEXT);
        CREATE TABLE tab_groups (id TEXT PRIMARY KEY, title TEXT, icon TEXT, theme TEXT, behavior TEXT);
        CREATE TABLE content_panes (id TEXT PRIMARY KEY, custom_title TEXT, variant TEXT);
        CREATE TABLE web_contents (id INTEGER PRIMARY KEY, content_pane_id TEXT, url TEXT, title TEXT);

        INSERT INTO spaces VALUES ('sp-work', 'Work', '2026-01-01 10:00:00.000', 'blue', 0.4);
        INSERT INTO spaces VALUES ('sp-play', 'Play', '2026-02-01 10:00:00.000', 'neutral', NULL);

        INSERT INTO nodes VALUES (1, 'favorites',        'fav-work',  NULL, 0, NULL, 'sp-work');
        INSERT INTO nodes VALUES (2, 'pinned_container', 'pin-work',  NULL, 0, NULL, 'sp-work');
        INSERT INTO nodes VALUES (3, 'window',           'win-work',  NULL, 0, NULL, 'sp-work');
        INSERT INTO nodes VALUES (4, 'window',           'win-old',   NULL, 1, '2026-03-01 00:00:00.000', 'sp-work');
        INSERT INTO nodes VALUES (5, 'pinned_container', 'pin-play',  NULL, 0, NULL, 'sp-play');

        INSERT INTO nodes VALUES (10, 'tab',          't-mail', 1, 0, NULL, '');
        INSERT INTO nodes VALUES (11, 'content_pane', 'p-mail', 10, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-mail', '2026-01-02 08:00:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-mail', NULL, 'web_content');
        INSERT INTO web_contents VALUES (1, 'p-mail', 'https://mail.example.com/', 'Mail');

        INSERT INTO nodes VALUES (20, 'group',        'g-docs', 2, 0, NULL, '');
        INSERT INTO tab_groups VALUES ('g-docs', 'Docs', '{"emoji":"D"}', 'green', 'standard');
        INSERT INTO nodes VALUES (21, 'group',        'g-sub', 20, 0, NULL, '');
        INSERT INTO tab_groups VALUES ('g-sub', 'Specs', NULL, 'blue', 'standard');
        INSERT INTO nodes VALUES (22, 'tab',          't-spec', 21, 0, NULL, '');
        INSERT INTO nodes VALUES (23, 'content_pane', 'p-spec', 22, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-spec', '2026-01-03 09:00:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-spec', 'My Spec', 'web_content');
        INSERT INTO web_contents VALUES (2, 'p-spec', 'https://spec.example.com/', 'Spec page');

        INSERT INTO nodes VALUES (30, 'tab',          't-split', 2, 1, NULL, '');
        INSERT INTO nodes VALUES (31, 'content_pane', 'p-split-a', 30, 0, NULL, '');
        INSERT INTO nodes VALUES (32, 'content_pane', 'p-split-b', 30, 1, NULL, '');
        INSERT INTO tabs VALUES ('t-split', '2026-01-04 09:00:00.000', '[0.35,0.65]');
        INSERT INTO content_panes VALUES ('p-split-a', NULL, 'web_content');
        INSERT INTO content_panes VALUES ('p-split-b', NULL, 'web_content');
        INSERT INTO web_contents VALUES (3, 'p-split-a', 'https://a.example.com/', 'A');
        INSERT INTO web_contents VALUES (4, 'p-split-b', 'https://b.example.com/', 'B');

        INSERT INTO nodes VALUES (40, 'tab',          't-today', 3, 0, NULL, '');
        INSERT INTO nodes VALUES (41, 'content_pane', 'p-today', 40, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-today', '2026-01-05 09:00:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-today', NULL, 'web_content');
        INSERT INTO web_contents VALUES (5, 'p-today', 'https://today.example.com/', 'Today');

        INSERT INTO nodes VALUES (42, 'tab',          't-ntp', 3, 1, NULL, '');
        INSERT INTO nodes VALUES (43, 'content_pane', 'p-ntp', 42, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-ntp', '2026-01-05 09:05:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-ntp', NULL, 'new_tab_page');

        INSERT INTO nodes VALUES (44, 'tab',          't-closed', 4, 0, NULL, '');
        INSERT INTO nodes VALUES (45, 'content_pane', 'p-closed', 44, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-closed', '2026-01-01 09:05:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-closed', NULL, 'web_content');
        INSERT INTO web_contents VALUES (6, 'p-closed', 'https://closed-window.example.com/', 'Closed');

        INSERT INTO nodes VALUES (50, 'tab',          't-deleted', 2, 2, '2026-03-01 00:00:00.000', '');

        INSERT INTO nodes VALUES (60, 'tab',          't-play', 5, 0, NULL, '');
        INSERT INTO nodes VALUES (61, 'content_pane', 'p-play', 60, 0, NULL, '');
        INSERT INTO tabs VALUES ('t-play', '2026-02-02 09:00:00.000', NULL);
        INSERT INTO content_panes VALUES ('p-play', NULL, 'web_content');
        INSERT INTO web_contents VALUES (7, 'p-play', 'https://play.example.com/', 'Play');
        """

    static func plainDatabase(_ sql: String, in directory: URL) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("plain.sqlite")
        var handle: OpaquePointer?
        guard sqlite3_open(file.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        return try Data(contentsOf: file)
    }

    static func profile(folder: String = "Default", key: SidebarImport.ProfileKey = .standard, in directory: URL,
                        withTabs: Bool = true) throws -> SidebarImportProfile {
        let profile = directory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        if withTabs { try Data("sealed".utf8).write(to: profile.appendingPathComponent("tabs.db")) }
        return SidebarImportProfile(key: key, directory: profile, name: folder)
    }

    static func read(_ sql: String = sql, folder: String = "Default", in directory: URL,
                     calls: DiaDecryptCalls = DiaDecryptCalls()) throws -> SidebarImport {
        let plain = try plainDatabase(sql, in: directory.appendingPathComponent("plain", isDirectory: true))
        let profile = try profile(folder: folder, key: SidebarImport.profileKey(directory: folder), in: directory)
        return try DiaSidebarReader.read(profiles: [profile], decrypt: { url, format in
            calls.record(url, format)
            return plain
        })
    }

    static func tab(_ url: String, _ title: String, custom: String? = nil) -> Item {
        .tab(Tab(title: title, url: url, customTitle: custom))
    }

    static func rounded(_ items: [Item]) -> [Item] { ArcSidebarImportTestsSupport.roundingFactors(items) }
}
