import AppKit

/// Native title input stays separate from the attributed body and its Undo owner.
@MainActor
final class NoteTitleTextView: LocalContentDropTextView {
    let localUndo = UndoManager()
    override var undoManager: UndoManager? { localUndo }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override func paste(_ sender: Any?) { _ = pasteTitle(from: .general) }
    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }
    override func readSelection(from board: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { pasteTitle(from: board) }
    @discardableResult func pasteTitle(from board: NSPasteboard) -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1,
              let value = board.pasteboardItems?.first?.string(forType: .string) else { return false }
        //
        // character and joins the pieces with spaces, including empty pieces.
        insertText(value.components(separatedBy: .newlines).joined(separator: " "), replacementRange: selectedRange())
        return true
    }
    func resetEditingHistory() {
        let level = localUndo.groupingLevel, automatic = localUndo.groupsByEvent
        localUndo.groupsByEvent = false; localUndo.removeAllActions()
        for _ in 0..<level { localUndo.beginUndoGrouping() }
        localUndo.groupsByEvent = automatic
    }
    //
    // NSTextView. AppKit draws it with native layout and composition rules;
    // it is never inserted into the title, selected, copied or persisted.
    @objc var placeholderAttributedString: NSAttributedString? {
        didSet {
            needsDisplay = true; invalidateIntrinsicContentSize()
            // Expose the hint separately from the real, possibly empty value.
            setAccessibilityPlaceholderValue(placeholderAttributedString?.string)
        }
    }

}

@MainActor
enum NoteKeyboardEditing {
    static func valid(_ range: NSRange, in string: String) -> Bool {
        let units = Array(string.utf16)
        guard range.location != NSNotFound, range.location <= units.count,
              range.length <= units.count - range.location else { return false }
        func boundary(_ n: Int) -> Bool {
            n == 0 || n == units.count || !(0xD800...0xDBFF).contains(units[n - 1]) || !(0xDC00...0xDFFF).contains(units[n])
        }
        return boundary(range.location) && boundary(NSMaxRange(range))
    }
    static func titleSuffix(_ title: String, selection: NSRange) -> NSRange? {
        guard valid(selection, in: title) else { return nil }
        return NSRange(location: selection.location, length: title.utf16.count - selection.location)
    }
    static func firstLine(_ string: String) -> (text: String, removal: NSRange) {
        let source = string as NSString
        let newline = source.rangeOfCharacter(from: .newlines)
        guard newline.location != NSNotFound else { return (string, NSRange(location: 0, length: source.length)) }
        // Consume a whole CRLF in current AppKit rather than leave a stray LF.
        var end = NSMaxRange(newline)
        if source.character(at: newline.location) == 13, end < source.length, source.character(at: end) == 10 { end += 1 }
        return (source.substring(to: newline.location), NSRange(location: 0, length: end))
    }
    static func isFirstVisualLine(_ text: NSTextView) -> Bool {
        let range = text.selectedRange()
        guard text.selectedRanges.count == 1, valid(range, in: text.string),
              (text.string as NSString).lineRange(for: range).location == 0 else { return false }
        if text.string.isEmpty { return true }
        guard let layout = text.layoutManager, let container = text.textContainer else { return false }
        layout.ensureLayout(for: container)
        let character = min(range.location, text.string.utf16.count - 1)
        let glyph = layout.glyphIndexForCharacter(at: character)
        let first = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let current = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return current.minY == first.minY
    }
    static func hasDefaultTyping(_ text: EaselStyledTextView) -> Bool {
        // The reference compares the complete typing dictionary to its default.
        // Compare the normalized current carrier, preserving explicit formatting.
        let sample = NSAttributedString(string: "x", attributes: text.typingAttributes)
        let base = NSAttributedString(string: "x", attributes: NoteDocumentAppearance.bodyAttributes)
        guard let actual = try? EaselRichTextCodec.snapshot(sample), let expected = try? EaselRichTextCodec.snapshot(base) else { return false }
        return actual == expected
    }
    ///
    /// line-prefix caret before Up/Left/Return. Title never consumes them.
    static func isBeginningOfLine(_ command: Selector) -> Bool {
        command == #selector(NSResponder.moveToBeginningOfLine(_:))
            || command == #selector(NSResponder.moveToLeftEndOfLine(_:))
            || command == #selector(NSResponder.moveToBeginningOfParagraph(_:))
    }
    ///
    ///
    /// characters from that start against the whole string. A too-short remainder
    /// keeps the line start; otherwise the caret is `min(end-1, prefixEnd)`.
    static func beginningOfLineCaret(in string: String, selection: NSRange) -> NSRange? {
        guard valid(selection, in: string) else { return nil }
        let source = string as NSString
        var line = source.lineRange(for: selection)
        if line.length > 0, source.character(at: NSMaxRange(line) - 1) == 10 {
            line.length -= 1
            // Original Character compare only drops LF. Consume a preceding CR so
            // a CRLF terminator cannot occupy the five-unit prefix window.
            if line.length > 0, source.character(at: NSMaxRange(line) - 1) == 13 { line.length -= 1 }
        }
        let units = source.length
        guard line.location <= units else { return nil }
        if units - line.location < 5 {
            return NSRange(location: line.location, length: 0)
        }
        let composed = source.rangeOfComposedCharacterSequences(for: NSRange(location: line.location, length: 5))
        let caret = min(units - 1, NSMaxRange(composed))
        return NSRange(location: caret, length: 0)
    }
}
