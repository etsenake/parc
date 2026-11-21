import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteSlashTriggerTests {
    func trigger(_ old: String, _ new: String, _ caret: Int? = nil) -> (NoteInlineTrigger, Int)? {
        NoteTriggerRule.trigger(from: old, to: new, caret: caret ?? (new as NSString).length).map { ($0.trigger, $0.start) }
    }

    func resumed(_ old: String, _ new: String, _ caret: Int? = nil) -> NoteResumedTrigger? {
        NoteTriggerRule.resumedTrigger(from: old, to: new, caret: caret ?? (new as NSString).length)
    }

    @Test(arguments: [("", "/", 0), ("Hello ", "Hello /", 6), ("Hello\n", "Hello\n/", 6)] as [(String, String, Int)])
    func aSlashAtAFreshStartOpensTheMenu(old: String, new: String, start: Int) {
        let found = trigger(old, new)
        #expect(found?.0 == .slash)
        #expect(found?.1 == start)
    }

    @Test func aSlashTypedBeforeAWordButAfterASpaceOpens() {
        let found = trigger(" b", " /b", 2)
        #expect(found?.0 == .slash)
        #expect(found?.1 == 1)
    }

    @Test(arguments: [("and", "and/", nil), ("(", "(/", nil), ("ab", "a/b", 2), ("", "x /", nil), ("Hello /", "Hello /", nil), ("Hello / ", "Hello /", 7)]
          as [(String, String, Int?)])
    func aSlashThatIsNotACommandStaysText(old: String, new: String, caret: Int?) {
        #expect(trigger(old, new, caret) == nil)
    }

    @Test(arguments: [("", "@", NoteInlineTrigger.mention, 0), ("see ", "see @", .mention, 4), ("(", "(@", .mention, 1), ("[", "[[", .noteLink, 0),
                      ("see [", "see [[", .noteLink, 4)] as [(String, String, NoteInlineTrigger, Int)])
    func atSignsAndDoubleBracketsOpenTheirMenus(old: String, new: String, kind: NoteInlineTrigger, start: Int) {
        let found = trigger(old, new)
        #expect(found?.0 == kind)
        #expect(found?.1 == start)
    }

    @Test(arguments: [("me", "me@"), ("a[", "a[[")]) func glueToAWordStaysText(old: String, new: String) {
        #expect(trigger(old, new) == nil)
    }

    @Test func insertionFindsWhatWasTypedAndWhere() {
        let insertion = NoteTriggerRule.insertion(from: "Hello", to: "Hel/lo", caret: 4)
        #expect(insertion?.range == 3..<4)
        #expect(insertion?.text == "/")
    }

    @Test func aReplacementIsNotAnInsertion() { #expect(NoteTriggerRule.insertion(from: "abc", to: "xbc", caret: 1) == nil) }

    @Test func insertionsCountUTF16LikeNoteText() { #expect(NoteTriggerRule.insertion(from: "a", to: "a👍", caret: 3)?.text == "👍") }

    @Test func colonSmSuggestsEmoji() {
        let emoji = NoteTriggerRule.emojiQuery(in: "hi :sm", caret: 6)
        #expect(emoji?.start == 3)
        #expect(emoji?.query == "sm")
    }

    @Test(arguments: [("hi :s", 5), ("12:30", 5), ("Note:ab", 7), ("http://ab", 9), ("hi :sm ile", 10), ("hi :sm", 5), (":+1", 3)] as [(String, Int)])
    func textThatIsNotAnEmojiQueryIsLeftAlone(text: String, caret: Int) {
        #expect(NoteTriggerRule.emojiQuery(in: text, caret: caret) == nil)
    }

    @Test func anEmojiAtTheStartOfABlockWorks() { #expect(NoteTriggerRule.emojiQuery(in: ":smile", caret: 6)?.query == "smile") }

    @Test func underscoresAndBracketsWork() { #expect(NoteTriggerRule.emojiQuery(in: "(:thumbs_up", caret: 11)?.query == "thumbs_up") }

    @Test func aShortcodeCompletes() {
        let done = NoteTriggerRule.completedShortcode(in: "hi :smile:", caret: 10)
        #expect(done?.range == 3..<10)
        #expect(done?.shortcode == "smile")
    }

    @Test(arguments: [("10:30:", 6), ("::", 2)] as [(String, Int)])
    func clockTimesAndEmptyShortcodesNeverComplete(text: String, caret: Int) {
        #expect(NoteTriggerRule.completedShortcode(in: text, caret: caret) == nil)
    }

    @Test func shortcodesAreCaseInsensitive() { #expect(NoteTriggerRule.completedShortcode(in: ":Heart:", caret: 7)?.shortcode == "heart") }

    @Test func anEmptyQueryStaysOpen() {
        var slash = NoteQueryTracker.slash
        #expect(slash.update(query: "", hasResults: true) == .open)
    }

    @Test func matchesKeepTheMenuOpen() {
        var slash = NoteQueryTracker.slash
        #expect(slash.update(query: "h", hasResults: true) == .open)
    }

    @Test func missesAreForgivenTwiceThenTheMenuCloses() {
        var slash = NoteQueryTracker.slash
        _ = slash.update(query: "h", hasResults: true)
        #expect(slash.update(query: "hx", hasResults: false) == .open)
        #expect(slash.update(query: "hxy", hasResults: false) == .open)
        #expect(slash.update(query: "hxyz", hasResults: false) == .close)
    }

    @Test func spacesAreFineWhileThingsMatch() {
        var spaced = NoteQueryTracker.slash
        _ = spaced.update(query: "red", hasResults: true)
        #expect(spaced.update(query: "red b", hasResults: true) == .open)
    }

    @Test func aSpaceWithNoResultsCloses() {
        var spaced = NoteQueryTracker.slash
        _ = spaced.update(query: "red", hasResults: true)
        #expect(spaced.update(query: "red bx ", hasResults: false) == .close)
    }

    @Test func aSlashFollowedByASpaceWasNeverACommand() {
        var leading = NoteQueryTracker.slash
        #expect(leading.update(query: " ", hasResults: false) == .close)
    }

    @Test func mentionsTolerateSpacesWhileYouTypeADate() {
        var mention = NoteQueryTracker.mention
        _ = mention.update(query: "dec", hasResults: true)
        #expect(mention.update(query: "dec ", hasResults: false) == .open)
        #expect(mention.update(query: "dec 3", hasResults: true) == .open)
    }

    @Test func mentionsGiveUpAfterAFewMisses() {
        var mention = NoteQueryTracker.mention
        _ = mention.update(query: "dec 3", hasResults: true)
        #expect(mention.update(query: "dec 3 zzzz", hasResults: false) == .close)
    }

    @Test func aLineBreakAlwaysCloses() {
        var newline = NoteQueryTracker.mention
        #expect(newline.update(query: "a\n", hasResults: false) == .close)
    }

    @Test(arguments: [9, 4, 1]) func theTokenIsEverythingTypedAfterTheTriggerWhereverTheCaretSits(caret: Int) {
        var at = NoteQueryToken(start: 0, trigger: "@", text: "@", caret: 1)
        #expect(at.resolve(in: "@tomorrow", caret: caret) == NoteQueryMatch(query: "tomorrow", range: 0..<9))
    }

    @Test func slippingLeftOfTheTriggerClosesTheMenu() {
        var at = NoteQueryToken(start: 0, trigger: "@", text: "@", caret: 1)
        #expect(at.resolve(in: "@tomorrow", caret: 0) == nil)
    }

    @Test func choosingReplacesTheWholeQuery() {
        var at = NoteQueryToken(start: 0, trigger: "@", text: "@", caret: 1)
        var dated = NoteText("@tomorrow")
        if let range = at.resolve(in: dated.string, caret: 4)?.range {
            dated.replace(range, with: .atom(.date(NoteDateMention(year: 2026, month: 11, day: 21))))
        }
        #expect(dated.string == NoteAtom.character)
    }

    func slashToken() -> NoteQueryToken { NoteQueryToken(start: 6, trigger: "/", text: "Hello / world", caret: 7) }

    @Test func wordsAfterTheTokenAreNotPartOfIt() {
        var token = slashToken()
        #expect(token.resolve(in: "Hello /hea world", caret: 10) == NoteQueryMatch(query: "hea", range: 6..<10))
    }

    @Test func theQueryIsTheWholeTokenWhereverTheCaretIs() {
        var token = slashToken()
        #expect(token.resolve(in: "Hello /hea world", caret: 8)?.query == "hea")
    }

    @Test func movingPastTheTokensEndClosesTheMenu() {
        var token = slashToken()
        #expect(token.resolve(in: "Hello /hea world", caret: 11) == nil)
    }

    @Test func typingInTheMiddleGrowsTheToken() {
        var token = slashToken()
        #expect(token.resolve(in: "Hello /head world", caret: 9)?.query == "head")
    }

    @Test func forwardDeletingIntoTheNextWordKeepsTheToken() {
        var token = slashToken()
        let match = token.resolve(in: "Hello /headworld", caret: 11)
        #expect(match?.query == "head")
        #expect(match?.range == 6..<11)
    }

    @Test func deletingTheTriggerClosesTheMenu() {
        var token = slashToken()
        #expect(token.resolve(in: "Hello head world", caret: 10) == nil)
    }

    @Test func aLineBreakInsideTheTokenClosesTheMenu() {
        var broken = NoteQueryToken(start: 0, trigger: "/", text: "/", caret: 1)
        #expect(broken.resolve(in: "/he\nad", caret: 3) == nil)
    }

    @Test func menusWithoutATriggerTrackTheirTokenToo() {
        var plus = NoteQueryToken(start: 0, trigger: "", text: "", caret: 0)
        #expect(plus.resolve(in: "quo", caret: 1)?.query == "quo")
    }

    @Test func pickingABlockWithTheCaretMidQueryLeavesNoStrayLetters() throws {
        let typed = NoteBlock.paragraph(NoteText("/heading"))
        var heading = NoteQueryToken(start: 0, trigger: "/", text: "/", caret: 1)
        let range = heading.resolve(in: "/heading", caret: 3)?.range ?? 0..<3
        let applied = try #require(NoteCatalogApplier.apply(.block(.heading(1)), to: NotePage(blocks: [typed]), at: NotePosition(typed.id, 0), removing: range))
        #expect(applied.page.blocks.first?.kind == .heading)
        #expect(applied.page.blocks.first?.text.isEmpty == true)
    }

    @Test func emojiTokensCoverTheWholeShortcode() {
        var shortcode = NoteQueryToken(start: 3, trigger: ":", text: "hi :sm", caret: 6)
        #expect(shortcode.resolve(in: "hi :smile", caret: 6) == NoteQueryMatch(query: "smile", range: 3..<9))
    }

    @Test(arguments: ["smile", "thumbs_up"]) func shortcodesAreEmojiQueries(text: String) { #expect(NoteTriggerRule.isEmojiQuery(text)) }

    @Test(arguments: ["s", "+1", "sm ile"]) func shortSymbolLedOrSpacedQueriesAreNot(text: String) { #expect(!NoteTriggerRule.isEmojiQuery(text)) }

    @Test(arguments: [
        ("@x", "@", NoteResumedTrigger.inline(.mention, start: 0)), ("see @jx", "see @j", .inline(.mention, start: 4)),
        ("see @j", "see @jo", .inline(.mention, start: 4)), ("@dec 3", "@dec 3 ", .inline(.mention, start: 0)),
        ("(@n", "(@", .inline(.mention, start: 1)), ("/hx", "/h", .inline(.slash, start: 0)), ("Hello /", "Hello /h", .inline(.slash, start: 6)),
        ("see [[ab", "see [[a", .inline(.noteLink, start: 4)), ("hi :smx", "hi :sm", .emoji(start: 3, query: "sm")),
        ("hi :sm", "hi :smi", .emoji(start: 3, query: "smi")), ("@dec :sm", "@dec :smi", .emoji(start: 5, query: "smi")),
    ] as [(String, String, NoteResumedTrigger)])
    func editingBackIntoATriggerBringsItsMenuBack(old: String, new: String, expected: NoteResumedTrigger) {
        #expect(resumed(old, new) == expected)
    }

    @Test(arguments: [
        ("/red b", "/red bl"), ("@ x", "@ "), ("me@x", "me@"), ("a/bx", "a/b"), ("@a\nbx", "@a\nb"),
        ("@a\(NoteAtom.character)bx", "@a\(NoteAtom.character)b"), ("@ab", "@ab"),
        ("@" + String(repeating: "a", count: 80), "@" + String(repeating: "a", count: 81)),
    ])
    func editsThatDoNotReopenAMenu(old: String, new: String) { #expect(resumed(old, new) == nil) }

    @Test func pastingNeverOpensAMenu() { #expect(resumed("", "@ab", 3) == nil) }

    @Test func anEditAwayFromTheCaretIsNotTypingThere() {
        #expect(NoteTriggerRule.resumedTrigger(from: "@abc", to: "@ac", caret: 3) == nil)
    }

    @Test func forwardDeleteAtTheCaretReopensTheMenu() {
        #expect(NoteTriggerRule.resumedTrigger(from: "@abc", to: "@ac", caret: 2) == .inline(.mention, start: 0))
    }

    @Test func aCaretBeforeTheAtSignIsOutsideIt() { #expect(NoteTriggerRule.activeTrigger(in: "@abc", caret: 0) == nil) }

    @Test(arguments: [(1, "@", 0, "@"), (4, "@", 0, "@foo")] as [(Int, String, Int, String)])
    func aBareTriggerAndItsQueryHoldAnEscape(caret: Int, trigger: String, start: Int, text: String) {
        #expect(NoteTriggerRule.caret(caret, isInside: trigger, at: start, in: text))
    }

    @Test(arguments: [(0, "@", 0, "@foo"), (3, "@", 0, "foo"), (4, "@", 0, "@a\nb"), (0, "", 0, "")] as [(Int, String, Int, String)])
    func movingAwayLetsATriggerGo(caret: Int, trigger: String, start: Int, text: String) {
        #expect(!NoteTriggerRule.caret(caret, isInside: trigger, at: start, in: text))
    }

    @Test func aReopenedMenuForgivesMissesAsIfItHadBeenTyped() {
        var tracker = NoteQueryTracker.slash
        tracker.resume(query: "hxy") { $0 == "h" }
        #expect(tracker.update(query: "hxy", hasResults: false) == .open)
    }

    @Test func aReopenedMenuClosesWhereTypingWould() {
        var tracker = NoteQueryTracker.slash
        tracker.resume(query: "hxyz") { $0 == "h" }
        #expect(tracker.update(query: "hxyz", hasResults: false) == .close)
    }

    @Test func aShortMissStaysOpenLikeAFreshAtSign() {
        var tracker = NoteQueryTracker.mention
        tracker.resume(query: "zz") { _ in false }
        #expect(tracker.update(query: "zz", hasResults: false) == .open)
    }
}
