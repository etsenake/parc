import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsMarkdownPersistence {
    private typealias Editor = EaselTextStyleTestsSupport.Editor

    @MainActor
    private final class MarkdownConversionRefusal: NSObject, NSTextViewDelegate {
        var refusals = 0
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if affectedCharRange.length > 0, (replacementString?.count ?? 0) > 1 { refusals += 1; return false }
            return true
        }
    }

    @MainActor @Test
    func inlineMarkdownKeepsExistingRanges() throws {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("before\n*word\nafter")
        let link = URL(string: "https://example.com")!
        let linkedRange = (view.string as NSString).range(of: "word")
        view.textStorage!.addAttributes([.link: link, .foregroundColor: NSColor.systemBlue], range: linkedRange)
        let before = view.attributedString().attributedSubstring(from: NSRange(location: 0, length: 7))
        view.setSelectedRange(NSRange(location: NSMaxRange(linkedRange), length: 0)); editor.type("*")
        #expect(view.string == "before\nword\nafter", "Range conversion preserves unrelated paragraphs")
        #expect(view.attributedString().attributedSubstring(from: NSRange(location: 0, length: 7)).isEqual(to: before), "Unrelated attributed content stays exact")
        #expect(view.attributedString().attribute(.link, at: 7, effectiveRange: nil) as? URL == link, "Existing inline link survives automatic emphasis")
        #expect(view.attributedString().attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor == NSColor.systemBlue, "Existing inline color survives automatic emphasis")
    }

    @MainActor @Test
    func convertedMarkdownRangesSurviveTheClipboard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("before\n*word\nafter")
        let link = URL(string: "https://example.com")!
        let linkedRange = (view.string as NSString).range(of: "word")
        view.textStorage!.addAttributes([.link: link, .foregroundColor: NSColor.systemBlue], range: linkedRange)
        view.setSelectedRange(NSRange(location: NSMaxRange(linkedRange), length: 0)); editor.type("*")
        let payload = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        try payload.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == payload, "Converted range attributes survive actual native copy and paste carrier")
    }

    @MainActor @Test
    func convertedMarkdownRangesSurviveReopeningAnEasel() throws {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("before\n*word\nafter")
        let link = URL(string: "https://example.com")!
        let linkedRange = (view.string as NSString).range(of: "word")
        view.textStorage!.addAttributes([.link: link, .foregroundColor: NSColor.systemBlue], range: linkedRange)
        view.setSelectedRange(NSRange(location: NSMaxRange(linkedRange), length: 0)); editor.type("*")
        let payload = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Markdown component")
        try session.perform("Type markdown") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 200, height: 100), text: payload.text, richText: payload.richText)] }
        #expect(try! EaselStore(directory: directory).load(session.document.id).document.items.first?.richText == payload.richText, "Actual file-backed document preserves typed markdown attributes")
    }

    @MainActor @Test
    func documentUndoAndRedoRestoreConvertedMarkdown() throws {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("before\n*word\nafter")
        let link = URL(string: "https://example.com")!
        let linkedRange = (view.string as NSString).range(of: "word")
        view.textStorage!.addAttributes([.link: link, .foregroundColor: NSColor.systemBlue], range: linkedRange)
        view.setSelectedRange(NSRange(location: NSMaxRange(linkedRange), length: 0)); editor.type("*")
        let payload = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Markdown component")
        try session.perform("Type markdown") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 200, height: 100), text: payload.text, richText: payload.richText)] }
        try session.undo(); #expect(session.document.items.isEmpty, "Document undo owns the durable typed-text transaction")
        try session.redo(); #expect(session.document.items.first?.richText == payload.richText, "Document redo restores original range formatting")
    }

    @MainActor @Test
    func aRefusedConversionKeepsTheAcceptedLiteralInput() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("*word")
        let refusingDelegate = MarkdownConversionRefusal()
        view.delegate = refusingDelegate
        editor.type("*")
        #expect(view.string == "*word*" && view.selectedRange().location == 6, "Delegate-refused conversion preserves the accepted literal input and caret")
        #expect(refusingDelegate.refusals == 1, "The actual native delegate receives conversion admission")
        view.retire()
    }

    @MainActor @Test
    func committingMarkedTextDoesNotConvertMarkdown() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("*word")
        editor.grouped { view.setMarkedText("*", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        #expect(view.hasMarkedText() && view.string == "*word*", "Input method retains literal marked text")
        editor.grouped { view.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        #expect(!view.hasMarkedText() && view.string == "*word*", "Composition commit is not intercepted as a markdown trigger")
        view.retire()
    }
}
