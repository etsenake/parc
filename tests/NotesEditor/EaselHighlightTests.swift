import Foundation

@main
struct EaselHighlightTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        palette()
        export()
        print("EaselHighlightTests passed")
    }

    static func palette() {
        for color in NoteColor.allCases {
            let light = EaselPalette.mark(color, dark: false), dark = EaselPalette.mark(color, dark: true)
            expect(light.count == 9 && dark.count == 9 && light != dark, "Every highlight has its own light and dark colour with an alpha")
            expect(EaselPalette.markColor(for: light) == color && EaselPalette.markColor(for: light.lowercased()) == color,
                   "A stored highlight maps back to its Notes colour")
            expect(EaselPalette.markVariable(for: light) == "--easel-mark-" + color.rawValue, "Each highlight has a CSS variable")
        }
        expect(EaselPalette.mark(.yellow, dark: false) == "#E8B53A29" && EaselPalette.mark(.yellow, dark: true) == "#D9A94A42",
               "Yellow uses Notes' background colours at the Notes tints")
        expect(EaselPalette.markColor(for: "#80808030") == nil && EaselPalette.markColor(for: "#E8B53AFF") == nil,
               "Inline code fill and opaque colours are not highlights")
        let light = EaselPalette.cssDeclarations(dark: false), dark = EaselPalette.cssDeclarations(dark: true)
        expect(light.contains("--easel-mark-red:" + EaselPalette.mark(.red, dark: false))
               && dark.contains("--easel-mark-red:" + EaselPalette.mark(.red, dark: true)), "The export defines every highlight for light and dark")
        var rich = EaselRichText(runs: [])
        var attributes = EaselRichText.Attributes(font: .init(name: "Menlo", size: 14), ink: "#000000FF")
        attributes.background = EaselPalette.mark(.green, dark: false)
        rich.runs = [.init(location: 0, length: 5, attributes: attributes)]
        expect((try? rich.validate(text: "hello")) != nil, "A highlighted run validates")
        rich.runs[0].attributes.background = "#12"
        expect((try? rich.validate(text: "hello")) == nil, "A malformed highlight is refused")
    }

    static func export() {
        let mark = EaselVectorMark(x: 4, y: 2, width: 40, height: 20, color: EaselPalette.mark(.blue, dark: false))
        var run = EaselVectorTextRun(x: 4, y: 16, text: "hi", fontFamily: "sans-serif", fontSize: 14)
        run.mark = mark
        let svg = EaselVectorExport.textRun(run)
        expect(svg.contains("<rect") && svg.contains("var(--easel-mark-blue,#3D8FC429)") && svg.range(of: "<rect")!.lowerBound < svg.range(of: "<text")!.lowerBound,
               "A highlighted run draws its colour behind the words, following light and dark")
        run.mark = EaselVectorMark(x: 0, y: 0, width: 10, height: 10, color: "javascript:")
        expect(!EaselVectorExport.textRun(run).contains("<rect"), "A bad highlight colour draws nothing")
        run.mark = EaselVectorMark(x: 0, y: 0, width: 10, height: 10, color: "#80808030")
        expect(EaselVectorExport.textRun(run).contains("fill:#80808030"), "Other 8-digit fills such as inline code draw as they are")
    }
}
