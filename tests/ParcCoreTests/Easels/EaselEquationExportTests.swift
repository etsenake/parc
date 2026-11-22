import Foundation
import Testing
@testable import ParcCore

struct EaselEquationExportTests {
    private static func equation(_ text: String = "x^2", frame: EaselRect = EaselRect(x: 10, y: 20, width: 128, height: 68),
                                 color: String? = nil) -> EaselItem {
        var item = EaselItem(kind: .equation, frame: frame, text: text)
        if let color { item.color = color }
        return item
    }

    private static let art = EaselVectorEquation(width: 100, height: 40,
                                                 parts: [EaselVectorEquationPart(path: "M0 0L10 0L10 10Z"),
                                                         EaselVectorEquationPart(path: "M20 0L30 0L30 10Z", color: "#FF0000", opacity: 0.5)])

    @Test func theObjectExportRoutesThroughTheEquationArt() {
        let item = Self.equation()
        #expect(EaselVectorExport.element(item, art: EaselVectorArt(equations: [item.id: Self.art])) == EaselVectorExport.equation(item, Self.art))
    }

    @Test(arguments: [
        "<path d=\"M0 0L10 0L10 10Z\"",
        "fill:var(--easel-ink)",
        "fill:#FF0000;fill-opacity:0.5",
        "translate(24 34)",
        "scale(1)",
        "aria-label=\"Equation: x^2\"",
    ])
    func theExportDrawsTheTypesetOutline(fragment: String) {
        #expect(EaselVectorExport.equation(Self.equation(), Self.art).contains(fragment))
    }

    @Test func resizingScalesTheExportedVectors() {
        let item = Self.equation(frame: EaselRect(x: 0, y: 0, width: 256, height: 136))
        #expect(EaselVectorExport.equation(item, Self.art).contains("scale(2)"))
    }

    @Test func aChosenInkIsExportedWithItsThemeColour() {
        let item = Self.equation(frame: EaselRect(x: 0, y: 0, width: 256, height: 136), color: "#2C6C91")
        #expect(EaselVectorExport.equation(item, Self.art).contains("var(--easel-ink-blue,#2C6C91)"))
    }

    @Test func aTexTypoExportsItsLabelledSource() {
        let failure = EaselVectorEquation(width: 0, height: 0, parts: [], error: "Missing }")
        let fallback = EaselVectorExport.equation(Self.equation("\\frac{"), failure)
        #expect(fallback.contains("<text") && fallback.contains("\\frac{"))
        #expect(fallback.contains("won\u{2019}t typeset"))
    }

    @Test func noArtFallsBackToTheSource() {
        #expect(EaselVectorExport.equation(Self.equation("\\frac{"), nil).contains("<text"))
    }

    @Test func aBlankEquationExportsNothing() {
        #expect(EaselVectorExport.equation(Self.equation("  "), Self.art).isEmpty)
    }

    @Test func theExportedSourceIsEscaped() {
        #expect(!EaselVectorExport.equation(Self.equation("<script>"), nil).contains("<script>"))
    }
}
