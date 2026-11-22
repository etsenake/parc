import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsHistoryTests {
    struct History: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let reason: NotePageHistoryReason
        let current: String
        let lastRecorded: String?
        let lastRecordedAt: Date?
        let expected: Bool
        let elapsed: TimeInterval
    }

    private static let histories: [History] = {
        let start = Date(timeIntervalSince1970: 1_000_000)
        return [
            History(testDescription: "the first save is always worth keeping", reason: .save, current: "a", lastRecorded: nil, lastRecordedAt: nil, expected: true, elapsed: 0),
            History(testDescription: "trailing whitespace alone isn't a new version", reason: .close, current: "a\n", lastRecorded: "a", lastRecordedAt: start, expected: false, elapsed: 0),
            History(testDescription: "saves within a few minutes wait", reason: .save, current: "ab", lastRecorded: "a", lastRecordedAt: start, expected: false, elapsed: 60),
            History(testDescription: "a save after five minutes records", reason: .save, current: "ab", lastRecorded: "a", lastRecordedAt: start, expected: true, elapsed: 301),
            History(testDescription: "going idle records right away", reason: .idle, current: "ab", lastRecorded: "a", lastRecordedAt: start, expected: true, elapsed: 10),
            History(testDescription: "closing records any real change", reason: .close, current: "ab", lastRecorded: "a", lastRecordedAt: start, expected: true, elapsed: 0),
            History(testDescription: "an unchanged page never records", reason: .idle, current: "a", lastRecorded: "a", lastRecordedAt: start, expected: false, elapsed: 999),
        ]
    }()

    @Test(arguments: histories) func pageHistoryRecordsChangesAtTheExpectedMoments(_ example: History) {
        let policy = NotePageHistoryPolicy()
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(policy.shouldRecord(example.reason, current: example.current, lastRecorded: example.lastRecorded,
                                    lastRecordedAt: example.lastRecordedAt, now: start.addingTimeInterval(example.elapsed)) == example.expected)
    }

    @Test func aRecentlyEditedNoteSaysJustNow() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        #expect(NoteRelativeTime.edited(now.addingTimeInterval(-10), now: now) == "Edited just now", "seconds ago is just now")
    }

    @Test func anUnsavedNoteHasNoEditedDate() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        #expect(NoteRelativeTime.edited(nil, now: now) == "Not saved yet", "no date means not saved")
    }

    @Test func aNoteEditedMinutesAgoUsesARelativeTime() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let minutes = NoteRelativeTime.edited(now.addingTimeInterval(-180), now: now)
        #expect(minutes.hasPrefix("Edited ") && minutes.contains("3"), "minutes read as a relative phrase (got \(minutes))")
    }
}
