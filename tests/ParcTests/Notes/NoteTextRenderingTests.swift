import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteTextRenderingTests {
    typealias Blocks = NoteEditorBlocks

    init() { NoteEditorFixtures.useMathFont() }

    func roundTrip(_ text: NoteText, in presentation: NoteTextPresentation = NoteTextPresentation()) {
        let attributed = NoteTextRendering.attributedString(text, presentation)
        #expect(attributed.length == text.length)
        #expect(NoteTextRendering.noteText(from: attributed) == text)
    }

    @Test func emptyTextSurvivesTheRoundTrip() { roundTrip(NoteText()) }

    @Test func plainTextSurvivesTheRoundTrip() { roundTrip("Plain words") }

    @Test func aSoftLineBreakSurvivesTheRoundTrip() { roundTrip("Two\nlines") }

    @Test func emojiAndAccentsSurviveTheRoundTrip() { roundTrip("Emoji 👩🏽‍💻 and ünïcode") }

    @Test func everyMarkSurvivesTheRoundTrip() {
        let link = Blocks.marks { $0.link = "https://parc.app" }
        let red = Blocks.marks { $0.color = .text(.red) }
        let highlight = Blocks.marks { $0.color = .background(.yellow) }
        let everything = Blocks.marks { $0.bold = true; $0.italic = true; $0.underline = true; $0.strikethrough = true }
        let code = Blocks.marks { $0.code = true }
        roundTrip(NoteText(pieces: [("Bold ", Blocks.bold), ("italic ", Blocks.italic), ("all ", everything), ("code", code),
                                    (" link", link), (" red", red), (" glow", highlight)]))
    }

    @Test func mergedRunsSurviveTheRoundTrip() {
        roundTrip(NoteText(pieces: [("same ", Blocks.bold), ("same", Blocks.bold)]))
    }

    @Test func everyAtomIncludingIdenticalNeighboursSurvivesTheRoundTrip() {
        let date = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true)
        let atoms = NoteText.atom(.equation("x^2")) + NoteText.atom(.equation("x^2")) + NoteText(" ")
            + NoteText.atom(.page(target: "Other.md", title: "Other")) + NoteText.atom(.date(date))
            + NoteText.atom(.link(url: "https://parc.app", title: "Parc")) + NoteText.atom(.raw("<kbd>K</kbd>"))
            + NoteText.atom(.equation("y"), marks: Blocks.bold)
        roundTrip(atoms)
    }

    @Test func aRawObjectCharacterWithoutAnAtomSurvivesTheRoundTrip() { roundTrip(NoteText("Stray \u{FFFC} object")) }

    @Test func aLinkAcrossMarksSurvivesTheRoundTrip() {
        let link = Blocks.marks { $0.link = "https://parc.app" }
        roundTrip(NoteText(pieces: [("linked ", link), ("bold link", Blocks.marks { $0.link = "https://parc.app"; $0.bold = true })]))
    }

    @Test func aCheckedTodoSurvivesTheRoundTrip() {
        let red = Blocks.marks { $0.color = .text(.red) }
        roundTrip(NoteText(pieces: [("done ", Blocks.bold), ("red", red)]), in: NoteTextPresentation(completed: true))
    }

    @Test func aHeadingSurvivesTheRoundTrip() {
        roundTrip("Heading", in: NoteTextPresentation(role: .heading(1)))
    }

    @Test func atomsRenderAsAttachments() {
        let attributed = NoteTextRendering.attributedString(NoteText.atom(.page(target: "a.md", title: "A")), NoteTextPresentation())
        #expect(attributed.attribute(.attachment, at: 0, effectiveRange: nil) is NoteAtomAttachment)
    }

    func styled() -> NSAttributedString {
        NoteTextRendering.attributedString(NoteText(pieces: [("x", Blocks.marks { $0.code = true }), ("y", Blocks.marks { $0.color = .background(.yellow) })]),
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

    func emojiBesideAnAtom() -> NoteText {
        let equation = Blocks.marks { $0.atom = .equation("x") }
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

    let base: NoteText = "Hello world"
    let committed: NoteText = "Hello 世界 world"

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

    func makeTextView(_ presentation: NoteTextPresentation, width: CGFloat) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.textContainer?.replaceLayoutManager(NoteLayoutManager())
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        view.isRichText = true
        view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
        return view
    }

    @Test func typedTextKeepsItsMarks() {
        let presentation = NoteTextPresentation()
        let view = makeTextView(presentation, width: 300)
        view.textStorage?.setAttributedString(NoteTextRendering.attributedString(NoteText(pieces: [("Hi ", .plain)]), presentation))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.typingAttributes = NoteTextRendering.typingAttributes(Blocks.bold, presentation)
        view.insertText("there", replacementRange: view.selectedRange())
        view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
        view.insertText("\n!", replacementRange: view.selectedRange())
        #expect(NoteTextRendering.noteText(from: view.textStorage!) == NoteText(pieces: [("Hi ", .plain), ("there", Blocks.bold), ("\n!", .plain)]))
    }

    @Test func typingNeverInheritsAnAtom() {
        let pending = NoteTextRendering.typingAttributes(NoteMarks(atom: .equation("x")), NoteTextPresentation())
        #expect((pending[.noteMarks] as? NoteMarksValue)?.marks.atom == nil)
    }

    struct Measurement: @unchecked Sendable, CustomTestStringConvertible {
        let presentation: NoteTextPresentation
        let presentationName: String
        let width: CGFloat
        let sample: NoteText

        var testDescription: String { "\(sample.string.debugDescription) at \(width) as \(presentationName)" }
    }

    nonisolated static let measurements: [Measurement] = {
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

    @Test(arguments: NoteTextRenderingTests.measurements)
    func measuredHeightMatchesTheLiveView(measurement: Measurement) {
        let presentation = measurement.presentation
        let lineHeight = NoteTextRendering.lineHeight(presentation)
        let view = makeTextView(presentation, width: measurement.width)
        view.textStorage?.setAttributedString(NoteTextRendering.attributedString(measurement.sample, presentation))
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        let live = max(lineHeight, ceil(view.layoutManager!.usedRect(for: view.textContainer!).height))
        #expect(NoteTextRendering.height(of: measurement.sample, presentation, width: measurement.width) == live)
    }

    @Test(arguments: NoteTextRenderingTests.measurements)
    func singleLinesStayOnTheLineHeightGrid(measurement: Measurement) {
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
        #expect(NoteTextPresentation(block: Blocks.todo("x", checked: true), settings: NotePageSettings()).completed)
    }

    @Test func completedTextIsStruckThroughAndFades() {
        let done = NoteTextPresentation(block: Blocks.todo("x", checked: true), settings: NotePageSettings())
        let attributes = NoteTextRendering.attributes(for: .plain, done)
        #expect(attributes[.strikethroughStyle] != nil)
        #expect((attributes[.foregroundColor] as? NSColor) == NoteTheme.todoDoneInk)
    }

    @Test func pageSettingsReachThePresentation() {
        var settings = NotePageSettings()
        settings.smallText = true
        settings.font = .serif
        let small = NoteTextPresentation(block: Blocks.para("x"), settings: settings)
        #expect(small.small)
        #expect(small.pageFont == .serif)
    }

    @Test func boldKeepsTheBodySize() {
        #expect(NoteTextRendering.font(for: Blocks.bold, NoteTextPresentation()).pointSize == NoteTextRendering.font(for: .plain, NoteTextPresentation()).pointSize)
    }

    @Test func inlineCodeIsATouchSmaller() {
        let code = NoteTextRendering.font(for: Blocks.marks { $0.code = true }, NoteTextPresentation())
        #expect(code.pointSize < NoteTextRendering.font(for: .plain, NoteTextPresentation()).pointSize)
    }

    @Test func textStartsNaturallyAligned() {
        #expect(NoteTextPresentation().alignment == .natural)
    }

    static let aligned: [(NoteTextPresentation, String)] = [
        (NoteTextPresentation(role: .tableCell, alignment: .center), "centred"),
        (NoteTextPresentation(role: .tableHeader, small: true, alignment: .right), "right-aligned"),
    ]

    var equation: NoteText { NoteText("Total ") + NoteText.atom(.equation("x^2")) + NoteText(" done", marks: Blocks.bold) }

    @Test(arguments: [0, 1])
    func alignedTextSurvivesTheRoundTrip(index: Int) {
        roundTrip("Two\nlines", in: Self.aligned[index].0)
    }

    @Test(arguments: [0, 1])
    func alignedTextWithAnEquationSurvivesTheRoundTrip(index: Int) {
        roundTrip(equation, in: Self.aligned[index].0)
    }

    @Test(arguments: [0, 1])
    func alignedRunsAllShareTheAlignment(index: Int) {
        let presentation = Self.aligned[index].0
        let attributed = NoteTextRendering.attributedString(equation, presentation)
        var alignments = Set<Int>()
        attributed.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            alignments.insert((value as? NSParagraphStyle)?.alignment.rawValue ?? -1)
        }
        #expect(alignments == [presentation.alignment.rawValue])
    }

    @Test(arguments: [0, 1])
    func alignedTypingKeepsTheAlignment(index: Int) {
        let presentation = Self.aligned[index].0
        let typing = NoteTextRendering.typingAttributes(Blocks.bold, presentation)
        #expect((typing[.paragraphStyle] as? NSParagraphStyle)?.alignment == presentation.alignment)
    }

    @Test(arguments: [0, 1])
    func alignedPlaceholdersLineUpWithTheText(index: Int) {
        let presentation = Self.aligned[index].0
        let placeholder = NoteTextRendering.placeholder("Type here", presentation)
        #expect((placeholder.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == presentation.alignment)
    }

    func centredAndPlain() -> (NoteTextPresentation, NoteTextPresentation) {
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

    @MainActor struct Artworks {
        let inline: (markup: String, size: CGSize)
        let display: (markup: String, size: CGSize)
    }

    func svgs() throws -> Artworks {
        let inline = try #require(NotePageEquationArtwork.svg("x^2 + y^2 = z^2", display: false))
        let display = try #require(NotePageEquationArtwork.svg("\\frac{a}{b} = c", display: true))
        return Artworks(inline: (inline.markup, inline.size), display: (display.markup, display.size))
    }

    @Test func artworkCarriesLightAndDarkInk() throws {
        let markup = try svgs().inline.markup
        #expect(markup.hasPrefix("<svg "))
        #expect(markup.contains("prefers-color-scheme:dark"))
    }

    @Test func artworkEmbedsALightAndADarkRendering() throws {
        #expect(try svgs().inline.markup.components(separatedBy: "data:image/png;base64,").count == 3)
    }

    @Test func inlineArtworkHasARealSize() throws {
        let size = try svgs().inline.size
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    @Test func inlineArtworkPadsAroundTheMathsNeverCroppingIt() throws {
        let fontSize = NotePageEquationArtwork.fontSize(display: false)
        let rendering = NoteMathRenderer.render("x^2 + y^2 = z^2", fontSize: fontSize, color: .black, display: false)
        #expect(try svgs().inline.size.height >= ceil(rendering.size.height))
    }

    @Test func displayMathsIsBiggerThanInlineMaths() throws {
        let pair = try svgs()
        #expect(pair.display.size.height > pair.inline.size.height)
        #expect(NotePageEquationArtwork.fontSize(display: true) > NotePageEquationArtwork.fontSize(display: false))
    }

    @Test(arguments: ["   ", "\\frac{"])
    func blankAndBrokenEquationsFallBackToTheirSource(source: String) {
        #expect(NotePageEquationArtwork.svg(source, display: false) == nil)
    }

    @Test func artworkBecomesAPercentEncodedSvgDataURL() throws {
        let url = try #require(NotePageEquationArtwork.art("e^{i\\pi} + 1 = 0", display: true)?.url)
        #expect(url.absoluteString.hasPrefix("data:image/svg+xml;charset=utf-8,%3Csvg"))
        #expect(url.absoluteString.removingPercentEncoding?.contains("width=") == true)
    }

    func mathPage() -> NotePage {
        NotePage(blocks: [NoteBlock(.equation, text: "a^2"), .paragraph(NoteText("Area ") + NoteText.atom(.equation("\\pi r^2")))])
    }

    func exportedHTML(_ page: NotePage) -> String {
        NotePageHTML.document(page, title: "Maths", assets: { _ in nil }, embedImages: true,
                              equationArt: { tex, display, numbering in NotePageEquationArtwork.art(tex, display: display, numbering: numbering) })
    }

    @Test func exportedHtmlTypesetsBlockAndInlineEquations() {
        #expect(exportedHTML(mathPage()).components(separatedBy: "data:image/svg+xml").count == 3)
    }

    @Test func noRawTexIsLeftBehindWhenArtworkRenders() {
        #expect(!exportedHTML(mathPage()).contains("<span class=\"tex\">"))
    }

    @Test func inlineArtworkKeepsItsOwnSizeInTheStylesheet() {
        #expect(exportedHTML(mathPage()).contains("img.equation{vertical-align:middle;max-width:100%}"))
    }

    @MainActor struct Numbered {
        let labelled = NoteBlock(.equation, text: "\\begin{equation} E = mc^2 \\label{energy} \\end{equation}")
        let page: NotePage
        let numbering: NotePageMathNumbering

        init() {
            page = NotePage(blocks: [NoteBlock(.equation, text: "\\begin{equation} a \\end{equation}"), labelled,
                                     .paragraph(NoteText("See ") + NoteText.atom(.equation("\\eqref{energy}")))])
            numbering = NotePageMathNumberer().numbering(for: page)
        }
    }

    @Test func aResolvedReferenceCarriesALinkRectangle() throws {
        let numbered = Numbered()
        let reference = try #require(NotePageEquationArtwork.art("\\eqref{energy}", display: false, numbering: numbered.numbering.inlineContext))
        let link = try #require(reference.links.first)
        #expect(link.key == "energy")
        #expect(link.rect.width > 0)
        #expect(link.rect.height > 0)
    }

    @Test func danglingReferencesStayUnlinked() {
        #expect(NotePageEquationArtwork.art("\\eqref{nowhere}", display: false)?.links.isEmpty == true)
    }

    @Test func artworkDrawsTheNoteWideNumberNotOne() {
        let numbered = Numbered()
        let plain = NotePageEquationArtwork.art(numbered.labelled.text.string, display: true)?.url
        let renumbered = NotePageEquationArtwork.art(numbered.labelled.text.string, display: true, numbering: numbered.numbering.context(for: numbered.labelled.id))?.url
        #expect(plain != nil)
        #expect(renumbered != nil)
        #expect(plain != renumbered)
    }

    @Test func exportedReferencesLinkToTheirEquation() {
        let exported = exportedHTML(Numbered().page)
        #expect(exported.contains("id=\"eq-energy\""))
        #expect(exported.contains("href=\"#eq-energy\""))
        #expect(exported.contains("usemap=\"#equation-links-"))
    }

    func listPage() -> NotePage {
        NotePage(blocks: [
            Blocks.numbered("one"), Blocks.numbered("two", [Blocks.numbered("a"), Blocks.numbered("b", [Blocks.numbered("i"), Blocks.numbered("ii")])]),
            Blocks.numbered("three"), Blocks.para("break"), Blocks.numbered("again", start: 5), Blocks.numbered("six"),
            Blocks.bullet("dot", [Blocks.bullet("ring", [Blocks.bullet("square", [Blocks.bullet("dot again")])])]),
        ])
    }

    @Test(arguments: [
        ([0], "1."), ([1], "2."), ([1, 0], "a."), ([1, 1], "b."), ([1, 1, 0], "i."), ([1, 1, 1], "ii."), ([2], "3."), ([4], "5."), ([5], "6."),
        ([6], "•"), ([6, 0], "◦"), ([6, 0, 0], "▪"), ([6, 0, 0, 0], "•"),
    ] as [([Int], String)])
    func listMarkersCountUpAndCycle(path: [Int], expected: String) {
        let page = listPage()
        var list = page.blocks
        var found: NoteBlock?
        for index in path {
            found = list[index]
            list = list[index].children
        }
        #expect(found.flatMap { NoteListMarker.label(for: $0, in: page) } == expected)
    }

    @Test(arguments: [(27, 1, "aa."), (4, 2, "iv.")] as [(Int, Int, String)])
    func numberLabelsRollOverAndUseRomanNumerals(number: Int, level: Int, expected: String) {
        #expect(NoteListMarker.numberLabel(number, level: level) == expected)
    }

    @Test func parenthesisDelimitersShow() {
        #expect(NoteListMarker.numberLabel(3, level: 0, delimiter: ")") == "3)")
    }

    static let dateNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
    }()

    func dateLabel(_ mention: NoteDateMention) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return NoteAtomRendering.dateLabel(mention, now: Self.dateNow, calendar: calendar, locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test(arguments: [
        (NoteDateMention(year: 2026, month: 11, day: 20), "Today"), (NoteDateMention(year: 2026, month: 11, day: 21), "Tomorrow"),
        (NoteDateMention(year: 2026, month: 11, day: 19), "Yesterday"), (NoteDateMention(year: 2026, month: 12, day: 25), "December 25, 2026"),
        (NoteDateMention(year: 2027, month: 1, day: 12), "January 12, 2027"),
        (NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 5), "Tomorrow 3:05 PM"),
    ] as [(NoteDateMention, String)])
    func dateMentionsReadInPlainWords(mention: NoteDateMention, expected: String) {
        #expect(dateLabel(mention) == expected)
    }

    func overdue(_ mention: NoteDateMention) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return NoteAtomRendering.isOverdue(mention, now: Self.dateNow, calendar: calendar)
    }

    @Test func aPastTimeIsOverdue() {
        #expect(overdue(NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 0)))
    }

    @Test func tomorrowIsNotOverdue() {
        #expect(!overdue(NoteDateMention(year: 2026, month: 11, day: 21)))
    }

    @Test func anAllDayReminderIsDueOnItsDay() {
        #expect(overdue(NoteDateMention(year: 2026, month: 11, day: 20)))
    }
}
