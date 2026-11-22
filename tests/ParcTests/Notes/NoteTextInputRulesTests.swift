import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteTextInputRulesTests {
    typealias Blocks = NoteEditorBlocks

    func typed(_ string: String, in kind: NoteBlockKind = .paragraph, caret: Int? = nil, text: NoteText? = nil,
               configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteInputRule? {
        let value = text ?? NoteText(string)
        let source = Blocks.block(kind, value.string, [], configure)
        let position = caret ?? value.length
        let inserted = (value.string as NSString).substring(with: NSRange(location: position - 1, length: 1))
        return NoteInputRules.afterTyping(inserted, text: value, caret: position, block: NoteBlock(kind, text: value, props: source.props))
    }

    func shortcut(_ string: String, in kind: NoteBlockKind = .paragraph, caret: Int? = nil) -> NoteBlockShortcut? {
        if case .block(let value) = typed(string, in: kind, caret: caret) { return value }
        return nil
    }

    func inline(_ string: String, text: NoteText? = nil) -> NoteInlineConversion? {
        if case .inline(let value) = typed(string, text: text) { return value }
        return nil
    }

    @Test(arguments: [("# ", 1), ("### ", 3), ("#### ", 4)] as [(String, Int)])
    func hashesMakeAHeading(typedText: String, level: Int) {
        #expect(shortcut(typedText)?.conversion == .heading(level))
    }

    @Test func sevenHashesStayText() { #expect(shortcut("####### ") == nil) }

    @Test func aShortcutTypedBeforeExistingTextConvertsTheBlock() {
        #expect(shortcut("# Title", caret: 2)?.prefixLength == 2)
    }

    @Test func doubleHashInAToggleMakesAToggleHeading() { #expect(shortcut("## ", in: .toggle)?.conversion == .toggleHeading(2)) }

    @Test func aHeading1StaysAHeading1() { #expect(shortcut("# ", in: .heading) == nil) }

    @Test(arguments: ["- ", "+ "]) func bulletMarkersMakeABullet(marker: String) {
        #expect(shortcut(marker)?.conversion == .bulletedList)
    }

    @Test func starKeepsItsMarkerForTheFile() { #expect(shortcut("* ")?.bulletMarker == "*") }

    @Test func aBulletStaysABullet() { #expect(shortcut("- ", in: .bulletedItem) == nil) }

    @Test(arguments: ["1. ", "a. ", "i. "]) func numberedMarkersMakeANumberedItem(marker: String) {
        #expect(shortcut(marker)?.conversion == .numberedList)
    }

    @Test func oneDotStartsAtOne() { #expect(shortcut("1. ")?.listStart == nil) }

    @Test func sevenDotStartsAtSeven() { #expect(shortcut("7. ")?.listStart == 7) }

    @Test func threeParenKeepsItsParenthesis() { #expect(shortcut("3) ")?.orderedDelimiter == ")") }

    @Test func bDotStaysText() { #expect(shortcut("b. ") == nil) }

    @Test(arguments: ["[] ", "[ ] "]) func bracketsMakeATodo(marker: String) {
        #expect(shortcut(marker)?.conversion == .todo)
    }

    @Test func xBracketsMakeADoneTodo() { #expect(shortcut("[x] ")?.checked == true) }

    @Test func emptyBracketsStartUnchecked() { #expect(shortcut("[] ")?.checked == false) }

    @Test func greaterThanMakesAToggle() { #expect(shortcut("> ")?.conversion == .toggle) }

    @Test func aToggleStaysAToggle() { #expect(shortcut("> ", in: .toggle) == nil) }

    @Test(arguments: ["\" ", "| "]) func quoteMarkersMakeAQuote(marker: String) {
        #expect(shortcut(marker)?.conversion == .quote)
    }

    @Test func threeHyphensMakeADivider() { #expect(shortcut("---")?.conversion == .divider) }

    @Test func threeHyphensFireOnTheThirdHyphenOnly() {
        #expect(shortcut("---", caret: 3) != nil)
        #expect(shortcut("--- ") == nil)
    }

    @Test func threeHyphensInFrontOfTextStayText() { #expect(typed("---x", caret: 3) == nil) }

    @Test func dollarsMakeAnEquationBlock() { #expect(shortcut("$$")?.conversion == .equation) }

    @Test func backticksAndASpaceMakeCode() { #expect(shortcut("``` ")?.conversion == .code) }

    @Test func aFenceWithALanguageAndASpaceMakesThatLanguage() { #expect(shortcut("```swift ")?.language == "swift") }

    func fence(_ text: String) -> NoteInputRule? {
        NoteInputRules.onNewline(text: NoteText(text), caret: (text as NSString).length, block: Blocks.para(text))
    }

    @Test func aFenceAndReturnMakeCode() {
        guard case .block(let value)? = fence("```python") else {
            Issue.record("```python and Return should make code")
            return
        }
        #expect(value.conversion == .code)
        #expect(value.language == "python")
        #expect(value.prefixLength == 9)
    }

    @Test func aFenceWithSpacesStaysText() { #expect(fence("``` x y") == nil) }

    @Test func plainTextSplitsNormally() { #expect(fence("hello") == nil) }

    @Test func codeBlocksNeverConvert() { #expect(shortcut("# ", in: .code) == nil) }

    @Test func aHashAfterTextStaysText() { #expect(shortcut("x# ") == nil) }

    @Test func anAtomNeverCountsAsAMarker() {
        let atomic = NoteText.atom(.equation("x")) + NoteText(" ")
        #expect(NoteInputRules.afterTyping(" ", text: atomic, caret: 2, block: Blocks.para()) == nil)
    }

    @Test func boldDelimitersDisappear() { #expect(inline("hello **world**")?.text.string == "hello world") }

    @Test func boldLandsOnTheWord() {
        let bold = inline("hello **world**")
        #expect(bold?.text.allHave(.bold, in: 6..<11) == true)
        #expect(bold?.text.marks(at: 5).bold == false)
    }

    @Test func theCaretSitsAfterTheBoldRun() { #expect(inline("hello **world**")?.caret == 11) }

    @Test func typingAfterTheConversionIsPlain() { #expect(inline("hello **world**")?.typingMarks.bold == false) }

    @Test func theBoldUndoStepIsCalledBold() { #expect(inline("hello **world**")?.name == "Bold") }

    @Test(arguments: ["hello **world*", "a **b** c **d*"])
    func aHalfClosedBoldWaits(text: String) { #expect(inline(text) == nil) }

    @Test func doubleUnderscoresMakeBold() { #expect(inline("__init__")?.text.allHave(.bold, in: 0..<4) == true) }

    @Test func starsMakeItalic() {
        let italic = inline("say *hi*")
        #expect(italic?.text.string == "say hi")
        #expect(italic?.text.allHave(.italic, in: 4..<6) == true)
    }

    @Test func underscoresMakeItalic() { #expect(inline("say _hi_")?.text.allHave(.italic, in: 4..<6) == true) }

    @Test func snakeCaseStaysText() { #expect(inline("snake_case_name") == nil) }

    @Test func underscoresRightAfterAnEmojiMakeItalic() { #expect(inline("😀_x_")?.text.allHave(.italic, in: 2..<3) == true) }

    @Test func starsRightAfterAJoinedEmojiMakeItalic() { #expect(inline("👩🏽‍💻*hi*")?.text.allHave(.italic, in: 7..<9) == true) }

    @Test(arguments: ["é_x_", "٣_x_"]) func aLetterOrDigitBeforeAnUnderscoreKeepsSnakeCase(text: String) {
        #expect(inline(text) == nil)
    }

    @Test func aLoneLeadSurrogateIsNotAWordCharacter() { #expect(!NoteInputRules.isWordCharacter(endingAt: 1, in: [0xD83D])) }

    @Test func aLoneTrailSurrogateIsNotAWordCharacter() { #expect(!NoteInputRules.isWordCharacter(endingAt: 1, in: [0xDE00])) }

    @Test func anAstralLetterIsAWordCharacter() { #expect(NoteInputRules.isWordCharacter(endingAt: 2, in: Array("𝒜".utf16))) }

    @Test(arguments: ["2*3*", "a * b *", "** **"]) func lookalikesStayText(text: String) { #expect(inline(text) == nil) }

    @Test func backticksMakeInlineCode() {
        let code = inline("run `ls -la`")
        #expect(code?.text.string == "run ls -la")
        #expect(code?.text.allHave(.code, in: 4..<10) == true)
        #expect(code?.typingMarks.code == false)
    }

    @Test func doubleTildesStrikeThrough() {
        let strike = inline("~~gone~~")
        #expect(strike?.text.string == "gone")
        #expect(strike?.text.allHave(.strikethrough, in: 0..<4) == true)
    }

    @Test func singleTildesStrikeThrough() { #expect(inline("~gone~")?.text.allHave(.strikethrough, in: 0..<4) == true) }

    @Test func doubleEqualsHighlight() {
        let highlight = inline("==wow==")
        #expect(highlight?.text.string == "wow")
        #expect(highlight?.text.marks(at: 0).color == .background(.yellow))
    }

    @Test func boldKeepsExistingItalic() {
        let styled = NoteText(pieces: [("**", .plain), ("hi", Blocks.italic), ("**", .plain)])
        let mixed = inline("", text: styled)
        #expect(mixed?.text.marks(at: 0).bold == true)
        #expect(mixed?.text.marks(at: 0).italic == true)
    }

    @Test func inlineCodeIsLeftAlone() {
        #expect(inline("", text: NoteText("x **y**", marks: Blocks.marks { $0.code = true })) == nil)
    }

    @Test func dollarsBecomeOneAtomCarryingTheirTeX() {
        let math = inline("so $x^2$")
        #expect(math?.text.string == "so " + NoteAtom.character)
        #expect(math?.text.marks(at: 3).atom == .equation("x^2"))
        #expect(math?.caret == 4)
    }

    @Test func doubleDollarsMakeAnInlineEquationToo() {
        #expect(inline("$$e=mc^2$$")?.text.marks(at: 0).atom == .equation("e=mc^2"))
    }

    @Test(arguments: ["costs $5 and $", "a$b$"]) func pricesAndGluedDollarsStayText(text: String) {
        #expect(inline(text) == nil)
    }

    @Test func aBareURLLinksOnSpace() {
        let link = inline("see https://parc.app ")
        #expect(link?.text.marks(at: 4).link == "https://parc.app")
        #expect(link?.text.marks(at: 20).link == nil)
        #expect(link?.name == "Link")
    }

    @Test func wwwLinksGetHttps() {
        #expect(inline("go to www.parc.app. ")?.text.marks(at: 6).link == "https://www.parc.app")
    }

    @Test func trailingPunctuationStaysOutsideTheLink() {
        #expect(inline("go to www.parc.app. ")?.text.marks(at: 18).link == nil)
    }

    @Test(arguments: ["https:// ", "localhost "]) func nonLinksStayText(text: String) { #expect(inline(text) == nil) }

    @Test func existingLinksAreLeftAlone() {
        let linked = NoteText(pieces: [("https://a.com", Blocks.marks { $0.link = "https://b.com" }), (" ", .plain)])
        #expect(inline("", text: linked) == nil)
    }

    @Test(arguments: [
        ("a->", "a\u{2192}"), ("<-", "\u{2190}"), ("x <->", "x \u{2194}"), ("so =>", "so \u{21D2}"), ("a >=", "a \u{2265}"),
        ("b <=", "b \u{2264}"), ("wait--", "wait\u{2014}"), ("--", "\u{2014}"),
    ])
    func typedSequencesTurnIntoSymbols(typedText: String, expected: String) {
        #expect(inline(typedText)?.text.string == expected)
        #expect(inline(typedText)?.caret == (expected as NSString).length)
    }

    @Test func finishingTheDoubleArrowAfterTheLeftArrowMakesADoubleArrow() {
        #expect(inline("", text: NoteText("\u{2190}>"))?.text.string == "\u{2194}")
    }

    @Test func theDoubleArrowRemembersWhatWasTyped() {
        let joined = inline("", text: NoteText("\u{2190}>"))
        #expect(joined?.literal?.string == "<->")
        #expect(joined?.literalCaret == 3)
    }

    @Test func aPlainArrowNeedsNoRewrite() { #expect(inline("a->")?.literal == nil) }

    @Test func theArrowUndoStepIsCalledArrow() { #expect(inline("a->")?.name == "Arrow") }

    @Test func theDashUndoStepIsCalledEmDash() { #expect(inline("--")?.name == "Em Dash") }

    @Test(arguments: ["a-->", "x >>=", "x <<=", "x ==>", "a---"]) func longerRunsStayAsTyped(text: String) {
        #expect(inline(text) == nil)
    }

    @Test func inlineCodeKeepsItsArrows() {
        #expect(inline("", text: NoteText("run a->", marks: Blocks.marks { $0.code = true })) == nil)
    }

    @Test func aSequenceThatStartsInsideInlineCodeStaysAsTyped() {
        let halfCode = NoteText(pieces: [("x -", Blocks.marks { $0.code = true }), (">", .plain)])
        #expect(inline("", text: halfCode) == nil)
    }

    @Test func anArrowRightAfterAnEquationStillConverts() {
        let afterEquation = NoteText.atom(.equation("x")) + NoteText("->")
        #expect(inline("", text: afterEquation)?.text.string == NoteAtom.character + "\u{2192}")
    }

    @Test func theArrowKeepsTheBoldItWasTypedIn() {
        #expect(inline("", text: NoteText("go->", marks: Blocks.marks { $0.bold = true }))?.text.marks(at: 2).bold == true)
    }

    @Test(arguments: [NoteBlockKind.code, .equation]) func codeAndEquationBlocksKeepTheirArrows(kind: NoteBlockKind) {
        #expect(NoteInputRules.afterTyping(">", text: NoteText("->"), caret: 2, block: NoteBlock(kind, text: NoteText("->"))) == nil)
    }

    @Test func aDashAndAHyphenAtTheStartStillMakeADivider() {
        guard case .block(let divider)? = typed("\u{2014}-") else {
            Issue.record("an em dash and a hyphen should make a divider")
            return
        }
        #expect(divider.conversion == .divider)
        #expect(divider.literal?.string == "---")
        #expect(divider.prefixLength == 3)
    }

    @Test func aDashAndAHyphenAfterTextStayText() { #expect(typed("x\u{2014}-") == nil) }

    func sessionWith(_ block: NoteBlock) -> NotePageSession { NotePageSession(page: NotePage(blocks: [block])) }

    func typeInto(_ session: NotePageSession, _ line: NoteBlock, _ value: String) {
        session.setText(NoteText(value), of: (line.id, .body), selection: .caret(NotePosition(line.id, NoteText(value).length)))
    }

    func convert(_ conversion: NoteInlineConversion, in session: NotePageSession, _ line: NoteBlock) {
        if let literal = conversion.literal {
            session.setText(literal, of: (line.id, .body), selection: .caret(NotePosition(line.id, conversion.literalCaret)))
        }
        session.breakCoalescing()
        session.applyInlineConversion(conversion, to: line.id)
    }

    func doubleArrowSession() throws -> (NotePageSession, NoteBlock) {
        let line = Blocks.para("")
        let session = sessionWith(line)
        typeInto(session, line, "<")
        typeInto(session, line, "<-")
        convert(try #require(inline("<-")), in: session, line)
        typeInto(session, line, "\u{2190}>")
        convert(try #require(inline("", text: NoteText("\u{2190}>"))), in: session, line)
        return (session, line)
    }

    @Test func leftArrowThenDoubleArrowBecomesADoubleArrow() throws {
        #expect(try doubleArrowSession().0.page.blocks[0].text.string == "\u{2194}")
    }

    @Test func oneUndoBringsBackExactlyWhatWasTyped() throws {
        let (session, _) = try doubleArrowSession()
        session.undo()
        #expect(session.page.blocks[0].text.string == "<->")
    }

    @Test func afterUndoTheCaretSitsAfterTheTypedCharacters() throws {
        let (session, line) = try doubleArrowSession()
        session.undo()
        #expect(session.selection.caret == NotePosition(line.id, 3))
    }

    @Test func redoPutsTheDoubleArrowBack() throws {
        let (session, _) = try doubleArrowSession()
        session.undo()
        session.redo()
        #expect(session.page.blocks[0].text.string == "\u{2194}")
    }

    func dividerThroughEmDash() throws -> NotePageSession {
        let dash = Blocks.para("")
        let session = sessionWith(dash)
        session.setText(NoteText("--"), of: (dash.id, .body), selection: .caret(NotePosition(dash.id, 2)))
        session.breakCoalescing()
        session.applyInlineConversion(try #require(inline("--")), to: dash.id)
        session.setText(NoteText("\u{2014}-"), of: (dash.id, .body), selection: .caret(NotePosition(dash.id, 2)))
        guard case .block(let rule)? = typed("\u{2014}-"), let literal = rule.literal else {
            Issue.record("expected a divider")
            return session
        }
        session.setText(literal, of: (dash.id, .body), selection: .caret(NotePosition(dash.id, literal.length)))
        session.breakCoalescing()
        session.applyBlockShortcut(rule, to: dash.id)
        return session
    }

    @Test func threeHyphensStillMakeADividerThroughTheEmDash() throws {
        #expect(Blocks.outline(try dividerThroughEmDash().page.blocks) == "divider\np")
    }

    @Test func undoBringsBackThreeHyphens() throws {
        let session = try dividerThroughEmDash()
        session.undo()
        #expect(session.page.blocks[0].text.string == "---")
    }

    func headingSession() throws -> (NotePageSession, NoteBlock, NotePosition?) {
        let first = Blocks.para("# Title")
        let session = sessionWith(first)
        session.setText("# Title", of: (first.id, .body))
        let rule = try #require(shortcut("# Title", caret: 2))
        return (session, first, session.applyBlockShortcut(rule, to: first.id))
    }

    @Test func theParagraphBecomesAHeadingWithoutItsMarker() throws {
        #expect(Blocks.outline(try headingSession().0.page.blocks) == "h1 Title")
    }

    @Test func theCaretLandsAtTheStartOfTheHeading() throws {
        let (_, first, position) = try headingSession()
        #expect(position == NotePosition(first.id, 0))
    }

    @Test func undoBringsBackTheLiteralMarker() throws {
        let (session, _, _) = try headingSession()
        session.undo()
        #expect(Blocks.outline(session.page.blocks) == "p # Title")
    }

    func checkedTodoSession() throws -> NotePageSession {
        let item = Blocks.para("[x] ")
        let session = sessionWith(item)
        session.applyBlockShortcut(try #require(shortcut("[x] ")), to: item.id)
        return session
    }

    @Test func xBracketsMakeACheckedTodoInOneGo() throws {
        #expect(Blocks.outline(try checkedTodoSession().page.blocks) == "done")
    }

    @Test func oneUndoStepUndoesTheWholeConversion() throws {
        let session = try checkedTodoSession()
        session.undo()
        #expect(Blocks.outline(session.page.blocks) == "p [x] ")
    }

    @Test func codeKeepsTheLanguage() throws {
        let fence = Blocks.para("```swift ")
        let session = sessionWith(fence)
        session.applyBlockShortcut(try #require(shortcut("```swift ")), to: fence.id)
        #expect(session.page.blocks[0].kind == .code)
        #expect(session.page.blocks[0].props.language == "swift")
    }

    @Test func threeHyphensLeaveADividerAndAFreshLine() throws {
        let rule = Blocks.para("---")
        let session = sessionWith(rule)
        let landing = session.applyBlockShortcut(try #require(shortcut("---")), to: rule.id)
        #expect(Blocks.outline(session.page.blocks) == "divider\np")
        #expect(landing?.block == session.page.blocks[1].id)
    }

    @Test func fourDotStartsTheListAtFour() throws {
        let source = Blocks.para("4. ")
        let session = sessionWith(source)
        session.applyBlockShortcut(try #require(shortcut("4. ")), to: source.id)
        #expect(Blocks.outline(session.page.blocks) == "ol@4")
    }

    func boldSession() throws -> (NotePageSession, NoteBlock) {
        let typedBold = Blocks.para("a **b**")
        let session = sessionWith(typedBold)
        session.applyInlineConversion(try #require(inline("a **b**")), to: typedBold.id)
        return (session, typedBold)
    }

    @Test func boldReachesTheSession() throws {
        #expect(try boldSession().0.page.blocks[0].text.allHave(.bold, in: 2..<3))
    }

    @Test func theCaretFollowsTheBoldRun() throws {
        let (session, line) = try boldSession()
        #expect(session.selection.caret == NotePosition(line.id, 3))
    }

    @Test func undoRestoresTheAsterisks() throws {
        let (session, _) = try boldSession()
        session.undo()
        #expect(session.page.blocks[0].text.string == "a **b**")
    }
}
