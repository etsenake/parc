import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsEnvironmentTests {
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test
    func alignatKeepsItsColumnPairsAndRowNumbers() throws {
        guard case .environment(let alignat)? = try Parser.parse("\\begin{alignat}{2} a &= b & c &= d \\\\ e &= f \\end{alignat}").first else {
            Issue.record("alignat parses")
            return
        }
        #expect(alignat.kind == .alignedAt && alignat.columns == [.right, .left, .right, .left], "alignat takes its column pairs")
        #expect(alignat.tags == [[.text("(1)", .roman)], [.text("(2)", .roman)]], "alignat numbers every row: \(alignat.tags)")
    }

    @Test
    func alignedatDoesNotNumberRows() throws {
        guard case .environment(let alignedat)? = try Parser.parse("\\begin{alignedat}{1} a &= b \\end{alignedat}").first else {
            Issue.record("alignedat parses")
            return
        }
        #expect(alignedat.kind == .alignedAt && alignedat.tags.isEmpty, "alignedat never numbers")
    }

    @Test
    func starredAlignatDoesNotNumberRows() throws {
        #expect(try Parser.parse("\\begin{alignat*}{1} a &= b \\\\ c &= d \\end{alignat*}").first.map { node in
            if case .environment(let environment) = node { return environment.tags.isEmpty }
            return false
        } == true, "alignat* stays unnumbered")
    }

    @Test(arguments: [
        ErrorCase("alignat caps the pairs", "\\begin{alignat}{1} a &= b & c \\end{alignat}",
                  .contains("more columns")),
        ErrorCase("alignat needs a count", "\\begin{alignat}{x} a \\end{alignat}",
                  .contains("column pairs")),
    ])
    func alignatChecksItsColumnPairCount(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func multlineKeepsAllRowsAndNumbersTheLast() throws {
        guard case .environment(let multline)? = try Parser.parse("\\begin{multline} a + b \\\\ c \\label{long} \\\\ d \\end{multline}").first else {
            Issue.record("multline parses")
            return
        }
        #expect(multline.kind == .multline && multline.rows.count == 3, "multline keeps its lines")
        #expect(multline.tags == [nil, nil, [.text("(1)", .roman)]], "multline takes one number on its last line: \(multline.tags)")
    }

    @Test
    func starredMultlineDropsATrailingBreakWithoutNumbering() throws {
        guard case .environment(let quiet)? = try Parser.parse("\\begin{multline*} a \\\\ b \\\\ \\end{multline*}").first else {
            Issue.record("multline* parses")
            return
        }
        #expect(quiet.tags.isEmpty && quiet.rows.count == 2, "multline* stays unnumbered and drops a trailing break")
    }

    @Test
    func aMultlineTagLandsOnTheLastLine() throws {
        guard case .environment(let tagged)? = try Parser.parse("\\begin{multline} a \\tag{M} \\\\ b \\end{multline}").first else {
            Issue.record("tagged multline parses")
            return
        }
        #expect(tagged.tags.count == 2 && tagged.tags[0] == nil && tagged.tags[1] != nil, "a multline tag lands on the last line")
    }

    @Test(arguments: [
        ErrorCase("multline has one column", "\\begin{multline} a & b \\end{multline}",
                  .contains("doesn't use &")),
    ])
    func multlineRejectsAColumnSeparator(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func subarrayUsesOneLeftAlignedColumn() throws {
        guard case .environment(let subarray)? = try Parser.parse("\\begin{subarray}{l} i < n \\\\ j < m \\end{subarray}").first else {
            Issue.record("subarray parses")
            return
        }
        #expect(subarray.kind == .subarray && subarray.columns == [.left] && subarray.rows.count == 2, "subarray is one left column")
    }

    @Test(arguments: [
        ErrorCase("subarray takes one column", "\\begin{subarray}{cc} a \\end{subarray}",
                  .contains("single column")),
        ErrorCase("subarray takes only c or l", "\\begin{subarray}{r} a \\end{subarray}",
                  .contains("single column")),
        ErrorCase("subarray rejects &", "\\begin{subarray}{c} a & b \\end{subarray}",
                  .contains("more columns")),
    ])
    func subarrayRejectsInvalidColumnSpecsAndRows(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func dcasesUsesDisplayCellsAndALeftBrace() throws {
        guard case .environment(let dcases)? = try Parser.parse("\\begin{dcases} \\frac12 & x > 0 \\end{dcases}").first else {
            Issue.record("dcases parses")
            return
        }
        #expect(dcases.kind == .cases && dcases.displayCells && dcases.left == "{" && dcases.columns == [.left, .left], "dcases")
    }

    @Test
    func drcasesUsesDisplayCellsAndARightBrace() throws {
        guard case .environment(let drcases)? = try Parser.parse("\\begin{drcases} a & b \\end{drcases}").first else {
            Issue.record("drcases parses")
            return
        }
        #expect(drcases.kind == .cases && drcases.displayCells && drcases.right == "}" && drcases.left == nil, "drcases")
    }

    @Test
    func darrayUsesDisplayCellsWithTheSpecifiedColumnAlignments() throws {
        guard case .environment(let darray)? = try Parser.parse("\\begin{darray}{rl} a & b \\end{darray}").first else {
            Issue.record("darray parses")
            return
        }
        #expect(darray.kind == .array && darray.displayCells && darray.columns == [.right, .left], "darray")
    }

    @Test
    func casesUsesTextStyleCells() throws {
        guard case .environment(let plainCases)? = try Parser.parse("\\begin{cases} a & b \\end{cases}").first else {
            Issue.record("cases parses")
            return
        }
        #expect(!plainCases.displayCells, "cases stays text style")
    }

    @Test
    func aStarredMatrixUsesTheSpecifiedAlignment() throws {
        guard case .environment(let starred)? = try Parser.parse("\\begin{pmatrix*}[r] 1 & -1 \\\\ -10 & 2 \\end{pmatrix*}").first else {
            Issue.record("pmatrix* parses")
            return
        }
        #expect(starred.kind == .matrix && starred.left == "(" && starred.columns == [.right, .right], "pmatrix* lines columns up")
    }

    @Test
    func aStarredMatrixDefaultsToCenteredColumns() throws {
        guard case .environment(let centred)? = try Parser.parse("\\begin{bmatrix*} 1 & 2 \\end{bmatrix*}").first else {
            Issue.record("bmatrix* parses")
            return
        }
        #expect(centred.left == "[" && centred.columns == [.center, .center], "matrix* defaults to centred")
    }

    @Test(arguments: [
        ErrorCase("matrix* checks its alignment", "\\begin{Vmatrix*}[x] 1 \\end{Vmatrix*}",
                  .contains("[l], [c] or [r]")),
    ])
    func starredMatricesRejectUnknownAlignment(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func anArrayDistinguishesDashedAndSolidRules() throws {
        guard case .environment(let dashed)? = try Parser.parse("\\begin{array}{c:c|c} a & b & c \\\\ \\hdashline d & e & f \\\\ \\hline \\end{array}").first else {
            Issue.record("dashed array parses")
            return
        }
        #expect(dashed.columnRules == [1, 2] && dashed.columnRuleDashes == [true, false], "colons draw dashed columns")
        #expect(dashed.rowRules == [1, 2] && dashed.rowRuleDashes == [true, false], "hdashline draws a dashed row rule")
    }

    @Test
    func pmatrixKeepsItsShapeAndCenteredColumns() throws {
        guard case .environment(let matrix)? = try Parser.parse("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}").first else {
            Issue.record("pmatrix parses")
            return
        }
        #expect(matrix.kind == .matrix && matrix.left == "(" && matrix.right == ")", "pmatrix delimiters")
        #expect(matrix.rows.count == 2 && matrix.rows.allSatisfy { $0.count == 2 }, "2 by 2 matrix")
        #expect(matrix.columns == [.center, .center], "matrix columns centre")
    }

    struct MatrixCase: Sendable, CustomTestStringConvertible {
        let name: String
        let left: String
        let right: String

        init(_ name: String, _ left: String, _ right: String) {
            self.name = name
            self.left = left
            self.right = right
        }

        var testDescription: String { name }
    }

    @Test(arguments: [
        MatrixCase("bmatrix", "[", "]"), MatrixCase("Bmatrix", "{", "}"),
        MatrixCase("vmatrix", "|", "|"), MatrixCase("Vmatrix", "‖", "‖"),
    ])
    func eachMatrixUsesItsOwnDelimiters(fixture: MatrixCase) throws {
        let name = fixture.name
        guard case .environment(let environment)? = try Parser.parse("\\begin{\(name)}1\\end{\(name)}").first else {
            Issue.record("\(name) parses")
            return
        }
        #expect(environment.left == fixture.left && environment.right == fixture.right, "\(name) delimiters")
    }

    @Test
    func aTrailingMatrixBreakDoesNotAddARow() throws {
        guard case .environment(let trailing)? = try Parser.parse("\\begin{matrix} 1 \\\\ 2 \\\\ \\end{matrix}").first else {
            Issue.record("trailing row break parses")
            return
        }
        #expect(trailing.rows.count == 2, "a trailing \\\\ doesn't add a row")
    }

    @Test
    func casesKeepTheirBraceAndLeftAlignedColumns() throws {
        guard case .environment(let cases)? = try Parser.parse("f(x) = \\begin{cases} 1 & x > 0 \\\\ 0 & \\text{otherwise} \\end{cases}").last else {
            Issue.record("cases parses")
            return
        }
        #expect(cases.kind == .cases && cases.left == "{" && cases.right == nil && cases.columns == [.left, .left], "cases shape")
    }

    @Test
    func alignedAlternatesRightAndLeftColumns() throws {
        guard case .environment(let aligned)? = try Parser.parse("\\begin{aligned} a &= b \\\\ &= c \\end{aligned}").first else {
            Issue.record("aligned parses")
            return
        }
        #expect(aligned.columns == [.right, .left] && aligned.rows[1][0].isEmpty, "aligned alternates right and left")
    }

    @Test
    func starredAlignProducesOneEnvironment() throws {
        #expect(try Parser.parse("\\begin{align*} x &= 1 \\end{align*}").count == 1, "align*")
    }

    @Test
    func gatheredKeepsItsRows() throws {
        guard case .environment(let gathered)? = try Parser.parse("\\begin{gathered} a \\\\ b \\end{gathered}").first else {
            Issue.record("gathered parses")
            return
        }
        #expect(gathered.kind == .gathered && gathered.rows.count == 2, "gathered")
    }

    @Test
    func arraysKeepTheirColumnRulesRowRulesAndSpacing() throws {
        guard case .environment(let array)? = try Parser.parse("\\begin{array}{|c|l|} \\hline a & b \\\\[2pt] \\hline c & d \\\\ \\hline \\end{array}").first else {
            Issue.record("array parses")
            return
        }
        #expect(array.columns == [.center, .left] && array.columnRules == [0, 1, 2], "array spec with rules")
        #expect(array.rowRules == [0, 1, 2] && array.rows.count == 2, "array hlines")
        #expect(array.rowSpacing[0] == 0.2, "row spacing after \\\\[2pt]")
    }

    @Test
    func aDiagramKeepsObjectsAndArrowsInTheirCells() throws {
        let source = "\\begin{CD} A @>a>b> B \\\\ @VcVdV @AAA \\\\ C @<<< D @= E \\\\ @| @. \\\\ \\end{CD}"
        guard case .environment(let diagram)? = try Parser.parse(source).first else { Issue.record("CD parses"); return }
        #expect(diagram.kind == .commutativeDiagram && diagram.rows.count == 4 && diagram.arrows.count == 4, "CD keeps object and arrow rows")
        #expect(try diagram.rows[0].count == 3 && diagram.rows[0][0] == Parser.parse("A") && diagram.rows[0][2] == Parser.parse("B"), "objects sit between arrows")
        #expect(try diagram.arrows[0][1] == NoteMathDiagramArrow(direction: .right, first: Parser.parse("a"), second: Parser.parse("b")), "@>a>b> puts a above and b below: \(diagram.arrows[0])")
        #expect(diagram.arrows[0][0] == nil && diagram.arrows[0][2] == nil, "object cells aren't arrows")
        #expect(try diagram.arrows[1].count == 3 && diagram.arrows[1][0] == NoteMathDiagramArrow(direction: .down, first: Parser.parse("c"), second: Parser.parse("d")), "@VcVdV labels both sides: \(diagram.arrows[1])")
        #expect(diagram.arrows[1][2]?.direction == .up && diagram.arrows[1][1] == nil, "@AAA points up under the next object")
        #expect(diagram.arrows[2][1]?.direction == .left && diagram.arrows[2][3]?.direction == .equals, "@<<< and @=")
        #expect(diagram.arrows[3][0]?.direction == .parallel && diagram.arrows[3][2]?.direction == .empty, "@| and @.")
        #expect(diagram.columns == Array(repeating: .center, count: 5), "CD centres every column")
    }

    @Test
    func aDiagramDoesNotConsumeAnEquationNumber() throws {
        let source = "\\begin{CD} A @>a>b> B \\\\ @VcVdV @AAA \\\\ C @<<< D @= E \\\\ @| @. \\\\ \\end{CD}"
        #expect((try? NoteMathParser.parseEquation(source, display: true).automaticNumbers) == 0, "CD never takes a number")
    }

    @Test(arguments: [
        ErrorCase("an unfinished arrow says so", "\\begin{CD} A @>a B \\end{CD}",
                  .contains("needs another >")),
        ErrorCase("a new arrow can't start inside a label", "\\begin{CD} A @>a @>>> B \\end{CD}",
                  .contains("needs another >")),
        ErrorCase("unknown arrow letters explain themselves", "\\begin{CD} A @x B \\end{CD}",
                  .contains("follow it with")),
        ErrorCase("an unclosed CD", "\\begin{CD} A @>>> B",
                  .exact("Missing \\end{CD}")),
        ErrorCase("mismatched CD end", "\\begin{CD} A \\end{matrix}",
                  .contains("ends with")),
    ])
    func aDiagramReportsMalformedArrowsAndEnds(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }
}
