import Foundation
import Testing
@testable import ParcCore

struct NoteMathHostileInputTests {
    private func message(parsing source: String) -> String? {
        runOnLargeStack { () -> String? in
            do { _ = try NoteMathParser.parse(source) } catch let error as NoteMathParseError { return error.message } catch { return "\(error)" }
            return nil
        }
    }

    private func rejects(_ source: String) throws {
        let text = try #require(message(parsing: source), "this should not parse")
        #expect(!text.isEmpty)
    }

    @Test(arguments: ["\\sqrt", "\\mathbf", "\\frac", "\\not", "\\overline", "\\boxed", "\\vec"])
    func aCommandChainedToItselfFailsInsteadOfOverflowingTheStack(_ command: String) throws {
        try rejects(String(repeating: command, count: 20_000) + " x")
    }

    @Test(arguments: ["\\bf", "\\displaystyle", "\\large", "\\color{red}", "\\rm"])
    func aSwitchRepeatedManyTimesFailsInsteadOfOverflowingTheStack(_ switchCommand: String) throws {
        try rejects(String(repeating: switchCommand, count: 20_000) + "x")
    }

    @Test func textNestedInsideItselfFailsInsteadOfOverflowingTheStack() throws {
        try rejects("\\text" + String(repeating: "{", count: 20_000) + "x" + String(repeating: "}", count: 20_000))
        try rejects("\\text{" + String(repeating: "\\textbf{", count: 20_000) + "x" + String(repeating: "}", count: 20_000) + "}")
        try rejects("\\text{" + String(repeating: "\\bf", count: 20_000) + "x}")
    }

    @Test func aFormulaNestedAsDeepAsPeopleWriteStillParses() throws {
        let source = String(repeating: "\\frac{1}{", count: 30) + "x" + String(repeating: "}", count: 30)
        #expect(message(parsing: source) == nil)
        #expect(message(parsing: String(repeating: "\\sqrt", count: 30) + "{x}") == nil)
    }

    @Test(arguments: ["4611686018427387904", "100000000", "9223372036854775807", "0", "51"])
    func alignedColumnPairsAreBounded(_ count: String) throws {
        try rejects("\\begin{alignedat}{\(count)} a \\end{alignedat}")
    }

    @Test func alignedColumnPairsWithinTheLimitStillWork() throws {
        #expect(message(parsing: "\\begin{alignedat}{50} a &= b \\end{alignedat}") == nil)
    }

    @Test(arguments: [
        "\\hspace{\(String(repeating: "9", count: 400))em}",
        "\\hspace{1000em}",
        "\\rule{1em}{9999999999999999999999999999em}",
        "\\\\[\(String(repeating: "9", count: 30))pt]",
    ])
    func sizesThatCouldNeverBeDrawnAreRejected(_ source: String) throws {
        try rejects(source)
    }

    @Test func ordinarySizesStillParse() throws {
        #expect(message(parsing: "a\\hspace{2em}b\\rule{1em}{3pt}\\kern 10mu c") == nil)
    }

    @Test func aMacroThatMultipliesItsArgumentIsStoppedBeforeItFillsMemory() throws {
        let source = "\\def\\a#1{" + String(repeating: "#1", count: 5_000) + "}\\a{" + String(repeating: "x", count: 5_000) + "}"
        #expect(try #require(message(parsing: source)).contains("too big"))
    }

    @Test func macroDefinitionsNestedInsideMacroDefinitionsAreStopped() throws {
        try rejects(String(repeating: "\\edef\\a{", count: 20_000) + "x" + String(repeating: "}", count: 20_000))
    }

    @Test func chemistryNestedInsideChemistryFailsInsteadOfOverflowingTheStack() throws {
        try rejects("\\ce{" + String(repeating: "\\frac{", count: 20_000) + "a" + String(repeating: "}", count: 20_000) + "}")
        try rejects("\\ce{" + String(repeating: "->[", count: 20_000) + "a" + String(repeating: "]", count: 20_000) + "}")
    }

    @Test func ordinaryChemistryStillParses() throws {
        #expect(message(parsing: "\\ce{2H2 + O2 -> 2H2O}") == nil)
        #expect(message(parsing: "\\ce{A ->[heat] B ->[x][y] C}") == nil)
        #expect(message(parsing: "\\ce{\\frac{1}{2}H2 -> H2O}") == nil)
    }
}
