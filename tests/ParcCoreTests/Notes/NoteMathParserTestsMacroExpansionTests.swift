import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsMacroExpansionTests {
    typealias ExpansionCase = NoteMathParserTestsSupport.ExpansionCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        ExpansionCase("expandafter expands the second token first", "\\def\\a{x.y}\\def\\b#1.{[#1]}\\expandafter\\b\\a",
                      "[x]y"),
        ExpansionCase("expandafter chains expand twice", "\\def\\a{1}\\def\\b{\\a}\\def\\c#1.{[#1]}\\expandafter\\expandafter\\expandafter\\c\\b.",
                      "[1]"),
        ExpansionCase("noexpand keeps a command for later in edef", "\\def\\a{1}\\edef\\b{\\noexpand\\a\\a}\\def\\a{2}\\b",
                      "21"),
        ExpansionCase("noexpand on a built-in", "\\noexpand\\alpha",
                      "\\alpha"),
        ExpansionCase("noexpand on a macro acts like relax", "x\\def\\q{1}\\noexpand\\q y",
                      "xy"),
        ExpansionCase("csname builds a command", "\\csname alpha\\endcsname",
                      "\\alpha"),
        ExpansionCase("csname defines and uses a macro, spaces and all", "\\expandafter\\def\\csname my thing\\endcsname{z}\\csname my thing\\endcsname",
                      "z"),
        ExpansionCase("macros expand inside csname", "\\def\\n{al}\\csname\\n pha\\endcsname",
                      "\\alpha"),
        ExpansionCase("an undefined csname is a no-op", "x\\csname nothinghere\\endcsname y",
                      "xy"),
        ExpansionCase("csname with let", "\\expandafter\\let\\csname b\\endcsname\\beta \\b",
                      "\\beta"),
        ExpansionCase("csname with newcommand", "\\expandafter\\newcommand\\csname sq\\endcsname[1]{#1^2}\\sq{y}",
                      "y^2"),
        ExpansionCase("a built name stays apart from the next letter", "\\csname alpha\\endcsname b",
                      "\\alpha b"),
        ExpansionCase("primitives in comments are ignored", "% \\csname alpha\\endcsname\n a",
                      "a"),
    ])
    func expansionPrimitivesProduceTheExpectedFormula(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test(arguments: [
        ErrorCase("without expandafter the macro sees \\a", "\\def\\a{x.y}\\def\\b#1.{[#1]}\\b\\a",
                  .prefix("\\b never finds")),
        ErrorCase("csname refuses commands that don't expand", "\\csname \\alpha\\endcsname",
                  .exact("\\csname builds names from letters and symbols, so \\alpha can't go inside")),
        ErrorCase("expandafter needs tokens", "\\expandafter",
                  .exact("\\expandafter needs two things after it")),
        ErrorCase("expandafter loops hit the limit", "\\def\\a{\\expandafter\\a\\a}\\a",
                  .contains("keeps expanding")),
        ErrorCase("csname loops hit the limit", "\\def\\a{\\csname a\\endcsname}\\a",
                  .contains("keeps expanding")),
    ])
    func expansionPrimitivesExplainBadInput(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func anUnclosedCsnamePointsToItsOpeningCommand() throws {
        let open = try Parser.failure("x \\csname alpha")
        #expect(open.message == "\\csname needs an \\endcsname to finish the name" && open.offset == 2, "csname needs its end")
    }

    @Test(arguments: [
        ExpansionCase("a definition works in its own cell", "\\begin{matrix}\\def\\x{1}\\x & 2\\end{matrix}",
                      "\\begin{matrix}1 & 2\\end{matrix}"),
        ExpansionCase("gdef still escapes a cell", "\\begin{matrix}\\gdef\\w{1}\\end{matrix}\\w",
                      "\\begin{matrix}\\end{matrix}1"),
        ExpansionCase("outer macros reach every cell", "\\def\\v{3}\\begin{matrix}\\v & \\v\\end{matrix}",
                      "\\begin{matrix}3 & 3\\end{matrix}"),
        ExpansionCase("array column specs don't confuse scopes", "\\begin{array}{cc}\\def\\u{4}\\u & 5\\end{array}",
                      "\\begin{array}{cc}4 & 5\\end{array}"),
        ExpansionCase("groups still work inside cells", "\\begin{matrix}{\\def\\s{1}\\s} & 2\\end{matrix}",
                      "\\begin{matrix}{1} & 2\\end{matrix}"),
    ])
    func macrosExpandWithinTablesAccordingToTheirScope(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test(arguments: [
        ErrorCase("a definition ends with its cell", "\\begin{matrix}\\def\\x{1}\\x & \\x\\end{matrix}",
                  .exact("Unknown command \\x")),
        ErrorCase("a new row starts fresh", "\\begin{aligned} \\def\\y{a} \\y \\\\ \\y \\end{aligned}",
                  .exact("Unknown command \\y")),
        ErrorCase("nothing leaks out of an environment", "\\begin{matrix}\\def\\z{1}\\end{matrix}\\z",
                  .exact("Unknown command \\z")),
        ErrorCase("nested environments scope their own cells", "\\begin{matrix}\\begin{matrix}\\def\\t{1}\\t\\end{matrix} & \\t\\end{matrix}",
                  .exact("Unknown command \\t")),
    ])
    func localMacrosDoNotEscapeTheirTableScope(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }
}
