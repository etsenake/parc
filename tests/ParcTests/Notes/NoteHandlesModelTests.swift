import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteHandlesModelTests {
    func ids(_ entries: [NoteBlockMenuEntry]) -> [String] { entries.map(\.id) }

    func menu(_ blocks: [NoteBlock], isReadOnly: Bool = false, canMoveToNotes: Bool = false, supportsBlockLinks: Bool = false,
              columnLimit: Int = 0, tableEntries: [NoteBlockMenuEntry] = []) -> [NoteBlockMenuEntry] {
        NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: blocks, isReadOnly: isReadOnly, canMoveToNotes: canMoveToNotes,
                                                             supportsBlockLinks: supportsBlockLinks, tableEntries: tableEntries, columnLimit: columnLimit))
    }

    func yellowParagraph() -> NoteBlock {
        var paragraph = NoteBlock.paragraph("Hello there")
        paragraph.color = .background(.yellow)
        return paragraph
    }

    @Test func aParagraphGetsNotionsOrderWithoutBlockLinks() {
        #expect(ids(menu([yellowParagraph()], canMoveToNotes: true)) == ["delete", "duplicate", "turn", "move", "color"])
    }

    @Test func deleteShowsABackspaceKeycapAndReadsAsDestructive() {
        let delete = menu([yellowParagraph()], canMoveToNotes: true)[0]
        #expect(delete.shortcut == "⌫")
        #expect(delete.isDestructive)
    }

    @Test func duplicateShowsCommandD() {
        #expect(menu([yellowParagraph()], canMoveToNotes: true)[1].shortcut == "⌘D")
    }

    @Test func moveToShowsItsShortcutAndOpensANotePicker() {
        let move = menu([yellowParagraph()], canMoveToNotes: true)[3]
        #expect(move.shortcut == "⇧⌘P")
        #expect(move.hasSubmenu)
    }

    @Test func turnIntoChecksTheParagraphsOwnType() {
        let turn = menu([yellowParagraph()], canMoveToNotes: true)[2].children
        #expect(turn.first?.title == "Text")
        #expect(turn.first?.isChecked == true)
        #expect(turn.filter(\.isChecked).count == 1)
    }

    @Test func turnIntoCoversToggleHeadingsAndEquations() {
        let turn = menu([yellowParagraph()], canMoveToNotes: true)[2].children
        #expect(turn.contains { $0.title == "Toggle Heading 2" })
        #expect(turn.contains { $0.title == "Block Equation" })
    }

    @Test func colourHasTenTextColoursAndTenBackgrounds() {
        #expect(menu([yellowParagraph()], canMoveToNotes: true)[4].children.count == 20)
    }

    @Test func theBlocksBackgroundIsChecked() {
        #expect(menu([yellowParagraph()], canMoveToNotes: true)[4].children.filter(\.isChecked).map(\.id) == ["color.background.yellow"])
    }

    @Test func defaultTextClearsTheColour() {
        let colors = menu([yellowParagraph()], canMoveToNotes: true)[4].children
        #expect(colors.first?.action == .color(nil))
        #expect(colors.first?.section == "Text Color")
    }

    @Test func aToggleHeadingChecksItsToggleStyle() {
        var heading = NoteBlock.heading(2, "Plan")
        heading.props.toggleable = true
        #expect(menu([heading])[2].children.filter(\.isChecked).map(\.title) == ["Toggle Heading 2"])
    }

    @Test func blockLinksAppearWhenTheFormatCanAnchorThem() {
        let linked = menu([yellowParagraph()], supportsBlockLinks: true)
        #expect(ids(linked).contains("link"))
        #expect(linked.first { $0.id == "link" }?.shortcut == "⌃⌘L")
    }

    @Test func rawHtmlGetsNoBlockLink() {
        #expect(!ids(menu([NoteBlock(.html, text: "<div></div>")], supportsBlockLinks: true)).contains("link"))
    }

    @Test func codeLinksButABareColumnDoesNot() {
        #expect(NoteBlockMenuModel.linkable(NoteBlock(.code)))
        #expect(!NoteBlockMenuModel.linkable(NoteBlock(.column)))
    }

    @Test func aLockedPageOnlyOffersTheLink() {
        #expect(ids(menu([yellowParagraph()], isReadOnly: true, canMoveToNotes: true, supportsBlockLinks: true)) == ["link"])
    }

    func codeBlock() -> NoteBlock {
        var code = NoteBlock(.code, text: "print(1)")
        code.props.language = "Python"
        code.props.wrap = true
        return code
    }

    @Test func codeGetsLanguageAndWrapButNoColour() {
        #expect(ids(menu([codeBlock()])) == ["delete", "duplicate", "turn", "language", "wrap"])
    }

    @Test func theLanguageRowNamesTheCurrentLanguage() {
        let language = menu([codeBlock()])[3]
        #expect(language.subtitle == "Python")
        #expect(language.children.filter(\.isChecked).map(\.title) == ["Python"])
    }

    @Test func wrapCodeShowsItsState() {
        #expect(menu([codeBlock()])[4].isChecked)
    }

    @Test func turnIntoChecksCode() {
        #expect(menu([codeBlock()])[2].children.first { $0.title == "Code" }?.isChecked == true)
    }

    func image(source: String? = "Attachments/cat.png") -> NoteBlock {
        var image = NoteBlock(.image)
        image.props.source = source
        image.props.alignment = .left
        return image
    }

    @Test func imagesGetAlignmentCropMaskAltTextDownloadAndTheOriginal() {
        #expect(ids(menu([image()], canMoveToNotes: true)) == ["delete", "duplicate", "align", "crop", "mask", "alt", "download", "original", "move"])
    }

    @Test func theImagesAlignmentIsChecked() {
        #expect(menu([image()], canMoveToNotes: true)[2].children.filter(\.isChecked).map(\.title) == ["Left"])
    }

    @Test func anEmptyImageHasNothingToDownload() {
        #expect(ids(menu([NoteBlock(.image)])) == ["delete", "duplicate", "align"])
    }

    func pdf(_ kind: NoteBlockKind, _ source: String) -> NoteBlock {
        var block = NoteBlock(kind)
        block.props.source = source
        return block
    }

    @Test func pdfsGetTurnIntoAlignmentDownloadTheOriginalAndFullScreen() {
        #expect(ids(menu([pdf(.pdf, "Attachments/report.pdf")], canMoveToNotes: true))
                == ["delete", "duplicate", "turn", "align", "download", "original", "fullScreen", "move"])
    }

    @Test func pdfsTurnIntoFileRowsAndBack() {
        let entries = menu([pdf(.pdf, "Attachments/report.pdf")], canMoveToNotes: true)
        #expect(entries.first { $0.id == "turn" }?.children.map(\.id) == ["turn.pdf", "turn.file"])
    }

    @Test func aPdfFileRowCanTurnIntoAPdf() {
        let entries = menu([pdf(.file, "Attachments/report.pdf")])
        #expect(entries.first { $0.id == "turn" }?.children.first { $0.isChecked }?.id == "turn.file")
    }

    @Test func otherFilesCannotBecomePdfs() {
        #expect(!ids(menu([pdf(.file, "Attachments/a.zip")])).contains("turn"))
    }

    @Test func bookmarksCopyAndOpenTheOriginalLink() {
        var bookmark = NoteBlock(.bookmark)
        bookmark.props.source = "https://parcbrowser.com"
        #expect(ids(menu([bookmark])) == ["delete", "duplicate", "copyOriginal", "original"])
    }

    @Test func dividersCanOnlyGoAwayDoubleOrMove() {
        #expect(ids(menu([NoteBlock(.divider)], canMoveToNotes: true)) == ["delete", "duplicate", "move"])
    }

    func tableMenu(isReadOnly: Bool = false) -> [NoteBlockMenuEntry] {
        var tableProps = NoteBlockProps()
        tableProps.table = .empty()
        let items = [NoteBlockMenuEntry(id: "table.headerRow", title: "Header Row", isChecked: true, action: .tableItem("table.headerRow")),
                     NoteBlockMenuEntry(id: "table.fitWidth", title: "Fit to Width", isEnabled: false, action: .tableItem("table.fitWidth"))]
        return menu([NoteBlock(.table, props: tableProps)], isReadOnly: isReadOnly, tableEntries: items)
    }

    @Test func tablesShowTheTablesOwnActions() {
        #expect(ids(tableMenu()) == ["delete", "duplicate", "table.headerRow", "table.fitWidth"])
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
        #expect(!ids(tableMenu(isReadOnly: true)).contains("table.headerRow"))
    }

    @Test func aTableOfContentsCanBeColouredButNotTurned() {
        #expect(ids(menu([NoteBlock(.tableOfContents)])) == ["delete", "duplicate", "color"])
    }

    let one = NoteBlock.paragraph("One")
    let two = NoteBlock(.bulletedItem, text: "Two")

    @Test func severalBlocksShareActionsButNeverASingleBlockLink() {
        #expect(ids(menu([one, two], supportsBlockLinks: true)) == ["delete", "duplicate", "turn", "color"])
    }

    @Test func mixedTypesCheckNothingInTurnInto() {
        let checked = menu([one, two])[2].children.filter { $0.isChecked }
        #expect(checked.isEmpty)
    }

    @Test func anImageInTheMixDropsTurnIntoAndColor() {
        #expect(ids(menu([one, NoteBlock(.image)])) == ["delete", "duplicate"])
    }

    func splits(_ entries: [NoteBlockMenuEntry]) -> [NoteBlockMenuEntry] {
        entries[2].children.filter { if case .turnIntoColumns = $0.action { return true } else { return false } }
    }

    @Test func severalBlocksCanBecomeAsManyColumnsAsThereAreBlocks() {
        #expect(splits(menu([one, two], columnLimit: 3)).map(\.title) == ["2 Columns", "3 Columns"])
    }

    @Test func columnRowsSitInTurnInto() {
        let rows = splits(menu([one, two], columnLimit: 3))
        #expect(rows.map(\.action) == [.turnIntoColumns(2), .turnIntoColumns(3)])
        #expect(rows.allSatisfy { $0.section == "Turn Into" })
    }

    @Test func anImageInTheMixStillOffersColumnsAndOnlyColumns() {
        let entries = menu([one, NoteBlock(.image)], columnLimit: 2)
        #expect(ids(entries) == ["delete", "duplicate", "turn"])
        #expect(entries[2].children.map(\.id) == ["turn.columns2"])
    }

    @Test func fiveColumnsIsTheMostOnOffer() {
        #expect(menu([one, two], columnLimit: 9)[2].children.last?.id == "turn.columns5")
    }

    @Test func aSharedColourIsChecked() {
        var redOne = one, redTwo = two
        redOne.color = .text(.red)
        redTwo.color = .text(.red)
        #expect(menu([redOne, redTwo])[3].children.filter(\.isChecked).map(\.id) == ["color.text.red"])
    }

    @Test func noColourOnEveryBlockChecksDefaultText() {
        #expect(menu([one, two])[3].children.filter(\.isChecked).map(\.id) == ["color.text.default"])
    }

    var searchable: [NoteBlockMenuEntry] { menu([.paragraph("Hi")], canMoveToNotes: true) }

    @Test func anEmptySearchChangesNothing() {
        #expect(NoteBlockMenuModel.filter(searchable, query: "") == searchable)
    }

    @Test func coloursAreFoundByName() {
        #expect(ids(NoteBlockMenuModel.filter(searchable, query: "red")) == ["color.text.red", "color.background.red"])
    }

    @Test func foundColoursAreGroupedUnderColor() {
        #expect(NoteBlockMenuModel.filter(searchable, query: "red").allSatisfy { $0.section == "Color" })
    }

    @Test func keywordsReachTurnIntoStyles() {
        #expect(ids(NoteBlockMenuModel.filter(searchable, query: "h2")) == ["turn.heading2", "turn.toggleHeading2"])
    }

    @Test(arguments: [("  DEL ", "delete"), ("remove", "delete"), ("move", "move"), ("todo", "turn.todo")])
    func searchIgnoresCaseSpacesAndHyphensAndKnowsAliases(query: String, id: String) {
        #expect(ids(NoteBlockMenuModel.filter(searchable, query: query)) == [id])
    }

    @Test func matchingASubmenuShowsItsRows() {
        #expect(NoteBlockMenuModel.filter(searchable, query: "turn").count == NoteBlockMenuModel.turnIntoStyles.count)
    }

    @Test func noMatchMeansNoRows() {
        #expect(NoteBlockMenuModel.filter(searchable, query: "zzz").isEmpty)
    }

    @Test func languagesAreSearchable() {
        var code = NoteBlock(.code)
        code.props.language = "swift"
        #expect(ids(NoteBlockMenuModel.filter(menu([code]), query: "pyth")) == ["language.python"])
    }

    @Test func theFooterCountsWordsAndCharactersChildrenToo() {
        let blocks = [NoteBlock.paragraph("Two words"), NoteBlock(.bulletedItem, text: "three more here", children: [NoteBlock(.bulletedItem, text: "nested")])]
        #expect(NoteBlockMenuModel.footer(for: blocks) == "6 words · 30 characters")
    }

    @Test func singularWordsReadNaturally() {
        #expect(NoteBlockMenuModel.footer(for: [.paragraph("Hi")]) == "1 word · 2 characters")
    }

    @Test func blocksWithoutWordsHaveNoFooter() {
        #expect(NoteBlockMenuModel.footer(for: [NoteBlock(.divider)]) == nil)
    }

    let frame = CGRect(x: 200, y: 100, width: 400, height: 60)

    @Test func theGripSitsASmallGapLeftOfTheBlock() {
        #expect(NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14).grip.maxX == frame.minX - NoteHandleGeometry.contentGap)
    }

    @Test func plusComesBeforeTheGrip() {
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        #expect(rects.plus.maxX == rects.grip.minX - NoteHandleGeometry.buttonGap)
    }

    @Test func bothCentreOnTheBlocksFirstLine() {
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        #expect(rects.plus.midY == 114)
        #expect(rects.grip.midY == 114)
    }

    @Test func buttonsKeepTheirSize() {
        #expect(NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14).plus.size == NoteHandleGeometry.buttonSize)
    }

    @Test func nestedBlocksGetHandlesAtTheirIndent() {
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        #expect(NoteHandleGeometry.rects(blockFrame: frame.offsetBy(dx: 26, dy: 0), anchorY: 14).grip.minX == rects.grip.minX + 26)
    }

    @Test func handlesNeverLeaveTheCanvas() {
        #expect(NoteHandleGeometry.rects(blockFrame: CGRect(x: 10, y: 0, width: 300, height: 20), anchorY: 10, minimumX: 0).plus.minX >= 0)
    }

    @Test func theBarHoldsBothButtons() {
        #expect(NoteHandleGeometry.barWidth == NoteHandleGeometry.buttonSize.width * 2 + NoteHandleGeometry.buttonGap)
    }

    @MainActor struct Targets {
        let a = NoteBlockID(), b = NoteBlockID(), child = NoteBlockID(), container = NoteBlockID(), left = NoteBlockID(), right = NoteBlockID()

        var flat: [NoteHandleTarget] {
            [NoteHandleTarget(id: a, frame: CGRect(x: 100, y: 0, width: 500, height: 30), depth: 0, anchorY: 15),
             NoteHandleTarget(id: b, frame: CGRect(x: 100, y: 32, width: 500, height: 30), depth: 0, anchorY: 15)]
        }

        var tree: [NoteHandleTarget] {
            [NoteHandleTarget(id: container, frame: CGRect(x: 100, y: 0, width: 500, height: 100), depth: 0, anchorY: 15),
             NoteHandleTarget(id: child, frame: CGRect(x: 126, y: 40, width: 474, height: 30), depth: 1, anchorY: 15)]
        }

        var columns: [NoteHandleTarget] {
            [NoteHandleTarget(id: left, frame: CGRect(x: 100, y: 0, width: 220, height: 30), depth: 2, anchorY: 15),
             NoteHandleTarget(id: right, frame: CGRect(x: 366, y: 0, width: 220, height: 30), depth: 2, anchorY: 15)]
        }
    }

    let targets = Targets()

    @Test func thePointerOverABlockPicksIt() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 10), in: targets.flat)?.id == targets.a)
    }

    @Test func theLeftGutterCountsAsTheBlock() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 70, y: 40), in: targets.flat)?.id == targets.b)
    }

    @Test func theGapBetweenBlocksStillShowsAHandle() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 31), in: targets.flat) != nil)
    }

    @Test(arguments: [CGPoint(x: 20, y: 10), CGPoint(x: 300, y: 200)])
    func farFromTheBlocksShowsNothing(point: CGPoint) {
        #expect(NoteHandleGeometry.target(at: point, in: targets.flat) == nil)
    }

    @Test func theDeepestBlockUnderThePointerWins() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 50), in: targets.tree)?.id == targets.child)
    }

    @Test func aNestedBlocksGutterIsItsOwn() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 110, y: 50), in: targets.tree)?.id == targets.child)
    }

    @Test func theContainersOwnRowIsTheContainer() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 10), in: targets.tree)?.id == targets.container)
    }

    @Test func eachColumnBlockHasItsOwnHandle() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 400, y: 10), in: targets.columns)?.id == targets.right)
    }

    @Test func theColumnGapBelongsToTheNextColumn() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 345, y: 10), in: targets.columns)?.id == targets.right)
    }

    @Test func justPastAColumnsEdgeIsStillThatColumn() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 325, y: 10), in: targets.columns)?.id == targets.left)
    }

    func velocity(_ pointerY: CGFloat, top: CGFloat = 1000, bottom: CGFloat = 1600) -> CGFloat {
        NoteAutoscroll.velocity(pointerY: pointerY, visibleMinY: top, visibleMaxY: bottom)
    }

    @Test func theMiddleOfTheViewNeverScrolls() {
        #expect(velocity(1300) == 0)
    }

    @Test func theTopEdgeScrollsUpFasterTheCloserYouGet() {
        let near = velocity(1040), at = velocity(1000), above = velocity(940)
        #expect(near < 0)
        #expect(at < near)
        #expect(above < at)
    }

    @Test func speedTopsOut() {
        #expect(velocity(1000 - 5000) == -NoteAutoscroll.maximumSpeed)
    }

    @Test func theEdgeZoneNeverCrawlsBelowTheMinimumSpeed() {
        #expect(velocity(1040) <= -NoteAutoscroll.minimumSpeed)
    }

    @Test func theBottomEdgeMirrorsTheTop() {
        #expect(velocity(1600 - 40) == -velocity(1000 + 40))
    }

    @Test func justOutsideTheZoneIsStill() {
        #expect(velocity(1000 + NoteAutoscroll.edgeZone + 1) == 0)
    }

    @Test func aShortViewKeepsAStillMiddle() {
        #expect(velocity(50, top: 0, bottom: 120) == 0)
    }

    @Test func aFrameMovesVelocityTimesTime() {
        #expect(NoteAutoscroll.step(velocity: 600, elapsed: 1.0 / 60) == 10)
    }

    @Test func aStalledFrameNeverJumpsFar() {
        #expect(NoteAutoscroll.step(velocity: 600, elapsed: 2) == 30)
    }

    func pageWithCopy() -> (NotePage, NoteBlock, NoteBlock) {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b")
        var page = NotePage(blocks: [a, b])
        page.place([.paragraph("copy")], beside: b.id, side: .left)
        return (page, a, b)
    }

    @Test func droppingBesideABlockMakesColumnsInItsPlace() {
        let (page, _, _) = pageWithCopy()
        #expect(page.blocks.count == 2)
        #expect(page.blocks[1].kind == .columns)
    }

    @Test func theLeftSidePutsTheCopyFirst() {
        #expect(pageWithCopy().0.blocks[1].children.map { $0.children.map(\.text.string) } == [["copy"], ["b"]])
    }

    @Test func besideAColumnBlockAddsAColumnNextToIt() {
        var (page, _, b) = pageWithCopy()
        let row = page.blocks[1].id
        page.update(row) { columns in for index in columns.children.indices { columns.children[index].props.width = 0.5 } }
        page.place([.paragraph("third")], beside: b.id, side: .right)
        let columns = page.block(row)!.children
        #expect(columns.map { $0.children.map(\.text.string) } == [["copy"], ["b"], ["third"]])
        #expect(columns.allSatisfy { $0.props.width == nil })
    }

    @Test func fiveColumnsIsTheLimit() {
        var full = NotePage(blocks: [NoteBlock(.columns, children: (0..<5).map { NoteBlock(.column, children: [NoteBlock.paragraph(NoteText("\($0)"))]) })])
        let before = full
        full.place([NoteBlock.paragraph("six")], beside: full.blocks[0].children[2].children[0].id, side: .right)
        #expect(full == before)
    }

    @Test func placingNothingChangesNothing() {
        let a = NoteBlock.paragraph("a")
        var page = NotePage(blocks: [a])
        page.place([], beside: a.id, side: .right)
        #expect(page.blocks == [a])
    }

    @MainActor struct Dragging {
        let a = NoteBlock.paragraph("a"), c = NoteBlock(.bulletedItem, text: "c")
        let b: NoteBlock
        let d = NoteBlock.paragraph("d")
        let left = NoteBlock(.column, children: [NoteBlock.paragraph("l")])
        let page: NotePage

        init() {
            b = NoteBlock(.bulletedItem, text: "b", children: [c])
            let right = NoteBlock(.column, children: [NoteBlock.paragraph("r")])
            page = NotePage(blocks: [a, b, d, NoteBlock(.columns, children: [left, right])])
        }
    }

    let drag = Dragging()

    @Test func anUnselectedBlockDragsAlone() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.d.id, selection: .none, page: drag.page) == [drag.d.id])
    }

    @Test func aSelectionDragsInDocumentOrder() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.d.id, selection: .blocks([drag.d.id, drag.a.id]), page: drag.page) == [drag.a.id, drag.d.id])
    }

    @Test func grabbingOutsideTheSelectionDragsJustThatBlock() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.a.id, selection: .blocks([drag.b.id]), page: drag.page) == [drag.a.id])
    }

    @Test func childrenTravelWithTheirSelectedParent() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.c.id, selection: .blocks([drag.b.id, drag.c.id, drag.a.id]), page: drag.page) == [drag.a.id, drag.b.id])
    }

    @Test func aBareColumnCannotBeDragged() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.left.id, selection: .none, page: drag.page).isEmpty)
    }

    @Test func missingBlocksDragNothing() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: NoteBlockID(), selection: .none, page: drag.page).isEmpty)
    }

    @Test func dimmingCoversVisibleChildren() {
        #expect(NoteDragPlan.affectedBlocks([drag.b.id], page: drag.page) == [drag.b.id, drag.c.id])
    }

    @Test func droppingBesideAnotherBlockIsFine() {
        #expect(NoteDragPlan.canDrop([drag.b.id], onto: drag.d.id, page: drag.page))
    }

    @Test func aBlockCannotBeDroppedIntoItself() {
        #expect(!NoteDragPlan.canDrop([drag.b.id], onto: drag.c.id, page: drag.page))
    }

    @Test func aBlockCannotBeDroppedOntoItself() {
        #expect(!NoteDragPlan.canDrop([drag.b.id], onto: drag.b.id, page: drag.page))
    }

    @Test func aWobbleIsStillAClick() {
        #expect(!NoteDragPlan.crossesThreshold(from: .zero, to: CGPoint(x: 2, y: 2)))
    }

    @Test func aRealMoveStartsADrag() {
        #expect(NoteDragPlan.crossesThreshold(from: .zero, to: CGPoint(x: 3, y: 3)))
    }

    var closedToggle: NoteBlock {
        var toggle = NoteBlock(.toggle, text: "t")
        toggle.props.expanded = false
        return toggle
    }

    @Test func aToggleWaitsBeforeOpening() {
        #expect(!NoteDragPlan.shouldExpand(closedToggle, hoveredSince: 10, now: 10.5))
    }

    @Test func aClosedToggleOpensAfterSixTenthsOfASecond() {
        #expect(NoteDragPlan.shouldExpand(closedToggle, hoveredSince: 10, now: 10.6))
    }

    @Test func onlyTogglesOpen() {
        #expect(!NoteDragPlan.shouldExpand(drag.a, hoveredSince: 10, now: 20))
    }

    @Test func noHoverNoOpening() {
        #expect(!NoteDragPlan.shouldExpand(closedToggle, hoveredSince: nil, now: 20))
    }

    @Test func copiesKeepOrderAndGetFreshIDs() {
        let copies = NoteDragPlan.copies(of: [drag.d.id, drag.b.id, drag.c.id], in: drag.page)
        #expect(copies.map(\.text.string) == ["b", "d"])
        #expect(copies.allSatisfy { $0.id != drag.b.id && $0.id != drag.d.id })
    }

    @Test func copiedChildrenAreFreshToo() {
        let copies = NoteDragPlan.copies(of: [drag.d.id, drag.b.id, drag.c.id], in: drag.page)
        #expect(copies[0].children.first?.id != drag.c.id)
        #expect(copies[0].children.first?.text.string == "c")
    }

    @Test func theGhostKeepsTheGrabOffset() {
        #expect(NoteDragPlan.ghostOrigin(pointer: CGPoint(x: 100, y: 80), grabOffset: CGPoint(x: 10, y: 5)) == CGPoint(x: 90, y: 75))
    }
}
