import AppKit
import Testing
@testable import ParcCommandBar

struct CommandBarEditTests {

    @MainActor private final class Edits {
        var deletion: Bool?
    }

    private func projected() -> CommandBarEditState {
        var state = CommandBarEditState(query: "weather")
        state.project(resultID: "native", text: "weather calgary")
        return state
    }

    private func typed(_ query: String) -> CommandBarEditState {
        var state = CommandBarEditState(query: "")
        state.userEdit(query, selection: NSRange(location: query.utf16.count, length: 0), hasMarkedText: false, didBackspace: false)
        return state
    }

    @MainActor private func field(for state: CommandBarEditState) -> NSTextView {
        _ = NSApplication.shared
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        editor.isRichText = false
        editor.string = state.displayedText
        editor.setSelectedRange(state.selection)
        return editor
    }

    @Test func movingBetweenCompletionsKeepsTheTypedQuery() {
        var state = CommandBarEditState(query: "weather")
        state.project(resultID: "native:1", text: "weather calgary")
        state.project(resultID: "native:2", text: "weather edmonton")
        #expect(state.query == "weather")
        #expect(state.displayedText == "weather edmonton")
    }

    @Test(arguments: [
        ("weather", "weather calgary", 7, 8),
        ("WÉA", "wéather", 3, 4),
        ("🌌", "🌌 night", 2, 6),
        ("e\u{301}", "e\u{301} sky", 2, 4),
        ("different", "https://example.test/", 0, 21),
        ("", "https://example.test/", 0, 21),
        ("parc://set", "parc://settings/", 10, 6),
    ]) func aCompletionSelectsOnlyTheNativeUTF16Suffix(query: String, completion: String, location: Int, length: Int) {
        var state = CommandBarEditState(query: query)
        state.project(resultID: "native", text: completion)
        #expect(state.selection == NSRange(location: location, length: length))
    }

    @Test func acceptingACompletionKeepsTheOriginalQueryAndMovesTheCaret() {
        var state = projected()
        state.accept()
        #expect(state.query == "weather")
        #expect(state.displayedText == "weather calgary")
        #expect(state.selection == NSRange(location: 15, length: 0))
    }

    @Test func republishingTheSameResultPreservesAcceptance() {
        var state = projected()
        state.accept()
        state.project(resultID: "native", text: "weather calgary")
        #expect(state.selection.length == 0)
    }

    @Test func leavingTheResultRestoresTheLiteralQuery() {
        var state = projected()
        state.clearProjection()
        #expect(state.displayedText == "weather")
        #expect(state.projection == nil)
    }

    @Test func typingAReplacementStartsAFreshQuery() {
        var state = projected()
        state.edit("weather rain")
        #expect(state.query == "weather rain")
        #expect(state.projection == nil)
    }

    @Test func anEmptyCompletionCannotEraseTheQuery() {
        var state = CommandBarEditState(query: "weather")
        state.project(resultID: "native", text: "")
        #expect(state.displayedText == "weather")
    }

    @Test @MainActor func typingReplacesOnlyTheSelectedSuffix() {
        var state = CommandBarEditState(query: "🌌")
        state.project(resultID: "native", text: "🌌 night")
        let editor = field(for: state)
        editor.insertText(" dawn", replacementRange: editor.selectedRange())
        #expect(editor.string == "🌌 dawn")
    }

    @Test @MainActor func typingAfterAcceptanceAppendsToTheCompletion() {
        var state = projected()
        state.accept()
        let editor = field(for: state)
        editor.insertText("!", replacementRange: editor.selectedRange())
        #expect(editor.string == "weather calgary!")
    }

    @Test @MainActor func backspaceRemovesOnlyTheSelectedSuffix() {
        let editor = field(for: projected())
        editor.deleteBackward(nil)
        #expect(editor.string == "weather")
    }

    @Test func typingAtTheEndAllowsAnAutomaticSuffix() {
        var state = typed("examp")
        let projected = state.projectInline(resultID: "default", text: "example.test", selection: NSRange(location: 5, length: 0), hasMarkedText: false)
        #expect(projected)
        #expect(state.query == "examp")
        #expect(state.projection?.automatic == true)
    }

    @Test func initialAddressTextDoesNotRequestInlineCompletion() {
        #expect(!CommandBarEditState(query: "https://example.test/").allowsInlineCompletion)
    }

    @Test(arguments: [
        (2, false, false, true),
        (2, true, false, false),
        (2, false, true, false),
        (1, false, false, false),
        (NSNotFound, false, false, false),
    ]) func nativeQueryEditsOnlyAllowCompletionAtAnUnmarkedEnd(location: Int, marked: Bool, backspace: Bool, expected: Bool) {
        var state = CommandBarEditState(query: "a")
        state.userEdit("ab", selection: NSRange(location: location, length: 0), hasMarkedText: marked, didBackspace: backspace)
        #expect(state.allowsInlineCompletion == expected)
    }

    @Test(arguments: [
        ("abc", 1, true), ("weather", 1, false), ("a", 1, false), ("abc", 0, false),
    ]) func anAutomaticReplyCannotReplaceEditedText(text: String, location: Int, marked: Bool) {
        var state = typed("a")
        let projected = state.projectInline(resultID: "native", text: text, selection: NSRange(location: location, length: 0), hasMarkedText: marked)
        #expect(!projected)
    }

    @Test func editingAfterBackspaceAllowsCompletionAgain() {
        var state = typed("examp")
        state.userEdit("examp", selection: NSRange(location: 5, length: 0), hasMarkedText: false, didBackspace: true)
        state.userEdit("exampl", selection: NSRange(location: 6, length: 0), hasMarkedText: false, didBackspace: false)
        let projected = state.projectInline(resultID: "next", text: "example.test", selection: NSRange(location: 6, length: 0), hasMarkedText: false)
        #expect(projected)
    }

    @Test func backspaceSuppressesTheNextNativeReply() {
        var state = typed("examp")
        state.userEdit("examp", selection: NSRange(location: 5, length: 0), hasMarkedText: false, didBackspace: true)
        let projected = state.projectInline(resultID: "late", text: "example.test", selection: NSRange(location: 5, length: 0), hasMarkedText: false)
        #expect(!projected)
    }

    @Test func acceptedUnicodeTextStaysInPlaceWhenAnotherReplyArrives() {
        var state = typed("🌌")
        let end = NSRange(location: 2, length: 0)
        _ = state.projectInline(resultID: "native", text: "🌌 sky", selection: end, hasMarkedText: false)
        state.accept()
        let projected = state.projectInline(resultID: "late", text: "🌌 stars", selection: state.selection, hasMarkedText: false)
        #expect(!projected)
        #expect(state.displayedText == "🌌 sky")
    }

    @Test(arguments: [(2, true), (Int.max, false)]) func onlyAValidRangeCanReachTheEnd(length: Int, expected: Bool) {
        #expect(CommandBarEditState.reachesEnd(NSRange(location: 1, length: length), of: "abc") == expected)
    }

    @Test(arguments: [("", true), ("a", false), ("longer text", false)]) @MainActor func nativeStorageDistinguishesDeletionFromAReplacement(replacement: String, deletes: Bool) throws {
        let editor = field(for: projected())
        let storage = try #require(editor.textStorage)
        let edits = Edits()
        let token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { notification in
            MainActor.assumeIsolated {
                guard let text = notification.object as? NSTextStorage, text.editedMask.contains(.editedCharacters) else { return }
                edits.deletion = CommandBarEditState.deletesCharacters(editedRange: text.editedRange, changeInLength: text.changeInLength)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        if replacement.isEmpty { editor.deleteBackward(nil) }
        else { editor.insertText(replacement, replacementRange: editor.selectedRange()) }
        #expect(edits.deletion == deletes)
    }
}
