import Foundation
import Testing
@testable import ParcCore

struct ZenSidebarReaderRecoveryTests {
    private typealias Fixture = ZenSidebarFixture

    private static func backups(_ profile: SidebarImportProfile) -> URL {
        profile.directory.appendingPathComponent("zen-sessions-backup", isDirectory: true)
    }

    @Test func aMissingProfileFolderReadsAsNothing() throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = SidebarImportProfile(key: Fixture.key, directory: root.appendingPathComponent("gone"), name: "Zen")
            let zen = try ZenSidebarReader.read(profiles: [profile])
            #expect(zen.spaces.isEmpty && zen.favorites.isEmpty && zen.routes.isEmpty && zen.warnings.isEmpty)
        }
    }

    @Test func aMissingSessionFallsBackToTheNewestDatedBackupAfterUnusableOnes() throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try Fixture.makeProfile(in: root, session: nil, routing: nil)
            let backups = Self.backups(profile)
            try Fixture.writeMozLz4(#"{ "spaces": [], "tabs": [] }"#, to: backups.appendingPathComponent("clean.jsonlz4"))
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            try Data("garbage".utf8).write(to: backups.appendingPathComponent("recovery.baklz4"))
            try Fixture.writeMozLz4(Fixture.minimalSession(title: "Old"),
                                    to: backups.appendingPathComponent("zen-sessions-2026-11-20-09.jsonlz4"))
            try Fixture.writeMozLz4(Fixture.minimalSession(title: "New"),
                                    to: backups.appendingPathComponent("zen-sessions-2026-11-24-18.jsonlz4"))
            let zen = try ZenSidebarReader.read(profiles: [profile])
            #expect(zen.spaces.map(\.title) == ["New"])
            #expect(zen.spaces.first?.pinned == [.tab(SidebarImport.Tab(title: "New", url: "https://new.example/"))])
            #expect(zen.warnings.isEmpty)
        }
    }

    @Test func aSessionWithoutSpacesUsesTheCleanBackupFirst() throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try Fixture.makeProfile(in: root, session: #"{ "spaces": [], "tabs": [] }"#, routing: nil)
            let backups = Self.backups(profile)
            try Fixture.writeMozLz4(Fixture.minimalSession(title: "Clean"), to: backups.appendingPathComponent("clean.jsonlz4"))
            try Fixture.writeMozLz4(Fixture.minimalSession(title: "Recovery"), to: backups.appendingPathComponent("recovery.baklz4"))
            let zen = try ZenSidebarReader.read(profiles: [profile])
            #expect(zen.spaces.map(\.title) == ["Clean"])
        }
    }

    @Test func anUnreadableSessionWithNoBackupWarns() throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try Fixture.makeProfile(in: root, session: nil, routing: nil)
            try Data("mozLz40\0broken".utf8).write(to: profile.directory.appendingPathComponent("zen-sessions.jsonlz4"))
            let zen = try ZenSidebarReader.read(profiles: [profile])
            #expect(zen.spaces.isEmpty)
            #expect(zen.warnings.count == 1)
        }
    }

    @Test func aContainerMissingFromContainersJsonFallsBackToTheZenProfile() throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try Fixture.makeProfile(in: root, session: Fixture.minimalSession(title: "Lost", container: 9),
                                                  routing: nil)
            let zen = try ZenSidebarReader.read(profiles: [profile])
            #expect(zen.spaces.map(\.profile) == [Fixture.key])
            #expect(zen.extraProfiles.isEmpty)
        }
    }

    @Test func severalZenProfilesMergeWithTheirOwnContainerProfiles() throws {
        try DataFixtures.withTemporaryDirectory { root in
            let first = try Fixture.makeProfile(in: root)
            let second = try Fixture.makeProfile(in: root, folder: "q9w8e7.Second",
                session: Fixture.minimalSession(title: "Side", container: 2),
                routing: Fixture.routing.replacingOccurrences(of: Fixture.work, with: "{dddddddd-0000-4000-8000-000000000004}"))
            let zen = try ZenSidebarReader.read(profiles: [first, second])
            let secondWork = SidebarImport.ProfileKey.extra("zen:q9w8e7.Second:2")
            #expect(zen.spaces.map(\.title) == ["Personal", "Work", "Side"])
            #expect(zen.spaces.map(\.profile) == [Fixture.key, Fixture.workKey, secondWork])
            #expect(zen.extraProfiles.map(\.key) == [Fixture.workKey, Fixture.clientsKey, secondWork])
            #expect(zen.routes.count == 4)
            #expect(zen.warnings.count == 1)
            #expect(zen.warnings.first?.hasPrefix("2 ") == true)
            #expect(zen.skippedItemCount == 4)
        }
    }

    @Test func aSplitWithoutALayoutTreeFollowsItsGridType() throws {
        let session = #"""
            { "spaces": [ { "uuid": "s", "name": "Grid", "containerTabId": 0 } ],
              "tabs": [
                { "zenSyncId": "a", "pinned": false, "zenWorkspace": "s", "groupId": "g",
                  "entries": [ { "url": "https://a.example/", "title": "A" } ], "index": 1 },
                { "zenSyncId": "b", "pinned": false, "zenWorkspace": "s", "groupId": "g",
                  "entries": [ { "url": "https://b.example/", "title": "B" } ], "index": 1 },
                { "zenSyncId": "c", "pinned": false, "zenWorkspace": "s", "groupId": "h",
                  "entries": [ { "url": "https://c.example/", "title": "C" } ], "index": 1 },
                { "zenSyncId": "d", "pinned": false, "zenWorkspace": "s", "groupId": "h",
                  "entries": [ { "url": "https://d.example/", "title": "D" } ], "index": 1 } ],
              "folders": [],
              "splitViewData": [ { "groupId": "g", "gridType": "hsep", "tabs": ["a", "b"] },
                                 { "groupId": "h", "gridType": "vsep", "tabs": ["c", "d"] } ] }
            """#
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try Fixture.makeProfile(in: root, session: session, routing: nil)
            let zen = try ZenSidebarReader.read(profiles: [profile])
            let today = Fixture.rounded(zen.spaces.first?.today ?? [])
            #expect(today == [
                .split(title: nil, icon: nil, tabs: [SidebarImport.Tab(title: "A", url: "https://a.example/"),
                       SidebarImport.Tab(title: "B", url: "https://b.example/")], orientation: .vertical, widthFactors: [0.5, 0.5]),
                .split(title: nil, icon: nil, tabs: [SidebarImport.Tab(title: "C", url: "https://c.example/"),
                       SidebarImport.Tab(title: "D", url: "https://d.example/")], orientation: .horizontal, widthFactors: [0.5, 0.5]),
            ])
        }
    }
}
