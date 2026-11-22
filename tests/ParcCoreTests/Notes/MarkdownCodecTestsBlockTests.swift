import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsBlockTests {
    private func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    @Test
    func atxHeadingsNeedASpaceAndAtMostSixMarks() {
        let headings = blocks("# A #\n\n## B ##\n\n####### not\n\n#5 not\n")
        #expect(headings.map(\.kind) == [.heading, .heading, .paragraph, .paragraph], "ATX headings need a space and at most six marks")
        #expect(headings[0].text.string == "A" && headings[1].props.level == 2, "closing hashes are dropped")
    }

    @Test
    func setextHeadingsTakeEveryParagraphLine() {
        let setext = blocks("Multi\nline title\n---\n")
        #expect(setext.count == 1 && setext[0].kind == .heading && setext[0].props.level == 2 && setext[0].text.string == "Multi\u{2028}line title", "setext headings take every paragraph line")
    }

    @Test func twoSpacesAndBackslashMakeHardBreaks() {
        let breaks = blocks("a  \nb\\\nc\nd\n")
        #expect(breaks[0].text.string == "a\nb\nc\u{2028}d", "two spaces and backslash are hard breaks, a newline is soft")
    }

    @Test
    func blankLinesBetweenListItemsMakeTheListLoose() {
        #expect(blocks("- a\n\n- b\n").allSatisfy { $0.props.looseList }, "a gap between items marks the list loose")
    }

    @Test
    func aChildParagraphDoesNotMakeTheListLoose() {
        let lists = blocks("- a\n- b\n\n  c\n- d\n")
        #expect(lists.count == 3 && !lists.contains { $0.props.looseList }, "only blank lines between items mark a list loose")
        #expect(lists[1].children.first?.text.string == "c", "a continuation paragraph becomes a child")
    }

    @Test func lazyContinuationLinesJoinTheParagraph() {
        let lazy = blocks("> lazy\ncontinuation\n\n- item\nlazy line\n")
        #expect(lazy[0].text.string == "lazy\u{2028}continuation" && lazy[1].text.string == "item\u{2028}lazy line", "lazy continuation lines join the paragraph")
    }

    @Test func startNumbersStayOnTheFirstItem() {
        let numbered = blocks("7. seven\n8. eight\n")
        #expect(numbered[0].props.listStart == 7 && numbered[1].props.listStart == nil, "start numbers stay on the first item")
    }

    @Test func aListStartingAboveOneCannotInterruptAParagraph() {
        let interrupt = blocks("text\n2. not a list\n")
        #expect(interrupt.count == 1 && interrupt[0].kind == .paragraph, "only a list starting at 1 can interrupt a paragraph")
    }

    @Test func changingTheMarkerStartsANewListAndKeepsTheMarker() {
        let markers = blocks("- a\n+ b\n* c\n")
        #expect(markers.map(\.props.bulletMarker) == [nil, "+", "*"], "changing the marker starts a new list and keeps the marker")
    }

    @Test
    func repeatedNumberMarkersContinueTheSameList() {
        let ordered = blocks("1. a\n1. b\n1. c\n")
        #expect(ordered.map(\.props.listStart) == [nil, nil, nil], "ordered items after the first follow on")
    }

    @Test
    func orderedTasksKeepTheirMarkerAndCheckedState() {
        let task = blocks("1. [x] ordered task\n")
        #expect(task[0].kind == .todo && task[0].props.checked && task[0].props.orderedDelimiter == ".", "ordered task items stay ordered")
    }

    @Test
    func tabsCountAsIndentation() {
        let tabs = blocks("-\tone\n\n>\tquoted\n")
        #expect(tabs[0].text.string == "one" && tabs[1].text.string == "quoted", "tabs count as indentation")
    }

    @Test
    func aTablePadsShortRowsAndTakesAlignmentFromTheDelimiter() {
        let table = blocks("| a | b |\n|---|:-:|\n| 1 | 2 | 3 |\n| only |\n")
        let model = table[0].props.table!
        #expect(model.rows == [["a", "b"], ["1", "2"], ["only", ""]], "extra cells are dropped and short rows padded")
        #expect(model.alignments == [nil, .center], "alignment comes from the delimiter row")
    }

    @Test
    func escapedPipesStayInsideTableCells() {
        let pipes = blocks("| `a\\|b` | c \\| d |\n| --- | --- |\n")
        #expect(pipes[0].props.table!.rows[0].map(\.string) == ["a|b", "c | d"], "escaped pipes stay inside cells, even in code")
    }

    @Test
    func aTableDelimiterRowMustMatchTheHeader() {
        let notTable = blocks("a | b\n-- | -- | --\n")
        #expect(notTable[0].kind == .paragraph, "the delimiter row must match the header")
    }

    @Test
    func anHTMLBlockEndsAtABlankLine() {
        let html = blocks("<div>\n*not emphasis*\n</div>\n\n*emphasis*\n")
        #expect(html[0].kind == .html && html[0].text.string == "<div>\n*not emphasis*\n</div>" && html[1].kind == .paragraph, "HTML blocks end at a blank line")
    }

    @Test
    func aScriptBlockRunsToItsClosingTag() {
        let script = blocks("<script>\nlet a = 1\n\nlet b = 2\n</script>\nafter\n")
        #expect(script[0].kind == .html && script[0].text.string.hasSuffix("</script>") && script[1].text.string == "after", "script blocks run to their closing tag")
    }

    @Test
    func linkReferencesResolveWithoutMatchingCase() {
        let references = blocks("[Ref]: /url\n\n[ref]\n")
        #expect(references[0].kind == .raw && references[1].text.marks(at: 0).link == "/url", "references resolve case-insensitively")
    }

    @Test
    func codeSpansKeepEntitiesLiteral() {
        let entityInCode = blocks("`&amp;` and \\`x\\`\n")
        #expect(entityInCode[0].text.string == "&amp; and `x`", "code spans keep entities literally")
    }
}
