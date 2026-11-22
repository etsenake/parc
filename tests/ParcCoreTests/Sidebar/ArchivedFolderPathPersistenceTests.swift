import Foundation
import Testing
@testable import ParcCore

extension ArchivedFolderPathTestsSupport {
    @MainActor
    struct ArchivedFolderPathPersistenceTests {
        struct OlderProvenance: Decodable, Equatable {
            var reason: ArchiveReason
            var spaceID: UUID
            var spaceName: String
            var groupID: UUID?
            var split: BrowserSplitLayout?
        }

        @MainActor struct Saved {
            let url: URL
            let json: [String: Any]
            let tabs: [[String: Any]]

            init(_ f: Fixture) throws {
                let store = try f.store()
                try f.delete([.folder(f.work.id)], in: store)
                try store.save()
                url = f.directory.appendingPathComponent("session.json")
                json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                tabs = try #require(json["tabs"] as? [[String: Any]])
            }

            func rewrite(_ transform: (inout [String: Any]) -> Void) throws {
                var copy = json
                copy["tabs"] = tabs.map { record -> [String: Any] in
                    guard var provenance = record["archiveProvenance"] as? [String: Any] else { return record }
                    var changed = record
                    transform(&provenance)
                    changed["archiveProvenance"] = provenance
                    return changed
                }
                try JSONSerialization.data(withJSONObject: copy).write(to: url)
            }
        }

        @Test func malformedPathsAreRejected() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            var cyclic = try #require(try f.tab(f.i1, store).archiveProvenance?.folderPath)
            cyclic.parentID = f.work.id
            #expect(!cyclic.isValid)
            #expect(!ArchivedFolderPath(parentID: nil, folders: [], siblings: []).isValid)
        }

        @Test func olderDecodingReadsANewerRecordAndIgnoresThePath() throws {
            let f = try Fixture()
            let saved = try Saved(f)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var olderReads = 0
            for record in saved.tabs {
                guard let provenance = record["archiveProvenance"] as? [String: Any], provenance["folderPath"] != nil else { continue }
                let bytes = try JSONSerialization.data(withJSONObject: provenance)
                let older = try decoder.decode(OlderProvenance.self, from: bytes)
                let current = try decoder.decode(ArchiveProvenance.self, from: bytes)
                #expect(older == OlderProvenance(reason: current.reason, spaceID: current.spaceID, spaceName: current.spaceName,
                                                 groupID: current.groupID, split: current.split))
                #expect(record["folderID"] == nil)
                olderReads += 1
            }
            #expect(olderReads == 4)
        }

        @Test func savedDataWithoutPathsLoadsCleanlyAndRestoresAtTopLevel() throws {
            let f = try Fixture()
            let saved = try Saved(f)
            try saved.rewrite { _ = $0.removeValue(forKey: "folderPath") }
            let older = try f.store()
            #expect(older.state.tabs.filter { $0.archivedAt != nil }.count == 4)
            #expect(older.state.tabs.allSatisfy { $0.archiveProvenance?.folderPath == nil })
            try f.putBack(f.w1, in: older)
            #expect(older.state.folders.isEmpty)
            #expect(try f.tab(f.w1, older).folderID == nil)
        }

        @Test func anUnreadablePathIsDroppedWithoutLosingTheRecord() throws {
            let f = try Fixture()
            let saved = try Saved(f)
            try saved.rewrite { $0["folderPath"] = ["future": [1, 2, 3]] }
            let future = try f.store()
            #expect(future.state.tabs.filter { $0.archivedAt != nil }.count == 4)
            #expect(future.state.tabs.allSatisfy { $0.archiveProvenance?.folderPath == nil && ($0.archivedAt == nil || $0.archiveProvenance?.reason == .manual) })
        }

        @Test func aPathWithAnUnknownIconAndMissingExpansionStillDecodes() throws {
            let f = try Fixture()
            let saved = try Saved(f)
            try saved.rewrite { provenance in
                guard var path = provenance["folderPath"] as? [String: Any], var folders = path["folders"] as? [[String: Any]] else { return }
                folders[0]["customIcon"] = ["icon": ["_0": "noSuchIcon"]]
                folders[0].removeValue(forKey: "isExpanded")
                path["folders"] = folders
                provenance["folderPath"] = path
            }
            let tolerant = try f.store()
            let path = try f.tab(f.w1, tolerant).archiveProvenance?.folderPath
            #expect(path?.folders.first?.customIcon == nil)
            #expect(path?.folders.first?.isExpanded == true)
            #expect(path?.folders.first?.name == "Work")
        }

        @Test func deletingAnArchivedRecordRemovesItWithItsPath() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            store.deleteArchivedTabs([f.w1], profileID: f.profile.id)
            #expect(store.state.tab(f.w1) == nil)
        }

        @Test func puttingBackAnArchivedRecordClearsItsPath() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            store.deleteArchivedTabs([f.w1], profileID: f.profile.id)
            try f.putBack(f.w2, in: store)
            #expect(try f.tab(f.w2, store).archiveProvenance == nil)
        }

        @Test func clearArchiveLeavesNoRecordedFolderPathOrDeletedFolderNameInSavedData() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            store.clearArchive(profileID: f.profile.id)
            try store.save()
            let saved = try String(contentsOf: f.directory.appendingPathComponent("session.json"), encoding: .utf8)
            #expect(store.state.tabs.allSatisfy { $0.archivedAt == nil })
            #expect(!saved.contains("folderPath"))
            #expect(!saved.contains("Inner"))
        }

        @Test func aSidebarBackupCarriesTheRecordedFolderPathAndReadsItBackIntact() throws {
            let f = try Fixture()
            var seconds: TimeInterval = 1_900_000_000
            let store = try BrowserStore(directory: f.directory, now: { seconds += 7_200; return Date(timeIntervalSince1970: seconds) },
                                         keepsBackups: true)
            try f.delete([.folder(f.work.id)], in: store)
            try store.save()
            let newest = try #require(SessionBackups.restorable(in: f.directory).first)
            let restored = try BrowserStore.savedSession(from: newest.data)
            #expect(restored.tabs.first { $0.id == f.i1 }?.archiveProvenance?.folderPath == (try f.tab(f.i1, store)).archiveProvenance?.folderPath)
        }

        @Test func clearArchiveLeavesNoSidebarBackupHoldingARecordedFolderPath() throws {
            let f = try Fixture()
            var seconds: TimeInterval = 1_900_000_000
            let store = try BrowserStore(directory: f.directory, now: { seconds += 7_200; return Date(timeIntervalSince1970: seconds) },
                                         keepsBackups: true)
            try f.delete([.folder(f.work.id)], in: store)
            try store.save()
            store.clearArchive(profileID: f.profile.id)
            try store.save()
            let remaining = try SessionBackups.list(in: f.directory).map { try String(contentsOf: $0.url, encoding: .utf8) }
            #expect(!remaining.isEmpty)
            #expect(remaining.allSatisfy { !$0.contains("folderPath") && !$0.contains("Inner") })
        }
    }
}
