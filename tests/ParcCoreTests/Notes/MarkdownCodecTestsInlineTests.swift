import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsInlineTests {
    private func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    private func text(_ source: String) -> NoteText { blocks(source)[0].text }

    @Test
    func italicCanNestInsideBold() {
        let nested = text("**bold *both* bold**")
        #expect(nested.string == "bold both bold" && nested.marks(at: 0).bold && nested.marks(at: 5).italic && nested.marks(at: 5).bold, "emphasis nests")
    }

    @Test
    func intrawordUnderscoresStayLiteralWhileStarsMarkItalic() {
        let intraword = text("snake_case_name and a*b*c")
        #expect(intraword.string == "snake_case_name and abc" && intraword.marks(at: 21).italic, "underscores stay literal inside words, stars do not")
    }

    @Test
    func theRuleOfThreeKeepsNestedEmphasis() {
        let ruleOfThree = text("*foo**bar**baz*")
        #expect(ruleOfThree.string == "foobarbaz" && ruleOfThree.marks(at: 4).bold && ruleOfThree.marks(at: 4).italic, "the rule of three keeps nesting right")
    }

    @Test
    func unmatchedEmphasisDelimitersStayLiteral() {
        let unmatched = text("**open and *close")
        #expect(unmatched.string == "**open and *close", "unmatched delimiters stay text")
    }

    @Test
    func strikethroughAcceptsOneOrTwoTildes() {
        let strike = text("~one~ ~~two~~ ~~~three~~~")
        #expect(strike.marks(at: 0).strikethrough && strike.marks(at: 4).strikethrough && !strike.marks(at: 12).strikethrough, "one or two tildes strike, three do not")
    }

    @Test
    func aCodeSpanStripsOnePaddingSpace() {
        let codeSpan = text("`` a ` b `` and ` x `")
        #expect(codeSpan.string == "a ` b and x", "code spans strip one padding space")
    }

    @Test
    func aTitledLinkStaysRaw() {
        let link = text("[a *b*](</my url> 'title') [c](d)")
        #expect(link.marks(at: 0).atom != nil, "titled links stay raw so the title survives")
    }

    @Test
    func anUntitledLinkBecomesALinkMark() {
        let link = text("[a *b*](</my url> 'title') [c](d)")
        #expect(link.marks(at: link.length - 1).link == "d", "plain links become link marks")
    }

    @Test
    func anAngleDestinationCanContainSpaces() {
        let angle = text("[x](<a b>)")
        #expect(angle.marks(at: 0).link == "a b", "angle destinations keep spaces")
    }

    @Test
    func angleAutolinksAndBareAddressesBecomeLinks() {
        let autolinks = text("<mailto:a@b.c> <a@b.co> www.example.com/path. https://x.org/a_(b) and foo@bar.baz.")
        let marks = (0..<autolinks.length).compactMap { autolinks.marks(at: $0).link }
        #expect(marks.contains("mailto:a@b.co") && marks.contains("http://www.example.com/path") && marks.contains("https://x.org/a_(b)") && marks.contains("mailto:foo@bar.baz"), "angle autolinks, www, URLs and emails all link: \(Set(marks))")
    }

    @Test
    func bareLinksExcludeTrailingPunctuation() {
        let trailing = text("Visit https://example.com/page).")
        #expect((0..<trailing.length).compactMap { trailing.marks(at: $0).link }.allSatisfy { $0 == "https://example.com/page" }, "trailing punctuation is left out")
    }

    @Test
    func aPairedHTMLSpanAppliesMarksToNestedText() {
        let html = text("a <span data-color=\"red\">red <b>bold</b></span> <mark>hi</mark> <ins>in</ins> <a href=\"https://x.y\">x</a>")
        let redIndex = (html.string as NSString).range(of: "red").location
        let boldIndex = (html.string as NSString).range(of: "bold").location
        #expect(html.marks(at: redIndex).color == .text(.red) && html.marks(at: boldIndex).bold && html.marks(at: boldIndex).color == .text(.red), "paired inline HTML becomes marks")
    }

    @Test
    func aBareHTMLMarkHighlightsInYellow() {
        let html = text("a <span data-color=\"red\">red <b>bold</b></span> <mark>hi</mark> <ins>in</ins> <a href=\"https://x.y\">x</a>")
        #expect(html.marks(at: (html.string as NSString).range(of: "hi").location).color == .background(.yellow), "a bare mark is a yellow highlight")
    }

    @Test
    func anHTMLInsTagUnderlines() {
        let html = text("a <span data-color=\"red\">red <b>bold</b></span> <mark>hi</mark> <ins>in</ins> <a href=\"https://x.y\">x</a>")
        #expect(html.marks(at: (html.string as NSString).range(of: "in").location).underline, "ins underlines")
    }

    @Test
    func anAnchorWithOnlyHrefBecomesALink() {
        let html = text("a <span data-color=\"red\">red <b>bold</b></span> <mark>hi</mark> <ins>in</ins> <a href=\"https://x.y\">x</a>")
        #expect(html.marks(at: html.length - 1).link == "https://x.y", "anchor tags with only href are links")
    }

    @Test
    func anUnpairedHTMLTagStaysRaw() {
        let unpaired = text("x <b>never closed and <span class=\"k\">kept</span>")
        #expect(unpaired.marks(at: 2).atom == .raw("<b>") && !unpaired.marks(at: 5).bold, "unpaired tags stay raw")
    }

    @Test
    func anUnknownSpanKeepsItsOpeningAndClosingTags() {
        let unpaired = text("x <b>never closed and <span class=\"k\">kept</span>")
        let spanAtoms = (0..<unpaired.length).compactMap { unpaired.marks(at: $0).atom }
        #expect(spanAtoms.contains(.raw("<span class=\"k\">")) && spanAtoms.contains(.raw("</span>")), "unknown spans stay raw on both ends")
    }

    @Test
    func aDigitAfterTheClosingDollarCancelsMath() {
        #expect(!(0..<text("$x$5").length).contains { text("$x$5").marks(at: $0).atom != nil }, "a digit after the closing dollar cancels math")
    }

    @Test
    func inlineMathNeedsTightDollarDelimiters() {
        let math = text("$a$ $ b$ $c $ costs $5 and $6 today. \\$e and $y$")
        let atoms = (0..<math.length).compactMap { math.marks(at: $0).atom }
        #expect(atoms == [.equation("a"), .equation("y")], "inline math needs tight dollars and no digit after: \(atoms)")
    }

    @Test
    func inlineDisplayMathStaysVerbatim() {
        let display = text("Area: $$\\pi r^2$$ done")
        #expect(display.marks(at: 6).atom == .raw("$$\\pi r^2$$"), "inline display math is kept verbatim")
    }

    @Test
    func wikiLinksBecomePageMentions() {
        let wiki = text("[[Note]] [[Folder/Note#Part|Alias]] [[ ]]")
        #expect(wiki.marks(at: 0).atom == .page(target: "Note", title: "Note")
               && wiki.marks(at: 2).atom == .page(target: "Folder/Note#Part", title: "Alias"), "wiki links become page mentions")
    }

    @Test
    func relativeLinksBecomeMentionsWhenTheLabelMatchesTheNote() {
        let relative = text("[Plan](Plan.md) and [the plan](Plan.md)")
        #expect(relative.marks(at: 0).atom == .page(target: "Plan.md", title: "Plan") && relative.marks(at: relative.length - 1).link == "Plan.md", "a relative link named after its note is a mention, other text stays a link")
    }

    @Test
    func htmlTimeTagsBecomeDateMentions() {
        let date = text("<time datetime=\"2026-01-02\">soon</time> <time datetime=\"bad\">x</time>")
        #expect(date.marks(at: 0).atom == .date(NoteDateMention(year: 2026, month: 1, day: 2)), "time tags become date mentions")
    }

    @Test
    func invalidHtmlTimeTagsStayRaw() {
        let date = text("<time datetime=\"2026-01-02\">soon</time> <time datetime=\"bad\">x</time>")
        #expect(date.marks(at: 2).atom == .raw("<time datetime=\"bad\">"), "invalid dates stay raw")
    }

    @Test func inlineAtomsSurviveAMarkdownRoundTrip() {
        var mentions = NoteText("Talk to ")
        mentions.append(.atom(.page(target: "People/Ada Lovelace.md", title: "Ada Lovelace")))
        mentions.append(NoteText(" and "))
        mentions.append(.atom(.page(target: "Grace", title: "Admiral Hopper")))
        mentions.append(NoteText(" on "))
        mentions.append(.atom(.date(NoteDateMention(year: 2026, month: 12, day: 1, hour: 14, minute: 5, remind: true))))
        mentions.append(NoteText(", read "))
        mentions.append(.atom(.link(url: "https://example.com/a?b=1&c=2", title: "Example *site* [1]")))
        mentions.append(NoteText(", solve "))
        mentions.append(.atom(.equation("x_1 + y^2")))
        mentions.append(NoteText(" and "))
        mentions.append(.atom(.equation("$ odd \\")))
        mentions.append(NoteText("5 then "))
        mentions.append(.atom(.raw("<kbd>")))
        mentions.append(NoteText("K"))
        mentions.append(.atom(.raw("</kbd>")))
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [.paragraph(mentions)]), "mentions")
    }
}
