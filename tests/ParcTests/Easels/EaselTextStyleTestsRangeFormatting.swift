import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselTextStyleTestsRangeFormatting {
    @MainActor @Test
    func versionTwoClipboardDataStillLoads() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let payload = EaselStyledText(version: 2, text: "Prior", style: .init(), color: "#252525")
        board.setData(try JSONEncoder().encode(payload), forType: EaselStyledText.previousPasteboardType)
        #expect(try EaselStyledText.read(from: board)?.text == payload.text)
    }

    @MainActor @Test
    func oldHistoryCleanupCannotEraseANewerEdit() throws {
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true
        view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        var cleanup: (() -> Void)?
        view.scheduleHistoryCleanup = { cleanup = $0 }
        view.localUndo.beginUndoGrouping(); view.resetEditingHistory(); view.localUndo.endUndoGrouping()
        let beforeNewEdit = view.string
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping(); view.insertText("Retained", replacementRange: view.selectedRange()); view.localUndo.endUndoGrouping()
        let run = try #require(cleanup)
        run()
        #expect(view.localUndo.canUndo, "Deferred rollback cleanup cannot erase a later native edit")
        view.undo(nil); #expect(view.string == beforeNewEdit, "Later edit still has its own original undo after stale cleanup retires")
        view.retire()
    }

    @MainActor @Test
    func underlineAppliesOnlyToTheSelectedRange() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.underline); view.localUndo.endUndoGrouping()
        #expect(view.hasEmphasis(.underline), "Selection receives real underline attributes")
        #expect(view.attributedString().attribute(.underlineStyle, at: 4, effectiveRange: nil) == nil, "Formatting does not leak into other ranges")
    }

    @MainActor @Test
    func undoAndRedoRestoreNativeUnderline() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.underline); view.localUndo.endUndoGrouping()
        view.undo(nil)
        #expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == EaselRichTextCodec.snapshot(original), "Native local undo restores range attributes")
        view.redo(nil)
        #expect(view.hasEmphasis(.underline), "Native local redo restores range attributes")
    }

    @MainActor @Test
    func copyingASelectionRebasesItsRanges() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.underline); view.localUndo.endUndoGrouping()
        let selected = try view.selectedPayload()!
        #expect(selected.text == "One" && selected.richText?.runs.first?.location == 0, "Selected copy rebases ranges to its substring")
    }

    @MainActor @Test
    func richPasteRestoresUnderlinedTextAtTheCaret() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.underline); view.localUndo.endUndoGrouping()
        let selected = try view.selectedPayload()!
        try selected.write(to: board)
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board), "Native rich paste succeeds"); view.localUndo.endUndoGrouping()
        #expect(view.string == original.string + "One", "Native rich paste inserts at the original caret")
        #expect((view.attributedString().attribute(.underlineStyle, at: view.attributedString().length - 1, effectiveRange: nil) as? NSNumber)?.intValue == 1, "Pasted selection retains attributes")
    }

    @MainActor @Test
    func aDamagedRichPastePreservesTheEditor() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        let before = view.attributedString()
        board.clearContents(); board.setData(Data("bad".utf8), forType: EaselStyledText.pasteboardType)
        #expect(!view.pasteContent(from: board) && view.attributedString().isEqual(to: before), "Rejected paste preserves existing editor content")
    }

    @MainActor @Test
    func caretFormattingChangesOnlyFutureTyping() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        let before = view.attributedString()
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.toggle(.italic)
        #expect((view.typingAttributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true, "Collapsed formatting changes future typing attributes")
        #expect(view.attributedString().isEqual(to: before), "Collapsed formatting leaves existing content untouched")
    }

    @MainActor @Test
    func unicodeRichRangesRoundTripThroughTheClipboard() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        let emoji = NSMutableAttributedString(attributedString: original)
        emoji.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: (original.string as NSString).range(of: "👩🏽‍💻"))
        let payload = try EaselStyledText.capture(emoji, style: .init(), color: "#252525")
        try payload.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == payload, "Unicode-rich selected ranges round trip in private carrier")
    }

    @MainActor @Test
    func changingTheSizePreservesBoldAndItalic() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.textStorage!.setAttributedString(original); view.localUndo.removeAllActions()
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.localUndo.beginUndoGrouping(); view.toggle(.bold); view.toggle(.italic); view.localUndo.endUndoGrouping()
        let emphasized = try EaselRichTextCodec.snapshot(view.attributedString())
        view.localUndo.beginUndoGrouping(); view.changeStyle { $0.size = .h1 }; view.localUndo.endUndoGrouping()
        #expect(view.hasEmphasis(.bold) && view.hasEmphasis(.italic), "Bold and italic survive palette size change")
        #expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 44, "Palette change really applies the new font size")
        let palette = EaselTextAppearance.paletteStyle(view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as! NSFont)
        #expect(palette == EaselTextStyle(family: .clean, size: .h1), "Palette recognizes emphasized range without losing its actual size")
        view.undo(nil)
        #expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == emphasized, "Undo restores emphasized range before palette change")
    }

    @MainActor @Test
    func resolvingAPaletteFontPreservesBothEmphasisTraits() throws {
        let old = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: [.boldFontMask, .italicFontMask])
        let result = try EaselTextAppearance.font(.init(family: .clean, size: .h2), preservingEmphasisFrom: old)
        #expect(result.fontDescriptor.symbolicTraits.contains([.bold, .italic]), "Shared object/range palette helper preserves both traits")
    }

    @MainActor @Test
    func nativeCompositionRefusesRangeFormatting() throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping()
        view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText(), "Native input method owns marked text")
        let composition = view.attributedString()
        view.toggle(.underline)
        #expect(view.attributedString().isEqual(to: composition), "Formatting does not mutate an active composition")
        view.finishComposition(); view.localUndo.endUndoGrouping()
        view.retire()
    }

    @MainActor @Test
    func finishingACompositionKeepsItsWords() throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("One 👩🏽‍💻 two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original)
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping()
        view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.finishComposition(); view.localUndo.endUndoGrouping()
        #expect(!view.hasMarkedText() && view.string.hasSuffix("かな"), "Finishing editor commits the actual native composition without dropping words")
        view.retire()
    }
}
