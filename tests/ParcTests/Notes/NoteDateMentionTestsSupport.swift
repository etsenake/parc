import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

enum NoteDateMentionTestsSupport {
    struct Fixture {
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

        func text(_ markdown: String) -> NoteText { NoteMarkdown.parse(markdown).blocks.first?.text ?? NoteText() }

        func markdown(_ text: NoteText) -> String {
            NoteMarkdown.serialize(NotePage(blocks: [.paragraph(text)])).trimmingCharacters(in: .newlines)
        }

        func mention(in text: NoteText) -> NoteDateMention? {
            for run in text.runs() { if case .date(let value)? = run.marks.atom { return value } }
            return nil
        }

        let parser = NoteDateParser(now: Fixture.now, calendar: Fixture.calendar, dayFirst: false, locale: Fixture.locale)

        var rangeMention: NoteDateMention {
            var range = NoteDateMention(year: 2027, month: 1, day: 3)
            range.end = NoteDateEnd(year: 2027, month: 1, day: 5)
            return range
        }
    }
}
