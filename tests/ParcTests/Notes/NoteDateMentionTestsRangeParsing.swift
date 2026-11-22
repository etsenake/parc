import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

struct NoteDateMentionTestsRangeParsing {
    private struct DateParseCase: Sendable, CustomTestStringConvertible {
        let input: String
        let wanted: String

        var testDescription: String { "\(input)" }
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

    @Test(arguments: [
        DateParseCase(input: "jan 3", wanted: "2027-01-03"),
        DateParseCase(input: "sept 9", wanted: "2026-09-09"),
        DateParseCase(input: "1/12", wanted: "2027-01-12"),
        DateParseCase(input: "Jan 3 \u{2192} Jan 5", wanted: "2027-01-03 > 2027-01-05"),
        DateParseCase(input: "@Jan 3 - 5", wanted: "2027-01-03 > 2027-01-05"),
        DateParseCase(input: "jan 3-5", wanted: "2027-01-03 > 2027-01-05"),
        DateParseCase(input: "jan 3\u{2013}5", wanted: "2027-01-03 > 2027-01-05"),
        DateParseCase(input: "3-5 jan", wanted: "2027-01-03 > 2027-01-05"),
        DateParseCase(input: "jan 3 -> jan 5", wanted: "2027-01-03 > 2027-01-05"),
        DateParseCase(input: "jan 3 to jan 5, 2028", wanted: "2028-01-03 > 2028-01-05"),
        DateParseCase(input: "dec 30 - jan 2", wanted: "2026-12-30 > 2027-01-02"),
        DateParseCase(input: "jan 30 - 2", wanted: "2027-01-30 > 2027-02-02"),
        DateParseCase(input: "today until monday", wanted: "2026-11-20 > 2026-11-23"),
        DateParseCase(input: "tomorrow 3pm - 5pm", wanted: "2026-11-21 15:00 > 2026-11-21 17:00"),
        DateParseCase(input: "3-5pm", wanted: "2026-11-20 15:00 > 2026-11-20 17:00"),
        DateParseCase(input: "11-1pm", wanted: "2026-11-20 11:00 > 2026-11-20 13:00"),
        DateParseCase(input: "dec 3 9am \u{2192} dec 5", wanted: "2026-12-03 09:00 > 2026-12-05 09:00"),
        DateParseCase(input: "dec 3 \u{2192} dec 5 6pm", wanted: "2026-12-03 18:00 > 2026-12-05 18:00"),
        DateParseCase(input: "2026-12-03", wanted: "2026-12-03"),
        DateParseCase(input: "12-3", wanted: "2026-12-03"),
    ])
    private func datesAndRangesParse(sample: DateParseCase) { #expect(describe(fixture.parser.parse(sample.input)) == sample.wanted) }

    @Test(arguments: ["jan 5 - jan 3", "jan 3 -", "jan 3 \u{2192} banana"])
    func brokenRangesDoNotParse(input: String) { #expect(describe(fixture.parser.parse(input)) == nil) }

    @Test(arguments: ["jan 3 -", "jan 3 \u{2192} ja"])
    func aHalfTypedRangeStillOffersItsStart(input: String) {
        #expect(fixture.parser.suggestions(for: input).contains { describe($0.mention) == "2027-01-03" })
    }

    @Test func aTypedRangeIsTheFirstSuggestion() {
        #expect(describe(fixture.parser.suggestions(for: "jan 3 \u{2192} jan 5").first?.mention) == "2027-01-03 > 2027-01-05")
    }

    @Test func aTypedRangeReadsAsARange() {
        #expect(fixture.plain(fixture.parser.suggestions(for: "jan 3 \u{2192} jan 5").first?.title ?? "") == "Sun, Jan 3, 2027 \u{2192} Tue, Jan 5, 2027")
    }

    @Test func completionsStayNearTheStart() {
        #expect(!fixture.parser.suggestions(for: "jan 3 \u{2192} jan").contains { ($0.mention.end?.year ?? 0) > 2027 })
    }

    @Test(arguments: ["jan 3 \u{2192} ja", "jan 3 to", "dec 3 3-5pm"])
    func rangeSyntaxKeepsTheMenuOpen(input: String) { #expect(fixture.parser.isPlausiblePrefix(input)) }

    @Test func aRangeReminderGivesBothEndsATime() {
        var range = NoteDateMention(year: 2026, month: 11, day: 24)
        range.end = NoteDateEnd(year: 2026, month: 11, day: 26)
        #expect(describe(fixture.parser.reminderVersion(of: range)) == "2026-11-24 09:00 > 2026-11-26 09:00")
    }

    @Test func remindWorksOnRanges() {
        #expect(describe(fixture.parser.suggestions(for: "nov 24 - 26", remind: true).first?.mention) == "2026-11-24 09:00 > 2026-11-26 09:00")
    }
}
