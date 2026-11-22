import AppKit
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteTextRenderingTestsEquationArtworkListsAndDates {
    private struct ListPathCase: Sendable, CustomTestStringConvertible {
        let path: [Int]
        let expected: String

        var testDescription: String { "\(path)" }
    }

    private struct ListNumberCase: Sendable, CustomTestStringConvertible {
        let number: Int
        let level: Int
        let expected: String

        var testDescription: String { "item \(number) at level \(level)" }
    }

    private struct DateLabelCase: @unchecked Sendable, CustomTestStringConvertible {
        let mention: NoteDateMention
        let expected: String

        var testDescription: String { expected }
    }

    init() { NoteEditorFixtures.useMathFont() }

    @MainActor private struct Artworks {
        let inline: (markup: String, size: CGSize)
        let display: (markup: String, size: CGSize)
    }

    private func svgs() throws -> Artworks {
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

    @Test func displayArtworkIsTallerThanInlineArtwork() throws {
        let pair = try svgs()
        #expect(pair.display.size.height > pair.inline.size.height)
    }

    @Test func displayArtworkUsesALargerFont() throws {
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

    private func mathPage() -> NotePage {
        NotePage(blocks: [NoteBlock(.equation, text: "a^2"), .paragraph(NoteText("Area ") + NoteText.atom(.equation("\\pi r^2")))])
    }

    private func exportedHTML(_ page: NotePage) -> String {
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

    @MainActor private struct Numbered {
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

    private func listPage() -> NotePage {
        NotePage(blocks: [
            NoteEditorBlocks.numbered("one"), NoteEditorBlocks.numbered("two", [NoteEditorBlocks.numbered("a"), NoteEditorBlocks.numbered("b", [NoteEditorBlocks.numbered("i"), NoteEditorBlocks.numbered("ii")])]),
            NoteEditorBlocks.numbered("three"), NoteEditorBlocks.para("break"), NoteEditorBlocks.numbered("again", start: 5), NoteEditorBlocks.numbered("six"),
            NoteEditorBlocks.bullet("dot", [NoteEditorBlocks.bullet("ring", [NoteEditorBlocks.bullet("square", [NoteEditorBlocks.bullet("dot again")])])]),
        ])
    }

    @Test(arguments: [
        ListPathCase(path: [0], expected: "1."),
        ListPathCase(path: [1], expected: "2."),
        ListPathCase(path: [1, 0], expected: "a."),
        ListPathCase(path: [1, 1], expected: "b."),
        ListPathCase(path: [1, 1, 0], expected: "i."),
        ListPathCase(path: [1, 1, 1], expected: "ii."),
        ListPathCase(path: [2], expected: "3."),
        ListPathCase(path: [4], expected: "5."),
        ListPathCase(path: [5], expected: "6."),
        ListPathCase(path: [6], expected: "•"),
        ListPathCase(path: [6, 0], expected: "◦"),
        ListPathCase(path: [6, 0, 0], expected: "▪"),
        ListPathCase(path: [6, 0, 0, 0], expected: "•"),
    ])
    private func listMarkersCountUpAndCycle(sample: ListPathCase) {
        let page = listPage()
        var list = page.blocks
        var found: NoteBlock?
        for index in sample.path {
            found = list[index]
            list = list[index].children
        }
        #expect(found.flatMap { NoteListMarker.label(for: $0, in: page) } == sample.expected)
    }

    @Test(arguments: [
        ListNumberCase(number: 27, level: 1, expected: "aa."),
        ListNumberCase(number: 4, level: 2, expected: "iv."),
    ])
    private func numberLabelsRollOverAndUseRomanNumerals(sample: ListNumberCase) {
        #expect(NoteListMarker.numberLabel(sample.number, level: sample.level) == sample.expected)
    }

    @Test func parenthesisDelimitersShow() {
        #expect(NoteListMarker.numberLabel(3, level: 0, delimiter: ")") == "3)")
    }

    private static let dateNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
    }()

    private func dateLabel(_ mention: NoteDateMention) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return NoteAtomRendering.dateLabel(mention, now: Self.dateNow, calendar: calendar, locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test(arguments: [
        DateLabelCase(mention: NoteDateMention(year: 2026, month: 11, day: 20), expected: "Today"),
        DateLabelCase(mention: NoteDateMention(year: 2026, month: 11, day: 21), expected: "Tomorrow"),
        DateLabelCase(mention: NoteDateMention(year: 2026, month: 11, day: 19), expected: "Yesterday"),
        DateLabelCase(mention: NoteDateMention(year: 2026, month: 12, day: 25), expected: "December 25, 2026"),
        DateLabelCase(mention: NoteDateMention(year: 2027, month: 1, day: 12), expected: "January 12, 2027"),
        DateLabelCase(mention: NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 5), expected: "Tomorrow 3:05 PM"),
    ])
    private func dateMentionsReadInPlainWords(sample: DateLabelCase) {
        #expect(dateLabel(sample.mention) == sample.expected)
    }

    private func overdue(_ mention: NoteDateMention) -> Bool {
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
