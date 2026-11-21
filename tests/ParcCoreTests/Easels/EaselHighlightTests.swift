import Foundation
import Testing
@testable import ParcCore

struct EaselHighlightTests {
    @Test(arguments: NoteColor.allCases)
    func everyHighlightHasItsOwnLightAndDarkColourWithAnAlpha(color: NoteColor) {
        let light = EaselPalette.mark(color, dark: false), dark = EaselPalette.mark(color, dark: true)
        #expect(light.count == 9 && dark.count == 9)
        #expect(light != dark)
    }

    @Test(arguments: NoteColor.allCases)
    func aStoredHighlightMapsBackToItsNotesColour(color: NoteColor) {
        let light = EaselPalette.mark(color, dark: false)
        #expect(EaselPalette.markColor(for: light) == color)
        #expect(EaselPalette.markColor(for: light.lowercased()) == color)
    }

    @Test(arguments: NoteColor.allCases)
    func eachHighlightHasACSSVariable(color: NoteColor) {
        #expect(EaselPalette.markVariable(for: EaselPalette.mark(color, dark: false)) == "--easel-mark-" + color.rawValue)
    }

    @Test func yellowUsesNotesBackgroundColoursAtTheNotesTints() {
        #expect(EaselPalette.mark(.yellow, dark: false) == "#E8B53A29")
        #expect(EaselPalette.mark(.yellow, dark: true) == "#D9A94A42")
    }

    @Test(arguments: ["#80808030", "#E8B53AFF"])
    func inlineCodeFillAndOpaqueColoursAreNotHighlights(fill: String) {
        #expect(EaselPalette.markColor(for: fill) == nil)
    }

    @Test(arguments: [false, true])
    func theExportDefinesEveryHighlightForEachAppearance(dark: Bool) {
        #expect(EaselPalette.cssDeclarations(dark: dark).contains("--easel-mark-red:" + EaselPalette.mark(.red, dark: dark)))
    }

    private static func highlighted(_ background: String) -> EaselRichText {
        var attributes = EaselRichText.Attributes(font: .init(name: "Menlo", size: 14), ink: "#000000FF")
        attributes.background = background
        return EaselRichText(runs: [.init(location: 0, length: 5, attributes: attributes)])
    }

    @Test func aHighlightedRunValidates() {
        #expect((try? Self.highlighted(EaselPalette.mark(.green, dark: false)).validate(text: "hello")) != nil)
    }

    @Test func aMalformedHighlightIsRefused() {
        #expect((try? Self.highlighted("#12").validate(text: "hello")) == nil)
    }

    private static func exported(_ color: String) -> String {
        var run = EaselVectorTextRun(x: 4, y: 16, text: "hi", fontFamily: "sans-serif", fontSize: 14)
        run.mark = EaselVectorMark(x: 4, y: 2, width: 40, height: 20, color: color)
        return EaselVectorExport.textRun(run)
    }

    @Test func aHighlightedRunDrawsItsColourBehindTheWordsFollowingLightAndDark() throws {
        let svg = Self.exported(EaselPalette.mark(.blue, dark: false))
        #expect(svg.contains("var(--easel-mark-blue,#3D8FC429)"))
        let rect = try #require(svg.range(of: "<rect"))
        let text = try #require(svg.range(of: "<text"))
        #expect(rect.lowerBound < text.lowerBound)
    }

    @Test func aBadHighlightColourDrawsNothing() {
        #expect(!Self.exported("javascript:").contains("<rect"))
    }

    @Test func otherEightDigitFillsSuchAsInlineCodeDrawAsTheyAre() {
        #expect(Self.exported("#80808030").contains("fill:#80808030"))
    }
}
