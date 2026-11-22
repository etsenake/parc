import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteDateMentionTestsMarkup {
    private typealias Fixture = NoteDateMentionTestsSupport.Fixture

    private let fixture = Fixture()

    private let legacy = "<time datetime=\"2026-11-20T09:30\" data-remind>2026-11-20 09:30</time>"

    @Test func olderRemindersStillRead() {
        #expect(fixture.mention(in: fixture.text(legacy)) == NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true))
    }

    @Test func olderRemindersSaveByteForByte() { #expect(fixture.markdown(fixture.text(legacy)) == legacy) }

    @Test func plainDatesSaveByteForByte() {
        let plainDate = "<time datetime=\"2026-11-20\">2026-11-20</time>"
        #expect(fixture.markdown(fixture.text(plainDate)) == plainDate)
    }

    private let rangeSource = "<time datetime=\"2027-01-03\" data-end=\"2027-01-05\">2027-01-03 \u{2192} 2027-01-05</time>"

    @Test func rangesSaveTheirEnd() { #expect(fixture.markdown(.atom(.date(fixture.rangeMention))) == rangeSource) }

    @Test func rangesReadBack() { #expect(fixture.mention(in: fixture.text(rangeSource)) == fixture.rangeMention) }

    private static var everything: NoteDateMention {
        var value = NoteDateMention(year: 2027, month: 1, day: 3, hour: 9, minute: 0, remind: true)
        value.end = NoteDateEnd(year: 2027, month: 1, day: 5, hour: 17, minute: 30)
        value.timeZone = "America/New_York"
        value.remindBefore = 30
        value.format = .full
        value.timeFormat = .twentyFourHour
        return value
    }

    private let fullSource = "<time datetime=\"2027-01-03T09:00\" data-end=\"2027-01-05T17:30\" data-timezone=\"America/New_York\" data-remind=\"30m\""
        + " data-format=\"full\" data-clock=\"24h\">2027-01-03 09:00 \u{2192} 2027-01-05 17:30</time>"

    @Test func everySettingHasItsAttribute() { #expect(fixture.markdown(.atom(.date(Self.everything))) == fullSource) }

    @Test func everySettingReadsBack() { #expect(fixture.mention(in: fixture.text(fullSource)) == Self.everything) }

    private let shuffledSource = "<time data-clock=\"24h\" data-remind=\"30m\" data-format=\"full\" data-timezone=\"America/New_York\""
        + " data-end=\"2027-01-05T17:30\" datetime=\"2027-01-03T09:00\">whatever</time>"

    @Test func attributeOrderDoesNotMatter() { #expect(fixture.mention(in: fixture.text(shuffledSource)) == Self.everything) }

    @Test func savingPutsTheAttributesInOrder() { #expect(fixture.markdown(fixture.text(shuffledSource)) == fullSource) }

    @Test func minutesReadAsMinutes() {
        #expect(fixture.mention(in: fixture.text("<time datetime=\"2026-12-01T10:00\" data-remind=\"60m\">x</time>"))?.remindBefore == 60)
    }

    @Test func leadsSaveInTheBiggestUnit() {
        #expect(fixture.markdown(fixture.text("<time datetime=\"2026-12-01T10:00\" data-remind=\"60m\">x</time>"))
                == "<time datetime=\"2026-12-01T10:00\" data-remind=\"1h\">2026-12-01 10:00</time>")
    }

    @Test func aZeroLeadIsThePlainReminder() {
        #expect(fixture.mention(in: fixture.text("<time datetime=\"2026-12-01\" data-remind=\"0m\">x</time>"))?.remindBefore == nil)
    }

    private static let badTimes = [
        "<time datetime=\"2026-12-01\" data-remind=\"soon\">x</time>", "<time datetime=\"2026-12-01\" class=\"x\">x</time>",
        "<time datetime=\"2026-12-01\" data-end=\"2026-12-02\" data-end=\"2026-12-03\">x</time>",
        "<time datetime=\"2026-12-01\" data-format=\"relative\">x</time>", "<time datetime=\"2026-12-01\" data-clock=\"36h\">x</time>",
        "<time datetime=\"2026-12-01\" data-end=\"soon\">x</time>", "<time datetime=\"2026-12-01\" data-timezone=\"\">x</time>",
        "<time data-end=\"2026-12-02\">x</time>",
    ]

    @Test(arguments: NoteDateMentionTestsMarkup.badTimes)
    func anUnreadableTimeStaysRaw(bad: String) { #expect(fixture.mention(in: fixture.text(bad)) == nil) }

    @Test(arguments: NoteDateMentionTestsMarkup.badTimes)
    func anUnreadableTimeSurvivesASave(bad: String) { #expect(fixture.markdown(fixture.text(bad)) == bad) }

    private struct RoundTripCase: @unchecked Sendable, CustomTestStringConvertible {
        let mention: NoteDateMention
        var testDescription: String { NoteAtom.date(mention).fallbackText }
    }

    private static let roundTripMentions: [RoundTripCase] = {
        var mentions: [NoteDateMention] = [Fixture().rangeMention, everything]
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
        return mentions.map { RoundTripCase(mention: $0) }
    }()

    @Test(arguments: NoteDateMentionTestsMarkup.roundTripMentions)
    private func aDateMentionRoundTripsThroughMarkdown(sample: RoundTripCase) {
        let markup = fixture.markdown(.atom(.date(sample.mention)))
        #expect(fixture.mention(in: fixture.text(markup)) == sample.mention)
    }

    @Test(arguments: NoteDateMentionTestsMarkup.roundTripMentions)
    private func aDateMentionRoundTripsThroughHTML(sample: RoundTripCase) {
        let html = NotePageHTML.fragment([.paragraph(.atom(.date(sample.mention)))])
        let parsed = NoteHTMLReader.blocks(from: html, baseURL: nil).first.flatMap { fixture.mention(in: $0.text) }
        #expect(parsed == sample.mention)
    }

    @Test func htmlShowsTheRange() {
        let exported = NotePageHTML.fragment([.paragraph(.atom(.date(fixture.rangeMention)))])
        #expect(exported.contains("data-end=\"2027-01-05\""))
        #expect(exported.contains("\u{2192}"))
    }

    @Test func plainTextKeepsBothEnds() { #expect(NoteAtom.date(fixture.rangeMention).fallbackText == "2027-01-03 \u{2192} 2027-01-05") }

    @Test func olderHTMLRemindersStillPaste() {
        let read = NoteHTMLReader.blocks(from: "<p><time data-mention=\"date\" datetime=\"2026-11-20T09:30\" data-remind=\"true\">@x</time></p>", baseURL: nil)
            .first.flatMap { fixture.mention(in: $0.text) }
        #expect(read == NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true))
    }
}
