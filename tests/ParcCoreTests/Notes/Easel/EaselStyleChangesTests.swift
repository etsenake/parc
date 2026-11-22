import Foundation
import Testing
@testable import ParcCore

struct EaselStyleChangesTests {
    @Test
    func recolouringTextOverridesEveryRun() {
        var text = EaselStyleTestsSupport.item(.text)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: .init(font: .init(name: "Nunito", size: 15), ink: "#194B93FF")),
            .init(location: 2, length: 2, attributes: .init(font: .init(name: "Nunito", size: 15), ink: "#000000FF", semanticInk: .noteBody)),
        ])
        text.text = "Hiya"
        #expect(EaselStyle.apply(.color(.palette(.note(.blue))), to: &text), "Text takes a colour")
        #expect(text.color == "#2C6C91" && text.richText?.runs.allSatisfy({ $0.attributes.ink == "#2C6C91FF" && $0.attributes.semanticInk == nil }) == true, "Recolouring text overrides every run")
    }

    @Test
    func recolouringShapesKeepsTheFillMode() {
        var shape = EaselStyleTestsSupport.item(.rectangle)
        EaselStyle.apply(.color(.palette(.note(.green))), to: &shape)
        #expect(shape.color == "#3B7255" && shape.fill == nil, "A shape without a fill keeps its tint")
        shape.fill = "#FFFFFF"
        EaselStyle.apply(.color(.palette(.note(.green))), to: &shape)
        #expect(shape.fill == "#DCEBE2", "A filled shape takes the matching pastel")
        EaselStyle.apply(.color(.palette(.automatic)), to: &shape)
        #expect(shape.color == "#252525" && shape.fill == "#FFFFFF", "Default outlines a white shape")
        EaselStyle.apply(.color(.custom("#ff8800")), to: &shape)
        #expect(shape.color == "#FF8800" && shape.fill == "#FF8800", "Custom colours are used as chosen")
    }

    @Test
    func aStickyColourChangesItsPaperAndKeepsAutomaticInk() {
        var sticky = EaselStyleTestsSupport.item(.sticky)
        EaselStyle.apply(.color(.palette(.note(.pink))), to: &sticky)
        #expect(sticky.fill == "#EDBAD5" && sticky.color == "#252525", "Stickies take paper and keep their automatic text")
        EaselStyle.apply(.color(.palette(.automatic)), to: &sticky)
        #expect(sticky.fill == EaselPalette.hex(EaselPalette.defaultSticky, role: .sticky), "Default gives a sticky the default paper, not white")
        EaselStyle.apply(.color(.palette(.neutral)), to: &sticky)
        #expect(sticky.fill == "#FFFFFF", "White paper is white")
    }

    @Test
    func sectionColoursSetTheBodyAndTitleInk() {
        var section = EaselStyleTestsSupport.item(.section)
        EaselStyle.apply(.color(.palette(.note(.purple))), to: &section)
        #expect(section.fill == "#EBE2F3" && section.color == "#8154A3", "Sections take a pastel body and a matching title ink")
        EaselStyle.apply(.color(.custom("#123456")), to: &section)
        #expect(section.fill == "#123456" && section.color == "#252525", "Custom sections keep the automatic title ink")
        EaselStyle.apply(.color(.palette(.automatic)), to: &section)
        #expect(section.fill == nil && section.color == "#252525", "Default takes a section back to its plain look")
    }

    @Test
    func highlightersUseTheHighlightPalette() {
        var marker = EaselStyleTestsSupport.item(.freehand)
        marker.brush = .highlighter
        EaselStyle.apply(.color(.palette(.note(.green))), to: &marker)
        #expect(marker.color == "#4F9A6E", "Highlighters store highlight colours")
        EaselStyle.apply(.color(.palette(.automatic)), to: &marker)
        #expect(marker.color == "#E8B53A", "A default highlighter is yellow")
    }

    @Test
    func imagesDoNotTakeStyleColours() {
        var picture = EaselStyleTestsSupport.item(.image)
        #expect(!EaselStyle.apply(.color(.palette(.note(.red))), to: &picture) && picture.color == "#252525", "Images are skipped")
    }

    @Test func solidDerivesThePastelFromTheOutline() {
        var shape = EaselStyleTestsSupport.item(.circle)
        shape.color = "#2C6C91"
        EaselStyle.apply(.fill(.solid), to: &shape)
        #expect(shape.fill == "#D8E9F3" && shape.fillOpacity == nil, "Solid derives the pastel from the outline")
        EaselStyle.apply(.fillOpacity(0.3), to: &shape)
        #expect(shape.fillOpacity == 0.3 && EaselStyle.fillMode(of: shape) == .solid, "Custom opacity keeps a solid fill's colour")
        EaselStyle.apply(.fillOpacity(4), to: &shape)
        #expect(shape.fillOpacity == nil, "Full opacity is omitted from the file")
        EaselStyle.apply(.fill(.none), to: &shape)
        #expect(shape.fillOpacity == 0 && shape.fill == "#D8E9F3" && EaselPaintRules.fill(shape) == .none, "No fill keeps the colour for later")
        EaselStyle.apply(.fill(.transparent), to: &shape)
        #expect(shape.fill == nil && shape.fillOpacity == nil && EaselPaintRules.fill(shape) == .wash(opacity: EaselPaintRules.washOpacity), "Transparent is the classic tint of the outline colour")
        EaselStyle.apply(.fillOpacity(0.3), to: &shape)
        #expect(shape.fill == nil && shape.fillOpacity == 0.3 && EaselStyle.fillMode(of: shape) == .transparent, "Opacity strengthens the tint")
        EaselStyle.apply(.fillOpacity(EaselPaintRules.washOpacity), to: &shape)
        #expect(shape.fillOpacity == nil, "The classic tint strength is omitted from the file")
        var plain = EaselStyleTestsSupport.item(.rectangle)
        #expect(EaselStyle.fillMode(of: plain) == .transparent && EaselStyle.fillOpacity(of: plain) == EaselPaintRules.washOpacity, "Shapes saved before styles read as the classic tint at its real strength")
        EaselStyle.apply(.fill(.transparent), to: &plain)
        #expect(plain.fill == nil && plain.fillOpacity == nil, "Transparent leaves a classic shape as it was")
        EaselStyle.apply(.fill(.solid), to: &plain)
        #expect(plain.fill == "#FFFFFF", "Solid on a default shape fills it with white paper")
        var custom = EaselStyleTestsSupport.item(.rectangle)
        custom.color = "#FF8800"
        EaselStyle.apply(.fill(.solid), to: &custom)
        #expect(custom.fill == "#FF8800", "Custom outlines fill with their own colour")
        var sticky = EaselStyleTestsSupport.item(.sticky)
        #expect(!EaselStyle.apply(.fill(.none), to: &sticky) && sticky.fillOpacity == nil, "Stickies stay opaque")
    }

    @Test func arrowsTakeWidthAndDots() {
        var arrow = EaselStyleTestsSupport.item(.arrow)
        EaselStyle.apply(.weight(.thick), to: &arrow)
        EaselStyle.apply(.dash(.dotted), to: &arrow)
        #expect(arrow.strokeWidth == 6 && arrow.strokeDash == .dotted, "Arrows take width and dots")
        EaselStyle.apply(.weight(.medium), to: &arrow)
        EaselStyle.apply(.dash(.solid), to: &arrow)
        #expect(arrow.strokeWidth == nil && arrow.strokeDash == nil, "Default width and solid lines are omitted from the file")
        #expect(!EaselStyle.apply(.weight(.none), to: &arrow), "Lines can't lose their stroke")
        var shape = EaselStyleTestsSupport.item(.rectangle)
        EaselStyle.apply(.weight(.none), to: &shape)
        #expect(shape.strokeWidth == 0, "Shapes can drop their outline")
        var drawing = EaselStyleTestsSupport.item(.freehand)
        #expect(!EaselStyle.apply(.dash(.dashed), to: &drawing) && drawing.strokeDash == nil, "Drawings skip dashes")
        EaselStyle.apply(.weight(.thin), to: &drawing)
        #expect(drawing.strokeWidth == 1.5, "Drawings take widths")
        var text = EaselStyleTestsSupport.item(.text)
        #expect(!EaselStyle.apply(.weight(.thick), to: &text), "Text skips widths")
        var labelled = EaselStyleTestsSupport.item(.arrow)
        EaselStyle.apply(.labelBackground(true), to: &labelled)
        #expect(labelled.labelBackground == true && EaselStyleSummary(items: [labelled]).labelBackground == true, "Connectors can show a label background")
        EaselStyle.apply(.labelBackground(false), to: &labelled)
        #expect(labelled.labelBackground == nil, "No label background is omitted from the file")
        var boxed = EaselStyleTestsSupport.item(.rectangle)
        #expect(!EaselStyle.apply(.labelBackground(true), to: &boxed) && boxed.labelBackground == nil, "Shapes have no label background")
    }

    @Test func oneColourAcrossRolesReadsAsThatColour() {
        var blue = EaselStyleTestsSupport.item(.rectangle)
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &blue)
        var blueArrow = EaselStyleTestsSupport.item(.arrow)
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &blueArrow)
        var blueSticky = EaselStyleTestsSupport.item(.sticky)
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &blueSticky)
        let summary = EaselStyleSummary(items: [blue, blueArrow, blueSticky, EaselStyleTestsSupport.item(.image)])
        #expect(summary.color == .palette(.note(.blue)), "One colour across roles reads as that colour")
        #expect(summary.weight == .medium, "Default outlines and lines both read as medium")
        var thick = blueArrow
        EaselStyle.apply(.weight(.thick), to: &thick)
        #expect(EaselStyleSummary(items: [blue, thick]).weight == nil, "Different line weights read as mixed")
        #expect(summary.fill == .transparent && summary.dash == .solid, "Only shapes decide the fill and only shapes and lines the dash")
        var red = EaselStyleTestsSupport.item(.rectangle)
        EaselStyle.apply(.color(.palette(.note(.red))), to: &red)
        #expect(EaselStyleSummary(items: [blue, red]).color == nil, "Different colours read as mixed")
        var text = EaselStyleTestsSupport.item(.text)
        text.text = "Hi"
        text.richText = EaselRichText(runs: [.init(location: 0, length: 2, attributes: .init(font: .init(name: "Nunito", size: 15), ink: "#194B93FF"))])
        #expect(EaselStyleSummary(items: [text]).color == nil, "Text with other run colours reads as mixed")
        #expect(EaselStyleSummary(items: [EaselStyleTestsSupport.item(.text)]).color == .palette(.automatic), "Plain text reads as the default ink")
        var custom = EaselStyleTestsSupport.item(.arrow)
        custom.color = "#ABCDEF"
        #expect(EaselStyleSummary(items: [custom]).color == .custom("#ABCDEF"), "Chosen colours read as custom")
        #expect(EaselStyleSummary(items: [EaselStyleTestsSupport.item(.sticky)]).color == .palette(EaselPalette.defaultSticky), "Plain stickies read as the default paper")
    }
}
