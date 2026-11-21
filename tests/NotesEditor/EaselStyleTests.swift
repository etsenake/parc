import Foundation

@main
struct EaselStyleTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    struct Dice: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    static func main() {
        families()
        controls()
        colors()
        fills()
        lines()
        summaries()
        memory()
        print("EaselStyleTests passed")
    }

    static func item(_ kind: EaselItemKind) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: 0, y: 0, width: 120, height: 80))
    }

    static func families() {
        expect(EaselStyleFamily.of(item(.rectangle)) == .shapes && EaselStyleFamily.of(item(.circle)) == .shapes, "Rectangles and ellipses are shapes")
        expect(EaselStyleFamily.of(item(.arrow)) == .lines && EaselStyleFamily.of(item(.text)) == .text, "Arrows are lines and text is text")
        expect(EaselStyleFamily.of(item(.sticky)) == .stickies && EaselStyleFamily.of(item(.section)) == .sections, "Stickies and sections")
        var drawing = item(.freehand)
        expect(EaselStyleFamily.of(drawing) == .pen, "Drawings default to the pen")
        drawing.brush = .highlighter
        expect(EaselStyleFamily.of(drawing) == .highlighter, "Highlighter strokes have their own family")
        drawing.brush = .washi
        expect(EaselStyleFamily.of(drawing) == .tape && EaselStyleControls(items: [drawing])?.weights.isEmpty == true
               && EaselStyleControls(items: [drawing])?.colors.first == .automatic, "Washi tape takes ink colours only, and Default keeps its design")
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &drawing)
        expect(drawing.color == "#2C6C91", "Tape retints to a Notes colour")
        for kind in [EaselItemKind.image, .link, .webCard, .browser] {
            expect(EaselStyleFamily.of(item(kind)) == nil, "\(kind.rawValue) has no style")
        }
        expect(EaselStyleFamily.shapes.width(.none) == 0 && EaselStyleFamily.shapes.width(.medium) == 2.5, "Shape outlines keep 2.5 as medium")
        expect(EaselStyleFamily.lines.width(.medium) == 3 && EaselStyleFamily.lines.width(.none) == nil, "Lines keep 3 as medium and can't vanish")
        expect(EaselStyleFamily.highlighter.width(.thick) == 24, "Highlighters are chunky")
        expect(EaselStyleFamily.lines.weight(forWidth: 2.9) == .medium && EaselStyleFamily.shapes.weight(forWidth: 0) == EaselStrokeWeight.none,
               "Widths show the nearest weight")
    }

    static func controls() {
        let text = EaselStyleControls(items: [item(.text)])
        expect(text?.colorRole == .ink && text?.fill == false && text?.weights.isEmpty == true && text?.dash == false,
               "Text shows colour only")
        let shapes = EaselStyleControls(items: [item(.rectangle), item(.circle)])
        expect(shapes?.fill == true && shapes?.weights == [EaselStrokeWeight.none, .thin, .medium, .thick] && shapes?.dash == true
               && shapes?.lineTitle == "Outline", "Shapes show everything")
        let lines = EaselStyleControls(items: [item(.arrow)])
        expect(lines?.fill == false && lines?.weights == [.thin, .medium, .thick] && lines?.dash == true && lines?.lineTitle == "Line",
               "Lines show colour, width and style")
        expect(EaselStyleControls(items: [item(.freehand)])?.dash == false, "The pen has no dashes")
        let sticky = EaselStyleControls(items: [item(.sticky)])
        expect(sticky?.colorRole == .sticky && sticky?.colors.count == 10 && sticky?.colors.first == .neutral,
               "Stickies pick paper: white and Notes' nine")
        var marker = item(.freehand)
        marker.brush = .highlighter
        expect(EaselStyleControls(items: [marker])?.colors.count == 8, "Highlighters get eight colours")
        expect(EaselStyleControls(items: [item(.rectangle), item(.sticky)])?.lineTitle == "Outline", "Only shapes take lines here, so it says Outline")
        let mixed = EaselStyleControls(items: [item(.rectangle), item(.arrow), item(.sticky)])
        expect(mixed?.colorRole == .ink && mixed?.weights == [.thin, .medium, .thick] && mixed?.fill == true,
               "Mixed selections show what any member takes, without options some can't use")
        expect(EaselStyleControls(items: [item(.image)]) == nil, "Images have no style controls")
        expect(lines?.labelBackground == true && shapes?.labelBackground == false, "Only connectors offer a label background")
        let cells = EaselStyleControls(colorRole: .fill, colors: EaselPalette.colors(for: .fill))
        expect(cells.colors.count == 10 && !cells.fill && cells.weights.isEmpty && !cells.dash && !cells.labelBackground,
               "Hosts can ask for a colour-only picker in any role")
    }

    static func colors() {
        var text = item(.text)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: .init(font: .init(name: "Nunito", size: 15), ink: "#194B93FF")),
            .init(location: 2, length: 2, attributes: .init(font: .init(name: "Nunito", size: 15), ink: "#000000FF", semanticInk: .noteBody)),
        ])
        text.text = "Hiya"
        expect(EaselStyle.apply(.color(.palette(.note(.blue))), to: &text), "Text takes a colour")
        expect(text.color == "#2C6C91" && text.richText?.runs.allSatisfy({ $0.attributes.ink == "#2C6C91FF" && $0.attributes.semanticInk == nil }) == true,
               "Recolouring text overrides every run")
        var shape = item(.rectangle)
        EaselStyle.apply(.color(.palette(.note(.green))), to: &shape)
        expect(shape.color == "#3B7255" && shape.fill == nil, "A shape without a fill keeps its tint")
        shape.fill = "#FFFFFF"
        EaselStyle.apply(.color(.palette(.note(.green))), to: &shape)
        expect(shape.fill == "#DCEBE2", "A filled shape takes the matching pastel")
        EaselStyle.apply(.color(.palette(.automatic)), to: &shape)
        expect(shape.color == "#252525" && shape.fill == "#FFFFFF", "Default outlines a white shape")
        EaselStyle.apply(.color(.custom("#ff8800")), to: &shape)
        expect(shape.color == "#FF8800" && shape.fill == "#FF8800", "Custom colours are used as chosen")
        var sticky = item(.sticky)
        EaselStyle.apply(.color(.palette(.note(.pink))), to: &sticky)
        expect(sticky.fill == "#EDBAD5" && sticky.color == "#252525", "Stickies take paper and keep their automatic text")
        EaselStyle.apply(.color(.palette(.automatic)), to: &sticky)
        expect(sticky.fill == EaselPalette.hex(EaselPalette.defaultSticky, role: .sticky), "Default gives a sticky the default paper, not white")
        EaselStyle.apply(.color(.palette(.neutral)), to: &sticky)
        expect(sticky.fill == "#FFFFFF", "White paper is white")
        var section = item(.section)
        EaselStyle.apply(.color(.palette(.note(.purple))), to: &section)
        expect(section.fill == "#EBE2F3" && section.color == "#8154A3", "Sections take a pastel body and a matching title ink")
        EaselStyle.apply(.color(.custom("#123456")), to: &section)
        expect(section.fill == "#123456" && section.color == "#252525", "Custom sections keep the automatic title ink")
        EaselStyle.apply(.color(.palette(.automatic)), to: &section)
        expect(section.fill == nil && section.color == "#252525", "Default takes a section back to its plain look")
        var marker = item(.freehand)
        marker.brush = .highlighter
        EaselStyle.apply(.color(.palette(.note(.green))), to: &marker)
        expect(marker.color == "#4F9A6E", "Highlighters store highlight colours")
        EaselStyle.apply(.color(.palette(.automatic)), to: &marker)
        expect(marker.color == "#E8B53A", "A default highlighter is yellow")
        var picture = item(.image)
        expect(!EaselStyle.apply(.color(.palette(.note(.red))), to: &picture) && picture.color == "#252525", "Images are skipped")
    }

    static func fills() {
        var shape = item(.circle)
        shape.color = "#2C6C91"
        EaselStyle.apply(.fill(.solid), to: &shape)
        expect(shape.fill == "#D8E9F3" && shape.fillOpacity == nil, "Solid derives the pastel from the outline")
        EaselStyle.apply(.fillOpacity(0.3), to: &shape)
        expect(shape.fillOpacity == 0.3 && EaselStyle.fillMode(of: shape) == .solid, "Custom opacity keeps a solid fill's colour")
        EaselStyle.apply(.fillOpacity(4), to: &shape)
        expect(shape.fillOpacity == nil, "Full opacity is omitted from the file")
        EaselStyle.apply(.fill(.none), to: &shape)
        expect(shape.fillOpacity == 0 && shape.fill == "#D8E9F3" && EaselPaintRules.fill(shape) == .none, "No fill keeps the colour for later")
        EaselStyle.apply(.fill(.transparent), to: &shape)
        expect(shape.fill == nil && shape.fillOpacity == nil && EaselPaintRules.fill(shape) == .wash(opacity: EaselPaintRules.washOpacity),
               "Transparent is the classic tint of the outline colour")
        EaselStyle.apply(.fillOpacity(0.3), to: &shape)
        expect(shape.fill == nil && shape.fillOpacity == 0.3 && EaselStyle.fillMode(of: shape) == .transparent, "Opacity strengthens the tint")
        EaselStyle.apply(.fillOpacity(EaselPaintRules.washOpacity), to: &shape)
        expect(shape.fillOpacity == nil, "The classic tint strength is omitted from the file")
        var plain = item(.rectangle)
        expect(EaselStyle.fillMode(of: plain) == .transparent && EaselStyle.fillOpacity(of: plain) == EaselPaintRules.washOpacity,
               "Shapes saved before styles read as the classic tint at its real strength")
        EaselStyle.apply(.fill(.transparent), to: &plain)
        expect(plain.fill == nil && plain.fillOpacity == nil, "Transparent leaves a classic shape as it was")
        EaselStyle.apply(.fill(.solid), to: &plain)
        expect(plain.fill == "#FFFFFF", "Solid on a default shape fills it with white paper")
        var custom = item(.rectangle)
        custom.color = "#FF8800"
        EaselStyle.apply(.fill(.solid), to: &custom)
        expect(custom.fill == "#FF8800", "Custom outlines fill with their own colour")
        var sticky = item(.sticky)
        expect(!EaselStyle.apply(.fill(.none), to: &sticky) && sticky.fillOpacity == nil, "Stickies stay opaque")
    }

    static func lines() {
        var arrow = item(.arrow)
        EaselStyle.apply(.weight(.thick), to: &arrow)
        EaselStyle.apply(.dash(.dotted), to: &arrow)
        expect(arrow.strokeWidth == 6 && arrow.strokeDash == .dotted, "Arrows take width and dots")
        EaselStyle.apply(.weight(.medium), to: &arrow)
        EaselStyle.apply(.dash(.solid), to: &arrow)
        expect(arrow.strokeWidth == nil && arrow.strokeDash == nil, "Default width and solid lines are omitted from the file")
        expect(!EaselStyle.apply(.weight(.none), to: &arrow), "Lines can't lose their stroke")
        var shape = item(.rectangle)
        EaselStyle.apply(.weight(.none), to: &shape)
        expect(shape.strokeWidth == 0, "Shapes can drop their outline")
        var drawing = item(.freehand)
        expect(!EaselStyle.apply(.dash(.dashed), to: &drawing) && drawing.strokeDash == nil, "Drawings skip dashes")
        EaselStyle.apply(.weight(.thin), to: &drawing)
        expect(drawing.strokeWidth == 1.5, "Drawings take widths")
        var text = item(.text)
        expect(!EaselStyle.apply(.weight(.thick), to: &text), "Text skips widths")
        var labelled = item(.arrow)
        EaselStyle.apply(.labelBackground(true), to: &labelled)
        expect(labelled.labelBackground == true && EaselStyleSummary(items: [labelled]).labelBackground == true, "Connectors can show a label background")
        EaselStyle.apply(.labelBackground(false), to: &labelled)
        expect(labelled.labelBackground == nil, "No label background is omitted from the file")
        var boxed = item(.rectangle)
        expect(!EaselStyle.apply(.labelBackground(true), to: &boxed) && boxed.labelBackground == nil, "Shapes have no label background")
    }

    static func summaries() {
        var blue = item(.rectangle)
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &blue)
        var blueArrow = item(.arrow)
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &blueArrow)
        var blueSticky = item(.sticky)
        EaselStyle.apply(.color(.palette(.note(.blue))), to: &blueSticky)
        let summary = EaselStyleSummary(items: [blue, blueArrow, blueSticky, item(.image)])
        expect(summary.color == .palette(.note(.blue)), "One colour across roles reads as that colour")
        expect(summary.weight == .medium, "Default outlines and lines both read as medium")
        var thick = blueArrow
        EaselStyle.apply(.weight(.thick), to: &thick)
        expect(EaselStyleSummary(items: [blue, thick]).weight == nil, "Different line weights read as mixed")
        expect(summary.fill == .transparent && summary.dash == .solid, "Only shapes decide the fill and only shapes and lines the dash")
        var red = item(.rectangle)
        EaselStyle.apply(.color(.palette(.note(.red))), to: &red)
        expect(EaselStyleSummary(items: [blue, red]).color == nil, "Different colours read as mixed")
        var text = item(.text)
        text.text = "Hi"
        text.richText = EaselRichText(runs: [.init(location: 0, length: 2, attributes: .init(font: .init(name: "Nunito", size: 15), ink: "#194B93FF"))])
        expect(EaselStyleSummary(items: [text]).color == nil, "Text with other run colours reads as mixed")
        expect(EaselStyleSummary(items: [item(.text)]).color == .palette(.automatic), "Plain text reads as the default ink")
        var custom = item(.arrow)
        custom.color = "#ABCDEF"
        expect(EaselStyleSummary(items: [custom]).color == .custom("#ABCDEF"), "Chosen colours read as custom")
        expect(EaselStyleSummary(items: [item(.sticky)]).color == .palette(EaselPalette.defaultSticky), "Plain stickies read as the default paper")
    }

    static func memory() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        expect(start.color.flatMap(EaselColorChoice.init(storage:)).map { choice -> Bool in
            if case .palette(.note) = choice { return true }
            return false
        } == true, "Each session starts stickies on a random Notes colour")
        var memory = EaselStyleMemory(sticky: start)
        let easel = UUID(), other = UUID()
        memory.record(.color(.palette(.note(.green))), for: .stickies, document: easel)
        var sticky = item(.sticky)
        memory.stamp(&sticky, document: other)
        expect(sticky.fill == "#B5D5C2", "The last sticky colour becomes the next sticky's paper in every Easel")
        memory.record(.color(.palette(.note(.red))), for: .lines, document: easel)
        memory.record(.weight(.thick), for: .lines, document: easel)
        memory.record(.dash(.dashed), for: .lines, document: easel)
        memory.record(.labelBackground(true), for: .lines, document: easel)
        var arrow = item(.arrow)
        memory.stamp(&arrow, document: easel)
        expect(arrow.color == "#C0322D" && arrow.strokeWidth == 6 && arrow.strokeDash == .dashed && arrow.labelBackground == true,
               "Connectors remember their style in their Easel")
        var elsewhere = item(.arrow)
        memory.stamp(&elsewhere, document: other)
        expect(elsewhere.color == "#252525" && elsewhere.strokeWidth == nil, "Another Easel's connectors start fresh")
        memory.record(.color(.palette(.note(.blue))), for: .shapes, document: easel)
        memory.record(.fill(.solid), for: .shapes, document: easel)
        var shape = item(.rectangle)
        memory.stamp(&shape, document: other)
        expect(shape.color == "#2C6C91" && shape.fill == "#D8E9F3", "Shapes remember colour and fill everywhere")
        memory.record(.fillOpacity(0.25), for: .shapes, document: easel)
        expect(memory.style(for: .shapes, document: nil).fill == .solid && memory.style(for: .shapes, document: nil).fillOpacity == 0.25,
               "A custom opacity keeps the remembered fill mode")
        var faded = item(.rectangle)
        memory.stamp(&faded, document: other)
        expect(faded.fill == "#D8E9F3" && faded.fillOpacity == 0.25, "New shapes get the remembered fill at its remembered strength")
        let restored = EaselStyleMemory(families: EaselStyleMemory.persistentFamilies(from: memory.persistentData), sticky: start)
        expect(restored.style(for: .shapes, document: nil) == memory.style(for: .shapes, document: nil), "Shape styles survive a relaunch")
        expect(restored.style(for: .stickies, document: nil) == start, "Sticky colours start over each session")
        expect(restored.style(for: .lines, document: easel) == EaselStyleMemory.Style(), "Connector styles start over each session")
        expect(EaselStyleMemory.persistentFamilies(from: Data("nonsense".utf8)).isEmpty, "Damaged memory is ignored")
        var image = item(.image)
        memory.stamp(&image, document: easel)
        expect(image.color == "#252525", "Kinds without a style are left alone")
    }
}
