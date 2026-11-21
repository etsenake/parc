import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct EaselStickyTextTests {
    func sizes(_ value: NSAttributedString) -> [CGFloat] {
        var result: [CGFloat] = []
        value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { font, _, _ in
            result.append((font as? NSFont)?.pointSize ?? 0)
        }
        return result
    }

    func sticky(scale: Double?, text: String = "") -> EaselItem {
        var item = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 1)
        item.text = text
        if let scale {
            item.textStyle = EaselBoardObjects.scaledStyle(nil, scale: scale)
            item.frame.width *= scale
            item.frame.height *= scale
        }
        return item
    }

    nonisolated static let scales: [Double] = [1, 2, 3]
    nonisolated static let refitScales: [Double] = [1, 2, 3, 1.37]

    @Test func unscaledTextKeepsTodaysInsetAndPadding() {
        let plain = EaselTextLayout.Layout(NSAttributedString(string: "Hi"), width: 100)
        #expect(plain.inset == NSSize(width: 5, height: 4))
        #expect(plain.container.lineFragmentPadding == 5)
    }

    @Test(arguments: EaselStickyTextTests.scales)
    func aStickysTextMarginGrowsWithIt(scale: Double) {
        let item = sticky(scale: scale == 1 ? nil : scale, text: "Margins")
        let layout = EaselStickyText.layout(EaselStickyText.presented(item, adaptive: false), for: item,
                                            width: EaselBoardObjects.stickyTextBox(item).width)
        let side = EaselBoardObjects.stickyInset(item) + Double(layout.inset.width + layout.container.lineFragmentPadding)
        let top = EaselBoardObjects.stickyInset(item) + Double(layout.inset.height)
        #expect(abs(side - 28 * scale) < 0.001)
        #expect(abs(top - 22 * scale) < 0.001)
    }

    @Test(arguments: EaselStickyTextTests.scales)
    func theEditorUsesTheSameInsetsAsTheDrawnText(scale: Double) {
        let item = sticky(scale: scale == 1 ? nil : scale, text: "Margins")
        let layout = EaselStickyText.layout(EaselStickyText.presented(item, adaptive: false), for: item,
                                            width: EaselBoardObjects.stickyTextBox(item).width)
        let editor = EaselStyledTextView(frame: .zero)
        EaselStickyText.applyInsets(item, to: editor)
        #expect(editor.textContainerInset == layout.inset)
        #expect(editor.textContainer?.lineFragmentPadding == layout.container.lineFragmentPadding)
    }

    func editedHeight(_ item: EaselItem) throws -> Double {
        let box = EaselBoardObjects.stickyTextBox(item)
        let editor = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: box.width, height: box.height))
        editor.textContainer?.widthTracksTextView = true
        EaselStickyText.applyInsets(item, to: editor)
        editor.textStorage?.setAttributedString(EaselStickyText.presented(item, adaptive: false))
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        manager.ensureLayout(for: container)
        return Double(ceil(max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)) + editor.textContainerInset.height * 2)
    }

    static let growingWords = String(repeating: "Big stickies keep roomy margins as they grow. ", count: 12)

    @Test(arguments: EaselStickyTextTests.refitScales)
    func aStickyMeasuresTheHeightItsEditorShows(scale: Double) throws {
        let item = sticky(scale: scale == 1 ? nil : scale, text: Self.growingWords)
        #expect(abs(try editedHeight(item) - EaselStickyText.height(item)) < 0.001)
    }

    @Test(arguments: EaselStickyTextTests.refitScales)
    func aStickyRefitsToTheHeightItsEditorShows(scale: Double) throws {
        let item = sticky(scale: scale == 1 ? nil : scale, text: Self.growingWords)
        let edited = try editedHeight(item)
        #expect(EaselTextPlacement.fittedFrameHeight(item, textHeight: EaselStickyText.height(item))
                == EaselBoardObjects.stickyHeight(item, textHeight: edited))
    }

    @Test func theEditorSitsInTheStickysPaddedTextBox() {
        let square = sticky(scale: nil)
        #expect(EaselTextPlacement.box(for: square) == EaselBoardObjects.stickyTextBox(square))
        #expect(EaselTextPlacement.canvasBox(for: square) == EaselBoardObjects.stickyTextBox(square))
    }

    @Test func aScaledStickyEditsInsideItsScaledPadding() {
        let big = sticky(scale: 2)
        #expect(EaselTextPlacement.box(for: big) == EaselBoardObjects.stickyTextBox(big))
    }

    @Test func stickiesTypeFromTheTopGrowInsteadOfClippingAndStayWhenEmptied() {
        let square = sticky(scale: nil)
        #expect(!EaselTextPlacement.centresVertically(square))
        #expect(!EaselTextPlacement.clipsOverflow(square))
        #expect(!EaselTextPlacement.retiresWhenEmpty(square))
    }

    @Test func anEmptyStickyIsNeverRemovedWhenEditingEnds() {
        #expect(EaselTextEditing.isEmpty(sticky(scale: nil)) == false)
    }

    @Test func anEmptyStickyKeepsItsSquareHeight() {
        #expect(EaselTextPlacement.fittedFrameHeight(sticky(scale: nil), textHeight: 0) == 220)
    }

    @Test func longTextGrowsTheStickyByItsPadding() {
        #expect(EaselTextPlacement.fittedFrameHeight(sticky(scale: nil), textHeight: 300) == 336)
    }

    @Test func deletingTextShrinksTheStickyBackToItsSquare() {
        var tall = sticky(scale: nil)
        tall.frame.height = 600
        #expect(EaselTextPlacement.fittedFrameHeight(tall, textHeight: 40) == 220)
    }

    @Test func aScaledStickyNeverShrinksBelowItsScaledSquare() {
        #expect(EaselTextPlacement.fittedFrameHeight(sticky(scale: 2), textHeight: 100) == 440)
    }

    @Test func lotsOfWordsMeasureTallerThanTheSquareAndRefitThroughTheSharedHeightRule() {
        let words = sticky(scale: nil, text: String(repeating: "Sticky notes grow as you type. ", count: 30))
        let measured = EaselStickyText.height(words)
        #expect(measured > 220)
        #expect(EaselTextPlacement.fittedFrameHeight(words, textHeight: measured) == EaselBoardObjects.stickyHeight(words, textHeight: measured))
    }

    @Test func doublingAStickysScaleDoublesALinesHeight() {
        let pad = 2 * Double(EaselTextLayout.inset.height)
        let line = EaselStickyText.height(sticky(scale: nil, text: "One line")) - pad
        let ratio = (EaselStickyText.height(sticky(scale: 2, text: "One line")) - 2 * pad) / line
        #expect(line > 0)
        #expect(abs(ratio - 2) < 0.15)
    }

    @Test func anEmptyStickyMeasuresNoText() {
        #expect(EaselStickyText.height(sticky(scale: nil)) == 0)
    }

    @Test func aScaledStickyShowsItsTextAtTwiceTheSize() {
        let item = sticky(scale: 2, text: "Plan the trip")
        let base = EaselTextAppearance.font(item.resolvedTextStyle).pointSize
        let shown = EaselStickyText.presented(item, adaptive: false)
        #expect(shown.string == item.text)
        #expect(sizes(shown).allSatisfy { abs($0 - base * 2) < 0.01 })
    }

    @Test func scaledTextSavesBackAsPlainUnscaledText() throws {
        let item = sticky(scale: 2, text: "Plan the trip")
        let shown = EaselStickyText.presented(item, adaptive: false)
        let saved = try EaselStyledText.capture(EaselStickyText.stored(shown, for: item), style: item.resolvedTextStyle, color: item.color)
        #expect(saved.text == item.text)
        #expect(saved.richText == nil)
    }

    @Test func anOddScaleRoundsBackToTheStoredSizeWithoutLeavingRichText() throws {
        let odd = sticky(scale: 1.37, text: "Odd scale")
        let back = try EaselStyledText.capture(EaselStickyText.stored(EaselStickyText.presented(odd, adaptive: false), for: odd),
                                               style: odd.resolvedTextStyle, color: odd.color)
        #expect(back.richText == nil)
    }

    func centredSticky() -> EaselItem {
        var aligned = sticky(scale: 2, text: "Plan the trip")
        aligned.textStyle?.alignment = .center
        return aligned
    }

    @Test func aStickysAlignmentShowsInItsText() {
        let centred = EaselStickyText.presented(centredSticky(), adaptive: false)
        #expect((centred.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .center)
    }

    @Test func alignmentIsDisplayOnlySoItDoesNotTurnPlainStickyTextRich() throws {
        let aligned = centredSticky()
        let centred = EaselStickyText.presented(aligned, adaptive: false)
        let flat = try EaselStyledText.capture(EaselStickyText.stored(centred, for: aligned), style: aligned.resolvedTextStyle, color: aligned.color)
        #expect(flat.richText == nil)
    }

    @Test func anEmptyScaledStickyTypesAtItsScaledSize() {
        let item = sticky(scale: 2)
        let attributes = EaselStickyText.typingAttributes(item, color: .black)
        let base = EaselTextAppearance.font(item.resolvedTextStyle).pointSize
        #expect(abs(((attributes[.font] as? NSFont)?.pointSize ?? 0) - base * 2) < 0.01)
    }

    @Test func anUnscaledStickyTypesAtTheRegularSize() {
        let item = sticky(scale: nil)
        let plain = EaselStickyText.typingAttributes(item, color: .black)
        #expect(abs(((plain[.font] as? NSFont)?.pointSize ?? 0) - EaselTextAppearance.font(item.resolvedTextStyle).pointSize) < 0.01)
    }

    @Test func scalingNoAttributesLeavesNone() {
        #expect(EaselStickyText.scaledAttributes([:], by: 2).isEmpty)
    }

    func scaledEditor() -> (EaselStyledTextView, EaselItem) {
        let item = sticky(scale: 2, text: "Big")
        let editor = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        editor.textStorage?.setAttributedString(EaselStickyText.presented(item, adaptive: false))
        editor.fontScale = 2
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        return (editor, item)
    }

    @Test func theSizeReadoutShowsTheStickysOwnSizeNotTheScaledOne() {
        let (editor, item) = scaledEditor()
        let base = Double(EaselTextAppearance.font(item.resolvedTextStyle).pointSize)
        #expect(abs((EaselTextStyleState.points(of: [item.resolvedTextStyle], editor: editor) ?? 0) - base) < 0.01)
    }

    @Test func aScaledStickysTextStillMatchesItsSizeStep() {
        let (editor, item) = scaledEditor()
        #expect(EaselTextStyleState.selectedStyles(in: editor).first??.size == item.resolvedTextStyle.size)
    }

    @Test func makingTextLargerWhileTypingInAScaledStickyKeepsItScaled() {
        let (editor, _) = scaledEditor()
        editor.changeStyle { $0.size = .h2 }
        let large = Double(EaselTextAppearance.font(EaselTextStyle(size: .h2)).pointSize)
        let after = sizes(editor.attributedString())
        #expect(!after.isEmpty)
        #expect(after.allSatisfy { abs(Double($0) - large * 2) < 0.01 })
    }
}
