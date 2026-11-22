import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteDateMentionTestsReminderSuggestions {
    private struct SuggestionRowCase: Sendable, CustomTestStringConvertible {
        let query: String
        let remind: Bool
        let title: String
        let wanted: String?

        var testDescription: String { "\(query) (reminder: \(remind))" }
    }

    private struct TimeReadingsCase: Sendable, CustomTestStringConvertible {
        let query: String
        let wanted: [String]

        var testDescription: String { "\(query)" }
    }

    private typealias Fixture = NoteDateMentionTestsSupport.Fixture

    private let fixture = Fixture()

    private func describe(_ mention: NoteDateMention?) -> String? {
        guard let mention else { return nil }
        var value = String(format: "%04d-%02d-%02d", mention.year, mention.month, mention.day)
        if let hour = mention.hour { value += String(format: " %02d:%02d", hour, mention.minute ?? 0) }
        if let end = mention.end {
            value += String(format: " > %04d-%02d-%02d", end.year, end.month, end.day)
            if let hour = end.hour { value += String(format: " %02d:%02d", hour, end.minute ?? 0) }
        }
        return value
    }

    private func earlyReminder() -> NoteDateMention {
        var early = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        early.remindBefore = 30
        return early
    }

    private func plans(_ mention: NoteDateMention) -> [NoteReminderPlan] {
        NoteReminderPlan.reminders(in: NotePage(blocks: [.paragraph(NoteText("Call ") + .atom(.date(mention)))]), parser: fixture.parser)
    }

    @Test func plansRingAtTheLead() { #expect(plans(earlyReminder()).first?.fireDate == fixture.at(2026, 11, 21, 15)) }

    @Test func plansKeepTheLeadInTheirKey() { #expect(plans(earlyReminder()).first?.key == "2026-11-21T15:30-30m") }

    @Test func plainRemindersKeepTheirOldKey() {
        #expect(plans(NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)).first?.key == "2026-11-21T15:30")
    }

    private func body(_ mention: NoteDateMention) -> String {
        fixture.plain(NoteReminderPlan.reminders(in: NotePage(blocks: [.paragraph(NoteText("Call Sam ") + .atom(.date(mention)))]), parser: fixture.parser).first?.body ?? "")
    }

    @Test func aNotificationNamesItsDayAsItReadsWhenItRings() {
        #expect(body(NoteDateMention(year: 2026, month: 11, day: 24, hour: 9, minute: 0, remind: true)) == "Call Sam Today 9:00 AM")
    }

    @Test func aDayEarlyNudgeSaysTomorrow() {
        var dayBefore = NoteDateMention(year: 2026, month: 11, day: 24, remind: true)
        dayBefore.remindBefore = NoteReminderLead.day
        #expect(body(dayBefore) == "Call Sam Tomorrow")
    }

    @Test func anEarlierNudgeNamesTheDateNeverABareWeekday() {
        var twoBefore = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
        twoBefore.remindBefore = 2 * NoteReminderLead.day
        #expect(body(twoBefore) == "Call Sam Thu, Dec 3")
    }

    private func nudge(_ mention: NoteDateMention) -> String { fixture.plain(fixture.parser.reminderHint(for: mention)) }

    @Test func thePickersNudgeLineDatesDaysThisWeek() {
        #expect(nudge(NoteDateMention(year: 2026, month: 11, day: 24, remind: true)) == "We’ll nudge you Tue, Nov 24 9:00 AM.")
    }

    @Test func theNudgeLineKeepsTomorrow() {
        #expect(nudge(NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)) == "We’ll nudge you Tomorrow 3:30 PM.")
    }

    @Test func theNudgeLineShowsTheYearWhenItIsNotThisYear() {
        #expect(nudge(NoteDateMention(year: 2027, month: 1, day: 3, remind: true)) == "We’ll nudge you Sun, Jan 3, 2027 9:00 AM.")
    }

    @Test func datesWithoutAReminderSayNothing() { #expect(nudge(NoteDateMention(year: 2026, month: 11, day: 24)) == "") }

    @Test func passedRemindersSaySo() {
        #expect(nudge(NoteDateMention(year: 2026, month: 11, day: 19, remind: true)) == "That moment’s passed. Pick a later one for a nudge.")
    }

    private func hint(_ mention: NoteDateMention, at moment: Date = Fixture.now) -> String? {
        NoteDateText.suggestionDateHint(mention, now: moment, calendar: Fixture.calendar, locale: Fixture.locale).map(fixture.plain)
    }

    @Test(arguments: [
        SuggestionRowCase(query: "today", remind: false, title: "Today", wanted: "Nov 20"),
        SuggestionRowCase(query: "tomorrow", remind: false, title: "Tomorrow", wanted: "Nov 21"),
        SuggestionRowCase(query: "yesterday", remind: false, title: "Yesterday", wanted: "Nov 19"),
        SuggestionRowCase(query: "nov 24", remind: false, title: "Tue, Nov 24", wanted: nil),
        SuggestionRowCase(query: "next friday", remind: false, title: "Fri, Nov 27", wanted: nil),
        SuggestionRowCase(query: "dec 3", remind: false, title: "Thu, Dec 3", wanted: nil),
        SuggestionRowCase(query: "in 2 weeks", remind: false, title: "Fri, Dec 4", wanted: nil),
        SuggestionRowCase(query: "jan 3", remind: false, title: "Sun, Jan 3, 2027", wanted: nil),
        SuggestionRowCase(query: "nov 24", remind: true, title: "Tue, Nov 24 9:00 AM", wanted: nil),
        SuggestionRowCase(query: "nov 29", remind: true, title: "Sun, Nov 29 9:00 AM", wanted: nil),
        SuggestionRowCase(query: "tomorrow", remind: true, title: "Tomorrow 9:00 AM", wanted: "Nov 21"),
        SuggestionRowCase(query: "nov 24 - 26", remind: false, title: "Tue, Nov 24 \u{2192} Thu, Nov 26", wanted: nil),
        SuggestionRowCase(query: "today until monday", remind: false, title: "Today \u{2192} Mon, Nov 23", wanted: "Nov 20"),
        SuggestionRowCase(query: "tomorrow 3pm - 5pm", remind: false, title: "Tomorrow 3:00 PM \u{2192} 5:00 PM", wanted: "Nov 21"),
        SuggestionRowCase(query: "jan 3 - 5", remind: false, title: "Sun, Jan 3, 2027 \u{2192} Tue, Jan 5, 2027", wanted: nil),
    ])
    private func aSuggestionRowShowsItsTitleAndTheDateBesideIt(sample: SuggestionRowCase) throws {
        let first = try #require(fixture.parser.suggestions(for: sample.query, remind: sample.remind).first)
        #expect(fixture.plain(first.title) == sample.title)
        #expect(hint(first.mention) == sample.wanted)
    }

    @Test func aRangeOfTwoNamedDaysDatesBothEnds() {
        var both = NoteDateMention(year: 2026, month: 11, day: 20)
        both.end = NoteDateEnd(year: 2026, month: 11, day: 21)
        #expect(hint(both) == "Nov 20 – 21")
    }

    @Test func tomorrowInAnotherYearShowsTheYear() {
        #expect(hint(NoteDateMention(year: 2027, month: 1, day: 1), at: fixture.at(2026, 12, 31, 10)) == "Jan 1, 2027")
    }

    private var evening: NoteDateParser { NoteDateParser(now: fixture.at(2026, 11, 20, 20, 31), calendar: Fixture.calendar, dayFirst: false, locale: Fixture.locale) }

    @Test func aReminderForThisMinuteCannotBeSet() {
        #expect(evening.suggestions(for: "today 8:31pm", remind: true).isEmpty)
    }

    @Test func aPassedReminderIsStillRecognisedAndNamed() {
        let passed = evening.passedReminder(for: "today 8:31pm")
        #expect(describe(passed?.mention) == "2026-11-20 20:31")
        #expect(passed.map { fixture.plain($0.title) } == "Today 8:31 PM")
    }

    @Test func earlierDaysHavePassedToo() {
        #expect(describe(evening.passedReminder(for: "nov 19 3pm")?.mention) == "2026-11-19 15:00")
    }

    @Test(arguments: ["today 9pm", "banana"]) func laterTodayAndNonsenseHaveNotPassed(query: String) {
        #expect(evening.passedReminder(for: query) == nil)
    }

    private func morningParser() -> NoteDateParser { fixture.parser }

    private func lateParser() -> NoteDateParser { NoteDateParser(now: fixture.at(2026, 11, 20, 20, 33), calendar: Fixture.calendar, dayFirst: false, locale: Fixture.locale) }

    private func offers(_ parser: NoteDateParser, _ query: String, remind: Bool = false) -> [String?] {
        parser.suggestions(for: query, remind: remind).map { describe($0.mention) }
    }

    @Test(arguments: ["nov 20th 8:40", "8:40", "at 8:40"])
    func lateInTheEveningOnlyTheReadingStillAheadIsOffered(query: String) {
        #expect(offers(lateParser(), query, remind: true) == ["2026-11-20 20:40"])
    }

    @Test(arguments: [
        TimeReadingsCase(query: "nov 21 8:40", wanted: ["2026-11-21 08:40", "2026-11-21 20:40"]),
        TimeReadingsCase(query: "11:15", wanted: ["2026-11-20 11:15", "2026-11-20 23:15"]),
        TimeReadingsCase(query: "tomorrow at 7", wanted: ["2026-11-21 07:00", "2026-11-21 19:00"]),
    ])
    private func anAmbiguousTimeOffersBothReadingsNearestFirstWhenReminding(sample: TimeReadingsCase) {
        #expect(offers(morningParser(), sample.query, remind: true) == sample.wanted)
    }

    @Test func asADateTheUpcomingReadingComesFirst() {
        #expect(offers(lateParser(), "8:40") == ["2026-11-20 20:40", "2026-11-20 08:40"])
    }

    @Test(arguments: [
        TimeReadingsCase(query: "12:30", wanted: ["2026-11-20 12:30", "2026-11-20 00:30"]),
        TimeReadingsCase(query: "13:00", wanted: ["2026-11-20 13:00"]),
        TimeReadingsCase(query: "0:30", wanted: ["2026-11-20 00:30"]),
        TimeReadingsCase(query: "8:40pm", wanted: ["2026-11-20 20:40"]),
        TimeReadingsCase(query: "8:40 am", wanted: ["2026-11-20 08:40"]),
        TimeReadingsCase(query: "tomorrow at noon", wanted: ["2026-11-21 12:00"]),
        TimeReadingsCase(query: "nov 21 8:00 - 9:30", wanted: ["2026-11-21 08:00 > 2026-11-21 09:30", "2026-11-21 20:00 > 2026-11-21 21:30"]),
        TimeReadingsCase(query: "11:00 - 1:00", wanted: ["2026-11-20 11:00 > 2026-11-20 13:00"]),
        TimeReadingsCase(query: "3:00-5:00pm", wanted: ["2026-11-20 15:00 > 2026-11-20 17:00"]),
        TimeReadingsCase(query: "nov 21 8:40 - 23", wanted: ["2026-11-21 08:40 > 2026-11-23 08:40", "2026-11-21 20:40 > 2026-11-23 20:40"]),
    ])
    private func meridiemsSettleOrLeaveBothReadings(sample: TimeReadingsCase) {
        #expect(offers(morningParser(), sample.query) == sample.wanted)
    }

    @Test func aRangeAlreadyOverHasNothingToRemind() { #expect(offers(lateParser(), "8:00 - 9:30", remind: true).isEmpty) }

    @Test func everyReadingPassedNamesTheLatest() {
        #expect(describe(lateParser().passedReminder(for: "today 8:31")?.mention) == "2026-11-20 20:31")
    }

    @Test func oneReadingAheadMeansNothingHasPassed() { #expect(lateParser().passedReminder(for: "nov 20 8:40") == nil) }
}
