import AppKit

@main @MainActor
struct EaselStickyTextTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func sizes(_ value: NSAttributedString) -> [CGFloat] {
        var result: [CGFloat] = []
        value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { font, _, _ in
            result.append((font as? NSFont)?.pointSize ?? 0)
        }
        return result
    }

    static func sticky(scale: Double?, text: String = "") -> EaselItem {
        var item = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 1)
        item.text = text
        if let scale { item.textStyle = EaselBoardObjects.scaledStyle(nil, scale: scale) }
        if let scale { item.frame.width *= scale; item.frame.height *= scale }
        return item
    }

    static func main() throws {
        placement()
        fitting()
        try roundTrip()
        typing()
        editorScale()
    }

    static func placement() {
        let square = sticky(scale: nil)
        expect(EaselTextPlacement.box(for: square) == EaselBoardObjects.stickyTextBox(square)
               && EaselTextPlacement.canvasBox(for: square) == EaselBoardObjects.stickyTextBox(square),
               "The editor sits in the sticky's padded text box")
        let big = sticky(scale: 2)
        expect(EaselTextPlacement.box(for: big) == EaselBoardObjects.stickyTextBox(big), "A scaled sticky edits inside its scaled padding")
        expect(!EaselTextPlacement.centresVertically(square) && !EaselTextPlacement.clipsOverflow(square)
               && !EaselTextPlacement.retiresWhenEmpty(square), "Stickies type from the top, grow instead of clipping and stay when emptied")
        expect(EaselTextEditing.isEmpty(square) == false, "An empty sticky is never removed when editing ends")
    }

    static func fitting() {
        let square = sticky(scale: nil)
        expect(EaselTextPlacement.fittedFrameHeight(square, textHeight: 0) == 220, "An empty sticky keeps its square height")
        expect(EaselTextPlacement.fittedFrameHeight(square, textHeight: 300) == 336, "Long text grows the sticky by its padding")
        var tall = square
        tall.frame.height = 600
        expect(EaselTextPlacement.fittedFrameHeight(tall, textHeight: 40) == 220, "Deleting text shrinks the sticky back to its square")
        let big = sticky(scale: 2)
        expect(EaselTextPlacement.fittedFrameHeight(big, textHeight: 100) == 440, "A scaled sticky never shrinks below its scaled square")
        let words = sticky(scale: nil, text: String(repeating: "Sticky notes grow as you type. ", count: 30))
        let measured = EaselStickyText.height(words)
        expect(measured > 220 && EaselTextPlacement.fittedFrameHeight(words, textHeight: measured) == EaselBoardObjects.stickyHeight(words, textHeight: measured),
               "Lots of words measure taller than the square and refit through the shared height rule")
        let pad = 2 * Double(EaselTextLayout.inset.height)
        let line = EaselStickyText.height(sticky(scale: nil, text: "One line")) - pad
        let ratio = (EaselStickyText.height(sticky(scale: 2, text: "One line")) - pad) / line
        expect(line > 0 && abs(ratio - 2) < 0.15, "Doubling a sticky's scale doubles a line's height, got \(ratio)")
        expect(EaselStickyText.height(square) == 0, "An empty sticky measures no text")
    }

    static func roundTrip() throws {
        let item = sticky(scale: 2, text: "Plan the trip")
        let base = EaselTextAppearance.font(item.resolvedTextStyle).pointSize
        let shown = EaselStickyText.presented(item, adaptive: false)
        expect(shown.string == item.text && sizes(shown).allSatisfy { abs($0 - base * 2) < 0.01 }, "A scaled sticky shows its text at twice the size")
        let saved = try EaselStyledText.capture(EaselStickyText.stored(shown, for: item), style: item.resolvedTextStyle, color: item.color)
        expect(saved.text == item.text && saved.richText == nil, "Scaled text saves back as plain unscaled text")
        let odd = sticky(scale: 1.37, text: "Odd scale")
        let back = try EaselStyledText.capture(EaselStickyText.stored(EaselStickyText.presented(odd, adaptive: false), for: odd),
                                               style: odd.resolvedTextStyle, color: odd.color)
        expect(back.richText == nil, "An odd scale rounds back to the stored size without leaving rich text behind")
        var aligned = item
        aligned.textStyle?.alignment = .center
        let centred = EaselStickyText.presented(aligned, adaptive: false)
        let paragraph = centred.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        expect(paragraph?.alignment == .center, "A sticky's alignment shows in its text")
        let flat = try EaselStyledText.capture(EaselStickyText.stored(centred, for: aligned), style: aligned.resolvedTextStyle, color: aligned.color)
        expect(flat.richText == nil, "Alignment is display-only, so it doesn't turn plain sticky text rich")
    }

    static func typing() {
        let item = sticky(scale: 2)
        let attributes = EaselStickyText.typingAttributes(item, color: .black)
        let base = EaselTextAppearance.font(item.resolvedTextStyle).pointSize
        expect(abs(((attributes[.font] as? NSFont)?.pointSize ?? 0) - base * 2) < 0.01, "An empty scaled sticky types at its scaled size")
        let plain = EaselStickyText.typingAttributes(sticky(scale: nil), color: .black)
        expect(abs(((plain[.font] as? NSFont)?.pointSize ?? 0) - base) < 0.01, "An unscaled sticky types at the regular size")
        expect(EaselStickyText.scaledAttributes([:], by: 2).isEmpty, "Scaling no attributes leaves none")
    }

    static func editorScale() {
        let item = sticky(scale: 2, text: "Big")
        let editor = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        editor.textStorage?.setAttributedString(EaselStickyText.presented(item, adaptive: false))
        editor.fontScale = 2
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        let base = Double(EaselTextAppearance.font(item.resolvedTextStyle).pointSize)
        let points = EaselTextStyleState.points(of: [item.resolvedTextStyle], editor: editor) ?? 0
        expect(abs(points - base) < 0.01, "The size readout shows the sticky's own size, not its scaled one")
        expect(EaselTextStyleState.selectedStyles(in: editor).first??.size == item.resolvedTextStyle.size,
               "A scaled sticky's text still matches its size step")
        editor.changeStyle { $0.size = .h2 }
        let large = Double(EaselTextAppearance.font(EaselTextStyle(size: .h2)).pointSize)
        let after = sizes(editor.attributedString())
        expect(!after.isEmpty && after.allSatisfy { abs(Double($0) - large * 2) < 0.01 },
               "Making text larger while typing in a scaled sticky keeps it scaled")
    }
}
