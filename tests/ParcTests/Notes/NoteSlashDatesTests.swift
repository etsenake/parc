import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

struct NoteSlashDatesTests {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.firstWeekday = 1
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10, minute: 30))!
    let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false)

    func day(_ input: String, _ parser: NoteDateParser? = nil) -> String? {
        (parser ?? self.parser).parse(input).map { mention in
            var value = String(format: "%04d-%02d-%02d", mention.year, mention.month, mention.day)
            if let hour = mention.hour { value += String(format: " %02d:%02d", hour, mention.minute ?? 0) }
            return value
        }
    }

    func plain(_ value: String?) -> String? {
        value.map { String($0.unicodeScalars.map { $0 == "\u{202F}" || $0 == "\u{00A0}" ? " " : Character($0) }) }
    }

    @Test(arguments: [
        ("today", "2026-11-20"), ("Today", "2026-11-20"), ("@today", "2026-11-20"), ("tomorrow", "2026-11-21"), ("tmrw", "2026-11-21"),
        ("yesterday", "2026-11-19"), ("friday", "2026-11-20"), ("fri", "2026-11-20"), ("monday", "2026-11-23"), ("this sunday", "2026-11-22"),
        ("next friday", "2026-11-27"), ("next wednesday", "2026-11-25"), ("last friday", "2026-11-13"), ("coming friday", "2026-11-27"),
        ("next week", "2026-11-27"), ("next month", "2026-12-20"), ("in 3 days", "2026-11-23"), ("in two weeks", "2026-12-04"),
        ("2 weeks ago", "2026-11-06"), ("3 days from now", "2026-11-23"),
    ])
    func relativeDaysParse(input: String, expected: String) { #expect(day(input) == expected) }

    @Test(arguments: [
        ("dec 3", "2026-12-03"), ("Dec 3, 2027", "2027-12-03"), ("december 3rd", "2026-12-03"), ("3 dec", "2026-12-03"),
        ("3rd of december", "2026-12-03"), ("sept 9", "2026-09-09"), ("2026-12-03", "2026-12-03"), ("2026/12/3", "2026-12-03"),
        ("12/3", "2026-12-03"), ("12/3/27", "2027-12-03"), ("3.12.2026", "2026-12-03"),
    ])
    func calendarDatesParse(input: String, expected: String) { #expect(day(input) == expected) }

    @Test func dayFirstReadsTwelveSlashThreeAsTheTwelfthOfMarch() {
        #expect(day("12/3", NoteDateParser(now: Self.now, calendar: Self.calendar, dayFirst: true)) == "2027-03-12")
    }

    @Test(arguments: [
        ("3pm", "2026-11-20 15:00"), ("3 pm", "2026-11-20 15:00"), ("at 3:45pm", "2026-11-20 15:45"), ("15:00", "2026-11-20 15:00"),
        ("noon", "2026-11-20 12:00"), ("midnight", "2026-11-20 00:00"), ("12am", "2026-11-20 00:00"), ("12pm", "2026-11-20 12:00"),
        ("tomorrow 3pm", "2026-11-21 15:00"), ("3pm tomorrow", "2026-11-21 15:00"), ("tomorrow at 9", "2026-11-21 09:00"),
        ("next friday at 9:30am", "2026-11-27 09:30"), ("dec 3 5pm", "2026-12-03 17:00"), ("2026-12-03 14:00", "2026-12-03 14:00"),
        ("in 2 hours", "2026-11-20 12:30"), ("in an hour", "2026-11-20 11:30"), ("in 45 minutes", "2026-11-20 11:15"),
        ("tonight", "2026-11-20 20:00"),
    ])
    func timesParse(input: String, expected: String) { #expect(day(input) == expected) }

    @Test(arguments: ["", "banana", "feb 30", "13/45", "25pm", "13pm", "tomorrow 9", "3 days", "march"])
    func nonDatesDoNotParse(input: String) { #expect(day(input) == nil) }

    @Test func anEmptyDateQueryOffersTodayTomorrowAndYesterday() {
        #expect(parser.suggestions(for: "").map(\.title) == ["Today", "Tomorrow", "Yesterday"])
    }

    @Test func tNarrowsToTodayAndTomorrow() { #expect(parser.suggestions(for: "t").map(\.title) == ["Today", "Tomorrow"]) }

    @Test func nextFCompletesToNextFriday() {
        #expect(parser.suggestions(for: "next f").contains { $0.mention.day == 27 && $0.mention.month == 11 })
    }

    @Test func aBareMonthOffersItsFirstDay() {
        #expect(parser.suggestions(for: "dec").first.map { $0.mention.month == 12 && $0.mention.day == 1 } == true)
    }

    @Test func parsedDatesReadNaturally() {
        #expect(plain(parser.suggestions(for: "dec 3 5pm").first?.title) == "Thu, Dec 3 5:00 PM")
    }

    @Test func datesThisWeekShowTheirDate() { #expect(parser.suggestions(for: "monday").first?.title == "Mon, Nov 23") }

    @Test func nonsenseSuggestsNothing() { #expect(parser.suggestions(for: "zzz").isEmpty) }

    @Test func remindersWithoutATimeRingAtNineAM() {
        #expect(parser.suggestions(for: "tomorrow", remind: true).first?.mention
                == NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true))
    }

    @Test func aNineAMReminderSaysSo() {
        #expect(plain(parser.suggestions(for: "tomorrow", remind: true).first?.title) == "Tomorrow 9:00 AM")
    }

    @Test func aReminderForTodayAfterNineRingsNextHour() {
        let reminder = parser.reminderVersion(of: NoteDateMention(year: 2026, month: 11, day: 20))
        #expect(reminder.hour == 11)
        #expect(reminder.minute == 0)
    }

    @Test func remindersNeverGoOffInThePast() { #expect(parser.suggestions(for: "yesterday", remind: true).isEmpty) }

    @Test func anEmptyReminderQueryOffersTodayAndTomorrow() {
        let defaults = parser.suggestions(for: "", remind: true)
        #expect(defaults.count == 2)
        #expect(defaults.allSatisfy { $0.mention.remind })
    }

    @Test func timedRemindersKeepTheirTime() { #expect(parser.suggestions(for: "3pm", remind: true).first?.mention.hour == 15) }

    @Test(arguments: [("remind me tomorrow", "tomorrow", true), ("reminder dec 3", "dec 3", true), ("rem", "", true),
                      ("re", "re", false), ("tomorrow", "tomorrow", false)] as [(String, String, Bool)])
    func reminderQueriesStripTheirPrefix(input: String, query: String, remind: Bool) {
        let parsed = NoteDateParser.reminderQuery(input)
        #expect(parsed.remind == remind)
        if remind { #expect(parsed.query == query) }
    }

    @Test(arguments: ["dec", "next fri", "dec 3 at 5", "tomo"])
    func aDateOnItsWayIsAPlausiblePrefix(input: String) { #expect(parser.isPlausiblePrefix(input)) }

    @Test(arguments: ["banana split", "tomo "])
    func fruitAndHalfAWordFollowedByASpaceAreNot(input: String) { #expect(!parser.isPlausiblePrefix(input)) }

    @Test func allDayRemindersFireAtNineAM() {
        let fire = parser.fireDate(for: NoteDateMention(year: 2026, month: 12, day: 3, remind: true))
        #expect(fire == Self.calendar.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 9)))
    }

    @Test func otherYearsShowTheWeekdayDateAndYear() {
        let label = NoteDateFormatting.label(NoteDateMention(year: 2027, month: 1, day: 2), now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(plain(label) == "Sat, Jan 2, 2027")
    }

    @Test func longLabelsSpellEverythingOut() {
        let long = NoteDateFormatting.longLabel(NoteDateMention(year: 2026, month: 12, day: 3, hour: 17, minute: 5), calendar: Self.calendar,
                                                locale: Locale(identifier: "en_US"))
        #expect(plain(long) == "Thursday, December 3, 2026 5:05 PM")
    }
}
