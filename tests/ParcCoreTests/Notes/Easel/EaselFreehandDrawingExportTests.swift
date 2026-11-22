import Foundation
import Testing
@testable import ParcCore

struct EaselFreehandDrawingExportTests {
    @Test
    func newDoodlesExportAsSmoothCurvesWithRoundEnds() {
        let doodle = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0), EaselFreehandDrawingTestsSupport.p(10, 10)], brush: .marker)
        let marker = EaselVectorExport.drawing(doodle)
        #expect(marker.contains("Q") && marker.contains("stroke-linecap:round") && !marker.contains("easel-highlight"), "New doodles export as smooth curves with round ends")
    }

    @Test
    func legacyDoodlesExportTheirStraightSegments() {
        let legacy = EaselVectorExport.element(EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0), EaselFreehandDrawingTestsSupport.p(10, 10)]), art: EaselVectorArt())
        #expect(!legacy.contains("Q") && legacy.contains("M0 0L10 0L10 10"), "Doodles saved before smoothing export their exact straight segments")
    }

    @Test
    func highlightsExportWideAndTranslucentInHighlightInk() {
        let highlight = EaselVectorExport.drawing(EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(80, 0)], brush: .highlighter))
        #expect(highlight.contains("class=\"easel-highlight\"") && highlight.contains("stroke-opacity:0.35") && highlight.contains("stroke-width:16"), "Highlights export translucent and wide with the multiply blend class")
        #expect(!highlight.contains("var(--easel-ink)"), "An automatic highlighter exports in the default highlight colour, not ink")
    }

    @Test
    func standaloneSVGIncludesAdaptiveHighlightBlending() {
        let lit = EaselVectorExport.svg([EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(80, 0)], brush: .highlighter)], art: EaselVectorArt(), title: "Board")
        #expect(lit.contains("mix-blend-mode:var(--easel-highlight-blend,multiply)") && lit.contains("prefers-color-scheme:dark){.easel-highlight{--easel-highlight-blend:normal}}"), "A standalone SVG carries its own highlight blend for light and dark viewers")
    }

    @Test
    func aDrawingWithoutHighlightsAddsNoBlendStyles() {
        let doodle = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0), EaselFreehandDrawingTestsSupport.p(10, 10)], brush: .marker)
        #expect(!EaselVectorExport.svg([doodle], art: EaselVectorArt(), title: "Board").contains("<style>"), "Boards without highlights add no styles")
        #expect(!EaselVectorExport.css(.standard).contains(".easel-highlight{"), "Page CSS leaves highlight blending to the SVG")
    }

    @Test
    func washiExportsItsPatternTranslucencyAndPlacement() {
        var strip = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(10, 10), EaselFreehandDrawingTestsSupport.p(110, 10)], brush: .washi)
        strip.pattern = "dots"
        let tape = EaselVectorExport.element(strip, art: EaselVectorArt())
        #expect(tape.contains("<pattern id=\"washi-") && tape.contains("fill:url(#washi-") && tape.contains("<circle"), "Tape exports as a pattern fill drawn from its design")
        #expect(tape.contains("opacity=\"0.9\"") && tape.contains("translate(10 10) rotate(0)"), "Tape keeps its translucency and placement")
    }

    @Test
    func eachStripExportsOnePattern() {
        let doodle = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0), EaselFreehandDrawingTestsSupport.p(10, 10)], brush: .marker)
        var strip = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(10, 10), EaselFreehandDrawingTestsSupport.p(110, 10)], brush: .washi)
        strip.pattern = "dots"
        let svg = EaselVectorExport.svg([strip, doodle], art: EaselVectorArt(), title: "Board")
        #expect(svg.components(separatedBy: "<pattern").count == 2, "Each strip carries one pattern")
    }

    @Test
    func separateExportsNeverReuseWashiDefinitionIDs() {
        var strip = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(10, 10), EaselFreehandDrawingTestsSupport.p(110, 10)], brush: .washi)
        strip.pattern = "dots"
        func ids(_ text: String) -> [String] {
            text.components(separatedBy: "id=\"").dropFirst().compactMap { $0.components(separatedBy: "\"").first }
        }
        let twice = EaselVectorExport.svg([strip], art: EaselVectorArt(), title: "One") + EaselVectorExport.svg([strip], art: EaselVectorArt(), title: "Two")
        let tapeIDs = ids(twice).filter { $0.hasPrefix("washi") }
        #expect(tapeIDs.count == 4 && Set(tapeIDs).count == 4, "The same strip exported twice on one page never reuses a pattern or clip id")
    }

    @Test
    func stripsThatShareAnObjectIDGetDistinctSVGDefinitions() {
        var strip = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(10, 10), EaselFreehandDrawingTestsSupport.p(110, 10)], brush: .washi)
        strip.pattern = "dots"
        func ids(_ text: String) -> [String] {
            text.components(separatedBy: "id=\"").dropFirst().compactMap { $0.components(separatedBy: "\"").first }
        }
        var twin = strip
        twin.frame.y += 60
        let pair = ids(EaselVectorExport.svg([strip, twin], art: EaselVectorArt(), title: "Pair")).filter { $0.hasPrefix("washi") }
        #expect(Set(pair).count == pair.count && pair.count == 4, "Strips that share an id still get their own pattern and clip")
    }
}
