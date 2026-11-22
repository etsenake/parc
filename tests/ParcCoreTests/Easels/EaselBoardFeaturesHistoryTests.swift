import Foundation
import Testing
@testable import ParcCore

struct EaselBoardFeaturesHistoryTests {
    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 700_000_000)
    }

    @Test
    func versionFileNamesRoundTripTheirTimeAndObjectCount() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let name = EaselHistory.fileName(savedAt: date, itemCount: 12)
        #expect(name == "v-1700000000123-12.json", "version files carry their time and object count")
        let parsed = EaselHistory.parse(name)
        #expect(parsed?.itemCount == 12 && parsed.map { abs($0.savedAt.timeIntervalSince1970 - 1_700_000_000.123) < 0.001 } == true,
               "version names read back")
    }

    @Test
    func strayAndMalformedVersionFileNamesAreIgnored() {
        #expect(EaselHistory.parse("v-1-2.json.tmp") == nil && EaselHistory.parse("../v-1-2.json") == nil, "stray files are ignored")
        #expect(EaselHistory.parse("v--1-2.json") == nil && EaselHistory.parse("v-x-2.json") == nil, "malformed names are ignored")
    }

    @Test
    func anOutOfRangeSaveTimeStillProducesAReadableVersionName() {
        let far = EaselHistory.fileName(savedAt: Date(timeIntervalSinceReferenceDate: 1e300), itemCount: 3)
        #expect(EaselHistory.parse(far)?.itemCount == 3, "a damaged far-future save time still names a readable version instead of crashing")
    }

    @Test
    func versionPolicyKeepsTheNewestVersionsThatFit() {
        var policy = EaselHistoryPolicy()
        policy.maximumVersions = 3
        policy.maximumBytes = 250
        let versions = (0..<5).map { (version: EaselVersion(id: "v\($0)", savedAt: Date(timeIntervalSince1970: Double($0)), itemCount: 0), bytes: 100) }
        #expect(Set(policy.expired(versions).map(\.id)) == ["v0", "v1", "v2"], "only the newest versions that fit the caps stay")
    }

    @Test
    func versionPolicyKeepsTheNewestEvenWhenItExceedsTheByteCap() {
        var policy = EaselHistoryPolicy()
        policy.maximumVersions = 3
        policy.maximumBytes = 250
        let huge = [(version: EaselVersion(id: "big", savedAt: Date(), itemCount: 0), bytes: 10_000)]
        #expect(policy.expired(huge).isEmpty, "the newest version stays even when it alone passes the size cap")
    }

    @Test
    func versionsRecordAtTheFirstChangeAndFiveMinuteIntervals() {
        let policy = EaselHistoryPolicy()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(policy.shouldRecord(lastRecordedAt: nil, now: start), "the first change always records")
        #expect(!policy.shouldRecord(lastRecordedAt: start, now: start.addingTimeInterval(299)), "changes within five minutes share a snapshot")
        #expect(policy.shouldRecord(lastRecordedAt: start, now: start.addingTimeInterval(300)), "five minutes later a new snapshot is due")
    }

    @MainActor @Test func versionsRecordTheEaselAsItWasAndLoadBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-history-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        do {
            let store = try EaselStore(directory: root, now: { clock.now })
            EaselHistories.attach(to: store)
            let session = try store.create(title: "Board")
            let id = session.document.id
            let history = try #require(EaselHistories.history(for: id), "attached stores keep a history")
            try session.perform("Add") { $0.items.append(EaselBoardFeaturesTestsSupport.item(.sticky, "one", x: 0, y: 0)) }
            clock.now.addTimeInterval(60)
            try session.perform("Edit") { $0.items[0].text = "two" }
            var versions = history.versions(of: id)
            #expect(versions.count == 1 && versions.first?.itemCount == 0, "the first change keeps the Easel as it was when opened")
            clock.now.addTimeInterval(400)
            try session.perform("Add more") { $0.items.append(EaselBoardFeaturesTestsSupport.item(.text, "three", x: 0, y: 300)) }
            versions = history.versions(of: id)
            #expect(versions.count == 2 && versions.first?.itemCount == 2, "five minutes on, the current state is kept too")
            let oldest = try history.document(versions[versions.count - 1], of: id)
            #expect(oldest.items.isEmpty && oldest.id == id, "versions load back as whole documents")
            #expect(!history.record(session.document, savedAt: clock.now, wait: true), "identical content is never stored twice")
            try store.delete(id)
            #expect(history.versions(of: id).isEmpty, "deleting an Easel deletes its history")
        } catch {
            Issue.record("history recording failed: \(error)")
        }
    }
}
