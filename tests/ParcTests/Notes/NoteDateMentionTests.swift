import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteDateMentionTests {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.firstWeekday = 1
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }()

    static let locale = Locale(identifier: "en_US")
    static let now = at(2026, 11, 20, 10, 30)

    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar = calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar = Self.calendar) -> Date {
        Self.at(year, month, day, hour, minute, in: calendar)
    }

    func plain(_ value: String) -> String {
        String(value.unicodeScalars.map { $0 == "\u{202F}" || $0 == "\u{00A0}" || $0 == "\u{2009}" ? " " : Character($0) })
    }

    func label(_ mention: NoteDateMention, now: Date? = NoteDateMentionTests.now) -> String {
        plain(NoteDateText.label(mention, now: now, calendar: Self.calendar, locale: Self.locale))
    }

    func text(_ markdown: String) -> NoteText { NoteMarkdown.parse(markdown).blocks.first?.text ?? NoteText() }

    func markdown(_ text: NoteText) -> String {
        NoteMarkdown.serialize(NotePage(blocks: [.paragraph(text)])).trimmingCharacters(in: .newlines)
    }

    func mention(in text: NoteText) -> NoteDateMention? {
        for run in text.runs() { if case .date(let value)? = run.marks.atom { return value } }
        return nil
    }

    func describe(_ mention: NoteDateMention?) -> String? {
        guard let mention else { return nil }
        var value = String(format: "%04d-%02d-%02d", mention.year, mention.month, mention.day)
        if let hour = mention.hour { value += String(format: " %02d:%02d", hour, mention.minute ?? 0) }
        if let end = mention.end {
            value += String(format: " > %04d-%02d-%02d", end.year, end.month, end.day)
            if let hour = end.hour { value += String(format: " %02d:%02d", hour, end.minute ?? 0) }
        }
        return value
    }

    let parser = NoteDateParser(now: NoteDateMentionTests.now, calendar: NoteDateMentionTests.calendar, dayFirst: false, locale: NoteDateMentionTests.locale)

    @Test(arguments: [
        ("jan 3", "2027-01-03"), ("sept 9", "2026-09-09"), ("1/12", "2027-01-12"), ("Jan 3 \u{2192} Jan 5", "2027-01-03 > 2027-01-05"),
        ("@Jan 3 - 5", "2027-01-03 > 2027-01-05"), ("jan 3-5", "2027-01-03 > 2027-01-05"), ("jan 3\u{2013}5", "2027-01-03 > 2027-01-05"),
        ("3-5 jan", "2027-01-03 > 2027-01-05"), ("jan 3 -> jan 5", "2027-01-03 > 2027-01-05"),
        ("jan 3 to jan 5, 2028", "2028-01-03 > 2028-01-05"), ("dec 30 - jan 2", "2026-12-30 > 2027-01-02"),
        ("jan 30 - 2", "2027-01-30 > 2027-02-02"), ("today until monday", "2026-11-20 > 2026-11-23"),
        ("tomorrow 3pm - 5pm", "2026-11-21 15:00 > 2026-11-21 17:00"), ("3-5pm", "2026-11-20 15:00 > 2026-11-20 17:00"),
        ("11-1pm", "2026-11-20 11:00 > 2026-11-20 13:00"), ("dec 3 9am \u{2192} dec 5", "2026-12-03 09:00 > 2026-12-05 09:00"),
        ("dec 3 \u{2192} dec 5 6pm", "2026-12-03 18:00 > 2026-12-05 18:00"), ("2026-12-03", "2026-12-03"), ("12-3", "2026-12-03"),
    ])
    func datesAndRangesParse(input: String, wanted: String) { #expect(describe(parser.parse(input)) == wanted) }

    @Test(arguments: ["jan 5 - jan 3", "jan 3 -", "jan 3 \u{2192} banana"])
    func brokenRangesDoNotParse(input: String) { #expect(describe(parser.parse(input)) == nil) }

    @Test(arguments: ["jan 3 -", "jan 3 \u{2192} ja"])
    func aHalfTypedRangeStillOffersItsStart(input: String) {
        #expect(parser.suggestions(for: input).contains { describe($0.mention) == "2027-01-03" })
    }

    @Test func aTypedRangeIsTheFirstSuggestion() {
        #expect(describe(parser.suggestions(for: "jan 3 \u{2192} jan 5").first?.mention) == "2027-01-03 > 2027-01-05")
    }

    @Test func aTypedRangeReadsAsARange() {
        #expect(plain(parser.suggestions(for: "jan 3 \u{2192} jan 5").first?.title ?? "") == "Sun, Jan 3, 2027 \u{2192} Tue, Jan 5, 2027")
    }

    @Test func completionsStayNearTheStart() {
        #expect(!parser.suggestions(for: "jan 3 \u{2192} jan").contains { ($0.mention.end?.year ?? 0) > 2027 })
    }

    @Test(arguments: ["jan 3 \u{2192} ja", "jan 3 to", "dec 3 3-5pm"])
    func rangeSyntaxKeepsTheMenuOpen(input: String) { #expect(parser.isPlausiblePrefix(input)) }

    @Test func aRangeReminderGivesBothEndsATime() {
        var range = NoteDateMention(year: 2026, month: 11, day: 24)
        range.end = NoteDateEnd(year: 2026, month: 11, day: 26)
        #expect(describe(parser.reminderVersion(of: range)) == "2026-11-24 09:00 > 2026-11-26 09:00")
    }

    @Test func remindWorksOnRanges() {
        #expect(describe(parser.suggestions(for: "nov 24 - 26", remind: true).first?.mention) == "2026-11-24 09:00 > 2026-11-26 09:00")
    }

    func earlyReminder() -> NoteDateMention {
        var early = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        early.remindBefore = 30
        return early
    }

    func plans(_ mention: NoteDateMention) -> [NoteReminderPlan] {
        NoteReminderPlan.reminders(in: NotePage(blocks: [.paragraph(NoteText("Call ") + .atom(.date(mention)))]), parser: parser)
    }

    @Test func plansRingAtTheLead() { #expect(plans(earlyReminder()).first?.fireDate == at(2026, 11, 21, 15)) }

    @Test func plansKeepTheLeadInTheirKey() { #expect(plans(earlyReminder()).first?.key == "2026-11-21T15:30-30m") }

    @Test func plainRemindersKeepTheirOldKey() {
        #expect(plans(NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)).first?.key == "2026-11-21T15:30")
    }

    func body(_ mention: NoteDateMention) -> String {
        plain(NoteReminderPlan.reminders(in: NotePage(blocks: [.paragraph(NoteText("Call Sam ") + .atom(.date(mention)))]), parser: parser).first?.body ?? "")
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

    func nudge(_ mention: NoteDateMention) -> String { plain(parser.reminderHint(for: mention)) }

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

    func hint(_ mention: NoteDateMention, at moment: Date = NoteDateMentionTests.now) -> String? {
        NoteDateText.suggestionDateHint(mention, now: moment, calendar: Self.calendar, locale: Self.locale).map(plain)
    }

    @Test(arguments: [
        ("today", false, "Today", "Nov 20"), ("tomorrow", false, "Tomorrow", "Nov 21"), ("yesterday", false, "Yesterday", "Nov 19"),
        ("nov 24", false, "Tue, Nov 24", nil), ("next friday", false, "Fri, Nov 27", nil), ("dec 3", false, "Thu, Dec 3", nil),
        ("in 2 weeks", false, "Fri, Dec 4", nil), ("jan 3", false, "Sun, Jan 3, 2027", nil), ("nov 24", true, "Tue, Nov 24 9:00 AM", nil),
        ("nov 29", true, "Sun, Nov 29 9:00 AM", nil), ("tomorrow", true, "Tomorrow 9:00 AM", "Nov 21"),
        ("nov 24 - 26", false, "Tue, Nov 24 \u{2192} Thu, Nov 26", nil), ("today until monday", false, "Today \u{2192} Mon, Nov 23", "Nov 20"),
        ("tomorrow 3pm - 5pm", false, "Tomorrow 3:00 PM \u{2192} 5:00 PM", "Nov 21"),
        ("jan 3 - 5", false, "Sun, Jan 3, 2027 \u{2192} Tue, Jan 5, 2027", nil),
    ] as [(String, Bool, String, String?)])
    func aSuggestionRowShowsItsTitleAndTheDateBesideIt(query: String, remind: Bool, title: String, wanted: String?) throws {
        let first = try #require(parser.suggestions(for: query, remind: remind).first)
        #expect(plain(first.title) == title)
        #expect(hint(first.mention) == wanted)
    }

    @Test func aRangeOfTwoNamedDaysDatesBothEnds() {
        var both = NoteDateMention(year: 2026, month: 11, day: 20)
        both.end = NoteDateEnd(year: 2026, month: 11, day: 21)
        #expect(hint(both) == "Nov 20 – 21")
    }

    @Test func tomorrowInAnotherYearShowsTheYear() {
        #expect(hint(NoteDateMention(year: 2027, month: 1, day: 1), at: at(2026, 12, 31, 10)) == "Jan 1, 2027")
    }

    var evening: NoteDateParser { NoteDateParser(now: at(2026, 11, 20, 20, 31), calendar: Self.calendar, dayFirst: false, locale: Self.locale) }

    @Test func aReminderForThisMinuteCannotBeSet() {
        #expect(evening.suggestions(for: "today 8:31pm", remind: true).isEmpty)
    }

    @Test func aPassedReminderIsStillRecognisedAndNamed() {
        let passed = evening.passedReminder(for: "today 8:31pm")
        #expect(describe(passed?.mention) == "2026-11-20 20:31")
        #expect(passed.map { plain($0.title) } == "Today 8:31 PM")
    }

    @Test func earlierDaysHavePassedToo() {
        #expect(describe(evening.passedReminder(for: "nov 19 3pm")?.mention) == "2026-11-19 15:00")
    }

    @Test(arguments: ["today 9pm", "banana"]) func laterTodayAndNonsenseHaveNotPassed(query: String) {
        #expect(evening.passedReminder(for: query) == nil)
    }

    func morningParser() -> NoteDateParser { parser }
    func lateParser() -> NoteDateParser { NoteDateParser(now: at(2026, 11, 20, 20, 33), calendar: Self.calendar, dayFirst: false, locale: Self.locale) }

    func offers(_ parser: NoteDateParser, _ query: String, remind: Bool = false) -> [String?] {
        parser.suggestions(for: query, remind: remind).map { describe($0.mention) }
    }

    @Test(arguments: ["nov 20th 8:40", "8:40", "at 8:40"])
    func lateInTheEveningOnlyTheReadingStillAheadIsOffered(query: String) {
        #expect(offers(lateParser(), query, remind: true) == ["2026-11-20 20:40"])
    }

    @Test(arguments: [
        ("nov 21 8:40", ["2026-11-21 08:40", "2026-11-21 20:40"]), ("11:15", ["2026-11-20 11:15", "2026-11-20 23:15"]),
        ("tomorrow at 7", ["2026-11-21 07:00", "2026-11-21 19:00"]),
    ] as [(String, [String])])
    func anAmbiguousTimeOffersBothReadingsNearestFirstWhenReminding(query: String, wanted: [String]) {
        #expect(offers(morningParser(), query, remind: true) == wanted)
    }

    @Test func asADateTheUpcomingReadingComesFirst() {
        #expect(offers(lateParser(), "8:40") == ["2026-11-20 20:40", "2026-11-20 08:40"])
    }

    @Test(arguments: [
        ("12:30", ["2026-11-20 12:30", "2026-11-20 00:30"]), ("13:00", ["2026-11-20 13:00"]), ("0:30", ["2026-11-20 00:30"]),
        ("8:40pm", ["2026-11-20 20:40"]), ("8:40 am", ["2026-11-20 08:40"]), ("tomorrow at noon", ["2026-11-21 12:00"]),
        ("nov 21 8:00 - 9:30", ["2026-11-21 08:00 > 2026-11-21 09:30", "2026-11-21 20:00 > 2026-11-21 21:30"]),
        ("11:00 - 1:00", ["2026-11-20 11:00 > 2026-11-20 13:00"]), ("3:00-5:00pm", ["2026-11-20 15:00 > 2026-11-20 17:00"]),
        ("nov 21 8:40 - 23", ["2026-11-21 08:40 > 2026-11-23 08:40", "2026-11-21 20:40 > 2026-11-23 20:40"]),
    ] as [(String, [String])])
    func meridiemsSettleOrLeaveBothReadings(query: String, wanted: [String]) {
        #expect(offers(morningParser(), query) == wanted)
    }

    @Test func aRangeAlreadyOverHasNothingToRemind() { #expect(offers(lateParser(), "8:00 - 9:30", remind: true).isEmpty) }

    @Test func everyReadingPassedNamesTheLatest() {
        #expect(describe(lateParser().passedReminder(for: "today 8:31")?.mention) == "2026-11-20 20:31")
    }

    @Test func oneReadingAheadMeansNothingHasPassed() { #expect(lateParser().passedReminder(for: "nov 20 8:40") == nil) }

    let legacy = "<time datetime=\"2026-11-20T09:30\" data-remind>2026-11-20 09:30</time>"

    @Test func olderRemindersStillRead() {
        #expect(mention(in: text(legacy)) == NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true))
    }

    @Test func olderRemindersSaveByteForByte() { #expect(markdown(text(legacy)) == legacy) }

    @Test func plainDatesSaveByteForByte() {
        let plainDate = "<time datetime=\"2026-11-20\">2026-11-20</time>"
        #expect(markdown(text(plainDate)) == plainDate)
    }

    var rangeMention: NoteDateMention {
        var range = NoteDateMention(year: 2027, month: 1, day: 3)
        range.end = NoteDateEnd(year: 2027, month: 1, day: 5)
        return range
    }

    let rangeSource = "<time datetime=\"2027-01-03\" data-end=\"2027-01-05\">2027-01-03 \u{2192} 2027-01-05</time>"

    @Test func rangesSaveTheirEnd() { #expect(markdown(.atom(.date(rangeMention))) == rangeSource) }

    @Test func rangesReadBack() { #expect(mention(in: text(rangeSource)) == rangeMention) }

    var everything: NoteDateMention {
        var value = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0, remind: true)
        value.end = NoteDateEnd(year: 2027, month: 1, day: 5, hour: 17, minute: 30)
        value.timeZone = "America/New_York"
        value.remindBefore = 30
        value.format = .full
        value.timeFormat = .twentyFourHour
        return value
    }

    let fullSource = "<time datetime=\"2027-01-03T09:00\" data-end=\"2027-01-05T17:30\" data-timezone=\"America/New_York\" data-remind=\"30m\""
        + " data-format=\"full\" data-clock=\"24h\">2027-01-03 09:00 \u{2192} 2027-01-05 17:30</time>"

    @Test func everySettingHasItsAttribute() { #expect(markdown(.atom(.date(everything))) == fullSource) }

    @Test func everySettingReadsBack() { #expect(mention(in: text(fullSource)) == everything) }

    let shuffledSource = "<time data-clock=\"24h\" data-remind=\"30m\" data-format=\"full\" data-timezone=\"America/New_York\""
        + " data-end=\"2027-01-05T17:30\" datetime=\"2027-01-03T09:00\">whatever</time>"

    @Test func attributeOrderDoesNotMatter() { #expect(mention(in: text(shuffledSource)) == everything) }

    @Test func savingPutsTheAttributesInOrder() { #expect(markdown(text(shuffledSource)) == fullSource) }

    @Test func minutesReadAsMinutes() {
        #expect(mention(in: text("<time datetime=\"2026-12-01T10:00\" data-remind=\"60m\">x</time>"))?.remindBefore == 60)
    }

    @Test func leadsSaveInTheBiggestUnit() {
        #expect(markdown(text("<time datetime=\"2026-12-01T10:00\" data-remind=\"60m\">x</time>"))
                == "<time datetime=\"2026-12-01T10:00\" data-remind=\"1h\">2026-12-01 10:00</time>")
    }

    @Test func aZeroLeadIsThePlainReminder() {
        #expect(mention(in: text("<time datetime=\"2026-12-01\" data-remind=\"0m\">x</time>"))?.remindBefore == nil)
    }

    static let badTimes = [
        "<time datetime=\"2026-12-01\" data-remind=\"soon\">x</time>", "<time datetime=\"2026-12-01\" class=\"x\">x</time>",
        "<time datetime=\"2026-12-01\" data-end=\"2026-12-02\" data-end=\"2026-12-03\">x</time>",
        "<time datetime=\"2026-12-01\" data-format=\"relative\">x</time>", "<time datetime=\"2026-12-01\" data-clock=\"36h\">x</time>",
        "<time datetime=\"2026-12-01\" data-end=\"soon\">x</time>", "<time datetime=\"2026-12-01\" data-timezone=\"\">x</time>",
        "<time data-end=\"2026-12-02\">x</time>",
    ]

    @Test(arguments: NoteDateMentionTests.badTimes)
    func anUnreadableTimeStaysRaw(bad: String) { #expect(mention(in: text(bad)) == nil) }

    @Test(arguments: NoteDateMentionTests.badTimes)
    func anUnreadableTimeSurvivesASave(bad: String) { #expect(markdown(text(bad)) == bad) }

    func roundTripMentions() -> [NoteDateMention] {
        var mentions: [NoteDateMention] = [rangeMention, everything]
        let formats: [NoteDateFormat?] = [nil] + NoteDateFormat.allCases.map { Optional($0) }
        for (index, format) in formats.enumerated() {
            var value = NoteDateMention(year: 2026, month: 12, day: 10 + index, hour: index % 2 == 0 ? 8 : nil, minute: index % 2 == 0 ? 15 : nil)
            value.format = format
            value.timeFormat = index % 3 == 0 ? nil : (index % 3 == 1 ? .twelveHour : .twentyFourHour)
            if index % 2 == 0 { value.timeZone = ["Europe/Paris", "Asia/Kolkata", "America/Los_Angeles"][index % 3] }
            if index > 2 { value.end = NoteDateEnd(year: 2026, month: 12, day: 20 + index, hour: value.hour.map { $0 + 1 }, minute: value.minute) }
            if index % 2 == 1 {
                value.remind = true
                value.remindBefore = [nil, 5, 1440, 10080, 90][index % 5]
            }
            mentions.append(value)
        }
        return mentions
    }

    @Test func everyMentionRoundTripsThroughMarkdown() {
        let failures = roundTripMentions().filter { mention(in: text(markdown(.atom(.date($0))))) != $0 }
        #expect(failures.isEmpty)
    }

    @Test func everyMentionRoundTripsThroughHTML() {
        let failures = roundTripMentions().filter { value in
            let html = NotePageHTML.fragment([.paragraph(.atom(.date(value)))])
            return NoteHTMLReader.blocks(from: html, baseURL: nil).first.flatMap { mention(in: $0.text) } != value
        }
        #expect(failures.isEmpty)
    }

    @Test func htmlShowsTheRange() {
        let exported = NotePageHTML.fragment([.paragraph(.atom(.date(rangeMention)))])
        #expect(exported.contains("data-end=\"2027-01-05\""))
        #expect(exported.contains("\u{2192}"))
    }

    @Test func plainTextKeepsBothEnds() { #expect(NoteAtom.date(rangeMention).fallbackText == "2027-01-03 \u{2192} 2027-01-05") }

    @Test func olderHTMLRemindersStillPaste() {
        let read = NoteHTMLReader.blocks(from: "<p><time data-mention=\"date\" datetime=\"2026-11-20T09:30\" data-remind=\"true\">@x</time></p>", baseURL: nil)
            .first.flatMap { mention(in: $0.text) }
        #expect(read == NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true))
    }

    @Test func rangesReadStartToEnd() { #expect(label(rangeMention) == "January 3, 2027 \u{2192} January 5, 2027") }

    func timedRange() -> NoteDateMention {
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

    @Test(arguments: [(20, "Today"), (21, "Tomorrow"), (19, "Yesterday"), (25, "November 25, 2026")] as [(Int, String)])
    func nearbyDaysReadInWords(day: Int, expected: String) {
        #expect(label(NoteDateMention(year: 2026, month: 11, day: day)) == expected)
    }

    @Test func relativeWordsTurnAbsoluteAsTimePasses() {
        #expect(label(NoteDateMention(year: 2026, month: 11, day: 20), now: at(2026, 11, 22, 8)) == "November 20, 2026")
    }

    @Test func exportsNeverSayToday() { #expect(label(NoteDateMention(year: 2026, month: 11, day: 20), now: nil) == "November 20, 2026") }

    @Test func relativeWordsWorkOnBothEnds() {
        var relativeRange = NoteDateMention(year: 2026, month: 11, day: 20)
        relativeRange.end = NoteDateEnd(year: 2026, month: 11, day: 21)
        #expect(label(relativeRange) == "Today \u{2192} Tomorrow")
    }

    @Test(arguments: [
        (NoteDateFormat.full, "November 20, 2026"), (.short, "Nov 20, 2026"), (.monthDayYear, "11/20/2026"), (.dayMonthYear, "20/11/2026"),
        (.yearMonthDay, "2026/11/20"),
    ] as [(NoteDateFormat, String)])
    func aDateFormatSpellsTheDateItsWay(format: NoteDateFormat, wanted: String) {
        var value = NoteDateMention(year: 2026, month: 11, day: 20)
        value.format = format
        #expect(label(value) == wanted)
    }

    @Test(arguments: [(NoteTimeFormat?.none, "Today 5:05 PM"), (.twentyFourHour, "Today 17:05"), (.twelveHour, "Today 5:05 PM")] as [(NoteTimeFormat?, String)])
    func theClockChoiceShapesTheTime(format: NoteTimeFormat?, wanted: String) {
        var clock = NoteDateMention(year: 2026, month: 11, day: 20, hour: 17, minute: 5)
        clock.timeFormat = format
        #expect(label(clock) == wanted)
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

    @Test func zoneOffsetsShowHalfHours() { #expect(NoteDateText.zoneOffset("Asia/Kolkata", at: Self.now) == "GMT+5:30") }

    var timedReminder: NoteDateMention { NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true) }

    @Test func atTimeOfEvent() { #expect(timedReminder.reminderDate(in: Self.calendar) == at(2026, 11, 21, 15, 30)) }

    @Test func thirtyMinutesBefore() {
        var early = timedReminder
        early.remindBefore = 30
        #expect(early.reminderDate(in: Self.calendar) == at(2026, 11, 21, 15))
    }

    @Test func oneDayBefore() {
        var early = timedReminder
        early.remindBefore = 1440
        #expect(early.reminderDate(in: Self.calendar) == at(2026, 11, 20, 15, 30))
    }

    @Test func allDayRemindersRingAtNineAM() {
        #expect(NoteDateMention(year: 2026, month: 12, day: 3, remind: true).reminderDate(in: Self.calendar) == at(2026, 12, 3, 9))
    }

    @Test func aWeekBeforeAtNineAM() {
        var weekBefore = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
        weekBefore.remindBefore = NoteReminderLead.week
        #expect(weekBefore.reminderDate(in: Self.calendar) == at(2026, 11, 26, 9))
    }

    @Test func dayLeadsKeepNineAMAcrossAClockChange() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var acrossDST = NoteDateMention(year: 2026, month: 11, day: 2, remind: true)
        acrossDST.remindBefore = NoteReminderLead.day
        #expect(acrossDST.reminderDate(in: newYork) == at(2026, 11, 1, 9, in: newYork))
    }

    func zonedReminder() -> NoteDateMention {
        var zoned = NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true)
        zoned.timeZone = "America/New_York"
        return zoned
    }

    @Test func zonedTimesRingAtThatZonesMoment() { #expect(zonedReminder().reminderDate(in: Self.calendar) == at(2026, 11, 21, 14)) }

    @Test func zonedTimesStartThere() { #expect(zonedReminder().startDate(in: Self.calendar) == at(2026, 11, 21, 14)) }

    @Test func aReminderTurnsDueOnceItsDayArrives() {
        #expect(NoteDateMention(year: 2026, month: 11, day: 20, hour: 18, minute: 0, remind: true).isDue(now: Self.now, calendar: Self.calendar))
    }

    @Test func tomorrowIsNotDue() {
        #expect(!NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true).isDue(now: Self.now, calendar: Self.calendar))
    }

    @Test func aReminderThatAlreadyRangIsDue() {
        var heads = NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true)
        heads.remindBefore = NoteReminderLead.day
        #expect(heads.isDue(now: Self.now, calendar: Self.calendar))
    }

    @Test func pastDatesAreOverdue() { #expect(NoteDateMention(year: 2026, month: 11, day: 1).isDue(now: Self.now, calendar: Self.calendar)) }

    @Test func redrawWhenAReminderRings() {
        let rings = NoteDateMention(year: 2026, month: 11, day: 20, hour: 15, minute: 0, remind: true)
        #expect(NoteDateText.nextChange(of: [rings], after: Self.now, calendar: Self.calendar) == at(2026, 11, 20, 15))
    }

    @Test func redrawAtMidnightWhenTheWordsChange() {
        #expect(NoteDateText.nextChange(of: [NoteDateMention(year: 2026, month: 12, day: 1)], after: Self.now, calendar: Self.calendar) == at(2026, 11, 21))
    }

    @Test func noDatesNoRedraws() { #expect(NoteDateText.nextChange(of: [], after: Self.now, calendar: Self.calendar) == nil) }

    @Test func anEndBeforeItsStartIsOutOfOrder() {
        var ordered = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 0)
        ordered.end = NoteDateEnd(year: 2026, month: 11, day: 20, hour: 8, minute: 0)
        #expect(!ordered.isOrdered(in: Self.calendar))
    }

    @Test func timedReminderChoices() {
        #expect(NoteReminderLead.timed.map { NoteReminderLead.title($0, allDay: false, locale: Self.locale) }
                == ["At time of event", "5 minutes before", "10 minutes before", "15 minutes before", "30 minutes before",
                    "1 hour before", "2 hours before", "1 day before", "2 days before"])
    }

    @Test func allDayReminderChoices() {
        #expect(NoteReminderLead.allDay.map { plain(NoteReminderLead.title($0, allDay: true, locale: Self.locale)) }
                == ["On day of event (9:00 AM)", "1 day before (9:00 AM)", "2 days before (9:00 AM)", "1 week before (9:00 AM)"])
    }

    @Test func theRingTimeFollowsTheClockChoice() {
        #expect(NoteReminderLead.title(0, allDay: true, timeFormat: .twentyFourHour, locale: Self.locale) == "On day of event (09:00)")
    }

    static let leads = Array(Set(NoteReminderLead.timed + NoteReminderLead.allDay).filter { $0 > 0 }).sorted()

    @Test(arguments: NoteDateMentionTests.leads)
    func aLeadSurvivesItsToken(lead: Int) { #expect(NoteReminderLead.lead(fromToken: NoteReminderLead.token(lead)) == lead) }

    @Test(arguments: [(30, "30m"), (120, "2h"), (2880, "2d"), (10080, "1w")] as [(Int, String)])
    func tokensUseTheBiggestUnit(lead: Int, token: String) { #expect(NoteReminderLead.token(lead) == token) }

    @Test func oddMinutesRead() { #expect(NoteReminderLead.lead(fromToken: "90m") == 90) }

    @Test func oddMinutesReadOut() { #expect(NoteReminderLead.span(90) == "90 minutes") }

    @Test(arguments: ["1y", "m"]) func badTokensAreRefused(token: String) { #expect(NoteReminderLead.lead(fromToken: token) == nil) }

    @Test func aLeadOutsideTheListFallsBackToTheEvent() { #expect(NoteReminderLead.fitting(45, allDay: false) == 0) }

    @Test func aLeadInTheListStays() { #expect(NoteReminderLead.fitting(1440, allDay: true) == 1440) }
}
