import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteDesignSystemTestsTypographyAndControls {
    private struct SyntaxFamilyCase: Sendable, CustomTestStringConvertible {
        let name: String
        let family: String

        var testDescription: String { "\(name)" }
    }

    private init() { NoteEditorFixtures.registerFonts() }

    private func sampleItems() -> [NoteMenuList.Item] {
        [
            .init(id: "text", title: "Text", icon: .glyph("Aa"), section: "Basic blocks"),
            .init(id: "h1", title: "Heading 1", icon: .glyph("H1"), shortcut: "#", section: "Basic blocks", keywords: ["title"]),
            .init(id: "todo", title: "To-do List", icon: .symbol("checkmark.square"), section: "Basic blocks", keywords: ["checkbox", "task"]),
            .init(id: "image", title: "Image", section: "Media", isEnabled: false),
            .init(id: "video", title: "Video", section: "Media"),
            .init(id: "delete", title: "Delete", shortcut: "Delete", separatorBefore: true),
        ]
    }

    @Test func coloursAreCached() {
        #expect(NoteTheme.color(.text(.red)) === NoteTheme.color(.text(.red)))
    }

    @Test(arguments: [
        SyntaxFamilyCase(name: "keyword.control", family: "keyword"),
        SyntaxFamilyCase(name: "stringLiteral", family: "string"),
        SyntaxFamilyCase(name: "comment", family: "comment"),
        SyntaxFamilyCase(name: "whatever", family: "plain"),
    ])
    private func syntaxNamesMapToFamilies(sample: SyntaxFamilyCase) {
        #expect(NoteTheme.syntaxFamily(sample.name) == sample.family)
    }

    @Test func commentsAreItalic() {
        #expect(NoteTheme.syntaxIsItalic("comment"))
    }

    nonisolated private static let syntaxFamilies: [NoteSyntaxKind: String] = [
        .keyword: "keyword", .type: "type", .string: "string", .number: "number", .comment: "comment", .function: "function",
        .property: "attribute", .operatorSymbol: "operator", .punctuation: "operator", .tag: "tag", .attribute: "attribute",
        .variable: "variable", .constant: "number", .regex: "escape", .builtin: "type", .inserted: "string", .deleted: "tag",
        .heading: "heading", .emphasis: "emphasis", .strong: "strong", .link: "link", .meta: "meta", .escape: "escape",
    ]

    @Test(arguments: NoteSyntaxKind.allCases)
    func everySyntaxKindHasItsOwnFamily(kind: NoteSyntaxKind) {
        #expect(NoteTheme.syntaxFamily(kind.rawValue) == Self.syntaxFamilies[kind])
    }

    @Test func codeEmphasisIsItalic() {
        #expect(NoteTheme.syntaxIsItalic(.emphasis))
    }

    @Test func codeStrongTextIsBold() {
        #expect(NoteTheme.syntaxIsBold(.strong))
    }

    @Test func codeLinksAreUnderlined() {
        #expect(NoteTheme.syntaxIsUnderlined(.link))
    }

    @Test func headingPlaceholdersNameTheirLevel() {
        #expect(NoteTheme.placeholder(for: .heading, level: 2) == "Heading 2")
    }

    @Test func wideWindowsKeepTheColumn() {
        #expect(NoteTheme.contentWidth(forViewport: 1200) == NoteTheme.pageColumnWidth)
    }

    @Test func narrowWindowsKeepTheMargins() {
        #expect(NoteTheme.contentWidth(forViewport: 500) == 500 - NoteTheme.minimumSideMargin * 2)
    }

    @Test func bodyLineHeightComesFromTheRatio() {
        #expect(NoteTheme.textStyle(.body).lineHeight == (NoteTheme.bodySize * NoteTheme.lineHeightRatio).rounded())
    }

    @Test func headingsStepDown() {
        #expect(NoteTheme.textStyle(.heading(1)).font.pointSize > NoteTheme.textStyle(.heading(3)).font.pointSize)
    }

    @Test func inlineCodeSitsOnTheBodyBaseline() {
        #expect(NoteTheme.textStyle(.inlineCode).baselineOffset == NoteTheme.textStyle(.body).baselineOffset)
    }

    @Test func runAttributesLeaveTheParagraphAlone() {
        #expect(NoteTheme.textStyle(.inlineCode).runAttributes[.paragraphStyle] == nil)
    }

    @Test(arguments: NotePageFont.allCases)
    func titlesBeatBodyTextInEveryPageFont(font: NotePageFont) {
        #expect(NoteTheme.titleFont(font, small: false).pointSize > NoteTheme.bodyFont(font).pointSize)
    }

    @Test(arguments: NotePageFont.allCases)
    func italicsKeepTheirSize(font: NotePageFont) {
        #expect(abs(NoteTheme.bodyFont(font, italic: true).pointSize - NoteTheme.bodyFont(font).pointSize) < 0.01)
    }

    @Test(arguments: NotePageFont.allCases)
    func italicsStayCloseToUprightWidth(font: NotePageFont) {
        func width(_ face: NSFont) -> CGFloat { NSAttributedString(string: "Slanted words", attributes: [.font: face]).size().width }
        #expect(width(NoteTheme.bodyFont(font, italic: true)) < width(NoteTheme.bodyFont(font)) * 1.3)
    }

    @Test(arguments: NotePageFont.allCases)
    func italicsActuallyLean(font: NotePageFont) {
        let italic = NoteTheme.bodyFont(font, italic: true)
        #expect(italic.fontDescriptor.symbolicTraits.contains(.italic) || italic.matrix[2] > 0.1)
    }

    @Test func theSerifPageFontIsEBGaramond() {
        #expect(NoteTheme.bodyFont(.serif).fontName.contains("Garamond"))
    }

    private func boldButton() -> NoteToolbarButton { NoteToolbarButton(icon: .glyph("B"), label: "Bold", shortcut: "⌘B") }

    @Test func iconButtonsAreSquare() {
        #expect(boldButton().frame.size == NoteTheme.toolbarButtonSize)
    }

    @Test func toolbarButtonsLeaveFocusInTheText() {
        #expect(!boldButton().acceptsFirstResponder)
    }

    @Test func theTooltipCarriesTheShortcut() {
        guard case .fixed(let shortcut)? = boldButton().parcTooltip?.shortcut else {
            Issue.record("the tooltip carries the shortcut")
            return
        }
        #expect(shortcut == KeyboardShortcut(key: "b", flags: .command))
    }

    @Test func accessibilityPressActivates() {
        let button = boldButton()
        var pressed = 0
        button.onPress = { pressed += 1 }
        #expect(button.accessibilityPerformPress())
        #expect(pressed == 1)
    }

    @Test func disabledButtonsDim() {
        let button = boldButton()
        button.isEnabled = false
        #expect(button.alphaValue == NoteTheme.disabledOpacity)
    }

    @Test func disabledButtonsRefuseAccessibilityPress() {
        let button = boldButton()
        button.isEnabled = false
        #expect(!button.accessibilityPerformPress())
    }

    @Test func textButtonsFitTheirLabel() {
        let text = NoteToolbarButton(.text("Text"), label: "Turn into")
        text.showsDisclosure = true
        #expect(text.intrinsicContentSize.width > NoteTheme.toolbarButtonSize.width)
    }

    @Test func chipsHaveTheirOwnHeight() {
        #expect(NoteChip("Add icon", icon: .symbol("face.smiling")).intrinsicContentSize.height == NoteTheme.chipHeight)
    }

    @Test func flashingAnnouncesTheNewLabel() {
        let chip = NoteChip("Add icon", icon: .symbol("face.smiling"))
        chip.flash("Copied!")
        #expect(chip.accessibilityLabel() == "Copied!")
    }

    @Test func theSearchFieldFiltersABoundMenu() {
        let field = NoteSearchField(placeholder: "Search")
        let list = NoteMenuList(items: sampleItems())
        field.bind(to: list)
        field.onChange?("vid")
        #expect(list.visibleItems.map(\.id) == ["video"])
    }

    @Test func arrowsReachTheBoundMenu() {
        let field = NoteSearchField(placeholder: "Search")
        let list = NoteMenuList(items: sampleItems())
        field.bind(to: list)
        field.onChange?("vid")
        #expect(field.onCommand?(#selector(NSResponder.moveDown(_:))) == true)
        #expect(list.highlightedItem?.id == "video")
    }
}
