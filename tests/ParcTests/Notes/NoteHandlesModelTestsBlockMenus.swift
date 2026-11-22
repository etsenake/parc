import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteHandlesModelTestsBlockMenus {
    private func yellowParagraph() -> NoteBlock {
        var paragraph = NoteBlock.paragraph("Hello there")
        paragraph.color = .background(.yellow)
        return paragraph
    }

    @Test func aParagraphGetsNotionsOrderWithoutBlockLinks() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)) == ["delete", "duplicate", "turn", "move", "color"])
    }

    @Test func deleteShowsABackspaceKeycap() {
        let delete = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[0]
        #expect(delete.shortcut == "⌫")
    }

    @Test func deleteIsDestructive() {
        let delete = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[0]
        #expect(delete.isDestructive)
    }

    @Test func duplicateShowsCommandD() {
        #expect(NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[1].shortcut == "⌘D")
    }

    @Test func moveToDisplaysItsShortcut() {
        let move = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[3]
        #expect(move.shortcut == "⇧⌘P")
    }

    @Test func moveToHasANotePickerSubmenu() {
        let move = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[3]
        #expect(move.hasSubmenu)
    }

    @Test func turnIntoChecksTheParagraphsOwnType() {
        let turn = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[2].children
        #expect(turn.first?.title == "Text")
        #expect(turn.first?.isChecked == true)
        #expect(turn.filter(\.isChecked).count == 1)
    }

    @Test func turnIntoCoversToggleHeadingsAndEquations() {
        let turn = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[2].children
        #expect(turn.contains { $0.title == "Toggle Heading 2" })
        #expect(turn.contains { $0.title == "Block Equation" })
    }

    @Test func colourHasTenTextColoursAndTenBackgrounds() {
        #expect(NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[4].children.count == 20)
    }

    @Test func theBlocksBackgroundIsChecked() {
        #expect(NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[4].children.filter(\.isChecked).map(\.id) == ["color.background.yellow"])
    }

    @Test func defaultTextClearsTheColour() {
        let colors = NoteHandlesModelTestsSupport.menu([yellowParagraph()], canMoveToNotes: true)[4].children
        #expect(colors.first?.action == .color(nil))
        #expect(colors.first?.section == "Text Color")
    }

    @Test func aToggleHeadingChecksItsToggleStyle() {
        var heading = NoteBlock.heading(2, "Plan")
        heading.props.toggleable = true
        #expect(NoteHandlesModelTestsSupport.menu([heading])[2].children.filter(\.isChecked).map(\.title) == ["Toggle Heading 2"])
    }

    @Test func blockLinksAppearWhenTheFormatCanAnchorThem() {
        let linked = NoteHandlesModelTestsSupport.menu([yellowParagraph()], supportsBlockLinks: true)
        #expect(NoteHandlesModelTestsSupport.ids(linked).contains("link"))
        #expect(linked.first { $0.id == "link" }?.shortcut == "⌃⌘L")
    }

    @Test func rawHtmlGetsNoBlockLink() {
        #expect(!NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([NoteBlock(.html, text: "<div></div>")], supportsBlockLinks: true)).contains("link"))
    }

    @Test func codeCanLinkToABlock() {
        #expect(NoteBlockMenuModel.linkable(NoteBlock(.code)))
    }

    @Test func aBareColumnCannotLinkToABlock() {
        #expect(!NoteBlockMenuModel.linkable(NoteBlock(.column)))
    }

    @Test func aLockedPageOnlyOffersTheLink() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([yellowParagraph()], isReadOnly: true, canMoveToNotes: true, supportsBlockLinks: true)) == ["link"])
    }

    private func codeBlock() -> NoteBlock {
        var code = NoteBlock(.code, text: "print(1)")
        code.props.language = "Python"
        code.props.wrap = true
        return code
    }

    @Test func codeGetsLanguageAndWrapButNoColour() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([codeBlock()])) == ["delete", "duplicate", "turn", "language", "wrap"])
    }

    @Test func theLanguageRowNamesTheCurrentLanguage() {
        let language = NoteHandlesModelTestsSupport.menu([codeBlock()])[3]
        #expect(language.subtitle == "Python")
    }

    @Test func theLanguageSubmenuChecksTheCurrentLanguage() {
        let language = NoteHandlesModelTestsSupport.menu([codeBlock()])[3]
        #expect(language.children.filter(\.isChecked).map(\.title) == ["Python"])
    }

    @Test func wrapCodeShowsItsState() {
        #expect(NoteHandlesModelTestsSupport.menu([codeBlock()])[4].isChecked)
    }

    @Test func turnIntoChecksCode() {
        #expect(NoteHandlesModelTestsSupport.menu([codeBlock()])[2].children.first { $0.title == "Code" }?.isChecked == true)
    }

    private func image(source: String? = "Attachments/cat.png") -> NoteBlock {
        var image = NoteBlock(.image)
        image.props.source = source
        image.props.alignment = .left
        return image
    }

    @Test func imagesGetAlignmentCropMaskAltTextDownloadAndTheOriginal() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([image()], canMoveToNotes: true)) == ["delete", "duplicate", "align", "crop", "mask", "alt", "download", "original", "move"])
    }

    @Test func theImagesAlignmentIsChecked() {
        #expect(NoteHandlesModelTestsSupport.menu([image()], canMoveToNotes: true)[2].children.filter(\.isChecked).map(\.title) == ["Left"])
    }

    @Test func anEmptyImageHasNothingToDownload() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([NoteBlock(.image)])) == ["delete", "duplicate", "align"])
    }

    private func pdf(_ kind: NoteBlockKind, _ source: String) -> NoteBlock {
        var block = NoteBlock(kind)
        block.props.source = source
        return block
    }

    @Test func pdfsGetTurnIntoAlignmentDownloadTheOriginalAndFullScreen() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([pdf(.pdf, "Attachments/report.pdf")], canMoveToNotes: true))
                == ["delete", "duplicate", "turn", "align", "download", "original", "fullScreen", "move"])
    }

    @Test func pdfsTurnIntoFileRowsAndBack() {
        let entries = NoteHandlesModelTestsSupport.menu([pdf(.pdf, "Attachments/report.pdf")], canMoveToNotes: true)
        #expect(entries.first { $0.id == "turn" }?.children.map(\.id) == ["turn.pdf", "turn.file"])
    }

    @Test func aPdfFileRowCanTurnIntoAPdf() {
        let entries = NoteHandlesModelTestsSupport.menu([pdf(.file, "Attachments/report.pdf")])
        #expect(entries.first { $0.id == "turn" }?.children.first { $0.isChecked }?.id == "turn.file")
    }

    @Test func otherFilesCannotBecomePdfs() {
        #expect(!NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([pdf(.file, "Attachments/a.zip")])).contains("turn"))
    }

    @Test func bookmarksCopyAndOpenTheOriginalLink() {
        var bookmark = NoteBlock(.bookmark)
        bookmark.props.source = "https://parcbrowser.com"
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([bookmark])) == ["delete", "duplicate", "copyOriginal", "original"])
    }

    @Test func dividersCanOnlyGoAwayDoubleOrMove() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([NoteBlock(.divider)], canMoveToNotes: true)) == ["delete", "duplicate", "move"])
    }

    private func tableMenu(isReadOnly: Bool = false) -> [NoteBlockMenuEntry] {
        var tableProps = NoteBlockProps()
        tableProps.table = .empty()
        let items = [NoteBlockMenuEntry(id: "table.headerRow", title: "Header Row", isChecked: true, action: .tableItem("table.headerRow")),
                     NoteBlockMenuEntry(id: "table.fitWidth", title: "Fit to Width", isEnabled: false, action: .tableItem("table.fitWidth"))]
        return NoteHandlesModelTestsSupport.menu([NoteBlock(.table, props: tableProps)], isReadOnly: isReadOnly, tableEntries: items)
    }

    @Test func tablesShowTheTablesOwnActions() {
        #expect(NoteHandlesModelTestsSupport.ids(tableMenu()) == ["delete", "duplicate", "table.headerRow", "table.fitWidth"])
    }

    @Test func tableActionsKeepTheirStateInTheKindGroup() {
        let table = tableMenu()
        #expect(table[2].isChecked)
        #expect(table[2].group == 1)
        #expect(!table[3].isEnabled)
    }

    @Test func disabledTableActionsStayOutOfSearch() {
        #expect(NoteBlockMenuModel.filter(tableMenu(), query: "fit").isEmpty)
    }

    @Test func aLockedTableOffersNoTableActions() {
        #expect(!NoteHandlesModelTestsSupport.ids(tableMenu(isReadOnly: true)).contains("table.headerRow"))
    }

    @Test func aTableOfContentsCanBeColouredButNotTurned() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([NoteBlock(.tableOfContents)])) == ["delete", "duplicate", "color"])
    }
}
