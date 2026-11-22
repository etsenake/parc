import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsInlineMarkdown {
    private typealias Editor = EaselTextStyleTestsSupport.Editor

    struct Delimiter: CustomTestStringConvertible {
        let testDescription: String
        let source: String
        let emphasis: EaselStyledTextView.Emphasis

        static let cases = [
            Self(testDescription: "Asterisks apply bold", source: "*One café*", emphasis: .bold),
            Self(testDescription: "Underscores apply italic", source: "_One café_", emphasis: .italic),
            Self(testDescription: "Hyphens apply strikethrough", source: "-One café-", emphasis: .strikethrough),
        ]
    }

    struct Shortcut: CustomTestStringConvertible {
        let source: String
        let shown: String
        var testDescription: String { source }

        static let cases = [Self(source: "**bold**", shown: "bold"), Self(source: "~~strike~~", shown: "strike")]
    }

    @MainActor @Test(arguments: Delimiter.cases)
    func aTypedInlineDelimiterFormatsItsRange(_ delimiter: Delimiter) {
        let source = delimiter.source
        let emphasis = delimiter.emphasis
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(source)
        #expect(view.string == "One café", "Typed original delimiter syntax consumes only its delimiters: \(source)")
        #expect(view.selectedRange() == NSRange(location: 8, length: 0), "Inline conversion preserves the original UTF-16 caret")
        let finished = view.attributedString()
        let attrs = finished.attributes(at: 0, effectiveRange: nil)
        let styled = emphasis == .strikethrough ? (attrs[.strikethroughStyle] as? NSNumber)?.intValue == 1
            : (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(emphasis == .bold ? .bold : .italic) == true
        #expect(styled, "Typed token creates the real native range attribute")
        #expect(!view.hasEmphasis(emphasis), "Conversion immediately restores the original unstyled typing attributes")
    }

    @MainActor @Test(arguments: Delimiter.cases)
    func undoAndRedoRestoreTheInlineConversion(_ delimiter: Delimiter) {
        let source = delimiter.source
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(source)
        let finished = view.attributedString()
        view.undo(nil)
        #expect(view.string == String(source.dropLast()), "One input transaction undoes the closing character and its conversion")
        view.redo(nil)
        #expect(view.attributedString().isEqual(to: finished), "Native redo restores converted text and attributes without a second transform")
    }

    @MainActor @Test(arguments: Delimiter.cases)
    func typingAfterInlineConversionKeepsTheOriginalTypingAttributes(_ delimiter: Delimiter) {
        let source = delimiter.source
        let emphasis = delimiter.emphasis
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(source)
        let finished = view.attributedString()
        editor.type(" after")
        view.setSelectedRange(NSRange(location: finished.length + 1, length: 5))
        #expect(!view.hasEmphasis(emphasis), "Conversion restores original typing attributes for following text")
    }

    @MainActor @Test(arguments: Shortcut.cases)
    func notesTypingShortcutsConvertInEaselText(_ shortcut: Shortcut) {
        let source = shortcut.source
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        view.textStorage!.setAttributedString(EaselTextAppearance.attributed("", style: .init(), color: "#252525"))
        view.typingAttributes = EaselTextAppearance.attributed("a", style: .init(), color: "#252525").attributes(at: 0, effectiveRange: nil)
        view.localUndo.removeAllActions(); view.setSelectedRange(NSRange(location: 0, length: 0))
        for character in source {
            view.localUndo.beginUndoGrouping()
            view.insertText(String(character), replacementRange: view.selectedRange())
            view.localUndo.endUndoGrouping()
        }
        #expect(view.string == shortcut.shown, "Notes typing shortcuts convert in Easel text: \(source)")
        let attrs = view.attributedString().attributes(at: 0, effectiveRange: nil)
        let styled = source.hasPrefix("**") ? (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
            : (attrs[.strikethroughStyle] as? NSNumber)?.intValue == NSUnderlineStyle.single.rawValue
        #expect(styled, "A Notes typing shortcut leaves the real native range attribute: \(source)")
    }

    @MainActor @Test(arguments: ["``", "[label](https://example.com)", "*incomplete", "*punctuation!*", "word*bold*", #"\*escaped*"#, "+ list", "2. list", "##### heading", ">quote"])
    func unsupportedMarkdownRemainsLiteral(_ literal: String) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(literal)
        #expect(view.string == literal, "Unsupported or incomplete syntax remains literal: \(literal)")
    }

    @MainActor @Test
    func aTypedCloserCompletesAnExistingInlineRange() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("before *one"); editor.type("*")
        #expect(view.string == "before one", "A typed closer may complete an existing original range at a word boundary")
    }

    @MainActor @Test
    func anUnrelatedEditLeavesExistingMarkdownLiteral() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("*word* other"); editor.type(" ")
        #expect(view.string == "*word* other ", "An unrelated later edit never retrospectively interprets imported tokens")
    }

    @MainActor @Test
    func replacingASelectionLeavesSurroundingMarkdownLiteral() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("*word*"); view.setSelectedRange(NSRange(location: 0, length: 1)); editor.type("*")
        #expect(view.string == "*word*", "Replacing a selection does not reinterpret its surrounding literal text")
    }

    @MainActor @Test
    func aPastedCloserStaysLiteral() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("*word")
        board.clearContents(); board.setString("*", forType: .string)
        editor.grouped { #expect(view.pasteContent(from: board), "Native plain paste succeeds") }
        #expect(view.string == "*word*", "Even a one-character pasted closer remains literal")
    }

    @MainActor @Test
    func privateRichPastePreservesLiteralMarkdown() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("")
        try EaselStyledText(text: "# Heading\n*word*", style: .init(), color: "#252525").write(to: board)
        editor.grouped { #expect(view.pasteContent(from: board), "Native private rich paste succeeds") }
        #expect(view.string == "# Heading\n*word*", "Private rich paste preserves literal syntax")
    }

    @MainActor @Test
    func rtfPasteInterpretsMarkdownLikeNotes() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        try EaselStyledText(text: "# Heading\n*word*", style: .init(), color: "#252525").write(to: board)
        let rtf = board.data(forType: .rtf)!
        board.clearContents(); board.setData(rtf, forType: .rtf); editor.load("")
        editor.grouped { #expect(view.pasteContent(from: board), "Native RTF paste succeeds") }
        #expect(view.string == "Heading\nword", "RTF whose plain text reads as Markdown pastes the way it does in a note")
    }

    @MainActor @Test
    func typedBackticksCreateInlineCode() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type("`let x = 1`")
        #expect(view.string == "let x = 1", "Typed backticks become inline code")
        let code = view.attributedString().attributes(at: 0, effectiveRange: nil)
        #expect((code[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true && code[.backgroundColor] != nil,
               "Inline code is monospaced on a soft fill")
        #expect((view.typingAttributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) != true, "Typing after code is plain again")
        #expect(EaselTextAppearance.isInlineCode(code) && !EaselTextAppearance.isInlineCode(view.typingAttributes), "Inline code is recognised, plain text isn't")
    }

    @MainActor @Test
    func highlightingPreservesWhetherTheTextIsCode() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type("`let x = 1`")
        let code = view.attributedString().attributes(at: 0, effectiveRange: nil)
        var marked = code
        marked[.backgroundColor] = EaselTextHighlight.color(.yellow)
        #expect(EaselTextAppearance.isInlineCode(marked), "Highlighted inline code is still code")
        marked[.font] = EaselTextAppearance.font(.init())
        #expect(!EaselTextAppearance.isInlineCode(marked), "A highlight on plain text isn't code")
    }

    @MainActor @Test
    func aTypedQuotePrefixCreatesAQuote() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type("> ")
        #expect(view.string == "\t\u{258E}\t" && view.paragraphKind() == .quote, "A typed > starts a quote")
    }

    @MainActor @Test
    func returnContinuesANonemptyQuote() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type("> ")
        editor.type("Quoted"); editor.grouped { view.insertNewline(nil) }
        #expect(view.string.hasSuffix("\n\t\u{258E}\t"), "Return continues the quote")
    }

    @MainActor @Test
    func returnExitsAnEmptyQuote() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type("> ")
        editor.type("Quoted"); editor.grouped { view.insertNewline(nil) }
        editor.grouped { view.insertNewline(nil) }
        #expect(view.paragraphKind() == .text, "An empty quote line ends the quote")
    }
}
