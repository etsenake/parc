import AppKit

@main @MainActor
struct EaselShapeTextTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func alignments(_ value: NSAttributedString) -> [NSTextAlignment] {
        var result: [NSTextAlignment] = []
        value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { style, _, _ in
            result.append((style as? NSParagraphStyle)?.alignment ?? .natural)
        }
        return result
    }

    static func main() throws {
        var shape = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 200, height: 120), text: "Two\nlines")
        shape.shape = .diamond
        let stored = EaselTextAppearance.attributed(shape.text, style: shape.resolvedTextStyle, color: shape.color)
        let shown = EaselTextPresentation.displayed(stored, for: shape)
        expect(shown.string == stored.string && alignments(shown).allSatisfy { $0 == .center }, "Shape text shows centred in every paragraph")
        let saved = try EaselStyledText.capture(EaselTextPresentation.stored(shown, for: shape), style: shape.resolvedTextStyle, color: shape.color)
        expect(saved.richText == nil && saved.text == shape.text, "Centring is display-only, so plain shape text saves as plain text")

        shape.textStyle = EaselTextStyle(alignment: .right)
        expect(alignments(EaselTextPresentation.displayed(stored, for: shape)).allSatisfy { $0 == .right }, "A chosen alignment wins")

        let text = EaselItem(kind: .text, frame: shape.frame, text: "Plain")
        let plain = EaselTextAppearance.attributed(text.text, style: text.resolvedTextStyle, color: text.color)
        expect(EaselTextPresentation.displayed(plain, for: text) === plain && EaselTextPresentation.stored(plain, for: text) === plain,
               "Text objects without an alignment pass through untouched")
        expect(EaselTextPresentation.typingAttributes([.font: NSFont.systemFont(ofSize: 12)], for: text)[.paragraphStyle] == nil,
               "Text objects type without an extra paragraph style")
        let typing = EaselTextPresentation.typingAttributes([.font: NSFont.systemFont(ofSize: 12)], for: shape)
        expect((typing[.paragraphStyle] as? NSParagraphStyle)?.alignment == .right, "An empty shape types with its alignment")

        var bubble = EaselItem(kind: .rectangle, frame: shape.frame, text: "Pasted")
        bubble.shape = .speechBubble
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let pasted = NSMutableAttributedString(string: "Pasted")
        let left = NSMutableParagraphStyle(); left.alignment = .left; left.headIndent = 4
        pasted.addAttribute(.paragraphStyle, value: left, range: NSRange(location: 0, length: pasted.length))
        editor.textStorage?.setAttributedString(pasted)
        editor.typingAttributes = [.paragraphStyle: left]
        EaselTextPresentation.enforce(bubble, in: editor)
        let fixed = editor.textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString()
        let style = fixed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.alignment == .center && style?.headIndent == 4, "Pasted paragraphs centre in a shape and keep their other settings")
        expect((editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center, "Typing after a paste stays centred")
        let restored = EaselTextPresentation.stored(fixed, for: bubble)
        expect((restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent == 4
               && alignments(restored).allSatisfy { $0 == .natural }, "Saving strips only the alignment")
        print("EaselShapeTextTests passed")
    }
}
