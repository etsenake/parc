import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteTextRenderingTestsInlineContentAndComposition {
    private let fixture = NoteTextRenderingTestsSupport.Fixture()

    @Test func emptyTextSurvivesTheRoundTrip() { fixture.roundTrip(NoteText()) }

    @Test func plainTextSurvivesTheRoundTrip() { fixture.roundTrip("Plain words") }

    @Test func aSoftLineBreakSurvivesTheRoundTrip() { fixture.roundTrip("Two\nlines") }

    @Test func emojiAndAccentsSurviveTheRoundTrip() { fixture.roundTrip("Emoji 👩🏽‍💻 and ünïcode") }

    @Test func everyMarkSurvivesTheRoundTrip() {
        let link = NoteEditorBlocks.marks { $0.link = "https://parc.app" }
        let red = NoteEditorBlocks.marks { $0.color = .text(.red) }
        let highlight = NoteEditorBlocks.marks { $0.color = .background(.yellow) }
        let everything = NoteEditorBlocks.marks { $0.bold = true; $0.italic = true; $0.underline = true; $0.strikethrough = true }
        let code = NoteEditorBlocks.marks { $0.code = true }
        fixture.roundTrip(NoteText(pieces: [("Bold ", NoteEditorBlocks.bold), ("italic ", NoteEditorBlocks.italic), ("all ", everything), ("code", code),
                                    (" link", link), (" red", red), (" glow", highlight)]))
    }

    @Test func mergedRunsSurviveTheRoundTrip() {
        fixture.roundTrip(NoteText(pieces: [("same ", NoteEditorBlocks.bold), ("same", NoteEditorBlocks.bold)]))
    }

    @Test func everyAtomIncludingIdenticalNeighboursSurvivesTheRoundTrip() {
        let date = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true)
        let atoms = NoteText.atom(.equation("x^2")) + NoteText.atom(.equation("x^2")) + NoteText(" ")
            + NoteText.atom(.page(target: "Other.md", title: "Other")) + NoteText.atom(.date(date))
            + NoteText.atom(.link(url: "https://parc.app", title: "Parc")) + NoteText.atom(.raw("<kbd>K</kbd>"))
            + NoteText.atom(.equation("y"), marks: NoteEditorBlocks.bold)
        fixture.roundTrip(atoms)
    }

    @Test func aRawObjectCharacterWithoutAnAtomSurvivesTheRoundTrip() { fixture.roundTrip(NoteText("Stray \u{FFFC} object")) }

    @Test func aLinkAcrossMarksSurvivesTheRoundTrip() {
        let link = NoteEditorBlocks.marks { $0.link = "https://parc.app" }
        fixture.roundTrip(NoteText(pieces: [("linked ", link), ("bold link", NoteEditorBlocks.marks { $0.link = "https://parc.app"; $0.bold = true })]))
    }

    @Test func aCheckedTodoSurvivesTheRoundTrip() {
        let red = NoteEditorBlocks.marks { $0.color = .text(.red) }
        fixture.roundTrip(NoteText(pieces: [("done ", NoteEditorBlocks.bold), ("red", red)]), in: NoteTextPresentation(completed: true))
    }

    @Test func aHeadingSurvivesTheRoundTrip() {
        fixture.roundTrip("Heading", in: NoteTextPresentation(role: .heading(1)))
    }

    @Test func atomsRenderAsAttachments() {
        let attributed = NoteTextRendering.attributedString(NoteText.atom(.page(target: "a.md", title: "A")), NoteTextPresentation())
        #expect(attributed.attribute(.attachment, at: 0, effectiveRange: nil) is NoteAtomAttachment)
    }

    private func styled() -> NSAttributedString {
        NoteTextRendering.attributedString(NoteText(pieces: [("x", NoteEditorBlocks.marks { $0.code = true }), ("y", NoteEditorBlocks.marks { $0.color = .background(.yellow) })]),
                                           NoteTextPresentation())
    }

    @Test func inlineCodeGetsItsPill() {
        #expect(styled().attribute(.noteInlineCode, at: 0, effectiveRange: nil) as? Bool == true)
    }

    @Test func highlightsGetTheirRoundedFill() {
        #expect(styled().attribute(.noteHighlight, at: 1, effectiveRange: nil) is NSColor)
    }

    @Test func highlightsNeverUseFlatBackgrounds() {
        #expect(styled().attribute(.backgroundColor, at: 1, effectiveRange: nil) == nil)
    }

    private func emojiBesideAnAtom() -> NoteText {
        let equation = NoteEditorBlocks.marks { $0.atom = .equation("x") }
        let tagged = NSAttributedString(string: "😀\u{FFFC}é👩🏽‍💻", attributes: [.noteMarks: NoteMarksValue(equation)])
        return NoteTextRendering.noteText(from: tagged)
    }

    @Test func emojiTypedBesideAnAtomStayEmoji() {
        #expect(emojiBesideAnAtom() == NoteText("😀") + NoteText.atom(.equation("x")) + NoteText("é👩🏽‍💻"))
    }

    @Test func noReplacementCharactersAppearBesideAnAtom() {
        #expect(!emojiBesideAnAtom().string.contains("\u{FFFD}"))
    }

    @Test func renderingKeepsEmojiBesideAtomsWhole() {
        let rendered = NoteTextRendering.attributedString(NoteText("🎉") + NoteText.atom(.equation("y")) + NoteText("🎈"), NoteTextPresentation())
        #expect(rendered.string == "🎉\u{FFFC}🎈")
    }

    private let base: NoteText = "Hello world"

    private let committed: NoteText = "Hello 世界 world"

    @Test func aCompositionOverUnchangedTextCommitsAsTyped() {
        #expect(NoteTextRendering.mergeComposition(committed: committed, base: base, external: base).text == committed)
    }

    @Test func anOutsideEditAfterTheCaretSurvivesTheCommit() {
        let appended = NoteTextRendering.mergeComposition(committed: committed, base: base, external: "Hello world, friends", caret: 8)
        #expect(appended.text.string == "Hello 世界 world, friends")
        #expect(appended.caret == 8)
    }

    @Test func anOutsideEditBeforeTheCaretSurvivesTheCommit() {
        let prepended = NoteTextRendering.mergeComposition(committed: committed, base: base, external: "Oh, Hello world", caret: 8)
        #expect(prepended.text.string == "Oh, Hello 世界 world")
        #expect(prepended.caret == 12)
    }

    @Test func aReplacedEmojiSwapsWholeInsteadOfByHalves() {
        #expect(NoteTextRendering.mergeComposition(committed: "😁", base: "😀", external: "😀?", caret: 2).text.string == "😁?")
    }

    @Test func mergingNeverSplitsASurrogatePair() {
        #expect(NoteTextRendering.mergeComposition(committed: "😀😁", base: "😀", external: "😀!", caret: 4).text.string == "😀😁!")
    }

    @Test func anOutsideRewriteWinsWhenTheCompositionCannotBePlaced() {
        #expect(NoteTextRendering.mergeComposition(committed: "abc", base: "xyz", external: "totally different").text.string == "totally different")
    }

    private var equation: NoteText { NoteText("Total ") + NoteText.atom(.equation("x^2")) + NoteText(" done", marks: NoteEditorBlocks.bold) }
}
