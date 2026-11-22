import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsReplacementTests {
    @Test func bodyReplacementLeavesTitleMatchesToTheHeader() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        var touched = page
        #expect(NotePageFinder.replace(matches.filter(\.isTitle), with: "x", in: &touched).isEmpty && touched == page, "page replace leaves title matches to the header")
    }

    @Test func titleReplacementRewritesEveryTitleMatch() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        #expect(NotePageFinder.replacingTitle("Park day at the park", matches: matches, with: "Garden") == "Garden day at the Garden", "title replace rewrites every title match")
    }

    @Test func titleReplacementCanRewriteOnlyTheCurrentMatch() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        #expect(NotePageFinder.replacingTitle("Park day at the park", matches: [matches[1]], with: "beach") == "Park day at the beach", "title replace can swap just the current match")
    }

    @Test func aStaleTitleMatchIsIgnored() {
        #expect(NotePageFinder.replacingTitle("tiny", matches: [.title(offset: 2, length: 10)], with: "x") == "tiny", "a stale title match past the end is ignored")
    }

    @Test func aTitleReplacementKeepsTheCaretInTheTitle() {
        let (page, _) = NotePageToolsTestsSupport.samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        let after = NotePageFinder.positionAfterReplacing(matches[0], with: "Garden")
        #expect(after.block == NoteFindMatch.titleBlock && after.offset == 6, "the caret after a title replace stays in the title")
    }

    @Test func replaceAllRewritesOnlyTheAffectedBlocks() {
        let (original, ids) = NotePageToolsTestsSupport.samplePage()
        var page = original
        let all = NotePageFinder.matches(of: "park", in: page)
        let touched = NotePageFinder.replace(all, with: "garden", in: &page)
        #expect(touched == Set([ids[0], ids[1], ids[2], ids[4], ids[5], ids[6]]), "replace all touches every block with a match")
        #expect(page.block(ids[0])?.text.string == "garden gardens garden at the garden.", "replace all rewrites the paragraph")
        #expect(page.block(ids[0])?.text.marks(at: 15).bold == true, "a replaced bold word stays bold")
        #expect(page.block(ids[0])?.text.marks(at: 7).bold == false, "plain words stay plain")
        #expect(page.block(ids[1])?.props.table?.rows[1][1].string == "gardened", "table cells get replaced")
        #expect(page.block(ids[2])?.props.caption.string == "A garden at dusk", "captions get replaced")
        #expect(page.block(ids[4])?.text.string == "Secret garden", "collapsed toggle children get replaced")
        #expect(page.block(ids[6])?.text.length == 8 && page.block(ids[6])?.text.marks(at: 0).atom != nil, "mentions survive while the text beside them changes")
        #expect(NotePageFinder.matches(of: "park", in: page).isEmpty, "nothing left to find afterwards")
    }

    @Test func replacingTheCurrentMatchLeavesOtherMatchesAlone() {
        let (original, ids) = NotePageToolsTestsSupport.samplePage()
        var single = original
        let first = NotePageFinder.matches(of: "park", in: single)
        NotePageFinder.replace([first[1]], with: "strolls past", in: &single)
        #expect(single.block(ids[0])?.text.string == "Park strolls pasts PARK at the park.", "replace swaps only the current match")
    }

    @Test func searchResumesAfterTheReplacement() {
        let (original, ids) = NotePageToolsTestsSupport.samplePage()
        var single = original
        let first = NotePageFinder.matches(of: "park", in: single)
        NotePageFinder.replace([first[1]], with: "strolls past", in: &single)
        let after = NotePageFinder.positionAfterReplacing(first[1], with: "strolls past")
        let next = NotePageFinder.matches(of: "park", in: single)
        let index = NotePageFinder.firstIndex(atOrAfter: after, in: next, page: single)
        #expect(index.map { next[$0].position.offset } == 19 && index.map { next[$0].block } == ids[0], "the next match after a replace is the following PARK")
    }

    @Test func searchSkipsTheReplacementEvenWhenItContainsTheQuery() {
        var grow = NotePage(blocks: [.paragraph("a a a")])
        let growMatches = NotePageFinder.matches(of: "a", in: grow)
        NotePageFinder.replace([growMatches[0]], with: "aa", in: &grow)
        let growAfter = NotePageFinder.positionAfterReplacing(growMatches[0], with: "aa")
        let regrown = NotePageFinder.matches(of: "a", in: grow)
        let growIndex = NotePageFinder.firstIndex(atOrAfter: growAfter, in: regrown, page: grow)
        #expect(grow.blocks[0].text.string == "aa a a" && growIndex.map { regrown[$0].position.offset } == 3, "a replacement containing the query never loops back onto itself")
    }

    @Test func aStaleBodyMatchIsIgnored() {
        var stale = NotePage(blocks: [.paragraph("tiny")])
        let bogus = NoteFindMatch(stale.blocks[0].id, offset: 2, length: 10)
        #expect(NotePageFinder.replace([bogus], with: "x", in: &stale).isEmpty && stale.blocks[0].text.string == "tiny", "a stale match past the end is ignored")
    }

    @Test func replacingAcrossAnInlineObjectSkipsThatMatch() {
        var atomMarks = NoteMarks.plain
        atomMarks.atom = .equation("x")
        var mixed = NotePage(blocks: [.paragraph(NoteText(pieces: [("ab", .plain), ("\u{FFFC}", atomMarks), ("cd ab", .plain)]))])
        let mixedID = mixed.blocks[0].id
        let spanning = NoteFindMatch(mixedID, offset: 1, length: 3), plain = NoteFindMatch(mixedID, offset: 6, length: 2)
        let outcome = NotePageFinder.replaceCounting([spanning, plain], with: "zz", in: &mixed)
        #expect(outcome.count == 1 && outcome.touched == [mixedID], "a match swallowing an inline object is skipped and not counted")
        #expect(mixed.blocks[0].text.string == "ab\u{FFFC}cd zz", "only the plain match is replaced")
    }

    @Test func aStaleMatchAddsNothingToTheReplacementCount() {
        let stale = NotePage(blocks: [.paragraph("tiny")])
        let bogus = NoteFindMatch(stale.blocks[0].id, offset: 2, length: 10)
        var untouched = NotePage(blocks: [.paragraph("tiny")])
        #expect(NotePageFinder.replaceCounting([bogus], with: "x", in: &untouched).count == 0, "stale matches count as zero")
    }

    @Test func titleReplacementCountsSkipOverlappingAndOutOfRangeMatches() {
        let titleMatches = [NoteFindMatch(NoteFindMatch.titleBlock, offset: 0, length: 2), NoteFindMatch(NoteFindMatch.titleBlock, offset: 1, length: 2),
                            NoteFindMatch(NoteFindMatch.titleBlock, offset: 8, length: 4)]
        #expect(NotePageFinder.titleReplacementCount("parkpark", matches: titleMatches) == 1, "title counting skips overlapping and out-of-range matches")
    }
}
