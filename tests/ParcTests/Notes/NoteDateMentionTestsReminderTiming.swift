import Foundation
import Testing
@testable import ParcCore

struct NoteDateMentionTestsReminderTiming {
    private struct LeadTokenCase: Sendable, CustomTestStringConvertible {
        let lead: Int
        let token: String

        var testDescription: String { "\(lead)" }
    }

    private typealias Fixture = NoteDateMentionTestsSupport.Fixture

    private let fixture = Fixture()

    private var timedReminder: NoteDateMention { NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true) }

    @Test func aTimedReminderRingsAtTheEvent() { #expect(timedReminder.reminderDate(in: Fixture.calendar) == fixture.at(2026, 11, 21, 15, 30)) }

    @Test func aReminderCanRingThirtyMinutesEarly() {
        var early = timedReminder
        early.remindBefore = 30
        #expect(early.reminderDate(in: Fixture.calendar) == fixture.at(2026, 11, 21, 15))
    }

    @Test func aReminderCanRingOneDayEarly() {
        var early = timedReminder
        early.remindBefore = 1440
        #expect(early.reminderDate(in: Fixture.calendar) == fixture.at(2026, 11, 20, 15, 30))
    }

    @Test func allDayRemindersRingAtNineAM() {
        #expect(NoteDateMention(year: 2026, month: 12, day: 3, remind: true).reminderDate(in: Fixture.calendar) == fixture.at(2026, 12, 3, 9))
    }

    @Test func aWeekBeforeAtNineAM() {
        var weekBefore = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
        weekBefore.remindBefore = NoteReminderLead.week
        #expect(weekBefore.reminderDate(in: Fixture.calendar) == fixture.at(2026, 11, 26, 9))
    }

    @Test func dayLeadsKeepNineAMAcrossAClockChange() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var acrossDST = NoteDateMention(year: 2026, month: 11, day: 2, remind: true)
        acrossDST.remindBefore = NoteReminderLead.day
        #expect(acrossDST.reminderDate(in: newYork) == fixture.at(2026, 11, 1, 9, in: newYork))
    }

    private func zonedReminder() -> NoteDateMention {
        var zoned = NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true)
        zoned.timeZone = "America/New_York"
        return zoned
    }

    @Test func zonedTimesRingAtThatZonesMoment() { #expect(zonedReminder().reminderDate(in: Fixture.calendar) == fixture.at(2026, 11, 21, 14)) }

    @Test func zonedTimesStartThere() { #expect(zonedReminder().startDate(in: Fixture.calendar) == fixture.at(2026, 11, 21, 14)) }

    @Test func aReminderTurnsDueOnceItsDayArrives() {
        #expect(NoteDateMention(year: 2026, month: 11, day: 20, hour: 18, minute: 0, remind: true).isDue(now: Fixture.now, calendar: Fixture.calendar))
    }

    @Test func tomorrowIsNotDue() {
        #expect(!NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true).isDue(now: Fixture.now, calendar: Fixture.calendar))
    }

    @Test func aReminderThatAlreadyRangIsDue() {
        var heads = NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true)
        heads.remindBefore = NoteReminderLead.day
        #expect(heads.isDue(now: Fixture.now, calendar: Fixture.calendar))
    }

    @Test func pastDatesAreOverdue() { #expect(NoteDateMention(year: 2026, month: 11, day: 1).isDue(now: Fixture.now, calendar: Fixture.calendar)) }

    @Test func redrawWhenAReminderRings() {
        let rings = NoteDateMention(year: 2026, month: 11, day: 20, hour: 15, minute: 0, remind: true)
        #expect(NoteDateText.nextChange(of: [rings], after: Fixture.now, calendar: Fixture.calendar) == fixture.at(2026, 11, 20, 15))
    }

    @Test func redrawAtMidnightWhenTheWordsChange() {
        #expect(NoteDateText.nextChange(of: [NoteDateMention(year: 2026, month: 12, day: 1)], after: Fixture.now, calendar: Fixture.calendar) == fixture.at(2026, 11, 21))
    }

    @Test func noDatesNoRedraws() { #expect(NoteDateText.nextChange(of: [], after: Fixture.now, calendar: Fixture.calendar) == nil) }

    @Test func anEndBeforeItsStartIsOutOfOrder() {
        var ordered = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 0)
        ordered.end = NoteDateEnd(year: 2026, month: 11, day: 20, hour: 8, minute: 0)
        #expect(!ordered.isOrdered(in: Fixture.calendar))
    }

    @Test func timedReminderChoicesReadInOrder() {
        #expect(NoteReminderLead.timed.map { NoteReminderLead.title($0, allDay: false, locale: Fixture.locale) }
                == ["At time of event", "5 minutes before", "10 minutes before", "15 minutes before", "30 minutes before",
                    "1 hour before", "2 hours before", "1 day before", "2 days before"])
    }

    @Test func allDayReminderChoicesReadInOrder() {
        #expect(NoteReminderLead.allDay.map { fixture.plain(NoteReminderLead.title($0, allDay: true, locale: Fixture.locale)) }
                == ["On day of event (9:00 AM)", "1 day before (9:00 AM)", "2 days before (9:00 AM)", "1 week before (9:00 AM)"])
    }

    @Test func theRingTimeFollowsTheClockChoice() {
        #expect(NoteReminderLead.title(0, allDay: true, timeFormat: .twentyFourHour, locale: Fixture.locale) == "On day of event (09:00)")
    }

    private static let leads = Array(Set(NoteReminderLead.timed + NoteReminderLead.allDay).filter { $0 > 0 }).sorted()

    @Test(arguments: NoteDateMentionTestsReminderTiming.leads)
    func aLeadSurvivesItsToken(lead: Int) { #expect(NoteReminderLead.lead(fromToken: NoteReminderLead.token(lead)) == lead) }

    @Test(arguments: [
        LeadTokenCase(lead: 30, token: "30m"),
        LeadTokenCase(lead: 120, token: "2h"),
        LeadTokenCase(lead: 2880, token: "2d"),
        LeadTokenCase(lead: 10080, token: "1w"),
    ])
    private func tokensUseTheBiggestUnit(sample: LeadTokenCase) { #expect(NoteReminderLead.token(sample.lead) == sample.token) }

    @Test func oddMinutesRead() { #expect(NoteReminderLead.lead(fromToken: "90m") == 90) }

    @Test func oddMinutesReadOut() { #expect(NoteReminderLead.span(90) == "90 minutes") }

    @Test(arguments: ["1y", "m"]) func badTokensAreRefused(token: String) { #expect(NoteReminderLead.lead(fromToken: token) == nil) }

    @Test func aLeadOutsideTheListFallsBackToTheEvent() { #expect(NoteReminderLead.fitting(45, allDay: false) == 0) }

    @Test func aLeadInTheListStays() { #expect(NoteReminderLead.fitting(1440, allDay: true) == 1440) }
}
