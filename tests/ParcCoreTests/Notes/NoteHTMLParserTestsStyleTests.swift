import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLParserTestsStyleTests {
    @Test
    func declarationsSplitOutsideParentheses() {
        let css = NoteHTMLStyleSheet.declarations("color: red; background: url(data:image/png;base64,AA==) no-repeat; font-weight:700 !important;;")
        #expect(css["color"] == "red" && css["font-weight"] == "700" && css["background"]?.hasPrefix("url(data:image/png;base64") == true, "declarations split outside parentheses: \(css)")
    }

    @Test
    func matchingStylesheetRulesApplyAndPrintRulesStayOut() {
        let document = NoteHTMLParser.parse("<style>/* x */ p.p1 {font: italic bold 12.0px Menlo} .s1{color:#f00} h1{color:blue} div span.no{x:y} @media print{.s1{color:green}}</style><p class=\"p1 s1\">t</p>")
        let sheet = NoteHTMLStyleSheet(document)
        let paragraph = document.first { $0.name == "p" }!
        let declarations = sheet.declarations(for: paragraph)
        #expect(declarations["color"] == "#f00", "class rules apply and @media is skipped: \(declarations)")
    }

    @Test
    func fontShorthandSetsStyleWeightFamilyAndSize() {
        let document = NoteHTMLParser.parse("<style>/* x */ p.p1 {font: italic bold 12.0px Menlo} .s1{color:#f00} h1{color:blue} div span.no{x:y} @media print{.s1{color:green}}</style><p class=\"p1 s1\">t</p>")
        let sheet = NoteHTMLStyleSheet(document)
        let paragraph = document.first { $0.name == "p" }!
        let declarations = sheet.declarations(for: paragraph)
        let font = NoteHTMLFont(declarations)
        #expect(font.bold == true && font.italic == true && font.isMonospace && font.size == 9, "font shorthand: \(font)")
    }

    struct FamilyCase: Sendable, CustomTestStringConvertible {
        let family: String
        let isMonospace: Bool

        init(_ family: String, _ isMonospace: Bool) {
            self.family = family
            self.isMonospace = isMonospace
        }

        var testDescription: String { family }
    }

    @Test(arguments: [FamilyCase("\"Courier New\", monospace", true), FamilyCase("Montserrat, sans-serif", false)])
    func fontFamiliesReportWhetherTheyAreMonospaced(fixture: FamilyCase) {
        #expect(NoteHTMLFont(["font-family": fixture.family]).isMonospace == fixture.isMonospace)
    }

    struct WeightCase: Sendable, CustomTestStringConvertible {
        let weight: String
        let isBold: Bool

        init(_ weight: String, _ isBold: Bool) {
            self.weight = weight
            self.isBold = isBold
        }

        var testDescription: String { weight }
    }

    @Test(arguments: [WeightCase("500", false), WeightCase("600", true)])
    func numericFontWeightsReportWhetherTheyAreBold(fixture: WeightCase) {
        #expect(NoteHTMLFont(["font-weight": fixture.weight]).bold == fixture.isBold)
    }

    struct ColorCase: Sendable, CustomTestStringConvertible {
        let value: String
        let expected: NoteColor?

        init(_ value: String, _ expected: NoteColor?) {
            self.value = value
            self.expected = expected
        }

        var testDescription: String { value }
    }

    @Test(arguments: [
        ColorCase("#ff0000", .red), ColorCase("rgb(212, 76, 71)", .red), ColorCase("#C00000", .red), ColorCase("#ffa500", .orange), ColorCase("#FF9900", .orange),
        ColorCase("#D9730D", .orange), ColorCase("#ffff00", .yellow), ColorCase("#FFF2CC", .yellow), ColorCase("#CB912F", .yellow), ColorCase("#00ff00", .green),
        ColorCase("#448361", .green), ColorCase("hsl(120, 60%, 35%)", .green), ColorCase("#0000ff", .blue), ColorCase("#1155cc", .blue), ColorCase("#337EA9", .blue),
        ColorCase("teal", .blue), ColorCase("#9900ff", .purple), ColorCase("purple", .purple), ColorCase("#9065B0", .purple), ColorCase("#ff00ff", .pink),
        ColorCase("#C14C8A", .pink), ColorCase("hotpink", .pink), ColorCase("#8B4513", .brown), ColorCase("#9F6B53", .brown), ColorCase("#000000", nil),
        ColorCase("#1d1c1d", nil), ColorCase("#333", nil), ColorCase("#777777", nil), ColorCase("#ffffff", nil), ColorCase("#f8f8f8", nil), ColorCase("rgb(29, 28, 29)", nil),
        ColorCase("#E9F3F7", nil)
    ])
    func cssColorsMapToTheExpectedPaletteColor(fixture: ColorCase) {
        let (value, expected) = (fixture.value, fixture.expected)
        let reading = NoteHTMLColor.read(value)
        let actual: NoteColor?
        if case .color(let color) = reading { actual = color } else { actual = nil }
        #expect(actual == expected, "\(value) maps to \(String(describing: actual)), expected \(String(describing: expected))")
    }

    @Test(arguments: ["transparent", "rgba(255,0,0,0.1)"])
    func transparentAndLowAlphaColorsReadAsTransparent(value: String) {
        #expect(NoteHTMLColor.read(value) == .transparent)
    }

    @Test
    func inheritDoesNotSpecifyAColor() {
        #expect(NoteHTMLColor.read("inherit") == nil, "keywords are not colours")
    }

    struct StyleCase: Sendable, CustomTestStringConvertible {
        let token: String
        let expected: NoteColorStyle?

        init(_ token: String, _ expected: NoteColorStyle?) {
            self.token = token
            self.expected = expected
        }

        var testDescription: String { token }
    }

    @Test(arguments: [
        StyleCase("red_background", .background(.red)), StyleCase("teal", .text(.green)), StyleCase("default", nil),
    ])
    func notionColorTokensMapToTheExpectedStyle(fixture: StyleCase) {
        #expect(NoteHTMLColor.style(token: fixture.token) == fixture.expected)
    }
}
