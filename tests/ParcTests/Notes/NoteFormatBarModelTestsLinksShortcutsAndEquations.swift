import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct NoteFormatBarModelTestsLinksShortcutsAndEquations {
    private struct LinkNormalizationCase: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: String

        var testDescription: String { "\(input)" }
    }

    private struct LinkDisplayCase: Sendable, CustomTestStringConvertible {
        let link: String
        let shown: String

        var testDescription: String { "\(link)" }
    }

    private struct ShortcutCase: Sendable, CustomTestStringConvertible {
        let key: String
        let flags: NSEvent.ModifierFlags
        let item: NoteFormatItem

        var testDescription: String { "\(key)" }
    }

    private struct FocusCase: Sendable, CustomTestStringConvertible {
        let from: Int?
        let step: Int
        let expected: Int?

        var testDescription: String { "from \(from.map(String.init) ?? "none"), step \(step)" }
    }

    @Test(arguments: [
        LinkNormalizationCase(input: "example.com", expected: "https://example.com"),
        LinkNormalizationCase(input: "  www.example.com/path?q=1#top \n", expected: "https://www.example.com/path?q=1#top"),
        LinkNormalizationCase(input: "<https://parc.example/a>", expected: "https://parc.example/a"),
        LinkNormalizationCase(input: "http://example.com", expected: "http://example.com"),
        LinkNormalizationCase(input: "https://intranet:8080/x", expected: "https://intranet:8080/x"),
        LinkNormalizationCase(input: "localhost:3000", expected: "http://localhost:3000"),
        LinkNormalizationCase(input: "192.168.1.10:8080/admin", expected: "http://192.168.1.10:8080/admin"),
        LinkNormalizationCase(input: "sub.domain.co.uk", expected: "https://sub.domain.co.uk"),
        LinkNormalizationCase(input: "someone@example.com", expected: "mailto:someone@example.com"),
        LinkNormalizationCase(input: "mailto:someone@example.com", expected: "mailto:someone@example.com"),
        LinkNormalizationCase(input: "tel:+15551234567", expected: "tel:+15551234567"),
        LinkNormalizationCase(input: "./Other Note.md", expected: "./Other%20Note.md"),
        LinkNormalizationCase(input: "Ideas.md", expected: "Ideas.md"),
        LinkNormalizationCase(input: "../Projects/Plan.md#goals", expected: "../Projects/Plan.md#goals"),
        LinkNormalizationCase(input: "#heading", expected: "#heading"),
        LinkNormalizationCase(input: "/Users/me/Notes/Plan.md", expected: "file:///Users/me/Notes/Plan.md"),
        LinkNormalizationCase(input: "obsidian://open?vault=x", expected: "obsidian://open?vault=x"),
    ])
    private func typedLinksNormalize(sample: LinkNormalizationCase) {
        #expect(NoteLinkInput.normalize(sample.input) == sample.expected)
    }

    @Test(arguments: [
        "hello world", "notalink", "http://", "", "   ", "example.c", "-bad-.com", "one\ntwo.com", "javascript:alert(1)",
        "  JavaScript:alert(document.cookie)", "<javascript:void(0)>", "java\tscript:alert(1)", "vbscript:msgbox(1)",
        "data:text/html,<script>alert(1)</script>", "DATA:image/png;base64,AAAA",
    ])
    func typedTextThatIsNotASafeLinkIsRefused(input: String) {
        #expect(NoteLinkInput.normalize(input) == nil)
    }

    @Test(arguments: [
        LinkDisplayCase(link: "https://www.example.com/", shown: "www.example.com"),
        LinkDisplayCase(link: "https://example.com/a%20b?x=1", shown: "example.com/a b?x=1"),
        LinkDisplayCase(link: "mailto:hi@parc.example", shown: "hi@parc.example"),
        LinkDisplayCase(link: "./Other%20Note.md", shown: "./Other Note.md"),
    ])
    private func linksDisplayWithoutTheirSchemeAndEscapes(sample: LinkDisplayCase) {
        #expect(NoteLinkInput.displayText(sample.link) == sample.shown)
    }

    @Test func relativeLinksAreToldApartFromWebLinksAndAnchors() {
        #expect(NoteLinkInput.isRelative("Ideas.md"))
        #expect(!NoteLinkInput.isRelative("https://x.com"))
        #expect(!NoteLinkInput.isRelative("#a"))
    }

    @Test func notePathsAreMarkdownOrText() {
        #expect(NoteLinkInput.isNotePath("Plan%20B.md"))
        #expect(!NoteLinkInput.isNotePath("photo.png"))
    }

    @Test(arguments: ["javascript:alert(1)", " \u{01}JAVASCRIPT:x", "java\nscript:x", "vbscript:x", "data:text/html,hi", "jav\u{00A0}ascript:x"])
    func unsafeSchemesAreRefusedAsLinks(link: String) {
        #expect(NoteLinkInput.isUnsafe(link))
    }

    @Test(arguments: ["https://example.com/javascript:x", "Ideas.md", "./data:notes.md", "mailto:hi@parc.example", "#data:x", "datas:x"])
    func ordinaryLinksAreNotUnsafe(link: String) {
        #expect(!NoteLinkInput.isUnsafe(link))
    }

    @Test func commandBMatches() {
        #expect(NoteFormatShortcut.bold.matches(characters: "b", flags: .command))
    }

    @Test func commandShiftBIsNotCommandB() {
        #expect(!NoteFormatShortcut.bold.matches(characters: "b", flags: [.command, .shift]))
    }

    @Test func strikethroughMatchesTheShiftedLetter() {
        #expect(NoteFormatShortcut.strikethrough.matches(characters: "S", flags: [.command, .shift]))
    }

    @Test func commandQuestionMarkFocusesTheToolbar() {
        #expect(NoteFormatShortcut.focusToolbar.matches(characters: "?", flags: [.command, .shift]))
    }

    @Test func capsLockNeverMatters() {
        #expect(NoteFormatShortcut.lastColor.matches(characters: "H", flags: [.command, .shift, .capsLock]))
    }

    @Test func theStrikethroughChordDisplaysShiftBeforeCommand() {
        #expect(NoteFormatShortcut.strikethrough.display == "⇧⌘S")
    }

    @Test func theLastColourChordSuppliesOrderedKeycaps() {
        #expect(NoteFormatShortcut.lastColor.glyphs == ["⇧", "⌘", "H"])
    }

    @Test(arguments: [
        ShortcutCase(key: "e", flags: NSEvent.ModifierFlags([.command, .shift]), item: NoteFormatItem.equation),
        ShortcutCase(key: "e", flags: .command, item: .code),
        ShortcutCase(key: "k", flags: .command, item: .link),
    ])
    private func chordsMapToTheirFormatItem(sample: ShortcutCase) {
        #expect(NoteFormatItem.shortcutItem(for: (sample.key, sample.flags)) == sample.item)
    }

    @Test func otherChordsPassThrough() {
        #expect(NoteFormatItem.shortcutItem(for: ("x", .command)) == nil)
    }

    private func linkedText() -> NoteText {
        var link = NoteMarks.plain
        link.link = "https://parc.example"
        var bold = link
        bold.bold = true
        var other = NoteMarks.plain
        other.link = "Other.md"
        return NoteText(pieces: [("See ", .plain), ("the ", link), ("bold", bold), (" docs", link), (" and ", .plain), ("this", other)])
    }

    @Test func aLinkSpansEveryRunThatSharesIt() {
        let span = NoteLinkSpan.at(9, in: linkedText())
        #expect(span?.range == 4..<17)
        #expect(span?.link == "https://parc.example")
    }

    @Test func plainTextHasNoLinkSpan() {
        #expect(NoteLinkSpan.at(2, in: linkedText()) == nil)
    }

    @Test func neighbouringLinksStaySeparate() {
        let span = NoteLinkSpan.at(22, in: linkedText())
        #expect(span?.range == 22..<26)
        #expect(span?.link == "Other.md")
    }

    @Test func pastTheEndThereIsNoLink() {
        #expect(NoteLinkSpan.at(26, in: linkedText()) == nil)
    }

    private func energy() -> NoteText {
        var bold = NoteMarks.plain
        bold.bold = true
        return NoteText(pieces: [("Energy ", .plain), (" E=mc^2 ", bold), ("rocks", .plain)])
    }

    @Test func spacesStayOutsideTheEquation() {
        #expect(NoteInlineEquation.wrap(energy(), range: 7..<15)?.text.string == "Energy  " + NoteAtom.character + " rocks")
    }

    @Test func theNewEquationIsReportedForSelecting() {
        #expect(NoteInlineEquation.wrap(energy(), range: 7..<15)?.atom == 8..<9)
    }

    @Test func theSourceBecomesAnEquationThatKeepsItsMarks() throws {
        let wrapped = try #require(NoteInlineEquation.wrap(energy(), range: 7..<15))
        let marks = wrapped.text.marks(at: wrapped.atom.lowerBound)
        #expect(marks.atom == .equation("E=mc^2"))
        #expect(marks.bold)
    }

    @Test func wrappingOnlySpacesDoesNothing() {
        #expect(NoteInlineEquation.wrap(energy(), range: 6..<7) == nil)
    }

    @Test func unwrappingRestoresTheSource() throws {
        let wrapped = try #require(NoteInlineEquation.wrap(energy(), range: 7..<15))
        let unwrapped = NoteInlineEquation.unwrap(wrapped.text, range: wrapped.atom)
        #expect(unwrapped.text.string == "Energy  E=mc^2 rocks")
        #expect(unwrapped.range == 8..<14)
    }

    @Test func unwrappedSourceKeepsItsMarks() throws {
        let wrapped = try #require(NoteInlineEquation.wrap(energy(), range: 7..<15))
        let unwrapped = NoteInlineEquation.unwrap(wrapped.text, range: wrapped.atom)
        #expect(unwrapped.text.marks(at: 9).bold)
        #expect(unwrapped.text.marks(at: 9).atom == nil)
    }

    @Test(arguments: [
        FocusCase(from: nil, step: 1, expected: 0),
        FocusCase(from: nil, step: -1, expected: 3),
        FocusCase(from: 1, step: 1, expected: 3),
        FocusCase(from: 3, step: 1, expected: 0),
        FocusCase(from: 0, step: -1, expected: 3),
    ])
    private func keyboardFocusMovesPastDisabledItemsAndWraps(sample: FocusCase) {
        #expect(NoteFormatBarFocus.move(from: sample.from, by: sample.step, enabled: [true, true, false, true]) == sample.expected)
    }

    @Test func nothingEnabledNothingFocused() {
        #expect(NoteFormatBarFocus.move(from: 0, by: 1, enabled: [false, false]) == nil)
    }
}
