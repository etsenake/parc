import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselShapeTextTests {
    func alignments(_ value: NSAttributedString) -> [NSTextAlignment] {
        var result: [NSTextAlignment] = []
        value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { style, _, _ in
            result.append((style as? NSParagraphStyle)?.alignment ?? .natural)
        }
        return result
    }

    func diamond() -> EaselItem {
        var shape = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 200, height: 120), text: "Two\nlines")
        shape.shape = .diamond
        return shape
    }

    func stored(_ item: EaselItem) -> NSAttributedString {
        EaselTextAppearance.attributed(item.text, style: item.resolvedTextStyle, color: item.color)
    }

    @Test func shapeTextShowsCentredInEveryParagraph() {
        let shape = diamond()
        let shown = EaselTextPresentation.displayed(stored(shape), for: shape)
        #expect(shown.string == stored(shape).string)
        #expect(alignments(shown).allSatisfy { $0 == .center })
    }

    @Test func plainShapeTextSavesAsPlainText() throws {
        let shape = diamond()
        let shown = EaselTextPresentation.displayed(stored(shape), for: shape)
        let saved = try EaselStyledText.capture(EaselTextPresentation.stored(shown, for: shape), style: shape.resolvedTextStyle, color: shape.color)
        #expect(saved.richText == nil)
        #expect(saved.text == shape.text)
    }

    @Test func aChosenAlignmentWins() {
        var shape = diamond()
        shape.textStyle = EaselTextStyle(alignment: .right)
        #expect(alignments(EaselTextPresentation.displayed(stored(shape), for: shape)).allSatisfy { $0 == .right })
    }

    @Test func textObjectsWithoutAnAlignmentPassThroughUntouched() {
        let text = EaselItem(kind: .text, frame: diamond().frame, text: "Plain")
        let plain = stored(text)
        #expect(EaselTextPresentation.displayed(plain, for: text) === plain)
        #expect(EaselTextPresentation.stored(plain, for: text) === plain)
    }

    @Test func textObjectsTypeWithoutAnExtraParagraphStyle() {
        let text = EaselItem(kind: .text, frame: diamond().frame, text: "Plain")
        #expect(EaselTextPresentation.typingAttributes([.font: NSFont.systemFont(ofSize: 12)], for: text)[.paragraphStyle] == nil)
    }

    @Test func anEmptyShapeTypesWithItsAlignment() {
        var shape = diamond()
        shape.textStyle = EaselTextStyle(alignment: .right)
        let typing = EaselTextPresentation.typingAttributes([.font: NSFont.systemFont(ofSize: 12)], for: shape)
        #expect((typing[.paragraphStyle] as? NSParagraphStyle)?.alignment == .right)
    }

    @MainActor struct Pasted {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let bubble: EaselItem

        init(frame: EaselRect) {
            var item = EaselItem(kind: .rectangle, frame: frame, text: "Pasted")
            item.shape = .speechBubble
            bubble = item
            let pasted = NSMutableAttributedString(string: "Pasted")
            let left = NSMutableParagraphStyle()
            left.alignment = .left
            left.headIndent = 4
            pasted.addAttribute(.paragraphStyle, value: left, range: NSRange(location: 0, length: pasted.length))
            editor.textStorage?.setAttributedString(pasted)
            editor.typingAttributes = [.paragraphStyle: left]
            EaselTextPresentation.enforce(bubble, in: editor)
        }

        var fixed: NSAttributedString { editor.textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString() }
    }

    @Test func pastedParagraphsCentreInAShapeAndKeepTheirOtherSettings() {
        let style = Pasted(frame: diamond().frame).fixed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .center)
        #expect(style?.headIndent == 4)
    }

    @Test func typingAfterAPasteStaysCentred() {
        let pasted = Pasted(frame: diamond().frame)
        #expect((pasted.editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center)
    }

    @Test func savingStripsOnlyTheAlignment() {
        let pasted = Pasted(frame: diamond().frame)
        let restored = EaselTextPresentation.stored(pasted.fixed, for: pasted.bubble)
        #expect((restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent == 4)
        #expect(alignments(restored).allSatisfy { $0 == .natural })
    }
}
