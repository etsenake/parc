import Foundation

@main
struct NoteSlashDatesTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.firstWeekday = 1
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10, minute: 30))!
    static let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false)

    static func day(_ input: String, _ parser: NoteDateParser = parser) -> String? {
        parser.parse(input).map { mention in
            var value = String(format: "%04d-%02d-%02d", mention.year, mention.month, mention.day)
            if let hour = mention.hour { value += String(format: " %02d:%02d", hour, mention.minute ?? 0) }
            return value
        }
    }

    static func check(_ input: String, _ expected: String?, _ parser: NoteDateParser = parser) {
        let found = day(input, parser)
        expect(found == expected, "\"\(input)\" should be \(expected ?? "nil"), got \(found ?? "nil")")
    }

    static func plain(_ value: String?) -> String? {
        value.map { String($0.unicodeScalars.map { $0 == "\u{202F}" || $0 == "\u{00A0}" ? " " : Character($0) }) }
    }

    static func main() {
        check("today", "2026-11-20")
        check("Today", "2026-11-20")
        check("@today", "2026-11-20")
        check("tomorrow", "2026-11-21")
        check("tmrw", "2026-11-21")
        check("yesterday", "2026-11-19")
        check("friday", "2026-11-20")
        check("fri", "2026-11-20")
        check("monday", "2026-11-23")
        check("this sunday", "2026-11-22")
        check("next friday", "2026-11-27")
        check("next wednesday", "2026-11-25")
        check("last friday", "2026-11-13")
        check("coming friday", "2026-11-27")
        check("next week", "2026-11-27")
        check("next month", "2026-12-20")
        check("in 3 days", "2026-11-23")
        check("in two weeks", "2026-12-04")
        check("2 weeks ago", "2026-11-06")
        check("3 days from now", "2026-11-23")
        check("dec 3", "2026-12-03")
        check("Dec 3, 2027", "2027-12-03")
        check("december 3rd", "2026-12-03")
        check("3 dec", "2026-12-03")
        check("3rd of december", "2026-12-03")
        check("sept 9", "2026-09-09")
        check("2026-12-03", "2026-12-03")
        check("2026/12/3", "2026-12-03")
        check("12/3", "2026-12-03")
        check("12/3/27", "2027-12-03")
        check("3.12.2026", "2026-12-03")
        check("12/3", "2027-03-12", NoteDateParser(now: now, calendar: calendar, dayFirst: true))
        check("3pm", "2026-11-20 15:00")
        check("3 pm", "2026-11-20 15:00")
        check("at 3:45pm", "2026-11-20 15:45")
        check("15:00", "2026-11-20 15:00")
        check("noon", "2026-11-20 12:00")
        check("midnight", "2026-11-20 00:00")
        check("12am", "2026-11-20 00:00")
        check("12pm", "2026-11-20 12:00")
        check("tomorrow 3pm", "2026-11-21 15:00")
        check("3pm tomorrow", "2026-11-21 15:00")
        check("tomorrow at 9", "2026-11-21 09:00")
        check("next friday at 9:30am", "2026-11-27 09:30")
        check("dec 3 5pm", "2026-12-03 17:00")
        check("2026-12-03 14:00", "2026-12-03 14:00")
        check("in 2 hours", "2026-11-20 12:30")
        check("in an hour", "2026-11-20 11:30")
        check("in 45 minutes", "2026-11-20 11:15")
        check("tonight", "2026-11-20 20:00")
        check("", nil)
        check("banana", nil)
        check("feb 30", nil)
        check("13/45", nil)
        check("25pm", nil)
        check("13pm", nil)
        check("tomorrow 9", nil)
        check("3 days", nil)
        check("march", nil)

        let empty = parser.suggestions(for: "")
        expect(empty.map(\.title) == ["Today", "Tomorrow", "Yesterday"], "an empty date query offers today, tomorrow and yesterday: \(empty.map(\.title))")
        let t = parser.suggestions(for: "t")
        expect(t.map(\.title) == ["Today", "Tomorrow"], "t narrows to today and tomorrow")
        let nextF = parser.suggestions(for: "next f")
        expect(nextF.contains { $0.mention.day == 27 && $0.mention.month == 11 }, "next f completes to next Friday")
        let dec = parser.suggestions(for: "dec")
        expect(dec.first.map { $0.mention.month == 12 && $0.mention.day == 1 } == true, "a bare month offers its first day")
        let parsed = parser.suggestions(for: "dec 3 5pm")
        expect(plain(parsed.first?.title) == "Thu, Dec 3 5:00 PM", "parsed dates read naturally: \(parsed.first?.title ?? "")")
        expect(parser.suggestions(for: "monday").first?.title == "Monday", "dates this week read as weekdays")
        expect(parser.suggestions(for: "zzz").isEmpty, "nonsense suggests nothing")

        let remind = parser.suggestions(for: "tomorrow", remind: true)
        expect(remind.first?.mention == NoteDateMention(year: 2026, month: 11, day: 21, hour: 9, minute: 0, remind: true),
               "reminders without a time ring at 9 AM")
        expect(plain(remind.first?.title) == "Tomorrow 9:00 AM", "and say so: \(remind.first?.title ?? "")")
        let todayReminder = parser.reminderVersion(of: NoteDateMention(year: 2026, month: 11, day: 20))
        expect(todayReminder.hour == 11 && todayReminder.minute == 0, "a reminder for today after 9 AM rings next hour")
        expect(parser.suggestions(for: "yesterday", remind: true).isEmpty, "reminders never go off in the past")
        let defaults = parser.suggestions(for: "", remind: true)
        expect(defaults.count == 2 && defaults.allSatisfy(\.mention.remind), "an empty reminder query offers today and tomorrow")
        expect(parser.suggestions(for: "3pm", remind: true).first?.mention.hour == 15, "timed reminders keep their time")

        expect(NoteDateParser.reminderQuery("remind me tomorrow") == ("tomorrow", true), "remind me strips off")
        expect(NoteDateParser.reminderQuery("reminder dec 3") == ("dec 3", true), "reminder strips off")
        expect(NoteDateParser.reminderQuery("rem") == ("", true), "rem is already a reminder")
        expect(NoteDateParser.reminderQuery("re").remind == false, "re is not")
        expect(NoteDateParser.reminderQuery("tomorrow").remind == false, "plain dates aren't reminders")

        expect(parser.isPlausiblePrefix("dec"), "a month is on its way to a date")
        expect(parser.isPlausiblePrefix("next fri"), "next fri is on its way")
        expect(parser.isPlausiblePrefix("dec 3 at 5"), "times are on their way")
        expect(parser.isPlausiblePrefix("tomo"), "half a word is fine at the end")
        expect(!parser.isPlausiblePrefix("banana split"), "fruit is not a date")
        expect(!parser.isPlausiblePrefix("tomo "), "half a word followed by a space is not")

        let fire = parser.fireDate(for: NoteDateMention(year: 2026, month: 12, day: 3, remind: true))
        expect(fire == calendar.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 9)), "all-day reminders fire at 9 AM")
        let label = NoteDateFormatting.label(NoteDateMention(year: 2027, month: 1, day: 2), now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        expect(label == "Jan 2, 2027", "other years show the year: \(label)")
        let long = NoteDateFormatting.longLabel(NoteDateMention(year: 2026, month: 12, day: 3, hour: 17, minute: 5), calendar: calendar,
                                                locale: Locale(identifier: "en_US"))
        expect(plain(long) == "Thursday, December 3, 2026 5:05 PM", "long labels spell everything out: \(long)")
        print("NoteSlashDatesTests passed")
    }
}
