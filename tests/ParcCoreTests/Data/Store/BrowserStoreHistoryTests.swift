import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreHistoryTests {
    @MainActor
    private struct HistoryFileFixture {
        let directory: URL
        let store: BrowserStore
        let legacyVisit: BrowserHistoryEntry
        let tab: UUID
        let clock: Clock

        final class Clock {
            var date = Date(timeIntervalSince1970: 2_000)
        }

        var session: URL { directory.appendingPathComponent("session.json") }
        var history: URL { directory.appendingPathComponent("history.jsonl") }

        func records() throws -> Int {
            try Data(contentsOf: history).split(separator: UInt8(ascii: "\n")).count
        }

        func inode() throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: history.path)[.systemFileNumber] as? NSNumber)?.intValue ?? -1
        }

        func addVisit() throws {
            clock.date = Date(timeIntervalSince1970: 3_000)
            store.updateTab(tab, title: "B", url: "https://split.test/b")
            try store.save()
        }

        func retitleVisit() throws {
            store.updateTab(tab, title: "B retitled", url: "https://split.test/b")
            try store.save()
        }

        func deleteLegacyVisit() throws {
            store.deleteHistory([legacyVisit.id], profileID: legacyVisit.profileID)
            try store.save()
        }

        func writeInlineVisit() throws -> BrowserHistoryEntry {
            var state = try BrowserStoreHistoryTests.decoder().decode(BrowserState.self, from: Data(contentsOf: session))
            let newer = BrowserHistoryEntry(id: UUID(), url: "https://older-build.test/", title: "Inline",
                                            visitedAt: Date(timeIntervalSince1970: 4_000), profileID: legacyVisit.profileID)
            state.history = [newer]
            try BrowserStoreHistoryTests.encoder().encode(state).write(to: session)
            return newer
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func seedInlineHistory(in directory: URL) throws -> BrowserHistoryEntry {
        var legacy = BrowserState.initial()
        let old = BrowserHistoryEntry(id: UUID(), url: "https://legacy.test/", title: "Legacy",
                                      visitedAt: Date(timeIntervalSince1970: 1_000), profileID: legacy.profiles[0].id)
        legacy.history = [old]
        try encoder().encode(legacy).write(to: directory.appendingPathComponent("session.json"))
        return old
    }

    private static func withHistoryFile(_ body: (HistoryFileFixture) throws -> Void) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let old = try seedInlineHistory(in: directory)
            let clock = HistoryFileFixture.Clock()
            let store = try BrowserStore(directory: directory, now: { clock.date })
            let tab = store.openResolvedURL(URL(string: "https://split.test/a")!, kind: .today)
            store.updateTab(tab, title: "A", url: "https://split.test/a")
            try store.save()
            try body(HistoryFileFixture(directory: directory, store: store, legacyVisit: old, tab: tab, clock: clock))
        }
    }

    @Test static func aLegacySessionLoadsItsInlineHistory() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let old = try seedInlineHistory(in: directory)
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000) })
            #expect(store.state.history == [old], "An inline legacy history loads")
        }
    }

    @Test static func aSaveMovesInlineHistoryIntoTheHistoryFile() throws {
        try withHistoryFile { fixture in
            let inline = try decoder().decode(BrowserState.self, from: Data(contentsOf: fixture.session))
            #expect(try inline.history.isEmpty && BrowserHistoryFile.decode(try Data(contentsOf: fixture.history)) == fixture.store.state.history
                    && fixture.store.state.history.first == fixture.legacyVisit, "The next save moves every visit into history.jsonl")
        }
    }

    @Test static func navigationAppendsOneRecordWithoutReplacingTheHistoryFile() throws {
        try withHistoryFile { fixture in
            let beforeVisit = try Data(contentsOf: fixture.history)
            let beforeRecords = try fixture.records()
            let file = try fixture.inode()
            try fixture.addVisit()
            let afterVisit = try Data(contentsOf: fixture.history)
            #expect(try afterVisit.starts(with: beforeVisit) && (try fixture.records()) == beforeRecords + 1 && (try fixture.inode()) == file, "A navigation appends one record to the same file and leaves the existing bytes")
        }
    }

    @Test static func retitlingAppendsARecordThatReplacesThePreviousVisitInPlace() throws {
        try withHistoryFile { fixture in
            let beforeRecords = try fixture.records()
            try fixture.addVisit()
            let afterVisit = try Data(contentsOf: fixture.history)
            try fixture.retitleVisit()
            #expect(try (try Data(contentsOf: fixture.history)).starts(with: afterVisit) && (try fixture.records()) == beforeRecords + 2, "Retitling the newest visit appends its new record")
            #expect(BrowserHistoryFile.decode(try Data(contentsOf: fixture.history)) == fixture.store.state.history, "The later record for a visit replaces the earlier one in place")
        }
    }

    @Test static func savingOnlySettingsLeavesTheHistoryFileUntouched() throws {
        try withHistoryFile { fixture in
            let file = try fixture.inode()
            try fixture.addVisit()
            try fixture.retitleVisit()
            let settled = try Data(contentsOf: fixture.history)
            fixture.store.updateSettings { $0.sidebarWidth = 310 }
            try fixture.store.save()
            #expect(try Data(contentsOf: fixture.history) == settled && (try fixture.inode()) == file, "A settings-only save leaves the history file untouched")
        }
    }

    @Test static func appendedHistoryAndItsRetitledVisitSurviveRestart() throws {
        try withHistoryFile { fixture in
            try fixture.addVisit()
            try fixture.retitleVisit()
            let reopened = try BrowserStore(directory: fixture.directory)
            #expect(reopened.state.history == fixture.store.state.history, "Appended records round-trip")
        }
    }

    @Test static func deletingTheOldestVisitRewritesTheHistoryFile() throws {
        try withHistoryFile { fixture in
            let file = try fixture.inode()
            try fixture.addVisit()
            try fixture.retitleVisit()
            let retitled = fixture.store.state.history
            try fixture.deleteLegacyVisit()
            #expect(try (try fixture.records()) == retitled.count - 1 && (try fixture.inode()) != file
                    && BrowserHistoryFile.decode(try Data(contentsOf: fixture.history)) == Array(retitled.dropFirst()), "Deleting the oldest visit rewrites the file instead of letting it return")
        }
    }

    @Test static func anIncompleteHistoryAppendIsIgnored() throws {
        try withHistoryFile { fixture in
            try fixture.addVisit()
            try fixture.retitleVisit()
            try fixture.deleteLegacyVisit()
            var torn = try Data(contentsOf: fixture.history)
            torn.append(Data("{\"id\":".utf8))
            try torn.write(to: fixture.history)
            #expect(BrowserHistoryFile.decode(torn) == fixture.store.state.history, "An append cut short is ignored")
        }
    }

    @Test static func inlineVisitsFromAnOlderVersionMergeAfterHistoryFileVisits() throws {
        try withHistoryFile { fixture in
            try fixture.addVisit()
            try fixture.retitleVisit()
            try fixture.deleteLegacyVisit()
            let newer = try fixture.writeInlineVisit()
            let merged = try BrowserStore(directory: fixture.directory)
            #expect(merged.state.history == fixture.store.state.history + [newer], "Visits an older build kept inline merge after the history file's visits")
        }
    }

    private static func withDamagedHistory(_ body: (HistoryFileFixture, BrowserStore, [BrowserHistoryEntry]) throws -> Void) throws {
        try withHistoryFile { fixture in
            try fixture.addVisit()
            try fixture.retitleVisit()
            try fixture.deleteLegacyVisit()
            let kept = try #require(fixture.store.state.history.first)
            let newer = try fixture.writeInlineVisit()
            var damaged = Data("not json\n".utf8)
            damaged.append(try BrowserHistoryFile.encode([kept]))
            try damaged.write(to: fixture.history)
            try body(fixture, BrowserStore(directory: fixture.directory), [kept, newer])
        }
    }

    @Test static func openingDamagedHistoryKeepsReadableAndInlineVisits() throws {
        try withDamagedHistory { _, recovered, expected in
            #expect(recovered.state.history == expected, "Unreadable lines are skipped, readable visits kept")
        }
    }

    @Test static func savingDamagedHistoryRewritesOnlyTheReadableVisits() throws {
        try withDamagedHistory { fixture, recovered, _ in
            try recovered.save()
            #expect((try fixture.records()) == 2, "The next write rewrites the file without the unreadable line")
        }
    }

    @Test static func clearingHistoryEmptiesTheHistoryFile() throws {
        try withDamagedHistory { fixture, recovered, _ in
            try recovered.save()
            recovered.clearHistory(profileID: fixture.legacyVisit.profileID)
            try recovered.save()
            #expect(try recovered.state.history.isEmpty && (try Data(contentsOf: fixture.history)).isEmpty, "Clearing history empties the history file")
        }
    }

    @Test static func aPrivateStoreNeverWritesAHistoryFile() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let normal = try BrowserStore(directory: directory)
            let parent = normal.activeSpace.profileID
            let privateStore = BrowserStore(privateParentProfileID: parent, engineProfilePath: "/tmp/parc-private-test",
                                            directory: directory, settings: normal.state.settings)
            let tab = privateStore.openResolvedURL(URL(string: "https://private.test/")!, kind: .today)
            privateStore.updateTab(tab, title: "Private", url: "https://private.test/next")
            try privateStore.save()
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(BrowserHistoryFile.name).path), "A private store never writes a history file")
        }
    }

    @Test static func aHistoryFileWithoutRecognizedRecordsIsPreserved() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let history = directory.appendingPathComponent(BrowserHistoryFile.name)
            let unknown = Data("{\"format\":2}\n".utf8)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(BrowserState.initial()).write(to: directory.appendingPathComponent("session.json"))
            try unknown.write(to: history)
            let store = try BrowserStore(directory: directory)
            let tab = store.openResolvedURL(URL(string: "https://future.test/")!, kind: .today)
            store.updateTab(tab, title: "Next", url: "https://future.test/next")
            try store.save()
            #expect(try !store.state.history.isEmpty && (try Data(contentsOf: history)) == unknown, "A history file with no readable records is left untouched for the session")
        }
    }


    struct HistoryChange: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let before: [Int]
        let after: [Int]
        let appended: [Int]?
    }

    @Test(arguments: [
        HistoryChange(testDescription: "New visit", before: [0, 1], after: [0, 1, 2], appended: [2]),
        HistoryChange(testDescription: "Remove oldest", before: [0, 1], after: [1, 2], appended: nil),
        HistoryChange(testDescription: "Remove middle", before: [0, 1, 2], after: [0, 2], appended: nil),
        HistoryChange(testDescription: "Remove newest", before: [0, 1, 2], after: [0, 1], appended: nil),
        HistoryChange(testDescription: "Clear history", before: [0], after: [], appended: nil),
        HistoryChange(testDescription: "First visit", before: [], after: [0], appended: [0]),
    ])
    static func historyChangesIdentifyWhichRecordsCanBeAppended(_ change: HistoryChange) {
        let visits = ["a", "b", "c"].map { title in
            BrowserHistoryEntry(id: UUID(), url: "https://x.test/", title: title,
                                visitedAt: Date(timeIntervalSince1970: 0), profileID: UUID())
        }
        #expect(BrowserHistoryFile.appended(from: change.before.map { visits[$0] }, to: change.after.map { visits[$0] })
                == change.appended?.map { visits[$0] })
    }

    @Test static func openingATabDoesNotAdvanceTheHistoryRevision() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            _ = id
            #expect(store.historyRevision == start, "Opening a tab does not fabricate history")
        }
    }

    @Test static func aNewVisitAdvancesTheHistoryRevision() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "A", url: "https://example.test/a")
            #expect(store.historyRevision == start + 1 && store.state.history.last?.url == "https://example.test/a", "A new visit advances historyRevision")
        }
    }

    @Test static func anUnchangedCoalescedTitleLeavesTheHistoryRevisionAlone() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "A", url: "https://example.test/a")
            store.updateTab(id, title: "A", url: "https://example.test/a")
            #expect(store.historyRevision == start + 1, "An unchanged coalesced title does not rewrite history")
        }
    }

    @Test static func aCoalescedTitleUpdateAdvancesTheHistoryRevision() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "A", url: "https://example.test/a")
            store.updateTab(id, title: "B", url: "https://example.test/a")
            #expect(store.historyRevision == start + 2 && store.state.history.last?.title == "B", "A coalesced title update advances historyRevision")
        }
    }

    @Test static func clearingVisitsAdvancesTheHistoryRevision() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "A", url: "https://example.test/a")
            store.updateTab(id, title: "B", url: "https://example.test/a")
            store.clearHistory()
            #expect(store.historyRevision == start + 3 && store.state.history.isEmpty, "Clearing visits advances historyRevision")
        }
    }
}
