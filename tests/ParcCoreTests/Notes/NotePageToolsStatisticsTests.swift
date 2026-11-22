import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsStatisticsTests {
    @Test func anEmptyPageHasNothingToRead() {
        let empty = NotePageStats(page: NotePage(blocks: [.paragraph()]))
        #expect(empty.words == 0 && empty.readingMinutes == 0 && empty.summary == "No words yet", "an empty page has nothing to read")
    }

    @Test func oneWordIsAOneMinuteRead() {
        let one = NotePageStats(page: NotePage(blocks: [.paragraph("Hello")]))
        #expect(one.words == 1 && one.wordLabel == "1 word" && one.readingMinutes == 1 && one.summary == "1 word · 1 min read", "one word is a one-minute read")
    }

    @Test func wordCountsIncludeCellsCaptionsCodeAndMentionTitles() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let sample = NotePageStats(page: page)
        #expect(sample.words == 22, "words count body, cells, captions, code and mention titles (got \(sample.words))")
    }

    @Test func readingMinutesRoundUp() {
        let long = NotePage(blocks: [.paragraph(NoteText(Array(repeating: "word", count: 239).joined(separator: " ")))])
        let longStats = NotePageStats(page: long)
        #expect(longStats.words == 239 && longStats.readingMinutes == 2, "239 words rounds up to two minutes")
    }

    @Test func largeWordCountsUseDigitGrouping() {
        #expect(NotePageStats(words: 1234, characters: 0).wordLabel.contains("234") && NotePageStats(words: 1234, characters: 0).wordLabel.hasSuffix(" words"), "big counts are grouped")
    }

    @Test func characterCountsUseGraphemesAndSkipLineBreaks() {
        let chars = NotePageStats(page: NotePage(blocks: [.paragraph("ab"), .paragraph("👋🏽")]))
        #expect(chars.characters == 3, "characters count graphemes and skip line breaks (got \(chars.characters))")
    }
}
