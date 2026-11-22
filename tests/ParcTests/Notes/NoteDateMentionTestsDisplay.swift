import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteDateMentionTestsDisplay {
    private struct RelativeDayCase: Sendable, CustomTestStringConvertible {
        let day: Int
        let expected: String

        var testDescription: String { "\(day)" }
    }

    private struct DateFormatCase: Sendable, CustomTestStringConvertible {
        let format: NoteDateFormat
        let wanted: String

        var testDescription: String { format.rawValue }
    }

    private struct ClockFormatCase: Sendable, CustomTestStringConvertible {
        let format: NoteTimeFormat?
        let wanted: String

        var testDescription: String { format?.rawValue ?? "default" }
    }

    private typealias Fixture = NoteDateMentionTestsSupport.Fixture

    private let fixture = Fixture()

    private func label(_ mention: NoteDateMention, now: Date? = Fixture.now) -> String {
        fixture.plain(NoteDateText.label(mention, now: now, calendar: Fixture.calendar, locale: Fixture.locale))
    }

    @Test func rangesReadStartToEnd() { #expect(label(fixture.rangeMention) == "January 3, 2027 \u{2192} January 5, 2027") }

    private func timedRange() -> NoteDateMention {
        var timed = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0)
        timed.end = NoteDateEnd(year: 2027, month: 1, day: 5, hour: 17, minute: 30)
        return timed
    }

    @Test func bothEndsShowTheirTimes() { #expect(label(timedRange()) == "January 3, 2027 9:00 AM \u{2192} January 5, 2027 5:30 PM") }

    @Test func aSameDayRangeNamesTheDayOnce() {
        var timed = timedRange()
        timed.end = NoteDateEnd(year: 2027, month: 1, day: 3, hour: 17, minute: 30)
        #expect(label(timed) == "January 3, 2027 9:00 AM \u{2192} 5:30 PM")
    }

    @Test(arguments: [
        RelativeDayCase(day: 20, expected: "Today"),
        RelativeDayCase(day: 21, expected: "Tomorrow"),
        RelativeDayCase(day: 19, expected: "Yesterday"),
        RelativeDayCase(day: 25, expected: "November 25, 2026"),
    ])
    private func nearbyDaysReadInWords(sample: RelativeDayCase) {
        #expect(label(NoteDateMention(year: 2026, month: 11, day: sample.day)) == sample.expected)
    }

    @Test func relativeWordsTurnAbsoluteAsTimePasses() {
        #expect(label(NoteDateMention(year: 2026, month: 11, day: 20), now: fixture.at(2026, 11, 22, 8)) == "November 20, 2026")
    }

    @Test func exportsNeverSayToday() { #expect(label(NoteDateMention(year: 2026, month: 11, day: 20), now: nil) == "November 20, 2026") }

    @Test func relativeWordsWorkOnBothEnds() {
        var relativeRange = NoteDateMention(year: 2026, month: 11, day: 20)
        relativeRange.end = NoteDateEnd(year: 2026, month: 11, day: 21)
        #expect(label(relativeRange) == "Today \u{2192} Tomorrow")
    }

    @Test(arguments: [
        DateFormatCase(format: NoteDateFormat.full, wanted: "November 20, 2026"),
        DateFormatCase(format: .short, wanted: "Nov 20, 2026"),
        DateFormatCase(format: .monthDayYear, wanted: "11/20/2026"),
        DateFormatCase(format: .dayMonthYear, wanted: "20/11/2026"),
        DateFormatCase(format: .yearMonthDay, wanted: "2026/11/20"),
    ])
    private func aDateFormatSpellsTheDateItsWay(sample: DateFormatCase) {
        var value = NoteDateMention(year: 2026, month: 11, day: 20)
        value.format = sample.format
        #expect(label(value) == sample.wanted)
    }

    @Test(arguments: [
        ClockFormatCase(format: NoteTimeFormat?.none, wanted: "Today 5:05 PM"),
        ClockFormatCase(format: .twentyFourHour, wanted: "Today 17:05"),
        ClockFormatCase(format: .twelveHour, wanted: "Today 5:05 PM"),
    ])
    private func theClockChoiceShapesTheTime(sample: ClockFormatCase) {
        var clock = NoteDateMention(year: 2026, month: 11, day: 20, hour: 17, minute: 5)
        clock.timeFormat = sample.format
        #expect(label(clock) == sample.wanted)
    }

    @Test func aChosenTimeZoneShowsItsName() {
        var zoned = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0)
        zoned.timeZone = "America/New_York"
        #expect(label(zoned) == "January 3, 2027 9:00 AM EST")
    }

    @Test func allDayDatesIgnoreTheZone() {
        var zoned = NoteDateMention(year: 2027, month: 1, day: 3)
        zoned.timeZone = "America/New_York"
        #expect(label(zoned) == "January 3, 2027")
    }

    @Test func zoneTitlesReadLikeCities() { #expect(NoteDateText.zoneTitle("America/Port_of_Spain") == "Port of Spain") }

    @Test func zoneOffsetsShowHalfHours() { #expect(NoteDateText.zoneOffset("Asia/Kolkata", at: Fixture.now) == "GMT+5:30") }
}
