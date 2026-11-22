import Foundation
import Testing
@testable import ParcCore

struct EaselStyleControlsTests {
    @Test func rectanglesAndEllipsesAreShapes() {
        #expect(EaselStyleFamily.of(EaselStyleTestsSupport.item(.rectangle)) == .shapes && EaselStyleFamily.of(EaselStyleTestsSupport.item(.circle)) == .shapes, "Rectangles and ellipses are shapes")
        #expect(EaselStyleFamily.of(EaselStyleTestsSupport.item(.arrow)) == .lines && EaselStyleFamily.of(EaselStyleTestsSupport.item(.text)) == .text, "Arrows are lines and text is text")
        #expect(EaselStyleFamily.of(EaselStyleTestsSupport.item(.sticky)) == .stickies && EaselStyleFamily.of(EaselStyleTestsSupport.item(.section)) == .sections, "Stickies and sections")
        var drawing = EaselStyleTestsSupport.item(.freehand)
        #expect(EaselStyleFamily.of(drawing) == .pen, "Drawings default to the pen")
        drawing.brush = .highlighter
        #expect(EaselStyleFamily.of(drawing) == .highlighter, "Highlighter strokes have their own family")
        drawing.brush = .washi
        #expect(EaselStyleFamily.of(drawing) == .tape && EaselStyleControls(items: [drawing])?.weights.isEmpty == true
               && EaselStyleControls(items: [drawing])?.colors.first == .automatic, "Washi tape takes ink colours only, and Default keeps its design")
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &drawing)
        #expect(drawing.color == "#2C6C91", "Tape retints to a Notes colour")
        for kind in [EaselItemKind.image, .link, .webCard, .browser] {
            #expect(EaselStyleFamily.of(EaselStyleTestsSupport.item(kind)) == nil, "\(kind.rawValue) has no style")
        }
        #expect(EaselStyleFamily.shapes.width(.none) == 0 && EaselStyleFamily.shapes.width(.medium) == 2.5, "Shape outlines keep 2.5 as medium")
        #expect(EaselStyleFamily.lines.width(.medium) == 3 && EaselStyleFamily.lines.width(.none) == nil, "Lines keep 3 as medium and can't vanish")
        #expect(EaselStyleFamily.highlighter.width(.thick) == 24, "Highlighters are chunky")
        #expect(EaselStyleFamily.lines.weight(forWidth: 2.9) == .medium && EaselStyleFamily.shapes.weight(forWidth: 0) == EaselStrokeWeight.none, "Widths show the nearest weight")
    }

    @Test func textShowsColourOnly() {
        let text = EaselStyleControls(items: [EaselStyleTestsSupport.item(.text)])
        #expect(text?.colorRole == .ink && text?.fill == false && text?.weights.isEmpty == true && text?.dash == false, "Text shows colour only")
        let shapes = EaselStyleControls(items: [EaselStyleTestsSupport.item(.rectangle), EaselStyleTestsSupport.item(.circle)])
        #expect(shapes?.fill == true && shapes?.weights == [EaselStrokeWeight.none, .thin, .medium, .thick] && shapes?.dash == true
               && shapes?.lineTitle == "Outline", "Shapes show everything")
        let lines = EaselStyleControls(items: [EaselStyleTestsSupport.item(.arrow)])
        #expect(lines?.fill == false && lines?.weights == [.thin, .medium, .thick] && lines?.dash == true && lines?.lineTitle == "Line", "Lines show colour, width and style")
        #expect(EaselStyleControls(items: [EaselStyleTestsSupport.item(.freehand)])?.dash == false, "The pen has no dashes")
        let sticky = EaselStyleControls(items: [EaselStyleTestsSupport.item(.sticky)])
        #expect(sticky?.colorRole == .sticky && sticky?.colors.count == 10 && sticky?.colors.first == .neutral, "Stickies pick paper: white and Notes' nine")
        var marker = EaselStyleTestsSupport.item(.freehand)
        marker.brush = .highlighter
        #expect(EaselStyleControls(items: [marker])?.colors.count == 8, "Highlighters get eight colours")
        #expect(EaselStyleControls(items: [EaselStyleTestsSupport.item(.rectangle), EaselStyleTestsSupport.item(.sticky)])?.lineTitle == "Outline", "Only shapes take lines here, so it says Outline")
        let mixed = EaselStyleControls(items: [EaselStyleTestsSupport.item(.rectangle), EaselStyleTestsSupport.item(.arrow), EaselStyleTestsSupport.item(.sticky)])
        #expect(mixed?.colorRole == .ink && mixed?.weights == [.thin, .medium, .thick] && mixed?.fill == true, "Mixed selections show what any member takes, without options some can't use")
        #expect(EaselStyleControls(items: [EaselStyleTestsSupport.item(.image)]) == nil, "Images have no style controls")
        #expect(lines?.labelBackground == true && shapes?.labelBackground == false, "Only connectors offer a label background")
        let cells = EaselStyleControls(colorRole: .fill, colors: EaselPalette.colors(for: .fill))
        #expect(cells.colors.count == 10 && !cells.fill && cells.weights.isEmpty && !cells.dash && !cells.labelBackground, "Hosts can ask for a colour-only picker in any role")
    }
}
