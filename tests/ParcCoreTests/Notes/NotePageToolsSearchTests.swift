import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsSearchTests {
    @Test func searchFindsEveryMatchInDocumentOrder() {
        let (page, ids) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page)
        let expected: [(NoteBlockID, NoteTextField, Int)] = [
            (ids[0], .body, 0), (ids[0], .body, 5), (ids[0], .body, 11), (ids[0], .body, 23),
            (ids[1], .cell(row: 0, column: 0), 0), (ids[1], .cell(row: 1, column: 1), 0),
            (ids[2], .caption, 2),
            (ids[4], .body, 7),
            (ids[5], .body, 4),
            (ids[6], .body, 2),
        ]
        #expect(matches.count == expected.count, "finds every park across body, cells, caption, collapsed toggle, code and mention text (got \(matches.count))")
        for (match, want) in zip(matches, expected) {
            #expect(match.block == want.0 && match.field == want.1 && match.position.offset == want.2 && match.length == 4, "match \(want) lands in document order")
        }
    }

    @Test func caseSensitiveSearchKeepsOnlyMatchingCapitalization() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let cased = NotePageFinder.matches(of: "Park", in: page, options: NoteFindOptions(matchCase: true))
        #expect(cased.count == 2, "match case keeps only the capitalised Parks (got \(cased.count))")
    }

    @Test func anEmptySearchMatchesNothing() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        #expect(NotePageFinder.matches(of: "", in: page).isEmpty, "an empty query matches nothing")
    }

    @Test func aWordOutsideThePageMatchesNothing() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        #expect(NotePageFinder.matches(of: "zebra", in: page).isEmpty, "a missing word matches nothing")
    }

    @Test func searchMatchesDoNotOverlap() {
        #expect(NotePageFinder.ranges(of: "aa", in: "aaaa") == [0..<2, 2..<4], "matches never overlap")
    }

    @Test func caseInsensitiveSearchFoldsDiacritics() {
        #expect(NotePageFinder.ranges(of: "cafe", in: "Café cafe") == [0..<4, 5..<9], "diacritics fold when case is ignored")
    }

    @Test func searchMatchesComposedAndDecomposedAccents() {
        #expect(NotePageFinder.ranges(of: "e\u{301}", in: "x\u{e9}y").count == 1, "composed and decomposed accents still meet")
    }

    @Test func searchCanFindAnAtomCharacterLiterally() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        #expect(NotePageFinder.matches(of: "\u{FFFC}", in: page).isEmpty == false, "the atom character itself is findable only literally")
    }

    @Test func searchStartsAtTheFirstMatchAfterTheCaret() {
        let (page, ids) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page)
        let caret = NotePosition(ids[2], 0, field: .body)
        #expect(NotePageFinder.firstIndex(atOrAfter: caret, in: matches, page: page) == 6, "the first match after the caret is the caption")
    }

    @Test func searchWrapsPastTheEndOfThePage() {
        let (page, ids) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page)
        let end = NotePosition(ids[6], 99)
        #expect(NotePageFinder.firstIndex(atOrAfter: end, in: matches, page: page) == 0, "searching past the end wraps to the top")
    }

    @Test func searchWithoutACaretStartsAtTheTop() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page)
        #expect(NotePageFinder.firstIndex(atOrAfter: nil, in: matches, page: page) == 0, "no caret starts at the top")
    }

    @Test func searchOffsetsUseUTF16() {
        let emoji = NotePage(blocks: [.paragraph("👋 park 👋 park")])
        let emojiMatches = NotePageFinder.matches(of: "park", in: emoji)
        #expect(emojiMatches.map(\.position.offset) == [3, 11], "offsets are UTF-16, so emoji count twice")
    }

    @Test func searchListsTitleMatchesInOrderBeforeTheBody() {
        let (page, ids) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        #expect(matches.count == 12, "the title adds its two parks to the ten in the body (got \(matches.count))")
        #expect(matches[0].isTitle && matches[0].position.offset == 0 && matches[1].isTitle && matches[1].position.offset == 16, "title matches come first, in order")
        #expect(!matches[2].isTitle && matches[2].block == ids[0], "the body follows the title")
        #expect(matches.filter(\.isTitle).allSatisfy { $0.field == .body && $0.length == 4 }, "title matches carry plain ranges")
    }

    @Test func anEmptyTitleAddsNoSearchMatches() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        #expect(NotePageFinder.matches(of: "park", in: page, title: "").count == 10, "an empty title adds nothing")
    }

    @Test func searchWithoutATitleReturnsOnlyBodyMatches() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        #expect(NotePageFinder.matches(of: "park", in: page, title: nil).count == 10, "no title means body only")
    }

    @Test func searchWithoutACaretStartsAtTheTitle() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        #expect(NotePageFinder.firstIndex(atOrAfter: nil, in: matches, page: page) == 0, "no caret starts at the title")
    }

    @Test func aBodyCaretSkipsEarlierTitleMatches() {
        let (page, ids) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        let inBody = NotePosition(ids[0], 0)
        #expect(NotePageFinder.firstIndex(atOrAfter: inBody, in: matches, page: page) == 2, "a caret in the body skips the title")
    }

    @Test func aTitleCaretFindsTheNextTitleMatch() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        let titleCaret = NotePosition(NoteFindMatch.titleBlock, 5)
        #expect(NotePageFinder.firstIndex(atOrAfter: titleCaret, in: matches, page: page) == 1, "a caret in the title finds the next title match")
    }

    @Test func searchWrapsToTheTitle() {
        let (page, ids) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        let end = NotePosition(ids[6], 99)
        #expect(NotePageFinder.firstIndex(atOrAfter: end, in: matches, page: page) == 0, "wrapping past the end lands back on the title")
    }

    @Test func caseSensitiveSearchIncludesTheTitle() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let cased = NotePageFinder.matches(of: "Park", in: page, title: "Park park", options: NoteFindOptions(matchCase: true))
        #expect(cased.filter(\.isTitle).count == 1, "match case applies to the title too")
    }
}
