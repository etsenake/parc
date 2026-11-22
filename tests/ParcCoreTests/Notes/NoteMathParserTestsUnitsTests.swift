import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsUnitsTests {
    typealias ExpansionCase = NoteMathParserTestsSupport.ExpansionCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        ExpansionCase("comma decimals stay commas", "\\pu{1,2e3 kJ}",
                      "{1{,}2\\cdot 10^{3}~\\mathrm{kJ}}"),
        ExpansionCase("written-out multiplication by a power of ten", "\\pu{1.2x10^3 kJ}",
                      "{1.2\\times 10^{3}~\\mathrm{kJ}}"),
        ExpansionCase("written-out dot product with a negative power", "\\pu{1.2*10^-3 m}",
                      "{1.2\\cdot 10^{-3}~\\mathrm{m}}"),
        ExpansionCase("number, product and exponent", "\\pu{1.2e3 kJ mol-1}",
                      "{1.2\\cdot 10^{3}~\\mathrm{kJ}\\,\\mathrm{mol}^{-1}}"),
        ExpansionCase("multiplication with a star", "\\pu{123 J*s}",
                      "{123~\\mathrm{J}\\cdot \\mathrm{s}}"),
        ExpansionCase("a dot also multiplies", "\\pu{123 J.s}",
                      "\\pu{123 J*s}"),
        ExpansionCase("quotient with a spaced denominator", "\\pu{75.3 J // mol K}",
                      "{75.3~\\frac{\\mathrm{J}}{\\mathrm{mol}\\,\\mathrm{K}}}"),
        ExpansionCase("ranges get an en dash", "\\pu{10-20 K}",
                      "{10\\text{\u{2013}}20~\\mathrm{K}}"),
        ExpansionCase("braced exponents", "\\pu{3 m^{-2}}",
                      "{3~\\mathrm{m}^{-2}}"),
        ExpansionCase("number and unit", "\\pu{123 kJ/mol}",
                      "{123~\\mathrm{kJ}/\\mathrm{mol}}"),
        ExpansionCase("lowercase e uses a dot", "\\pu{1.2e3 kJ}",
                      "{1.2\\cdot 10^{3}~\\mathrm{kJ}}"),
        ExpansionCase("capital E uses a cross", "\\pu{1.2E-3 kJ}",
                      "{1.2\\times 10^{-3}~\\mathrm{kJ}}"),
        ExpansionCase("exponents without a caret", "\\pu{kJ mol-1}",
                      "{\\mathrm{kJ}\\,\\mathrm{mol}^{-1}}"),
        ExpansionCase("exponents with a caret", "\\pu{m/s^2}",
                      "{\\mathrm{m}/\\mathrm{s}^{2}}"),
        ExpansionCase("multiplied units", "\\pu{kg*m2}",
                      "{\\mathrm{kg}\\cdot \\mathrm{m}^{2}}"),
        ExpansionCase("digit groups", "\\pu{12345.67891 m}",
                      "{12\\,345.678\\,91~\\mathrm{m}}"),
        ExpansionCase("four digits stay together", "\\pu{1234 m}",
                      "{1234~\\mathrm{m}}"),
        ExpansionCase("double slash makes a fraction", "\\pu{J//mol}",
                      "{\\frac{\\mathrm{J}}{\\mathrm{mol}}}"),
        ExpansionCase("degrees Celsius", "\\pu{25 °C}",
                      "{25~{}^{\\circ}\\mathrm{C}}"),
        ExpansionCase("uncertainty", "\\pu{1.2+-0.1 mm}",
                      "{1.2\\pm 0.1~\\mathrm{mm}}"),
        ExpansionCase("negative numbers", "\\pu{-40 K}",
                      "{-40~\\mathrm{K}}"),
        ExpansionCase("micro sign", "\\pu{5 µm}",
                      "{5~\\mu \\mathrm{m}}"),
    ])
    func scientificUnitsProduceTheExpectedNotation(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }
}
