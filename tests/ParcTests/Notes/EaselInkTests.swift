import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct EaselInkTests {
    func hex(_ color: NSColor, in name: NSAppearance.Name) -> String {
        var result = "unresolved"
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            result = (try? EaselRichTextCodec.hex(color)) ?? "unresolved"
        }
        return result
    }

    func rgb(_ color: NSColor, in name: NSAppearance.Name) -> String { String(hex(color, in: name).prefix(7)) }

    func mix(_ base: String, _ top: String, _ amount: Double) -> String {
        let b = UInt32(base.dropFirst(), radix: 16) ?? 0, t = UInt32(top.dropFirst(), radix: 16) ?? 0
        let parts = [16, 8, 0].map { shift -> Int in
            Int((Double(b >> UInt32(shift) & 255) * (1 - amount) + Double(t >> UInt32(shift) & 255) * amount).rounded())
        }
        return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
    }

    func snapshots(of shown: NSAttributedString, and saved: NSAttributedString, in name: NSAppearance.Name) -> (EaselRichText?, EaselRichText?) {
        var snapshot: EaselRichText?
        var original: EaselRichText?
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            snapshot = try? EaselRichTextCodec.snapshot(shown)
            original = try? EaselRichTextCodec.snapshot(saved)
        }
        return (snapshot, original)
    }

    func savedDefaultAndBlue() -> NSAttributedString {
        let saved = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Old default ", style: .init(), color: "#252525"))
        saved.append(EaselTextAppearance.attributed("blue", style: .init(), color: "#194B93"))
        return saved
    }

    func savedPalette() -> NSAttributedString {
        let saved = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Blue ", style: .init(), color: "#2C6C91"))
        saved.append(EaselTextAppearance.attributed("pink ", style: .init(), color: "#AD3C78"))
        saved.append(EaselTextAppearance.attributed("chosen", style: .init(), color: "#194B93"))
        return saved
    }

    nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @Test(arguments: ["#252525", "#252525ff", "#252525FF"])
    func theStoredDefaultColourIsTheAutomaticInk(stored: String) {
        #expect(EaselInk.isAutomatic(stored))
    }

    @Test(arguments: ["#252526", "#25252580", "#194B93"])
    func chosenColoursAreNeverAutomaticInk(stored: String) {
        #expect(!EaselInk.isAutomatic(stored))
    }

    @Test func defaultColouredObjectsDrawWithTheAdaptiveInk() {
        #expect(EaselInk.isAdaptive(EaselInk.color(EaselInk.automatic, adaptive: true)))
    }

    @Test(arguments: EaselInkTests.appearances)
    func easelInkIsTheNotesInk(name: NSAppearance.Name) {
        let ink = EaselInk.color(EaselInk.automatic, adaptive: true)
        #expect(hex(ink, in: name) == hex(NoteTheme.ink, in: name))
    }

    @Test func darkEaselInkIsLightEnoughToReadOnDarkPaper() {
        #expect(hex(EaselInk.color(EaselInk.automatic, adaptive: true), in: .darkAqua) == "#EDEBFAFF")
    }

    @Test(arguments: EaselInkTests.appearances)
    func theCaptureEditorKeepsItsFixedAnnotationInk(name: NSAppearance.Name) {
        let fixed = EaselInk.color(EaselInk.automatic, adaptive: false)
        #expect(!EaselInk.isAdaptive(fixed))
        #expect(hex(fixed, in: name) == "#252525FF")
    }

    @Test(arguments: EaselInkTests.appearances)
    func explicitlyChosenColoursStayAsChosen(name: NSAppearance.Name) {
        #expect(hex(EaselInk.color("#194B93", adaptive: true), in: name) == "#194B93FF")
    }

    @Test func savedDefaultColouredTextDisplaysWithTheAdaptiveInk() {
        let shown = EaselInk.adapting(savedDefaultAndBlue())
        let first = shown.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(first.map(EaselInk.isAdaptive) == true)
    }

    @Test func savedColouredRunsKeepTheirColour() {
        let shown = EaselInk.adapting(savedDefaultAndBlue())
        let last = shown.attribute(.foregroundColor, at: shown.length - 1, effectiveRange: nil) as? NSColor
        #expect(last.map { hex($0, in: .darkAqua) } == "#194B93FF")
    }

    @Test func adaptingInkNeverChangesTheText() {
        let saved = savedDefaultAndBlue()
        #expect(EaselInk.adapting(saved).string == saved.string)
    }

    @Test(arguments: EaselInkTests.appearances)
    func editedTextStoresThePortableDefaultColour(name: NSAppearance.Name) {
        let saved = savedDefaultAndBlue()
        let (snapshot, original) = snapshots(of: EaselInk.adapting(saved), and: saved, in: name)
        #expect(snapshot != nil)
        #expect(snapshot == original)
        #expect(snapshot?.runs.first?.attributes.ink == "#252525FF")
    }

    @Test func plainDefaultTextTypedInDarkModeNeedsNoRichColourRuns() {
        let shown = EaselInk.adapting(EaselTextAppearance.attributed("Plain", style: .init(), color: EaselInk.automatic))
        var payload: EaselStyledText?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            payload = try? EaselStyledText.capture(shown, style: .init(), color: EaselInk.automatic)
        }
        #expect(payload != nil)
        #expect(payload?.richText == nil)
    }

    @Test func paletteInkAdaptsAndRemembersItsStoredColour() {
        let blue = EaselInk.color("#2C6C91", adaptive: true)
        #expect(EaselInk.isAdaptive(blue))
        #expect(EaselInk.canonicalHex(of: blue) == "#2C6C91")
    }

    @Test func blueInkLightensOnDarkPaper() {
        let blue = EaselInk.color("#2C6C91", adaptive: true)
        #expect(hex(blue, in: .aqua) == "#2C6C91FF")
        #expect(hex(blue, in: .darkAqua) == "#4CA5D8FF")
    }

    @Test func theCaptureEditorKeepsPaletteColoursFixed() {
        let fixed = EaselInk.color("#2C6C91", adaptive: false)
        #expect(!EaselInk.isAdaptive(fixed))
        #expect(hex(fixed, in: .darkAqua) == "#2C6C91FF")
    }

    @Test func blueFillTurnsDeepBlueOnDarkPaper() {
        let fill = EaselInk.color("#D8E9F3", adaptive: true, role: .fill)
        #expect(hex(fill, in: .aqua) == "#D8E9F3FF")
        #expect(hex(fill, in: .darkAqua) == "#27425AFF")
    }

    @Test func aFillColourUsedAsInkStaysFixed() {
        #expect(!EaselInk.isAdaptive(EaselInk.color("#D8E9F3", adaptive: true)))
    }

    @Test func adaptivePaletteColoursAreShared() {
        #expect(EaselInk.color("#2C6C91", adaptive: true) === EaselInk.color("#2C6C91", adaptive: true))
    }

    @Test func onlyAdaptiveEaselColoursStoreAToken() {
        #expect(EaselInk.storedInk(EaselInk.adaptive) == "#252525FF")
        #expect(EaselInk.storedInk(EaselInk.color("#2C6C91", adaptive: true)) == "#2C6C91FF")
        #expect(EaselInk.storedInk(.systemBlue) == nil)
    }

    @Test(arguments: [(0, "#4CA5D8FF"), (5, "#DC7FAFFF"), (10, "#194B93FF")] as [(Int, String)])
    func textRunsFollowDarkPaperUnlessChosen(offset: Int, expected: String) {
        let shown = EaselInk.adapting(savedPalette())
        let color = shown.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
        #expect(color.map { hex($0, in: .darkAqua) } == expected)
    }

    @Test(arguments: EaselInkTests.appearances)
    func paletteTextStoresItsLightColour(name: NSAppearance.Name) {
        let saved = savedPalette()
        let (snapshot, original) = snapshots(of: EaselInk.adapting(saved), and: saved, in: name)
        #expect(snapshot != nil)
        #expect(snapshot == original)
    }

    @Test func greenTextTypedInDarkModeNeedsNoRichColourRuns() {
        let plain = EaselInk.adapting(EaselTextAppearance.attributed("Plain", style: .init(), color: "#3B7255"))
        var payload: EaselStyledText?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            payload = try? EaselStyledText.capture(plain, style: .init(), color: "#3B7255")
        }
        #expect(payload != nil)
        #expect(payload?.richText == nil)
    }

    @Test func textCopiedToOtherAppsCarriesTheLightPaletteColour() {
        let copied = EaselStyledText(text: "Blue", style: .init(), color: "#2C6C91").attributed
        let ink = copied.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(ink.map { !EaselInk.isAdaptive($0) && hex($0, in: .darkAqua) == "#2C6C91FF" } == true)
    }

    @Test func pastedEaselTextWithAnImpossibleSizeIsRefused() {
        var huge = EaselTextStyle()
        huge.customSize = 1e300
        var unscaled = EaselTextStyle()
        unscaled.textScale = .nan
        #expect((try? EaselStyledText(text: "Big", style: huge, color: "#2C6C91").validate()) == nil)
        #expect((try? EaselStyledText(text: "Big", style: unscaled, color: "#2C6C91").validate()) == nil)
    }

    @Test func pastedEaselTextWithARealCustomSizeStillPastes() {
        var sized = EaselTextStyle()
        sized.customSize = 72
        #expect((try? EaselStyledText(text: "Big", style: sized, color: "#2C6C91").validate()) != nil)
    }

    @Test func theAutomaticInkMatchesTheNotesInk() {
        #expect(rgb(NoteTheme.ink, in: .aqua) == EaselPalette.inkLight)
        #expect(rgb(NoteTheme.ink, in: .darkAqua) == EaselPalette.inkDark)
    }

    @Test func theDarkNeutralIsTheNotesPanelColour() {
        #expect(rgb(NoteTheme.panelFill, in: .darkAqua) == EaselPalette.neutralDark)
    }

    @Test(arguments: NoteColor.allCases)
    func aNoteColourInkIsTheNotesTextColour(note: NoteColor) {
        let ink = EaselPalette.variants(EaselPalette.hex(.note(note), role: .ink) ?? "", role: .ink)
        #expect(ink?.light == rgb(NoteTheme.color(.text(note)), in: .aqua))
        #expect(ink?.dark == rgb(NoteTheme.color(.text(note)), in: .darkAqua))
    }

    @Test(arguments: NoteColor.allCases)
    func aNoteColourFillIsTheNotesBackgroundAsAnOpaquePastel(note: NoteColor) {
        let fill = EaselPalette.variants(EaselPalette.hex(.note(note), role: .fill) ?? "", role: .fill)
        #expect(fill?.light == mix("#FFFFFF", rgb(NoteTheme.swatch(note), in: .aqua), 0.2))
        #expect(fill?.dark == mix("#1D1C22", rgb(NoteTheme.swatch(note), in: .darkAqua), 0.3))
    }

    @Test(arguments: NoteColor.allCases)
    func aNoteColourStickyPaperIsAStrongerNotesBackground(note: NoteColor) {
        let sticky = EaselPalette.variants(EaselPalette.hex(.note(note), role: .sticky) ?? "", role: .sticky)
        #expect(sticky?.light == mix("#FFFFFF", rgb(NoteTheme.swatch(note), in: .aqua), 0.42))
        #expect(sticky?.dark == mix("#1D1C22", rgb(NoteTheme.swatch(note), in: .darkAqua), 0.45))
    }

    @Test func arrowsSavedBeforeStylesDrawAsBefore() {
        let arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 100, height: 20))
        let legacy = EaselPaint(arrow, adaptive: true)
        #expect(legacy.lineWidth == 3)
        #expect(legacy.dash.isEmpty)
        #expect(EaselInk.isAdaptive(legacy.inkColor))
        #expect(legacy.fillColor == nil)
    }

    @Test func styledArrowsUseTheirWidthDashesAndAdaptiveColour() {
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 100, height: 20))
        arrow.strokeWidth = 6
        arrow.strokeDash = .dashed
        arrow.color = "#C0322D"
        let styled = EaselPaint(arrow, adaptive: true)
        #expect(styled.lineWidth == 6)
        #expect(styled.dash == [18, 18])
        #expect(hex(styled.inkColor, in: .darkAqua) == "#E77F7DFF")
    }

    @Test func shapesSavedBeforeStylesKeepTheInkWash() {
        let shape = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 100, height: 80))
        let wash = EaselPaint(shape, adaptive: true)
        #expect(wash.lineWidth == 2.5)
        #expect(wash.fillColor.map { hex($0, in: .darkAqua) } == hex(NoteTheme.ink.withAlphaComponent(0.09), in: .darkAqua))
    }

    func filledShape() -> EaselItem {
        var shape = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 100, height: 80))
        shape.fill = "#D8E9F3"
        shape.fillOpacity = 0.5
        return shape
    }

    @Test func fillsResolveOnDarkPaperAndKeepTheirOpacity() {
        #expect(EaselPaint(filledShape(), adaptive: true).fillColor.map { hex($0, in: .darkAqua) } == "#27425A80")
    }

    @Test func fixedCanvasesKeepFillsAsSaved() {
        #expect(EaselPaint(filledShape(), adaptive: false).fillColor.map { hex($0, in: .darkAqua) } == "#D8E9F380")
    }
}
