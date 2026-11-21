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
        print("EaselInk: assertions passed")
    }
}
