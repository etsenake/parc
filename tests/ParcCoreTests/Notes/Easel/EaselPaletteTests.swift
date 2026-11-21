import Foundation
import Testing
@testable import ParcCore

struct EaselPaletteTests {
    func luminance(_ hex: String) -> Double {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        func channel(_ shift: UInt32) -> Double {
            let c = Double(value >> shift & 255) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    func ratio(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func item(_ kind: EaselItemKind) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: 0, y: 0, width: 100, height: 80))
    }

    @Test func inkOffersTheAutomaticInkAndNotesNineColours() {
        #expect(EaselPalette.colors(for: .ink) == [.automatic] + NoteColor.allCases.map { .note($0) }, "Ink offers the automatic ink and Notes' nine colours, in Notes order")
        for role in [EaselColorRole.fill, .sticky] {
            #expect(EaselPalette.colors(for: role) == [.neutral] + NoteColor.allCases.map { .note($0) }, "\(role.rawValue) offers the neutral and Notes' nine colours")
        }
        #expect(EaselPalette.colors(for: .highlight).count == 8 && !EaselPalette.colors(for: .highlight).contains(.note(.brown)), "Highlighters offer eight Notes colours")
        #expect(EaselPalette.stored(.automatic, role: .highlight) == EaselPalette.hex(EaselPalette.defaultHighlight, role: .highlight)
               && EaselPalette.stored(.automatic, role: .sticky) == "#FFFFFF" && EaselPalette.stored(.neutral, role: .ink) == "#252525", "Swatches a role lacks store that role's default")
        for role in EaselColorRole.allCases {
            let hexes = EaselPalette.colors(for: role).compactMap { EaselPalette.hex($0, role: role) }
            #expect(hexes.count == EaselPalette.colors(for: role).count, "Every \(role.rawValue) swatch stores a colour")
            #expect(Set(hexes).count == hexes.count, "\(role.rawValue) swatches never share a stored colour")
            #expect(hexes.allSatisfy { EaselPalette.normalized($0) == $0 }, "Stored \(role.rawValue) colours are canonical hex")
        }
        #expect(EaselPalette.hex(.automatic, role: .ink) == "#252525", "The automatic ink keeps the saved default colour")
        #expect(EaselPalette.hex(.automatic, role: .fill) == nil && EaselPalette.hex(.neutral, role: .ink) == nil, "Roles only offer the swatches that suit them")
        #expect(EaselPalette.hex(.note(.blue), role: .ink) == "#2C6C91", "Blue ink is the Notes blue text colour")
        for color in EaselPaletteColor.allCases {
            #expect(EaselPaletteColor(id: color.id) == color, "\(color.id) survives a round trip through its identifier")
        }
        #expect(EaselPaletteColor(id: "teal") == nil, "Unknown identifiers are not palette colours")
        #expect(EaselPaletteColor.neutral.title(dark: false) == "White" && EaselPaletteColor.neutral.title(dark: true) == "Black", "The neutral is named for how it looks on the paper")
        #expect(EaselPaletteColor.automatic.title(dark: true) == "Default" && EaselPaletteColor.note(.pink).title(dark: false) == "Pink", "Swatches use the names Notes uses")
    }

    @Test func lowercaseAndOpaqueEightDigitColoursNormalise() {
        #expect(EaselPalette.normalized("#2c6c91") == "#2C6C91" && EaselPalette.normalized("#2C6C91ff") == "#2C6C91", "Lowercase and opaque eight-digit colours normalise")
        for bad in ["#2C6C9180", "2C6C91", "#2C6C9", "#GGGGGG", "", "#2C6C91FF00", "#\u{FF11}\u{FF12}\u{FF13}456"] {
            #expect(EaselPalette.normalized(bad) == nil, "\(bad) is not a stored opaque colour")
        }
        #expect(EaselPalette.parseHex(" #2c6c91 ") == "#2C6C91" && EaselPalette.parseHex("2C6C91") == "#2C6C91"
               && EaselPalette.parseHex("#f80") == "#FF8800", "Typed hex codes accept short and long forms, with or without #")
        for bad in ["#2C6C9", "#2C6C9180", "blue", "#", "##123456", "#12 456"] {
            #expect(EaselPalette.parseHex(bad) == nil, "\(bad) is not a hex code")
        }
        for role in EaselColorRole.allCases {
            for color in EaselPalette.colors(for: role) {
                guard let hex = EaselPalette.hex(color, role: role) else { continue }
                #expect(EaselPalette.color(for: hex, role: role) == color, "\(color.id) is recognised from its \(role.rawValue) colour")
                #expect(EaselPalette.color(for: hex.lowercased() + "ff", role: role) == color, "\(color.id) is recognised from a rich-text run colour")
            }
        }
        #expect(EaselPalette.color(for: "#194B93", role: .ink) == nil, "Chosen colours are not palette colours")
        let blueFill = EaselPalette.hex(.note(.blue), role: .fill) ?? ""
        #expect(EaselPalette.color(for: blueFill, role: .ink) == nil, "A fill colour used as ink stays a chosen colour")
        #expect(EaselPalette.color(for: "#FFFFFF", role: .ink) == nil, "White text stays white, so pasted white text never flips")
    }

    @Test func theAutomaticInkResolvesToTheNotesInk() {
        #expect(EaselPalette.resolve("#252525", role: .ink, dark: false) == EaselPalette.inkLight
               && EaselPalette.resolve("#252525FF", role: .ink, dark: true) == EaselPalette.inkDark, "The automatic ink resolves to the Notes ink on light and dark paper")
        for role in EaselColorRole.allCases {
            for color in EaselPalette.colors(for: role) {
                guard let hex = EaselPalette.hex(color, role: role), let variants = EaselPalette.variants(hex, role: role) else {
                    Issue.record("\(color.id) has \(role.rawValue) variants")
                    return
                }
                #expect(variants.canonical == hex, "Variants keep the stored colour")
                #expect(variants.adapts, "\(color.id) \(role.rawValue) has its own dark-paper colour")
                if case .note = color { #expect(variants.light == hex, "\(color.id) \(role.rawValue) draws as stored on light paper") }
                #expect(EaselPalette.resolve(hex, role: role, dark: true) == variants.dark, "Dark resolution matches the variants")
            }
        }
        #expect(EaselPalette.resolve("#2C6C91", role: .ink, dark: true) == "#4CA5D8", "Blue ink lightens on dark paper")
        #expect(EaselPalette.resolve("#FFFFFF", role: .sticky, dark: true) == EaselPalette.neutralDark, "A white sticky turns into a dark sticky on dark paper")
        for role in EaselColorRole.allCases {
            #expect(EaselPalette.resolve("#194B93", role: role, dark: true) == "#194B93", "Chosen colours never change")
        }
        #expect(EaselPalette.variants("#194B93", role: .ink) == EaselColorVariants(canonical: "#194B93", light: "#194B93", dark: "#194B93"), "Chosen colours expose identical light and dark values")
        #expect(EaselPalette.variants("#194B93", role: .ink)?.adapts == false, "Chosen colours do not adapt")
        #expect(EaselPalette.variants("blue", role: .ink) == nil, "Invalid colours have no variants")
    }

    @Test func contrast() {
        for dark in [false, true] {
            let ink = EaselPalette.resolve(EaselPalette.automaticInk, role: .ink, dark: dark)
            for role in [EaselColorRole.fill, .sticky] {
                for color in EaselPalette.colors(for: role) {
                    guard let hex = EaselPalette.hex(color, role: role) else { continue }
                    let paper = EaselPalette.resolve(hex, role: role, dark: dark)
                    #expect(ratio(ink, paper) >= 4.5, "Default text reads on \(color.id) \(role.rawValue) in \(dark ? "dark" : "light")")
                }
            }
            for note in NoteColor.allCases {
                guard let line = EaselPalette.hex(.note(note), role: .ink), let fill = EaselPalette.hex(.note(note), role: .fill) else { continue }
                let outline = EaselPalette.resolve(line, role: .ink, dark: dark), inside = EaselPalette.resolve(fill, role: .fill, dark: dark)
                #expect(ratio(outline, inside) >= 3, "A \(note.rawValue) outline stands out from its own fill in \(dark ? "dark" : "light")")
            }
        }
    }

    @Test func shapesSavedBeforeStylesKeepTheir25Point() {
        #expect(EaselPaintRules.strokeWidth(item(.rectangle)) == 2.5 && EaselPaintRules.strokeWidth(item(.circle)) == 2.5, "Shapes saved before styles keep their 2.5-point outline")
        #expect(EaselPaintRules.strokeWidth(item(.arrow)) == 3 && EaselPaintRules.strokeWidth(item(.freehand)) == 3, "Arrows and drawings saved before styles keep their 3-point line")
        #expect(EaselPaintRules.strokeWidth(item(.text)) == 0 && EaselPaintRules.strokeWidth(item(.sticky)) == 0, "Text and stickies have no outline by default")
        var shape = item(.rectangle)
        shape.strokeWidth = 0
        #expect(EaselPaintRules.strokeWidth(shape) == 0, "Zero width means no outline")
        shape.strokeWidth = 900
        #expect(EaselPaintRules.strokeWidth(shape) == EaselPaintRules.maximumWidth, "Widths stay within the saved range")
        shape.strokeWidth = .nan
        #expect(EaselPaintRules.strokeWidth(shape) == 2.5, "A damaged width falls back to the default")
        var arrow = item(.arrow)
        arrow.strokeWidth = 0
        #expect(EaselPaintRules.strokeWidth(arrow) == EaselPaintRules.minimumLineWidth, "Arrows never vanish while staying clickable")
        var marker = item(.freehand)
        marker.brush = .highlighter
        #expect(EaselPaintRules.strokeWidth(marker) == 16 && EaselPaintRules.strokeOpacity(marker) == 0.35, "Highlighters are wide and see-through")
        #expect(EaselPaintRules.ink(marker) == (EaselPalette.stored(EaselPalette.defaultHighlight, role: .highlight), .highlight), "A default highlighter draws in the default highlight colour")
        var text = item(.text)
        text.strokeWidth = 6
        #expect(EaselPaintRules.strokeWidth(text) == 0, "Kinds without an outline ignore a stray width")
        #expect(EaselPaintRules.dashPattern(nil, width: 3).isEmpty && EaselPaintRules.dashPattern(.solid, width: 3).isEmpty, "Solid lines have no dashes")
        #expect(EaselPaintRules.dashPattern(.dashed, width: 3) == [9, 9], "Dashes scale with the line width")
        #expect(EaselPaintRules.dashPattern(.dotted, width: 4) == [0, 8], "Dots are round caps spaced by twice the width")
        #expect(EaselPaintRules.dashPattern(.dotted, width: 0.25) == [0, 2], "Hairline dots stay visible")
        #expect(EaselPaintRules.arrowHeadLength(width: 3) == 16, "Default arrows keep their 16-point head")
        #expect(EaselPaintRules.arrowHeadLength(width: 8) > EaselPaintRules.arrowHeadLength(width: 3), "Heads grow with the line")
    }

    @Test func shapesSavedBeforeStylesKeepTheirLightInkWash() {
        #expect(EaselPaintRules.fill(item(.rectangle)) == .wash(opacity: 0.09), "Shapes saved before styles keep their light ink wash")
        #expect(EaselPaintRules.fill(item(.text)) == .none && EaselPaintRules.fill(item(.arrow)) == .none
               && EaselPaintRules.fill(item(.image)) == .none, "Only shapes, stickies and sections take a fill")
        var shape = item(.circle)
        shape.fill = "#d8e9f3"
        #expect(EaselPaintRules.fill(shape) == .color(hex: "#D8E9F3", role: .fill, opacity: 1), "A chosen fill is opaque by default")
        shape.fillOpacity = 0.5
        #expect(EaselPaintRules.fill(shape) == .color(hex: "#D8E9F3", role: .fill, opacity: 0.5), "Fill opacity applies to the fill")
        shape.fillOpacity = 0
        #expect(EaselPaintRules.fill(shape) == .none, "Zero opacity means no fill")
        shape.fill = nil
        shape.fillOpacity = 0.3
        #expect(EaselPaintRules.fill(shape) == .wash(opacity: 0.3), "Opacity without a colour tints the outline colour")
        let sticky = item(.sticky)
        #expect(EaselPaintRules.fill(sticky) == .color(hex: EaselPalette.hex(EaselPalette.defaultSticky, role: .sticky) ?? "", role: .sticky, opacity: 1), "Stickies without a colour use the default sticky paper")
        var paper = item(.sticky)
        paper.fill = EaselPalette.hex(.note(.green), role: .sticky)
        if case .color(_, let role, _) = EaselPaintRules.fill(paper) { #expect(role == .sticky, "Stickies resolve their paper as sticky colours") }
        else { Issue.record("A coloured sticky has paper"); return }
    }
}
