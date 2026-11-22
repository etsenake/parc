import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteSlashCatalogTests {
    func top(_ query: String, _ context: NoteCatalogContext = .slash) -> String? {
        NoteBlockCatalog.results(for: query, in: context).first?.id
    }

    func ids(_ query: String, _ context: NoteCatalogContext = .slash) -> [String] {
        NoteBlockCatalog.results(for: query, in: context).map(\.id)
    }

    var everyItem: [NoteCatalogItem] { NoteBlockCatalog.items + NoteBlockCatalog.turnIntoItems + NoteBlockCatalog.turnIntoMenuItems }

    @Test func everyCatalogIDIsUnique() {
        #expect(Set(everyItem.map(\.id)).count == everyItem.count)
    }

    @Test func everyItemHasATitleAndAShortDescription() {
        #expect(everyItem.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
    }

    var unfiltered: [NoteCatalogItem] { NoteBlockCatalog.results(for: "") }

    @Test func theEmptyMenuRunsBasicMediaAdvancedThenInline() {
        var sections: [NoteCatalogSection] = []
        for item in unfiltered where sections.last != item.section { sections.append(item.section) }
        #expect(sections == [.basic, .media, .advanced, .inline])
    }

    @Test func coloursAndActionsWaitForAQuery() {
        #expect(!unfiltered.contains { $0.section == .colors || $0.section == .actions })
    }

    @Test func textThenTheHeadingsLeadTheMenu() {
        #expect(unfiltered.map(\.id).prefix(4) == ["text", "heading1", "heading2", "heading3"])
    }

    @Test func basicBlocksFollowNotionsOrder() {
        #expect(unfiltered.filter { $0.section == .basic }.map(\.id)
                == ["text", "heading1", "heading2", "heading3", "heading4", "bulleted", "numbered", "todo", "toggle",
                    "toggleHeading1", "toggleHeading2", "toggleHeading3", "toggleHeading4", "quote", "callout", "divider", "newNote",
                    "linkToNote", "table"])
    }

    @Test func mediaOrder() {
        #expect(unfiltered.filter { $0.section == .media }.map(\.id) == ["image", "video", "audio", "file", "pdf", "bookmark", "embed", "easel"])
    }

    @Test func advancedOrder() {
        #expect(unfiltered.filter { $0.section == .advanced }.map(\.id)
                == ["tableOfContents", "equation", "button", "code", "breadcrumb", "synced", "columns2", "columns3", "columns4", "columns5"])
    }

    @Test func inlineOrder() {
        #expect(unfiltered.filter { $0.section == .inline }.map(\.id) == ["mention", "date", "emoji", "inlineEquation"])
    }

    @Test(arguments: [
        ("h1", "heading1"), ("#", "heading1"), ("##", "heading2"), ("###", "heading3"), ("h4", "heading4"), ("####", "heading4"),
        ("th4", "toggleHeading4"), ("toggle h4", "toggleHeading4"), ("todo", "todo"), ("[]", "todo"),
        ("ul", "bulleted"), ("ol", "numbered"), ("num", "numbered"), ("img", "image"), ("hr", "divider"), ("div", "divider"),
        ("---", "divider"), ("math", "equation"), ("tex", "equation"), ("latex", "equation"), ("plain", "text"), ("call", "callout"),
        ("book", "bookmark"), ("web", "bookmark"), ("toc", "tableOfContents"), ("bread", "breadcrumb"), ("breadcrumb", "breadcrumb"),
        ("red", "color.red"), ("red background", "background.red"), ("red b", "background.red"), ("grey", "color.gray"),
        ("default", "color.default"), ("del", "action.delete"), ("dup", "action.duplicate"), ("code", "code"), ("```", "code"),
        ("quote", "quote"), ("\"", "quote"), (">", "toggle"), ("page", "newNote"), ("link", "linkToNote"), ("2 col", "columns2"),
        ("3col", "columns3"), ("emoji", "emoji"), ("mention", "mention"), ("date", "date"), ("remind", "date"),
        ("inline math", "inlineEquation"), ("th2", "toggleHeading2"), ("to-do", "todo"), ("todolist", "todo"), ("bullet", "bulleted"),
        ("heading 2", "heading2"), ("video", "video"), ("button", "button"), ("template", "button"),
    ])
    func anAliasPutsItsBlockFirst(query: String, expected: String) {
        #expect(top(query) == expected)
    }

    @Test func aLoneHListsEveryHeadingBeforeAnythingAnAliasDragsIn() {
        #expect(ids("h").prefix(8) == ["heading1", "heading2", "heading3", "heading4", "toggleHeading1", "toggleHeading2", "toggleHeading3", "toggleHeading4"])
    }

    @Test func listFindsEveryListInCatalogOrder() {
        #expect(ids("list").prefix(4) == ["bulleted", "numbered", "todo", "toggle"])
    }

    @Test func backListsTheNineBackgrounds() {
        let back = ids("back")
        #expect(back.count == 9)
        #expect(back.allSatisfy { $0.hasPrefix("background.") })
    }

    @Test func colorListsDefaultPlusNineTextAndNineBackgroundColours() {
        let colors = ids("color")
        #expect(colors.count == 19)
        #expect(colors.first == "color.default")
    }

    @Test func redPutsTheTextColourAboveTheBackground() {
        #expect(ids("red").prefix(2) == ["color.red", "background.red"])
    }

    @Test func togListsOnlyToggles() {
        let tog = ids("tog")
        #expect(!tog.isEmpty)
        #expect(tog.allSatisfy { $0.lowercased().contains("toggle") })
    }

    @Test(arguments: [("td", "todo"), ("hdg", "heading1"), ("tbl", "table")])
    func fuzzySubsequencesStillFindTheBlock(query: String, id: String) {
        #expect(ids(query).contains(id))
    }

    @Test func nonsenseFindsNothing() { #expect(ids("zzzz").isEmpty) }

    @Test func aSingleLetterOnlyMatchesWordStarts() { #expect(ids("x").isEmpty) }

    @Test func turnListsEveryTurnInto() {
        let turn = ids("turn")
        #expect(turn.count == NoteCatalogBlock.turnIntoTargets.count)
        #expect(turn.allSatisfy { $0.hasPrefix("turn.") })
    }

    @Test(arguments: [
        ("turnbullet", "turn.bulleted"), ("turn into h1", "turn.heading1"), ("turn into h4", "turn.heading4"),
        ("turninto quote", "turn.quote"), ("turn callout", "turn.callout"),
    ])
    func aTurnQueryGoesStraightToItsTarget(query: String, id: String) {
        #expect(top(query) == id)
    }

    @Test func thePlusMenuNeverOffersActionsOnItsFreshBlock() { #expect(!ids("delete", .plus).contains("action.delete")) }

    @Test func thePlusMenuStillPaintsColours() { #expect(ids("red", .plus).first == "color.red") }

    @Test func columnsHideInsideColumns() {
        var nested = NoteCatalogContext.slash
        nested.allowsColumns = false
        #expect(!ids("columns", nested).contains { $0.hasPrefix("columns") })
    }

    @Test func newNoteHidesWhenThereIsNoFolderToPutItIn() {
        var nested = NoteCatalogContext.slash
        nested.allowsNewNote = false
        #expect(!ids("page", nested).contains("newNote"))
    }

    var turnMenu: [NoteCatalogItem] { NoteBlockCatalog.results(for: "", in: .turnInto) }

    @Test func turnIntoListsPlainBlockNames() {
        #expect(turnMenu.map(\.title).prefix(5) == ["Text", "Heading 1", "Heading 2", "Heading 3", "Heading 4"])
    }

    @Test(arguments: ["into.toggleHeading4", "into.button"])
    func turnIntoOffersTheBlock(id: String) { #expect(turnMenu.contains { $0.id == id }) }

    @Test func turnIntoRowsOnlyConvert() {
        #expect(turnMenu.allSatisfy { if case .turnInto = $0.effect { return true } else { return false } })
    }

    @Test func turnIntoFiltersToo() { #expect(NoteBlockCatalog.results(for: "quo", in: .turnInto).first?.id == "into.quote") }

    @Test func slashButtonMakesAClosedStarterButtonWithOneEmptyInsert() {
        let button = NoteCatalogBlock.button.makeBlock()
        #expect(button.kind == .button)
        #expect(button.buttonValue == NoteButton.starter)
        #expect(!button.props.expanded)
    }

    @Test func aSingleBlockGetsNoColumnChoices() {
        #expect(NoteBlockCatalog.turnIntoMenuItems(columnLimit: 1).map(\.id) == NoteBlockCatalog.turnIntoMenuItems.map(\.id))
    }

    @Test func severalBlocksGetTwoColumnsUpToTheirCount() {
        let split = NoteBlockCatalog.turnIntoMenuItems(columnLimit: 3).filter { $0.id.hasPrefix("into.columns") }
        #expect(split.map(\.id) == ["into.columns2", "into.columns3"])
        #expect(split.map(\.title) == ["2 columns", "3 columns"])
    }

    @Test func columnChoicesTurnTheBlocksIntoColumns() {
        let split = NoteBlockCatalog.turnIntoMenuItems(columnLimit: 3).filter { $0.id.hasPrefix("into.columns") }
        #expect(split.first?.effect == .turnInto(.columns(2)))
    }

    @Test func theListStopsAtFiveColumns() {
        #expect(NoteBlockCatalog.turnIntoMenuItems(columnLimit: 8).last?.id == "into.columns5")
    }

    @Test func oneBlockNeverTurnsIntoABareColumnSet() {
        let lone = NoteBlock.paragraph("Solo")
        #expect(NoteCatalogApplier.apply(.turnInto(.columns(2)), to: NotePage(blocks: [lone]), at: NotePosition(lone.id, 0), removing: 0..<0) == nil)
    }

    @Test func templatesRecogniseTheirBlocks() {
        let todo = NoteBlock(.todo)
        #expect(NoteCatalogBlock.todo.describes(todo))
        #expect(!NoteCatalogBlock.text.describes(todo))
    }

    @Test func toggleHeadingsAndHeadingsStayDistinct() {
        var toggleHeading = NoteBlock.heading(2)
        toggleHeading.props.toggleable = true
        #expect(NoteCatalogBlock.toggleHeading(2).describes(toggleHeading))
        #expect(!NoteCatalogBlock.heading(2).describes(toggleHeading))
    }

    @Test func threeColumnsBuildsThreeColumnsWithAnEmptyParagraphEach() {
        let columns = NoteCatalogBlock.columns(3).makeBlock()
        #expect(columns.kind == .columns)
        #expect(columns.children.count == 3)
        #expect(columns.children.allSatisfy { $0.kind == .column && $0.children.first?.kind == .paragraph })
    }

    @Test func breadMakesAnEmptyBreadcrumbBlock() {
        let crumb = NoteCatalogBlock.breadcrumb.makeBlock()
        #expect(crumb.kind == .breadcrumb)
        #expect(crumb.text.isEmpty)
        #expect(crumb.children.isEmpty)
    }

    @Test func theBreadcrumbTakesTheEmptyLineAndAFreshLineFollows() throws {
        let line = NoteBlock.paragraph("/bread")
        let placed = try #require(NoteCatalogApplier.apply(.block(.breadcrumb), to: NotePage(blocks: [line]), at: NotePosition(line.id, 0), removing: 0..<6))
        #expect(placed.page.blocks.map(\.kind) == [.breadcrumb, .paragraph])
        #expect(placed.selection.caret?.block == placed.page.blocks[1].id)
    }

    @Test func aFreshCalloutGetsAnIcon() {
        let callout = NoteCatalogBlock.callout.makeBlock()
        #expect(callout.kind == .callout)
        #expect(callout.props.icon != nil)
    }

    @Test func toggleHeading1IsAFoldingH1() {
        let heading = NoteCatalogBlock.toggleHeading(1).makeBlock()
        #expect(heading.kind == .heading)
        #expect(heading.props.toggleable)
        #expect(heading.props.expanded)
        #expect(heading.props.level == 1)
    }

    @Test func heading4IsAPlainH4() {
        let fourth = NoteCatalogBlock.heading(4).makeBlock()
        #expect(fourth.kind == .heading)
        #expect(!fourth.props.toggleable)
        #expect(fourth.props.level == 4)
    }

    @Test func toggleHeading4Folds() {
        let folding = NoteCatalogBlock.toggleHeading(4).makeBlock()
        #expect(folding.props.toggleable)
        #expect(folding.props.level == 4)
    }
}
