import Foundation
import Testing
@testable import ParcCore

struct TabHistoryArchiveTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-tab-history-" + UUID().uuidString)
    let profile = UUID()
    let other = UUID()
    let bytes = Data([1, 2, 3])

    func names() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
    }

    func record(_ url: String, _ navigation: Data) -> TabHistoryArchive.Record {
        .init(url: url, profileID: profile, navigation: navigation)
    }

    @Test func pruneRemovesGoneTabsAndRemoveDropsAClosedOne() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = UUID(), moved = UUID(), archived = UUID(), paged = UUID(), closed = UUID()
        let session = TabHistoryArchive(directory: root)
        for id in [kept, moved, archived, paged, closed] { session.store(record("https://a.invalid/", bytes), for: id) }
        session.remove(closed)
        session.prune(keeping: [kept, moved, paged, closed])
        session.flush()
        #expect(try names() == Set([kept, moved, paged].map(\.uuidString)))
    }

    @Test func anUnchangedRecordIsNotWrittenAgainButAChangedOneIs() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let paged = UUID()
        let session = TabHistoryArchive(directory: root)
        session.store(record("https://a.invalid/", bytes), for: paged)
        session.flush()
        try FileManager.default.removeItem(at: root.appendingPathComponent(paged.uuidString))
        session.store(record("https://a.invalid/", bytes), for: paged)
        session.flush()
        #expect(!(try names()).contains(paged.uuidString))
        session.store(record("https://a.invalid/", Data([5])), for: paged)
        session.flush()
        #expect((try names()).contains(paged.uuidString))
    }

    @Test func theLatestRecordComesBackAfterARelaunchOnlyForTheTabsFirstPage() {
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = UUID()
        let session = TabHistoryArchive(directory: root)
        session.store(record("https://a.invalid/", bytes), for: kept)
        session.store(record("https://b.invalid/", Data([4])), for: kept)
        session.flush()
        let relaunch = TabHistoryArchive(directory: root)
        #expect(relaunch.takeLaunchNavigation(for: kept, url: "https://b.invalid/", profileID: profile) == Data([4]))
        #expect(relaunch.takeLaunchNavigation(for: kept, url: "https://b.invalid/", profileID: profile) == nil)
    }

    @Test func aTabNowAtAnotherAddressGetsNothing() {
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = UUID()
        let session = TabHistoryArchive(directory: root)
        session.store(record("https://a.invalid/", bytes), for: moved)
        session.flush()
        let relaunch = TabHistoryArchive(directory: root)
        #expect(relaunch.takeLaunchNavigation(for: moved, url: "https://c.invalid/", profileID: profile) == nil)
    }

    @Test func aPrunedTabGetsNothing() {
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = UUID(), archived = UUID()
        let session = TabHistoryArchive(directory: root)
        session.store(record("https://a.invalid/", bytes), for: kept)
        session.store(record("https://a.invalid/", bytes), for: archived)
        session.prune(keeping: [kept])
        session.flush()
        let relaunch = TabHistoryArchive(directory: root)
        #expect(relaunch.takeLaunchNavigation(for: archived, url: "https://a.invalid/", profileID: profile) == nil)
    }

    @Test func aTabThatAlreadyHadAPageThisLaunchGetsNothing() {
        defer { try? FileManager.default.removeItem(at: root) }
        let paged = UUID()
        let session = TabHistoryArchive(directory: root)
        session.store(record("https://a.invalid/", bytes), for: paged)
        session.flush()
        let relaunch = TabHistoryArchive(directory: root)
        relaunch.pageCreated(paged)
        #expect(relaunch.takeLaunchNavigation(for: paged, url: "https://a.invalid/", profileID: profile) == nil)
    }

    @Test func aTabNowInAnotherProfileGetsNothing() {
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = UUID()
        let session = TabHistoryArchive(directory: root)
        session.store(record("https://a.invalid/", bytes), for: moved)
        session.flush()
        let relaunch = TabHistoryArchive(directory: root)
        #expect(relaunch.takeLaunchNavigation(for: moved, url: "https://a.invalid/", profileID: other) == nil)
    }

    @Test func aHistoryDeletionDropsEveryRecord() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TabHistoryArchive(directory: root)
        for _ in 0..<3 { session.store(record("https://a.invalid/", bytes), for: UUID()) }
        session.flush()
        let relaunch = TabHistoryArchive(directory: root)
        relaunch.removeAll()
        relaunch.flush()
        #expect(try names().isEmpty)
    }
}
