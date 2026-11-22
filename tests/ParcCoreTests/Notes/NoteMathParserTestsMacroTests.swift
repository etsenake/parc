import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsMacroTests {
    typealias ExpansionCase = NoteMathParserTestsSupport.ExpansionCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        ExpansionCase("newcommand without arguments", "\\newcommand{\\RR}{\\mathbb{R}} \\RR^n",
                      "\\mathbb{R}^n"),
        ExpansionCase("argument count with braced and bare arguments", "\\newcommand\\sq[1]{#1^2} \\sq{a}+\\sq b",
                      "a^2+b^2"),
        ExpansionCase("optional argument with a default", "\\newcommand{\\pair}[2][0]{(#1,#2)} \\pair{x} \\pair[1]{y}",
                      "(0,x) (1,y)"),
        ExpansionCase("starred newcommand", "\\newcommand*{\\one}{1}\\one",
                      "1"),
        ExpansionCase("renewcommand replaces a macro", "\\newcommand{\\e}{e}\\renewcommand{\\e}{f}\\e",
                      "f"),
        ExpansionCase("renewcommand can redefine a built-in", "\\renewcommand{\\alpha}{a}\\alpha",
                      "a"),
        ExpansionCase("providecommand only fills gaps", "\\providecommand{\\pi}{p}\\providecommand{\\q}{q}\\pi\\q",
                      "\\pi q"),
        ExpansionCase("def with parameter text", "\\def\\f#1#2{#1+#2}\\f ab",
                      "a+b"),
        ExpansionCase("def without parameters", "\\def\\g{x}\\g\\g",
                      "xx"),
        ExpansionCase("expansions keep control words apart from letters", "\\def\\g{\\alpha}\\g x",
                      "\\alpha x"),
        ExpansionCase("let copies a built-in", "\\let\\a\\alpha \\a",
                      "\\alpha"),
        ExpansionCase("let with an equals sign", "\\let\\a=\\beta\\a",
                      "\\beta"),
        ExpansionCase("let snapshots a macro's meaning", "\\def\\b{y}\\let\\c=\\b \\def\\b{z}\\c\\b",
                      "yz"),
        ExpansionCase("let snapshots a built-in", "\\renewcommand{\\beta}{b}\\let\\c\\alpha\\renewcommand{\\alpha}{a}\\c",
                      "\\alpha"),
        ExpansionCase("definitions work inside their group", "{\\def\\h{1}\\h}",
                      "{1}"),
        ExpansionCase("gdef escapes its group", "{\\gdef\\k{w}}\\k",
                      "{}w"),
        ExpansionCase("global prefix", "{\\global\\def\\m{v}}\\m",
                      "{}v"),
        ExpansionCase("edef expands when defined", "\\def\\n{a}\\edef\\o{\\n}\\def\\n{b}\\o",
                      "a"),
        ExpansionCase("## builds nested parameters", "\\def\\outer{\\def\\inner##1{##1!}}\\outer\\inner x",
                      "x!"),
        ExpansionCase("macros nest", "\\newcommand{\\abs}[1]{\\left|#1\\right|}\\abs{\\abs{x}}",
                      "\\left|\\left|x\\right|\\right|"),
        ExpansionCase("arguments carry structure", "\\newcommand{\\ip}[2]{\\langle #1, #2 \\rangle}\\ip{\\frac12}{y}",
                      "\\langle \\frac12, y \\rangle"),
        ExpansionCase("definitions in comments are ignored", "% \\def\\a{b}\n a",
                      "a"),
    ])
    func macroDefinitionsExpandToTheExpectedFormula(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test(arguments: [
        ErrorCase("definitions end with their group", "{\\def\\h{1}}\\h",
                  .exact("Unknown command \\h")),
    ])
    func localMacroDefinitionsEndAtTheGroup(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func hundredsOfMacroExpansionsFitWithinTheLimit() throws {
        let many = "\\def\\a{x}" + String(repeating: "\\a", count: 900)
        #expect(try Parser.parse(many).count == 900, "hundreds of expansions are fine")
    }

    @Test
    func runawayRecursionPointsToTheCall() throws {
        let loop = try Parser.failure("\\def\\a{\\a}\\a")
        #expect(loop.message == "\\a keeps expanding (over 1,000 times). Is it calling itself?" && loop.offset == 10 && loop.length == 2, "runaway recursion is caught at the call: \(loop.message) \(loop.offset) \(loop.length)")
    }

    @Test(arguments: [
        ErrorCase("exponential recursion is caught", "\\def\\a{\\a\\a}\\a",
                  .prefix("\\a keeps expanding")),
        ErrorCase("mutual recursion is caught", "\\newcommand{\\b}{\\c}\\newcommand{\\c}{\\b}\\b",
                  .prefix("\\b keeps expanding")),
    ])
    func recursiveMacrosHitTheExpansionLimit(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func newcommandReportsTheRangeOfAnExistingName() throws {
        let taken = try Parser.failure("\\newcommand{\\alpha}{x}")
        #expect(taken.message == "\\alpha already means something; use \\renewcommand to change it" && taken.offset == 12 && taken.length == 6, "newcommand refuses to clobber")
    }

    @Test(arguments: [
        ErrorCase("newcommand twice", "\\newcommand{\\f}{x}\\newcommand{\\f}{y}",
                  .prefix("\\f already means something")),
        ErrorCase("renewcommand needs a definition", "\\renewcommand{\\nope}{x}",
                  .exact("\\nope isn't defined yet, so use \\newcommand")),
        ErrorCase("parameter out of range", "\\newcommand{\\f}[1]{#2}",
                  .exact("\\f only takes 1 argument, so there's no #2")),
        ErrorCase("argument count range", "\\newcommand{\\f}[10]{x}",
                  .exact("The number of arguments has to be 0 to 9")),
        ErrorCase("def parameters in order", "\\def\\f#2{x}",
                  .prefix("\\def parameters have to be #1, #2")),
        ErrorCase("newcommand needs a name", "\\newcommand",
                  .prefix("\\newcommand needs a command name")),
        ErrorCase("newcommand needs a body", "\\newcommand{\\z}",
                  .exact("\\newcommand{\\z} needs a definition in braces")),
        ErrorCase("def needs a body", "\\def\\z",
                  .prefix("\\def\\z needs a definition")),
        ErrorCase("unclosed definition", "\\newcommand{\\z}{x",
                  .exact("Missing } to close this {")),
    ])
    func invalidMacroDefinitionsExplainTheError(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func aShortMacroCallReportsItsMissingArguments() throws {
        let short = try Parser.failure("\\newcommand{\\x}[3]{#1#2#3}\\x ab")
        #expect(short.message == "\\x needs 3 arguments" && short.offset == 26 && short.length == 2, "missing macro argument")
    }

    @Test
    func anErrorInsideAMacroPointsToItsUse() throws {
        let inner = try Parser.failure("\\newcommand{\\y}{\\frac{a}}\\y")
        #expect(inner.message == "\\frac needs 2 arguments" && inner.offset == 25 && inner.length == 2, "errors inside a macro point at its use")
    }

    @Test(arguments: [
        ExpansionCase("delimiters around and between parameters", "\\def\\pt(#1,#2){#1+#2}\\pt(a,b)",
                      "a+b"),
        ExpansionCase("an argument runs to its delimiter", "\\def\\foo#1.{[#1]}\\foo abc.d",
                      "[abc]d"),
        ExpansionCase("braces hide the delimiter and come off", "\\def\\foo#1.{[#1]}\\foo {a.b}.",
                      "[a.b]"),
        ExpansionCase("braces stay when they don't wrap the whole argument", "\\def\\foo#1.{[#1]}\\foo {a}{b}.",
                      "[{a}{b}]"),
        ExpansionCase("an empty delimited argument", "\\def\\foo#1.{[#1]}\\foo .",
                      "[]"),
        ExpansionCase("a command works as a delimiter", "\\def\\foo#1\\stop{(#1)}\\foo xy\\stop",
                      "(xy)"),
        ExpansionCase("undelimited then delimited", "\\def\\foo#1#2;{#2#1}\\foo ab c;",
                      "bca"),
        ExpansionCase("a space is a delimiter too", "\\def\\foo#1 #2.{#2#1}\\foo x y.",
                      "yx"),
        ExpansionCase("text before the first parameter has to match", "\\def\\foo.#1{#1!}\\foo.x",
                      "x!"),
        ExpansionCase("#{ stops at a brace and leaves it", "\\def\\foo#1#{#1\\boxed}\\foo ab{c}",
                      "ab\\boxed{c}"),
        ExpansionCase("delimited macros inside macros", "\\def\\foo#1.{#1}\\def\\bar{\\foo x.}\\bar",
                      "x"),
        ExpansionCase("two delimited parameters", "\\def\\cs#1.#2.{#2#1}\\cs a.b.",
                      "ba"),
        ExpansionCase("the shortest argument that the delimiter follows", "\\def\\ab#1ab{[#1]}\\ab aab",
                      "[a]"),
    ])
    func delimitedMacroParametersExpandToTheExpectedFormula(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test
    func aMismatchedPrefixPointsToTheMacroCall() throws {
        let mismatch = try Parser.failure("\\def\\foo.#1{#1}\\foo x")
        #expect(mismatch.message == "\\foo has to be followed by \u{201C}.\u{201D}, the way it was defined" && mismatch.offset == 15, "a prefix that doesn't match: \(mismatch.message)")
    }

    @Test
    func aMissingDelimiterPointsToTheMacroCall() throws {
        let runaway = try Parser.failure("\\def\\foo#1.{#1}\\foo abc")
        #expect(runaway.message == "\\foo never finds the \u{201C}.\u{201D} that ends its argument" && runaway.offset == 15, "a missing delimiter: \(runaway.message)")
    }

    @Test(arguments: [
        ErrorCase("a brace can't close mid-argument", "{\\def\\foo#1.{#1}\\foo a}.",
                  .exact("\\foo's argument has an extra }")),
        ErrorCase("stray brace in parameter text", "\\def\\foo#1}{x}",
                  .exact("\\def\\foo has a } before its definition starts")),
    ])
    func aStrayBraceExplainsWhereTheMacroArgumentFailed(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }
}
