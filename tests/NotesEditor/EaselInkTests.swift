import AppKit

@main @MainActor
struct EaselInkTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func hex(_ color: NSColor, in name: NSAppearance.Name) -> String {
        var result = "unresolved"
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            result = (try? EaselRichTextCodec.hex(color)) ?? "unresolved"
        }
        return result
    }

    static func main() throws {
        expect(EaselInk.isAutomatic("#252525") && EaselInk.isAutomatic("#252525ff") && EaselInk.isAutomatic("#252525FF"),
               "The stored default colour, with or without alpha, is the automatic ink")
        expect(!EaselInk.isAutomatic("#252526") && !EaselInk.isAutomatic("#25252580") && !EaselInk.isAutomatic("#194B93"),
               "Chosen colours are never treated as automatic ink")

        let ink = EaselInk.color(EaselInk.automatic, adaptive: true)
        expect(EaselInk.isAdaptive(ink), "Default-coloured Easel objects draw with the adaptive ink")
        expect(hex(ink, in: .aqua) == hex(NoteTheme.ink, in: .aqua), "Light Easel ink is the Notes ink")
        expect(hex(ink, in: .darkAqua) == hex(NoteTheme.ink, in: .darkAqua), "Dark Easel ink is the Notes ink")
        expect(hex(ink, in: .darkAqua) == "#EDEBFAFF", "Dark Easel ink is light enough to read on dark paper")

        let fixed = EaselInk.color(EaselInk.automatic, adaptive: false)
        expect(!EaselInk.isAdaptive(fixed) && hex(fixed, in: .darkAqua) == "#252525FF" && hex(fixed, in: .aqua) == "#252525FF",
               "The capture editor keeps its fixed annotation ink")
        let chosen = EaselInk.color("#194B93", adaptive: true)
        expect(hex(chosen, in: .aqua) == "#194B93FF" && hex(chosen, in: .darkAqua) == "#194B93FF",
               "Explicitly chosen colours stay as chosen in both appearances")

        let saved = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Old default ", style: .init(), color: "#252525"))
        saved.append(EaselTextAppearance.attributed("blue", style: .init(), color: "#194B93"))
        let shown = EaselInk.adapting(saved)
        let first = shown.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let last = shown.attribute(.foregroundColor, at: shown.length - 1, effectiveRange: nil) as? NSColor
        expect(first.map(EaselInk.isAdaptive) == true, "Saved default-coloured text displays with the adaptive ink")
        expect(last.map { hex($0, in: .darkAqua) } == "#194B93FF", "Saved coloured runs keep their colour")
        expect(shown.string == saved.string, "Adapting ink never changes the text")

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var snapshot: EaselRichText?
            var original: EaselRichText?
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                snapshot = try? EaselRichTextCodec.snapshot(shown)
                original = try? EaselRichTextCodec.snapshot(saved)
            }
            expect(snapshot != nil && snapshot == original,
                   "Edited text stores the portable default colour in \(name.rawValue), so saved Easels stay unchanged")
            expect(snapshot?.runs.first?.attributes.ink == "#252525FF", "Adaptive ink is saved as the default colour token")
        }

        let plainShown = EaselInk.adapting(EaselTextAppearance.attributed("Plain", style: .init(), color: EaselInk.automatic))
        var payload: EaselStyledText?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            payload = try? EaselStyledText.capture(plainShown, style: .init(), color: EaselInk.automatic)
        }
        expect(payload != nil && payload?.richText == nil, "Plain default text typed in dark mode needs no rich colour runs")
        palette()
        notesColours()
        paint()
        print("EaselInk: assertions passed")
    }

    static func palette() {
        let blue = EaselInk.color("#2C6C91", adaptive: true)
        expect(EaselInk.isAdaptive(blue) && EaselInk.canonicalHex(of: blue) == "#2C6C91", "Palette ink adapts and remembers its stored colour")
        expect(hex(blue, in: .aqua) == "#2C6C91FF" && hex(blue, in: .darkAqua) == "#4CA5D8FF", "Blue ink lightens on dark paper")
        let fixed = EaselInk.color("#2C6C91", adaptive: false)
        expect(!EaselInk.isAdaptive(fixed) && hex(fixed, in: .darkAqua) == "#2C6C91FF", "The capture editor keeps palette colours fixed")
        let fill = EaselInk.color("#D8E9F3", adaptive: true, role: .fill)
        expect(hex(fill, in: .aqua) == "#D8E9F3FF" && hex(fill, in: .darkAqua) == "#27425AFF", "Blue fill turns deep blue on dark paper")
        expect(!EaselInk.isAdaptive(EaselInk.color("#D8E9F3", adaptive: true)), "A fill colour used as ink stays fixed")
        expect(EaselInk.color("#2C6C91", adaptive: true) === blue, "Adaptive palette colours are shared")
        expect(EaselInk.storedInk(EaselInk.adaptive) == "#252525FF" && EaselInk.storedInk(blue) == "#2C6C91FF"
               && EaselInk.storedInk(.systemBlue) == nil, "Only adaptive Easel colours store a token")

        let saved = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Blue ", style: .init(), color: "#2C6C91"))
        saved.append(EaselTextAppearance.attributed("pink ", style: .init(), color: "#AD3C78"))
        saved.append(EaselTextAppearance.attributed("chosen", style: .init(), color: "#194B93"))
        let shown = EaselInk.adapting(saved)
        func run(_ at: Int) -> NSColor? { shown.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor }
        expect(run(0).map { hex($0, in: .darkAqua) } == "#4CA5D8FF" && run(5).map { hex($0, in: .darkAqua) } == "#DC7FAFFF",
               "Palette text runs follow dark paper")
        expect(run(10).map { hex($0, in: .darkAqua) } == "#194B93FF", "Chosen text runs keep their colour")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var snapshot: EaselRichText?
            var original: EaselRichText?
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                snapshot = try? EaselRichTextCodec.snapshot(shown)
                original = try? EaselRichTextCodec.snapshot(saved)
            }
            expect(snapshot != nil && snapshot == original, "Palette text stores its light colour in \(name.rawValue)")
        }
        let plain = EaselInk.adapting(EaselTextAppearance.attributed("Plain", style: .init(), color: "#3B7255"))
        var payload: EaselStyledText?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            payload = try? EaselStyledText.capture(plain, style: .init(), color: "#3B7255")
        }
        expect(payload != nil && payload?.richText == nil, "Green text typed in dark mode needs no rich colour runs")
        let copied = EaselStyledText(text: "Blue", style: .init(), color: "#2C6C91").attributed
        let copiedInk = copied.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        expect(copiedInk.map { !EaselInk.isAdaptive($0) && hex($0, in: .darkAqua) == "#2C6C91FF" } == true,
               "Text copied to other apps carries the light palette colour")
    }

    static func notesColours() {
        func rgb(_ color: NSColor, in name: NSAppearance.Name) -> String { String(hex(color, in: name).prefix(7)) }
        func mix(_ base: String, _ top: String, _ amount: Double) -> String {
            let b = UInt32(base.dropFirst(), radix: 16) ?? 0, t = UInt32(top.dropFirst(), radix: 16) ?? 0
            let parts = [16, 8, 0].map { shift -> Int in
                Int((Double(b >> UInt32(shift) & 255) * (1 - amount) + Double(t >> UInt32(shift) & 255) * amount).rounded())
            }
            return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
        }
        expect(rgb(NoteTheme.ink, in: .aqua) == EaselPalette.inkLight && rgb(NoteTheme.ink, in: .darkAqua) == EaselPalette.inkDark,
               "The automatic ink matches the Notes ink")
        expect(rgb(NoteTheme.panelFill, in: .darkAqua) == EaselPalette.neutralDark, "The dark neutral is the Notes panel colour")
        for note in NoteColor.allCases {
            let ink = EaselPalette.variants(EaselPalette.hex(.note(note), role: .ink) ?? "", role: .ink)
            expect(ink?.light == rgb(NoteTheme.color(.text(note)), in: .aqua) && ink?.dark == rgb(NoteTheme.color(.text(note)), in: .darkAqua),
                   "\(note.rawValue) ink is the Notes \(note.rawValue) text colour")
            let swatchLight = rgb(NoteTheme.swatch(note), in: .aqua), swatchDark = rgb(NoteTheme.swatch(note), in: .darkAqua)
            let fill = EaselPalette.variants(EaselPalette.hex(.note(note), role: .fill) ?? "", role: .fill)
            expect(fill?.light == mix("#FFFFFF", swatchLight, 0.2) && fill?.dark == mix("#1D1C22", swatchDark, 0.3),
                   "\(note.rawValue) fill is the Notes \(note.rawValue) background as an opaque pastel")
            let sticky = EaselPalette.variants(EaselPalette.hex(.note(note), role: .sticky) ?? "", role: .sticky)
            expect(sticky?.light == mix("#FFFFFF", swatchLight, 0.42) && sticky?.dark == mix("#1D1C22", swatchDark, 0.45),
                   "\(note.rawValue) sticky paper is a stronger Notes \(note.rawValue) background")
        }
    }

    static func paint() {
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 100, height: 20))
        let legacy = EaselPaint(arrow, adaptive: true)
        expect(legacy.lineWidth == 3 && legacy.dash.isEmpty && EaselInk.isAdaptive(legacy.inkColor) && legacy.fillColor == nil,
               "Arrows saved before styles draw as before")
        arrow.strokeWidth = 6; arrow.strokeDash = .dashed; arrow.color = "#C0322D"
        let styled = EaselPaint(arrow, adaptive: true)
        expect(styled.lineWidth == 6 && styled.dash == [18, 18] && hex(styled.inkColor, in: .darkAqua) == "#E77F7DFF",
               "Styled arrows use their width, dashes and adaptive colour")
        var shape = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 100, height: 80))
        let wash = EaselPaint(shape, adaptive: true)
        expect(wash.lineWidth == 2.5 && wash.fillColor.map { hex($0, in: .darkAqua) } == hex(NoteTheme.ink.withAlphaComponent(0.09), in: .darkAqua),
               "Shapes saved before styles keep the ink wash")
        shape.fill = "#D8E9F3"; shape.fillOpacity = 0.5
        let filled = EaselPaint(shape, adaptive: true)
        expect(filled.fillColor.map { hex($0, in: .darkAqua) } == "#27425A80", "Fills resolve on dark paper and keep their opacity")
        expect(EaselPaint(shape, adaptive: false).fillColor.map { hex($0, in: .darkAqua) } == "#D8E9F380", "Fixed canvases keep fills as saved")
    }
}
