import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsTagsAndReferencesTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    typealias ExpansionCase = NoteMathParserTestsSupport.ExpansionCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test
    func aTagWrapsItsLabelAndLeavesTheFormulaIntact() throws {
        let plain = try Parser.equation("E = mc^2 \\tag{1}")
        #expect(try plain.tag == [.text("(1)", .roman)] && plain.nodes == Parser.parse("E = mc^2"), "tag wraps its label in parentheses")
    }

    @Test
    func aStarredTagKeepsItsLabelAsWritten() throws {
        #expect(try Parser.equation("x \\tag*{A.1}").tag == [.text("A.1", .roman)], "tag* keeps the label as written")
    }

    @Test
    func aTagCanContainInlineMath() throws {
        #expect(try Parser.equation("x \\tag{$\\ast$}").tag == [.text("(", .roman), .mathStyle(.text, [.char("∗", .bin)]), .text(")", .roman)], "math inside a tag")
    }

    @Test
    func aTagCanPrecedeItsEquation() throws {
        #expect(try Parser.equation("\\tag{eq} x").tag == [.text("(eq)", .roman)], "a tag can come first")
    }

    @Test
    func notagOnItsOwnLeavesTheEquationUntagged() throws {
        #expect(try Parser.equation("x \\notag").tag == nil)
    }

    @Test
    func nonumberLeavesTheFormulaIntact() throws {
        #expect(try Parser.equation("x \\nonumber").nodes == Parser.parse("x"))
    }

    @Test(arguments: [
        ExpansionCase("parse drops the tag from the formula", "x \\tag{1}",
                      "x"),
    ])
    func theNodeParserLeavesTagsOutOfTheFormula(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test
    func anInlineTagReportsWhereItAppears() throws {
        let inline = try Parser.failure("x \\tag{1}", display: false)
        #expect(inline.message == "\\tag only works in display equations" && inline.offset == 2 && inline.length == 4, "inline tags explain themselves")
    }

    @Test(arguments: [
        ErrorCase("one tag per line", "x \\tag{1} \\tag{2}",
                  .exact("Only one \\tag per line")),
        ErrorCase("tag inside a script", "x^\\tag{1}",
                  .exact("\\tag has to stand on its own, not inside a script or argument")),
        ErrorCase("tag needs a label", "x \\tag",
                  .exact("\\tag needs {text} after it")),
        ErrorCase("one tag per align row", "\\begin{align} a \\tag{1} \\tag{2} \\end{align}",
                  .exact("Only one \\tag per line")),
    ])
    func invalidTagsExplainTheError(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func aSingleCharacterTagNeedsNoBraces() throws {
        #expect(try Parser.equation("x \\tag 1").tag == [.text("(1)", .roman)], "a one-character tag needs no braces")
    }

    @Test
    func alignNumbersEveryRow() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)], two: [NoteMathNode] = [.text("(2)", .roman)]
        #expect(try Parser.rowTags("\\begin{align} a &= b \\\\ c &= d \\end{align}") == [one, two], "align numbers every row")
    }

    @Test
    func aTrailingBreakDoesNotNumberAnEmptyRow() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)], two: [NoteMathNode] = [.text("(2)", .roman)]
        #expect(try Parser.rowTags("\\begin{align} a &= b \\\\ c &= d \\\\ \\end{align}") == [one, two], "a trailing break doesn't number an empty row")
    }

    @Test
    func notagSkipsARow() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)]
        #expect(try Parser.rowTags("\\begin{align} a &= b \\notag \\\\ c &= d \\end{align}") == [nil, one], "notag skips a row")
    }

    @Test
    func nonumberRemovesAllAutomaticTags() throws {
        #expect(try Parser.rowTags("\\begin{align} a &= b \\nonumber \\\\ c &= d \\nonumber \\end{align}") == [], "nonumber everywhere leaves no tags")
    }

    @Test
    func anExplicitTagDoesNotConsumeANumber() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)]
        #expect(try Parser.rowTags("\\begin{align} a &= b \\tag{x} \\\\ c &= d \\end{align}") == [[.text("(x)", .roman)], one], "an explicit tag doesn't use up a number")
    }

    @Test
    func starredAlignOnlyShowsExplicitTags() throws {
        #expect(try Parser.rowTags("\\begin{align*} a &= b \\\\ c &= d \\tag{y} \\end{align*}") == [nil, [.text("(y)", .roman)]], "align* only shows explicit tags, here on its last line")
        #expect(try Parser.rowTags("\\begin{align*} a \\\\ b \\end{align*}") == [], "align* has no numbers")
    }

    @Test
    func gatherNumbersEveryRow() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)], two: [NoteMathNode] = [.text("(2)", .roman)]
        #expect(try Parser.rowTags("\\begin{gather} a \\\\ b \\end{gather}") == [one, two], "gather numbers rows")
    }

    @Test
    func equationGetsAnAutomaticNumber() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)]
        #expect(try Parser.rowTags("\\begin{equation} E = mc^2 \\end{equation}") == [one], "equation is numbered")
    }

    @Test
    func aStarredEquationCanTakeAnExplicitTag() throws {
        #expect(try Parser.rowTags("\\begin{equation*} E = mc^2 \\tag{$\\star$} \\end{equation*}").count == 1, "equation* takes a tag")
    }

    @Test
    func aTagInsideAlignedAppliesToTheWholeEquation() throws {
        let one: [NoteMathNode] = [.text("(1)", .roman)]
        let aligned = try Parser.equation("\\begin{aligned} a &= b \\tag{1} \\\\ c &= d \\end{aligned}")
        #expect(aligned.tag == one, "a tag inside aligned tags the whole equation")
        if case .environment(let environment)? = aligned.nodes.first { #expect(environment.tags.isEmpty, "aligned rows carry no tags") }
    }

    @Test
    func aTagAfterAlignedAppliesToTheWholeEquation() throws {
        let two: [NoteMathNode] = [.text("(2)", .roman)]
        let after = try Parser.equation("\\begin{aligned} a &= b \\\\ c &= d \\end{aligned} \\tag{2}")
        #expect(after.tag == two, "a tag after aligned tags the whole equation")
    }

    @Test
    func inlineAlignStaysUnnumbered() throws {
        if case .environment(let environment)? = (try? NoteMathParser.parseEquation("\\begin{align} a \\\\ b \\end{align}", display: false))?.nodes.first {
            #expect(environment.tags.isEmpty, "inline align stays unnumbered")
        } else {
            Issue.record("inline align parses")
            return
        }
    }

    @Test
    func aMacroCanSupplyATag() throws {
        #expect(try Parser.equation("\\newcommand{\\eq}[1]{\\tag{#1}} x \\eq{7}").tag == [.text("(7)", .roman)], "tags from macros")
    }

    @Test
    func labelsAttachToRowNumbersAndTags() throws {
        let numbered = try Parser.equation("\\begin{align} a &= b \\label{first} \\\\ c &= d \\tag{x}\\label{second} \\\\ e \\label{third} \\end{align}")
        #expect(numbered.labels == [NoteMathLabel(key: "first", target: .automatic(1)), NoteMathLabel(key: "second", target: .tag([.text("x", .roman)])),
                                   NoteMathLabel(key: "third", target: .automatic(2))] && numbered.automaticNumbers == 2, "labels attach to row numbers and tags: \(numbered.labels)")
    }

    @Test
    func automaticNumbersContinueFromEarlierEquations() throws {
        let later = NoteMathNumberingContext(firstNumber: 4)
        let shifted = try? NoteMathParser.parseEquation("\\begin{gather} a \\\\ b \\end{gather}", display: true, numbering: later)
        if case .environment(let environment)? = shifted?.nodes.first {
            #expect(environment.tags == [[.text("(5)", .roman)], [.text("(6)", .roman)]], "numbers continue from earlier equations")
        } else {
            Issue.record("numbered gather parses")
            return
        }
    }

    @Test
    func referencesResolveKnownLabelsAndKeepMissingOnes() throws {
        let context = NoteMathNumberingContext(references: ["e": [.text("3", .roman)]])
        let refs = try? NoteMathParser.parseEquation("\\eqref{e} + \\ref{e} + \\eqref{nope}", display: false, numbering: context)
        #expect(refs?.nodes == [.reference("e", parenthesized: true, label: [.text("3", .roman)]), .char("+", .bin),
                               .reference("e", parenthesized: false, label: [.text("3", .roman)]), .char("+", .bin),
                               .reference("nope", parenthesized: true, label: nil)], "references resolve or stay missing")
    }

    @Test(arguments: [
        NodeCase("references work inside text", "\\text{see \\eqref{a}}") { [.group([.text("see ", .roman), .reference("a", parenthesized: true, label: nil)])] },
    ])
    func referencesWorkInsideText(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func aTaggedEquationTakesALabel() throws {
        #expect(try Parser.equation("x \\tag{A} \\label{k}").labels == [NoteMathLabel(key: "k", target: .tag([.text("A", .roman)]))], "a tagged display takes a label")
    }

    @Test(arguments: [
        ErrorCase("an unnumbered display can't take a label", "x \\label{k}",
                  .prefix("\\label needs a numbered equation")),
        ErrorCase("duplicate labels in one equation", "\\begin{align} a \\label{k} \\\\ b \\label{k} \\end{align}",
                  .exact("\u{201C}k\u{201D} already labels another line here")),
        ErrorCase("labels need numbered rows", "\\begin{align*} a \\label{k} \\end{align*}",
                  .exact("\\label needs a numbered line, and this one isn't numbered")),
        ErrorCase("one label per line", "\\begin{align} a \\label{x} \\label{y} \\end{align}",
                  .exact("Only one \\label per line")),
        ErrorCase("references need a key", "\\eqref{}",
                  .exact("\\eqref needs a label, like \\eqref{eq:energy}")),
    ])
    func labelsAndReferencesReportInvalidPlacementOrKeys(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func anInlineLabelRequiresADisplayEquation() throws {
        #expect(try Parser.failure("x \\label{k}", display: false).message == "\\label only works in display equations", "inline labels explain themselves")
    }

    @Test
    func aLabelCannotBeReusedAcrossEquations() throws {
        let taken = NoteMathNumberingContext(takenLabels: ["k"])
        do {
            _ = try NoteMathParser.parseEquation("\\begin{equation} a \\label{k} \\end{equation}", display: true, numbering: taken)
            Issue.record("a label taken by an earlier equation fails")
        } catch {
            #expect(error.message == "\u{201C}k\u{201D} already labels an earlier equation", "labels are unique across the note")
        }
    }
}
