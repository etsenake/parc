import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteTextRenderingTestsTypingMetricsAndAlignment {
    private let fixture = NoteTextRenderingTestsSupport.Fixture()

    @Test func typedTextKeepsItsMarks() {
        let presentation = NoteTextPresentation()
        let view = fixture.makeTextView(presentation, width: 300)
        view.textStorage?.setAttributedString(NoteTextRendering.attributedString(NoteText(pieces: [("Hi ", .plain)]), presentation))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.typingAttributes = NoteTextRendering.typingAttributes(NoteEditorBlocks.bold, presentation)
        view.insertText("there", replacementRange: view.selectedRange())
        view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
        view.insertText("\n!", replacementRange: view.selectedRange())
        #expect(NoteTextRendering.noteText(from: view.textStorage!) == NoteText(pieces: [("Hi ", .plain), ("there", NoteEditorBlocks.bold), ("\n!", .plain)]))
    }

    @Test func typingNeverInheritsAnAtom() {
        let pending = NoteTextRendering.typingAttributes(NoteMarks(atom: .equation("x")), NoteTextPresentation())
        #expect((pending[.noteMarks] as? NoteMarksValue)?.marks.atom == nil)
    }

    private struct Measurement: @unchecked Sendable, CustomTestStringConvertible {
        let presentation: NoteTextPresentation
        let presentationName: String
        let width: CGFloat
        let sample: NoteText

        var testDescription: String { "\(sample.string.debugDescription) at \(width) as \(presentationName)" }
    }

    nonisolated private static let measurements: [Measurement] = {
        let samples: [NoteText] = [
            "", "Short", "A line that is long enough to wrap around the narrow column at least once, maybe twice even.",
            "Ends with a break\n", "Two\nlines\n\nwith a gap", "😀 emoji line that also wraps around because it keeps going on",
            NoteText(pieces: [("Inline ", .plain), ("code", NoteEditorBlocks.marks { $0.code = true }), (" and ", .plain)])
                + NoteText.atom(.page(target: "x.md", title: "A page mention")) + NoteText(" and ")
                + NoteText.atom(.date(NoteDateMention(year: 2026, month: 1, day: 2))),
            NoteText("Equation ") + NoteText.atom(.equation("\\frac{a}{b}")) + NoteText(" inline"),
        ]
        let presentations: [(String, NoteTextPresentation)] = [
            ("body", NoteTextPresentation()), ("heading 1", NoteTextPresentation(role: .heading(1))),
            ("heading 3", NoteTextPresentation(role: .heading(3))), ("small", NoteTextPresentation(small: true)),
            ("quote", NoteTextPresentation(role: .quote)),
        ]
        return presentations.flatMap { name, presentation in
            [120.0, 260.0, 600.0].flatMap { width in
                samples.map { Measurement(presentation: presentation, presentationName: name, width: CGFloat(width), sample: $0) }
            }
        }
    }()

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.measurements)
    private func measuredHeightMatchesTheLiveView(measurement: Measurement) {
        let presentation = measurement.presentation
        let lineHeight = NoteTextRendering.lineHeight(presentation)
        let view = fixture.makeTextView(presentation, width: measurement.width)
        view.textStorage?.setAttributedString(NoteTextRendering.attributedString(measurement.sample, presentation))
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        let live = max(lineHeight, ceil(view.layoutManager!.usedRect(for: view.textContainer!).height))
        #expect(NoteTextRendering.height(of: measurement.sample, presentation, width: measurement.width) == live)
    }

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.measurements)
    private func singleLinesStayOnTheLineHeightGrid(measurement: Measurement) {
        let sample = measurement.sample
        guard !sample.string.contains("\n"), !NoteTextRendering.needsFlexibleLines(sample) else { return }
        let lineHeight = NoteTextRendering.lineHeight(measurement.presentation)
        let measured = NoteTextRendering.height(of: sample, measurement.presentation, width: measurement.width)
        #expect(measured.truncatingRemainder(dividingBy: lineHeight) == 0)
    }

    @Test func anEmptyBlockIsOneLineTall() {
        #expect(NoteTextRendering.height(of: NoteText(), NoteTextPresentation(), width: 300) == NoteTextRendering.lineHeight(NoteTextPresentation()))
    }

    @Test func headingsUseTheirLevel() {
        #expect(NoteTextPresentation(block: NoteBlock.heading(2, "Hi"), settings: NotePageSettings()).role == .heading(2))
    }

    @Test func checkedTodosAreCompleted() {
        #expect(NoteTextPresentation(block: NoteEditorBlocks.todo("x", checked: true), settings: NotePageSettings()).completed)
    }

    @Test func completedTextIsStruckThrough() {
        let done = NoteTextPresentation(block: NoteEditorBlocks.todo("x", checked: true), settings: NotePageSettings())
        let attributes = NoteTextRendering.attributes(for: .plain, done)
        #expect(attributes[.strikethroughStyle] != nil)
    }

    @Test func completedTextUsesMutedInk() {
        let done = NoteTextPresentation(block: NoteEditorBlocks.todo("x", checked: true), settings: NotePageSettings())
        let attributes = NoteTextRendering.attributes(for: .plain, done)
        #expect((attributes[.foregroundColor] as? NSColor) == NoteTheme.todoDoneInk)
    }

    @Test func smallTextReachesThePresentation() {
        var settings = NotePageSettings()
        settings.smallText = true
        settings.font = .serif
        let small = NoteTextPresentation(block: NoteEditorBlocks.para("x"), settings: settings)
        #expect(small.small)
    }

    @Test func thePageFontReachesThePresentation() {
        var settings = NotePageSettings()
        settings.smallText = true
        settings.font = .serif
        let small = NoteTextPresentation(block: NoteEditorBlocks.para("x"), settings: settings)
        #expect(small.pageFont == .serif)
    }

    @Test func boldKeepsTheBodySize() {
        #expect(NoteTextRendering.font(for: NoteEditorBlocks.bold, NoteTextPresentation()).pointSize == NoteTextRendering.font(for: .plain, NoteTextPresentation()).pointSize)
    }

    @Test func inlineCodeIsATouchSmaller() {
        let code = NoteTextRendering.font(for: NoteEditorBlocks.marks { $0.code = true }, NoteTextPresentation())
        #expect(code.pointSize < NoteTextRendering.font(for: .plain, NoteTextPresentation()).pointSize)
    }

    @Test func textStartsNaturallyAligned() {
        #expect(NoteTextPresentation().alignment == .natural)
    }

    private struct AlignmentCase: @unchecked Sendable, CustomTestStringConvertible {
        let presentation: NoteTextPresentation
        let testDescription: String
    }

    nonisolated private static let aligned = [
        AlignmentCase(presentation: NoteTextPresentation(role: .tableCell, alignment: .center), testDescription: "centred"),
        AlignmentCase(presentation: NoteTextPresentation(role: .tableHeader, small: true, alignment: .right), testDescription: "right-aligned"),
    ]

    private var equation: NoteText { NoteText("Total ") + NoteText.atom(.equation("x^2")) + NoteText(" done", marks: NoteEditorBlocks.bold) }

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.aligned)
    private func alignedTextSurvivesTheRoundTrip(sample: AlignmentCase) {
        fixture.roundTrip("Two\nlines", in: sample.presentation)
    }

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.aligned)
    private func alignedTextWithAnEquationSurvivesTheRoundTrip(sample: AlignmentCase) {
        fixture.roundTrip(equation, in: sample.presentation)
    }

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.aligned)
    private func alignedRunsAllShareTheAlignment(sample: AlignmentCase) {
        let presentation = sample.presentation
        let attributed = NoteTextRendering.attributedString(equation, presentation)
        var alignments = Set<Int>()
        attributed.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            alignments.insert((value as? NSParagraphStyle)?.alignment.rawValue ?? -1)
        }
        #expect(alignments == [presentation.alignment.rawValue])
    }

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.aligned)
    private func alignedTypingKeepsTheAlignment(sample: AlignmentCase) {
        let presentation = sample.presentation
        let typing = NoteTextRendering.typingAttributes(NoteEditorBlocks.bold, presentation)
        #expect((typing[.paragraphStyle] as? NSParagraphStyle)?.alignment == presentation.alignment)
    }

    @Test(arguments: NoteTextRenderingTestsTypingMetricsAndAlignment.aligned)
    private func alignedPlaceholdersLineUpWithTheText(sample: AlignmentCase) {
        let presentation = sample.presentation
        let placeholder = NoteTextRendering.placeholder("Type here", presentation)
        #expect((placeholder.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == presentation.alignment)
    }

    private func centredAndPlain() -> (NoteTextPresentation, NoteTextPresentation) {
        let centered = NoteTextPresentation(role: .tableCell, alignment: .center)
        var plain = centered
        plain.alignment = .natural
        return (centered, plain)
    }

    @Test func alignmentNeverChangesTheLineHeight() {
        let (centered, plain) = centredAndPlain()
        #expect(NoteTextRendering.lineHeight(centered) == NoteTextRendering.lineHeight(plain))
    }

    @Test func alignmentNeverChangesTheFont() {
        let (centered, plain) = centredAndPlain()
        #expect(NoteTextRendering.font(for: .plain, centered) == NoteTextRendering.font(for: .plain, plain))
    }

    @Test func alignmentIsPartOfThePresentationSoViewsRefresh() {
        let (centered, plain) = centredAndPlain()
        #expect(centered != plain)
    }

    @Test func centredTextLaysOutInTheMiddle() {
        let attributed = NoteTextRendering.attributedString("Middle", centredAndPlain().0)
        let width: CGFloat = 300
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: 1000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let glyphs = manager.boundingRect(forGlyphRange: manager.glyphRange(for: container), in: container)
        #expect(abs(glyphs.midX - width / 2) < 2)
    }
}
