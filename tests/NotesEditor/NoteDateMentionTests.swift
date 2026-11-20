import Foundation

@main
struct NoteDateMentionTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func expectEqual<T: Equatable>(_ found: T, _ wanted: T, _ message: String) {
        if found != wanted { failTest(message + ": got \(found), wanted \(wanted)") }
    }

    static var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.firstWeekday = 1
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }()

    static let locale = Locale(identifier: "en_US")
    static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10, minute: 30))!

    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar = calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func plain(_ value: String) -> String {
        String(value.unicodeScalars.map { $0 == "\u{202F}" || $0 == "\u{00A0}" ? " " : Character($0) })
    }

    static func label(_ mention: NoteDateMention, now: Date? = now) -> String {
        plain(NoteDateText.label(mention, now: now, calendar: calendar, locale: locale))
    }

    static func text(_ markdown: String) -> NoteText {
        NoteMarkdown.parse(markdown).blocks.first?.text ?? NoteText()
    }

    static func markdown(_ text: NoteText) -> String {
        NoteMarkdown.serialize(NotePage(blocks: [.paragraph(text)])).trimmingCharacters(in: .newlines)
    }

    static func mention(in text: NoteText) -> NoteDateMention? {
        for run in text.runs() { if case .date(let value)? = run.marks.atom { return value } }
        return nil
    }

    static func main() {
        codec()
        labels()
        reminders()
        leads()
        parser()
        print("NoteDateMentionTests passed")
    }

    static func describe(_ mention: NoteDateMention?) -> String? {
        guard let mention else { return nil }
        var value = String(format: "%04d-%02d-%02d", mention.year, mention.month, mention.day)
        if let hour = mention.hour { value += String(format: " %02d:%02d", hour, mention.minute ?? 0) }
        if let end = mention.end {
            value += String(format: " > %04d-%02d-%02d", end.year, end.month, end.day)
            if let hour = end.hour { value += String(format: " %02d:%02d", hour, end.minute ?? 0) }
        }
        return value
    }

    static func parser() {
        let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: locale)
        func check(_ input: String, _ wanted: String?) {
            expectEqual(describe(parser.parse(input)), wanted, "\"\(input)\"")
        }
        check("jan 3", "2027-01-03")
        check("sept 9", "2026-09-09")
        check("1/12", "2027-01-12")
        check("Jan 3 \u{2192} Jan 5", "2027-01-03 > 2027-01-05")
        check("@Jan 3 - 5", "2027-01-03 > 2027-01-05")
        check("jan 3-5", "2027-01-03 > 2027-01-05")
        check("jan 3\u{2013}5", "2027-01-03 > 2027-01-05")
        check("3-5 jan", "2027-01-03 > 2027-01-05")
        check("jan 3 -> jan 5", "2027-01-03 > 2027-01-05")
        check("jan 3 to jan 5, 2028", "2028-01-03 > 2028-01-05")
        check("dec 30 - jan 2", "2026-12-30 > 2027-01-02")
        check("jan 30 - 2", "2027-01-30 > 2027-02-02")
        check("today until monday", "2026-11-20 > 2026-11-23")
        check("tomorrow 3pm - 5pm", "2026-11-21 15:00 > 2026-11-21 17:00")
        check("3-5pm", "2026-11-20 15:00 > 2026-11-20 17:00")
        check("11-1pm", "2026-11-20 11:00 > 2026-11-20 13:00")
        check("dec 3 9am \u{2192} dec 5", "2026-12-03 09:00 > 2026-12-05 09:00")
        check("dec 3 \u{2192} dec 5 6pm", "2026-12-03 18:00 > 2026-12-05 18:00")
        check("jan 5 - jan 3", nil)
        check("jan 3 -", nil)
        check("jan 3 \u{2192} banana", nil)
        check("2026-12-03", "2026-12-03")
        check("12-3", "2026-12-03")

        expect(parser.suggestions(for: "jan 3 -").contains { describe($0.mention) == "2027-01-03" }, "a half-typed range still offers its start")
        expect(parser.suggestions(for: "jan 3 \u{2192} ja").contains { describe($0.mention) == "2027-01-03" }, "and keeps offering it")
        let whole = parser.suggestions(for: "jan 3 \u{2192} jan 5")
        expectEqual(describe(whole.first?.mention), "2027-01-03 > 2027-01-05", "a typed range is the first suggestion")
        expectEqual(plain(whole.first?.title ?? ""), "Jan 3, 2027 \u{2192} Jan 5, 2027", "and reads as a range")
        expect(!parser.suggestions(for: "jan 3 \u{2192} jan").contains { ($0.mention.end?.year ?? 0) > 2027 }, "completions stay near the start")
        expect(parser.isPlausiblePrefix("jan 3 \u{2192} ja"), "an arrow keeps the menu open")
        expect(parser.isPlausiblePrefix("jan 3 to"), "so does to")
        expect(parser.isPlausiblePrefix("dec 3 3-5pm"), "and a time range")

        var range = NoteDateMention(year: 2026, month: 11, day: 24)
        range.end = NoteDateEnd(year: 2026, month: 11, day: 26)
        let reminder = parser.reminderVersion(of: range)
        expectEqual(describe(reminder), "2026-11-24 09:00 > 2026-11-26 09:00", "a range reminder gives both ends a time")
        let ranged = parser.suggestions(for: "nov 24 - 26", remind: true)
        expectEqual(describe(ranged.first?.mention), "2026-11-24 09:00 > 2026-11-26 09:00", "remind works on ranges")

        var early = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        early.remindBefore = 30
        let page = NotePage(blocks: [.paragraph(NoteText("Call ") + .atom(.date(early)))])
        let plans = NoteReminderPlan.reminders(in: page, parser: parser)
        expectEqual(plans.first?.fireDate, at(2026, 11, 21, 15), "plans ring at the lead")
        expectEqual(plans.first?.key, "2026-11-21T15:30-30m", "and keep the lead in their key")
        let ordinary = NoteReminderPlan.reminders(in: NotePage(blocks: [.paragraph(.atom(.date(NoteDateMention(year: 2026, month: 11, day: 21,
                                                                                                              hour: 15, minute: 30, remind: true))))]),
                                               parser: parser)
        expectEqual(ordinary.first?.key, "2026-11-21T15:30", "plain reminders keep their old key")
    }

    static func codec() {
        let legacy = "<time datetime=\"2026-11-20T09:30\" data-remind>2026-11-20 09:30</time>"
        expectEqual(mention(in: text(legacy)), NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true),
                    "older reminders still read")
        expectEqual(markdown(text(legacy)), legacy, "older reminders save byte for byte")
        let plainDate = "<time datetime=\"2026-11-20\">2026-11-20</time>"
        expectEqual(markdown(text(plainDate)), plainDate, "plain dates save byte for byte")

        var range = NoteDateMention(year: 2027, month: 1, day: 3)
        range.end = NoteDateEnd(year: 2027, month: 1, day: 5)
        let rangeSource = "<time datetime=\"2027-01-03\" data-end=\"2027-01-05\">2027-01-03 \u{2192} 2027-01-05</time>"
        expectEqual(markdown(.atom(.date(range))), rangeSource, "ranges save their end")
        expectEqual(mention(in: text(rangeSource)), range, "ranges read back")

        var everything = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0, remind: true)
        everything.end = NoteDateEnd(year: 2027, month: 1, day: 5, hour: 17, minute: 30)
        everything.timeZone = "America/New_York"
        everything.remindBefore = 30
        everything.format = .full
        everything.timeFormat = .twentyFourHour
        let full = "<time datetime=\"2027-01-03T09:00\" data-end=\"2027-01-05T17:30\" data-timezone=\"America/New_York\" data-remind=\"30m\""
            + " data-format=\"full\" data-clock=\"24h\">2027-01-03 09:00 \u{2192} 2027-01-05 17:30</time>"
        expectEqual(markdown(.atom(.date(everything))), full, "every setting has its attribute")
        expectEqual(mention(in: text(full)), everything, "and every setting reads back")
        let shuffled = "<time data-clock=\"24h\" data-remind=\"30m\" data-format=\"full\" data-timezone=\"America/New_York\""
            + " data-end=\"2027-01-05T17:30\" datetime=\"2027-01-03T09:00\">whatever</time>"
        expectEqual(mention(in: text(shuffled)), everything, "attribute order doesn't matter")
        expectEqual(markdown(text(shuffled)), full, "and saving puts them in order")

        expectEqual(mention(in: text("<time datetime=\"2026-12-01T10:00\" data-remind=\"60m\">x</time>"))?.remindBefore, 60,
                    "minutes read as minutes")
        expectEqual(markdown(text("<time datetime=\"2026-12-01T10:00\" data-remind=\"60m\">x</time>")),
                    "<time datetime=\"2026-12-01T10:00\" data-remind=\"1h\">2026-12-01 10:00</time>", "and save in the biggest unit")
        expectEqual(mention(in: text("<time datetime=\"2026-12-01\" data-remind=\"0m\">x</time>"))?.remindBefore, nil,
                    "a zero lead is the plain reminder")

        for bad in ["<time datetime=\"2026-12-01\" data-remind=\"soon\">x</time>",
                    "<time datetime=\"2026-12-01\" class=\"x\">x</time>",
                    "<time datetime=\"2026-12-01\" data-end=\"2026-12-02\" data-end=\"2026-12-03\">x</time>",
                    "<time datetime=\"2026-12-01\" data-format=\"relative\">x</time>",
                    "<time datetime=\"2026-12-01\" data-clock=\"36h\">x</time>",
                    "<time datetime=\"2026-12-01\" data-end=\"soon\">x</time>",
                    "<time datetime=\"2026-12-01\" data-timezone=\"\">x</time>",
                    "<time data-end=\"2026-12-02\">x</time>"] {
            let read = text(bad)
            expect(mention(in: read) == nil, "\(bad) stays raw")
            expectEqual(markdown(read), bad, "\(bad) survives a save")
        }

        var mentions: [NoteDateMention] = [range, everything]
        let formats: [NoteDateFormat?] = [nil] + NoteDateFormat.allCases.map { Optional($0) }
        for (index, format) in formats.enumerated() {
            var value = NoteDateMention(year: 2026, month: 12, day: 10 + index, hour: index % 2 == 0 ? 8 : nil, minute: index % 2 == 0 ? 15 : nil)
            value.format = format
            value.timeFormat = index % 3 == 0 ? nil : (index % 3 == 1 ? .twelveHour : .twentyFourHour)
            if index % 2 == 0 { value.timeZone = ["Europe/Paris", "Asia/Kolkata", "America/Los_Angeles"][index % 3] }
            if index > 2 {
                value.end = NoteDateEnd(year: 2026, month: 12, day: 20 + index, hour: value.hour.map { $0 + 1 }, minute: value.minute)
            }
            if index % 2 == 1 {
                value.remind = true
                value.remindBefore = [nil, 5, 1440, 10080, 90][index % 5]
            }
            mentions.append(value)
        }
        for value in mentions {
            let source = markdown(.atom(.date(value)))
            expectEqual(mention(in: text(source)), value, "\(source) round-trips through Markdown")
            let html = NotePageHTML.fragment([.paragraph(.atom(.date(value)))])
            let back = NoteHTMLReader.blocks(from: html, baseURL: nil).first.flatMap { mention(in: $0.text) }
            expectEqual(back, value, "\(html) round-trips through HTML")
        }
        let exported = NotePageHTML.fragment([.paragraph(.atom(.date(range)))])
        expect(exported.contains("data-end=\"2027-01-05\"") && exported.contains("\u{2192}"), "HTML shows the range: \(exported)")
        expectEqual(NoteAtom.date(range).fallbackText, "2027-01-03 \u{2192} 2027-01-05", "plain text keeps both ends")
        let legacyHTML = NoteHTMLReader.blocks(from: "<p><time data-mention=\"date\" datetime=\"2026-11-20T09:30\" data-remind=\"true\">@x</time></p>",
                                               baseURL: nil).first.flatMap { mention(in: $0.text) }
        expectEqual(legacyHTML, NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true), "older HTML reminders still paste")
    }

    static func labels() {
        var range = NoteDateMention(year: 2027, month: 1, day: 3)
        range.end = NoteDateEnd(year: 2027, month: 1, day: 5)
        expectEqual(label(range), "January 3, 2027 \u{2192} January 5, 2027", "ranges read start to end")
        var timed = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0)
        timed.end = NoteDateEnd(year: 2027, month: 1, day: 5, hour: 17, minute: 30)
        expectEqual(label(timed), "January 3, 2027 9:00 AM \u{2192} January 5, 2027 5:30 PM", "both ends show their times")
        timed.end = NoteDateEnd(year: 2027, month: 1, day: 3, hour: 17, minute: 30)
        expectEqual(label(timed), "January 3, 2027 9:00 AM \u{2192} 5:30 PM", "a same-day range names the day once")

        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 20)), "Today", "today reads as Today")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 21)), "Tomorrow", "tomorrow reads as Tomorrow")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 19)), "Yesterday", "yesterday reads as Yesterday")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 25)), "November 25, 2026", "other days spell out")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 20), now: at(2026, 11, 22, 8)), "November 20, 2026",
                    "relative words turn absolute as time passes")
        expectEqual(label(NoteDateMention(year: 2026, month: 11, day: 20), now: nil), "November 20, 2026", "exports never say Today")
        var relativeRange = NoteDateMention(year: 2026, month: 11, day: 20)
        relativeRange.end = NoteDateEnd(year: 2026, month: 11, day: 21)
        expectEqual(label(relativeRange), "Today \u{2192} Tomorrow", "relative words work on both ends")

        let samples: [(NoteDateFormat, String)] = [(.full, "November 20, 2026"), (.short, "Nov 20, 2026"), (.monthDayYear, "11/20/2026"),
                                                   (.dayMonthYear, "20/11/2026"), (.yearMonthDay, "2026/11/20")]
        for (format, wanted) in samples {
            var value = NoteDateMention(year: 2026, month: 11, day: 20)
            value.format = format
            expectEqual(label(value), wanted, "\(format) format")
        }
        var clock = NoteDateMention(year: 2026, month: 11, day: 20, hour: 17, minute: 5)
        expectEqual(label(clock), "Today 5:05 PM", "times follow the locale")
        clock.timeFormat = .twentyFourHour
        expectEqual(label(clock), "Today 17:05", "24 hour clock")
        clock.timeFormat = .twelveHour
        expectEqual(label(clock), "Today 5:05 PM", "12 hour clock")
        var zoned = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0)
        zoned.timeZone = "America/New_York"
        expectEqual(label(zoned), "January 3, 2027 9:00 AM EST", "a chosen time zone shows its name")
        zoned.hour = nil
        zoned.minute = nil
        expectEqual(label(zoned), "January 3, 2027", "all-day dates ignore the zone")
        expectEqual(NoteDateText.zoneTitle("America/Port_of_Spain"), "Port of Spain", "zone titles read like cities")
        expectEqual(NoteDateText.zoneOffset("Asia/Kolkata", at: now), "GMT+5:30", "zone offsets show half hours")
    }

    static func reminders() {
        let timed = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        expectEqual(timed.reminderDate(in: calendar), at(2026, 11, 21, 15, 30), "at time of event")
        var early = timed
        early.remindBefore = 30
        expectEqual(early.reminderDate(in: calendar), at(2026, 11, 21, 15), "30 minutes before")
        early.remindBefore = 1440
        expectEqual(early.reminderDate(in: calendar), at(2026, 11, 20, 15, 30), "1 day before")
        let allDay = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
        expectEqual(allDay.reminderDate(in: calendar), at(2026, 12, 3, 9), "all-day reminders ring at 9 AM")
        var weekBefore = allDay
        weekBefore.remindBefore = NoteReminderLead.week
        expectEqual(weekBefore.reminderDate(in: calendar), at(2026, 11, 26, 9), "a week before at 9 AM")

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var acrossDST = NoteDateMention(year: 2026, month: 11, day: 2, remind: true)
        acrossDST.remindBefore = NoteReminderLead.day
        expectEqual(acrossDST.reminderDate(in: newYork), at(2026, 11, 1, 9, in: newYork), "day leads keep 9 AM across a clock change")

        var zoned = NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true)
        zoned.timeZone = "America/New_York"
        expectEqual(zoned.reminderDate(in: calendar), at(2026, 11, 21, 14), "zoned times ring at that zone's moment")
        expectEqual(zoned.startDate(in: calendar), at(2026, 11, 21, 14), "and start there")

        expect(NoteDateMention(year: 2026, month: 11, day: 20, hour: 18, minute: 0, remind: true).isDue(now: now, calendar: calendar),
               "a reminder turns due once its day arrives")
        expect(!NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true).isDue(now: now, calendar: calendar),
               "tomorrow isn't due")
        var heads = NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true)
        heads.remindBefore = NoteReminderLead.day
        expect(heads.isDue(now: now, calendar: calendar), "a reminder that already rang is due")
        expect(NoteDateMention(year: 2026, month: 11, day: 1).isDue(now: now, calendar: calendar), "past dates are overdue")

        let ringsLater = NoteDateMention(year: 2026, month: 11, day: 20, hour: 15, minute: 0, remind: true)
        expectEqual(NoteDateText.nextChange(of: [ringsLater], after: now, calendar: calendar), at(2026, 11, 20, 15), "redraw when a reminder rings")
        expectEqual(NoteDateText.nextChange(of: [NoteDateMention(year: 2026, month: 12, day: 1)], after: now, calendar: calendar),
                    at(2026, 11, 21), "redraw at midnight when the words change")
        expectEqual(NoteDateText.nextChange(of: [], after: now, calendar: calendar), nil, "no dates, no redraws")
        var ordered = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 0)
        ordered.end = NoteDateEnd(year: 2026, month: 11, day: 20, hour: 8, minute: 0)
        expect(!ordered.isOrdered(in: calendar), "an end before its start is out of order")
    }

    static func leads() {
        let timed = NoteReminderLead.timed.map { NoteReminderLead.title($0, allDay: false, locale: locale) }
        expectEqual(timed, ["At time of event", "5 minutes before", "10 minutes before", "15 minutes before", "30 minutes before",
                            "1 hour before", "2 hours before", "1 day before", "2 days before"], "timed reminder choices")
        let allDay = NoteReminderLead.allDay.map { plain(NoteReminderLead.title($0, allDay: true, locale: locale)) }
        expectEqual(allDay, ["On day of event (9:00 AM)", "1 day before (9:00 AM)", "2 days before (9:00 AM)", "1 week before (9:00 AM)"],
                    "all-day reminder choices")
        expectEqual(NoteReminderLead.title(0, allDay: true, timeFormat: .twentyFourHour, locale: locale), "On day of event (09:00)",
                    "the ring time follows the clock choice")
        for lead in Set(NoteReminderLead.timed + NoteReminderLead.allDay) where lead > 0 {
            expectEqual(NoteReminderLead.lead(fromToken: NoteReminderLead.token(lead)), lead, "lead \(lead) survives its token")
        }
        expectEqual(NoteReminderLead.token(30), "30m", "minutes token")
        expectEqual(NoteReminderLead.token(120), "2h", "hours token")
        expectEqual(NoteReminderLead.token(2880), "2d", "days token")
        expectEqual(NoteReminderLead.token(10080), "1w", "weeks token")
        expectEqual(NoteReminderLead.lead(fromToken: "90m"), 90, "odd minutes read")
        expectEqual(NoteReminderLead.span(90), "90 minutes", "and read out")
        expectEqual(NoteReminderLead.lead(fromToken: "1y"), nil, "years aren't a unit")
        expectEqual(NoteReminderLead.lead(fromToken: "m"), nil, "a unit needs a number")
        expectEqual(NoteReminderLead.fitting(45, allDay: false), 0, "a lead outside the list falls back to the event")
        expectEqual(NoteReminderLead.fitting(1440, allDay: true), 1440, "a lead in the list stays")
    }
}
