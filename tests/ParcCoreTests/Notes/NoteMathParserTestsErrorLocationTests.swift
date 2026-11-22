import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsErrorLocationTests {
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test
    func aSecondSuperscriptReportsItsRange() throws {
        let double = try Parser.failure("x^2^3")
        #expect(double.message.hasPrefix("Double superscript") && double.offset == 3 && double.length == 1, "double superscript at the second ^")
    }

    @Test
    func anUnclosedBracePointsAtTheOpeningBrace() throws {
        let open = try Parser.failure("a + {x")
        #expect(open.message == "Missing } to close this {" && open.offset == 4, "unclosed brace points at the brace")
    }

    @Test
    func aStrayBraceReportsItsOffset() throws {
        let close = try Parser.failure("x}")
        #expect(close.message == "There's a } without a matching {" && close.offset == 1, "stray brace")
    }

    @Test
    func anUnknownCommandReportsItsRange() throws {
        let unknown = try Parser.failure("1 + \\foo")
        #expect(unknown.message == "Unknown command \\foo" && unknown.offset == 4 && unknown.length == 4, "unknown command range")
    }

    @Test
    func errorOffsetsCountUTF16Units() throws {
        let wide = try Parser.failure("😀 \\foo")
        #expect(wide.offset == 3, "offsets count UTF-16 units")
    }

    @Test
    func anUnclosedFencePointsAtLeft() throws {
        let fence = try Parser.failure("\\left( x")
        #expect(fence.message == "Missing \\right to close this \\left" && fence.offset == 0, "unclosed left")
    }

    @Test
    func mismatchedEnvironmentsNameBothEnds() throws {
        let mismatch = try Parser.failure("\\begin{matrix} a \\end{pmatrix}")
        #expect(mismatch.message == "\\begin{matrix} ends with \\end{pmatrix}", "mismatched environment")
    }

    @Test
    func aMissingFractionArgumentNamesTheCommandAndArity() throws {
        let missingArgument = try Parser.failure("\\frac{a}")
        #expect(missingArgument.message == "\\frac needs 2 arguments", "missing argument message: \(missingArgument.message)")
    }

    @Test(arguments: [
        ErrorCase("double subscript", "x_1_2",
                  .prefix("Double subscript")),
        ErrorCase("prime after superscript", "x^2'",
                  .prefix("Double superscript")),
        ErrorCase("stray right", "x \\right)",
                  .exact("\\right without a matching \\left")),
        ErrorCase("stray middle", "\\middle|",
                  .prefix("\\middle only works")),
        ErrorCase("left needs a delimiter", "\\left x \\right)",
                  .prefix("\\left needs a delimiter")),
        ErrorCase("unclosed environment", "\\begin{matrix} a",
                  .exact("Missing \\end{matrix}")),
        ErrorCase("unknown environment", "\\begin{foo} a \\end{foo}",
                  .exact("Unknown environment \u{201C}foo\u{201D}")),
        ErrorCase("bad array spec", "\\begin{array}{cx} a \\end{array}",
                  .exact("Array columns only take l, c, r, | and :")),
        ErrorCase("too many cells", "\\begin{array}{c} a & b \\end{array}",
                  .prefix("This row has more columns")),
        ErrorCase("gathered has one column", "\\begin{gathered} a & b \\end{gathered}",
                  .exact("gathered doesn't use &")),
        ErrorCase("stray ampersand", "a & b",
                  .prefix("& only works")),
        ErrorCase("unknown colour", "\\color{nope}{x}",
                  .exact("Unknown colour \u{201C}nope\u{201D}")),
        ErrorCase("empty superscript", "x^",
                  .exact("^ needs something to raise")),
        ErrorCase("empty subscript", "x_}",
                  .exact("_ needs something to lower")),
        ErrorCase("unclosed degree", "\\sqrt[3",
                  .exact("Missing ] to close this [")),
        ErrorCase("unclosed text", "\\text{abc",
                  .exact("Missing } to close this \\text")),
        ErrorCase("math command in text", "\\text{\\alpha}",
                  .exact("\\alpha doesn't work inside \\text")),
        ErrorCase("dollar signs", "$x$",
                  .prefix("You're already in math mode")),
        ErrorCase("bad size", "\\hspace{2furlongs}",
                  .suffix("isn't a size I understand, like 1em or 3mu")),
        ErrorCase("lone backslash", "x\\",
                  .exact("A lone \\ needs a command name after it")),
        ErrorCase("limits needs an operator", "x\\limits",
                  .prefix("\\limits has to come right after")),
        ErrorCase("ambiguous over", "{a \\over b \\over c}",
                  .prefix("Only one \\over")),
    ])
    func malformedFormulasExplainTheirErrors(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test @MainActor
    func deepNestingReportsTheDepthLimit() throws {
        #expect(try Parser.failure(String(repeating: "{", count: 400)).message == "This formula nests too deep to draw", "deep nesting is caught")
    }
}
