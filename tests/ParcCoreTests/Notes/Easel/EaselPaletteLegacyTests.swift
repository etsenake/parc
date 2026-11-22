import Foundation
import Testing
@testable import ParcCore

struct EaselPaletteLegacyTests {
    func item(_ kind: EaselItemKind) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: 0, y: 0, width: 100, height: 80))
    }

    @Test
    func legacyOutlineWidthsDependOnTheObjectKind() {
        #expect(EaselPaintRules.strokeWidth(item(.rectangle)) == 2.5 && EaselPaintRules.strokeWidth(item(.circle)) == 2.5, "Shapes saved before styles keep their 2.5-point outline")
        #expect(EaselPaintRules.strokeWidth(item(.arrow)) == 3 && EaselPaintRules.strokeWidth(item(.freehand)) == 3, "Arrows and drawings saved before styles keep their 3-point line")
        #expect(EaselPaintRules.strokeWidth(item(.text)) == 0 && EaselPaintRules.strokeWidth(item(.sticky)) == 0, "Text and stickies have no outline by default")
    }

    @Test
    func shapeStrokeWidthsClampAndFallBackWhenDamaged() {
        var shape = item(.rectangle)
        shape.strokeWidth = 0
        #expect(EaselPaintRules.strokeWidth(shape) == 0, "Zero width means no outline")
        shape.strokeWidth = 900
        #expect(EaselPaintRules.strokeWidth(shape) == EaselPaintRules.maximumWidth, "Widths stay within the saved range")
        shape.strokeWidth = .nan
        #expect(EaselPaintRules.strokeWidth(shape) == 2.5, "A damaged width falls back to the default")
    }

    @Test
    func arrowsKeepAMinimumVisibleWidth() {
        var arrow = item(.arrow)
        arrow.strokeWidth = 0
        #expect(EaselPaintRules.strokeWidth(arrow) == EaselPaintRules.minimumLineWidth, "Arrows never vanish while staying clickable")
    }

    @Test
    func highlightersUseWideTranslucentHighlightInk() {
        var marker = item(.freehand)
        marker.brush = .highlighter
        #expect(EaselPaintRules.strokeWidth(marker) == 16 && EaselPaintRules.strokeOpacity(marker) == 0.35, "Highlighters are wide and see-through")
        #expect(EaselPaintRules.ink(marker) == (EaselPalette.stored(EaselPalette.defaultHighlight, role: .highlight), .highlight), "A default highlighter draws in the default highlight colour")
    }

    @Test
    func textIgnoresAStrayStrokeWidth() {
        var text = item(.text)
        text.strokeWidth = 6
        #expect(EaselPaintRules.strokeWidth(text) == 0, "Kinds without an outline ignore a stray width")
    }

    @Test
    func dashLengthsFollowTheStrokeWidth() {
        #expect(EaselPaintRules.dashPattern(nil, width: 3).isEmpty && EaselPaintRules.dashPattern(.solid, width: 3).isEmpty, "Solid lines have no dashes")
        #expect(EaselPaintRules.dashPattern(.dashed, width: 3) == [9, 9], "Dashes scale with the line width")
        #expect(EaselPaintRules.dashPattern(.dotted, width: 4) == [0, 8], "Dots are round caps spaced by twice the width")
        #expect(EaselPaintRules.dashPattern(.dotted, width: 0.25) == [0, 2], "Hairline dots stay visible")
    }

    @Test
    func arrowheadLengthGrowsWithTheStrokeWidth() {
        #expect(EaselPaintRules.arrowHeadLength(width: 3) == 16, "Default arrows keep their 16-point head")
        #expect(EaselPaintRules.arrowHeadLength(width: 8) > EaselPaintRules.arrowHeadLength(width: 3), "Heads grow with the line")
    }

    @Test
    func legacyShapesUseALightInkWash() {
        #expect(EaselPaintRules.fill(item(.rectangle)) == .wash(opacity: 0.09), "Shapes saved before styles keep their light ink wash")
    }

    @Test
    func textArrowsAndImagesHaveNoFill() {
        #expect(EaselPaintRules.fill(item(.text)) == .none && EaselPaintRules.fill(item(.arrow)) == .none
               && EaselPaintRules.fill(item(.image)) == .none, "Only shapes, stickies and sections take a fill")
    }

    @Test
    func fillColoursUseTheSavedOpacity() {
        var shape = item(.circle)
        shape.fill = "#d8e9f3"
        #expect(EaselPaintRules.fill(shape) == .color(hex: "#D8E9F3", role: .fill, opacity: 1), "A chosen fill is opaque by default")
        shape.fillOpacity = 0.5
        #expect(EaselPaintRules.fill(shape) == .color(hex: "#D8E9F3", role: .fill, opacity: 0.5), "Fill opacity applies to the fill")
        shape.fillOpacity = 0
        #expect(EaselPaintRules.fill(shape) == .none, "Zero opacity means no fill")
    }

    @Test
    func opacityWithoutAFillUsesTheOutlineColour() {
        var shape = item(.circle)
        shape.fillOpacity = 0.3
        #expect(EaselPaintRules.fill(shape) == .wash(opacity: 0.3), "Opacity without a colour tints the outline colour")
    }

    @Test
    func stickyPaperUsesTheStickyPalette() {
        let sticky = item(.sticky)
        #expect(EaselPaintRules.fill(sticky) == .color(hex: EaselPalette.hex(EaselPalette.defaultSticky, role: .sticky) ?? "", role: .sticky, opacity: 1), "Stickies without a colour use the default sticky paper")
        var paper = item(.sticky)
        paper.fill = EaselPalette.hex(.note(.green), role: .sticky)
        if case .color(_, let role, _) = EaselPaintRules.fill(paper) { #expect(role == .sticky, "Stickies resolve their paper as sticky colours") }
        else { Issue.record("A coloured sticky has paper"); return }
    }
}
