import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

struct NoteHandlesModelTestsMultiBlockMenusAndSearch {
    private struct SearchCase: Sendable, CustomTestStringConvertible {
        let query: String
        let id: String

        var testDescription: String { "\(query)" }
    }

    private let one = NoteBlock.paragraph("One")

    private let two = NoteBlock(.bulletedItem, text: "Two")

    @Test func severalBlocksShareActionsButNeverASingleBlockLink() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([one, two], supportsBlockLinks: true)) == ["delete", "duplicate", "turn", "color"])
    }

    @Test func mixedTypesCheckNothingInTurnInto() {
        let checked = NoteHandlesModelTestsSupport.menu([one, two])[2].children.filter { $0.isChecked }
        #expect(checked.isEmpty)
    }

    @Test func anImageInTheMixDropsTurnIntoAndColor() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteHandlesModelTestsSupport.menu([one, NoteBlock(.image)])) == ["delete", "duplicate"])
    }

    private func splits(_ entries: [NoteBlockMenuEntry]) -> [NoteBlockMenuEntry] {
        entries[2].children.filter { if case .turnIntoColumns = $0.action { return true } else { return false } }
    }

    @Test func severalBlocksCanBecomeAsManyColumnsAsThereAreBlocks() {
        #expect(splits(NoteHandlesModelTestsSupport.menu([one, two], columnLimit: 3)).map(\.title) == ["2 Columns", "3 Columns"])
    }

    @Test func columnRowsSitInTurnInto() {
        let rows = splits(NoteHandlesModelTestsSupport.menu([one, two], columnLimit: 3))
        #expect(rows.map(\.action) == [.turnIntoColumns(2), .turnIntoColumns(3)])
        #expect(rows.allSatisfy { $0.section == "Turn Into" })
    }

    @Test func anImageInTheMixStillOffersColumnsAndOnlyColumns() {
        let entries = NoteHandlesModelTestsSupport.menu([one, NoteBlock(.image)], columnLimit: 2)
        #expect(NoteHandlesModelTestsSupport.ids(entries) == ["delete", "duplicate", "turn"])
        #expect(entries[2].children.map(\.id) == ["turn.columns2"])
    }

    @Test func fiveColumnsIsTheMostOnOffer() {
        #expect(NoteHandlesModelTestsSupport.menu([one, two], columnLimit: 9)[2].children.last?.id == "turn.columns5")
    }

    @Test func aSharedColourIsChecked() {
        var redOne = one, redTwo = two
        redOne.color = .text(.red)
        redTwo.color = .text(.red)
        #expect(NoteHandlesModelTestsSupport.menu([redOne, redTwo])[3].children.filter(\.isChecked).map(\.id) == ["color.text.red"])
    }

    @Test func noColourOnEveryBlockChecksDefaultText() {
        #expect(NoteHandlesModelTestsSupport.menu([one, two])[3].children.filter(\.isChecked).map(\.id) == ["color.text.default"])
    }

    private var searchable: [NoteBlockMenuEntry] { NoteHandlesModelTestsSupport.menu([.paragraph("Hi")], canMoveToNotes: true) }

    @Test func anEmptySearchChangesNothing() {
        #expect(NoteBlockMenuModel.filter(searchable, query: "") == searchable)
    }

    @Test func coloursAreFoundByName() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteBlockMenuModel.filter(searchable, query: "red")) == ["color.text.red", "color.background.red"])
    }

    @Test func foundColoursAreGroupedUnderColor() {
        #expect(NoteBlockMenuModel.filter(searchable, query: "red").allSatisfy { $0.section == "Color" })
    }

    @Test func keywordsReachTurnIntoStyles() {
        #expect(NoteHandlesModelTestsSupport.ids(NoteBlockMenuModel.filter(searchable, query: "h2")) == ["turn.heading2", "turn.toggleHeading2"])
    }

    @Test(arguments: [
        SearchCase(query: "  DEL ", id: "delete"),
        SearchCase(query: "remove", id: "delete"),
        SearchCase(query: "move", id: "move"),
        SearchCase(query: "todo", id: "turn.todo"),
    ])
    private func searchIgnoresCaseSpacesAndHyphensAndKnowsAliases(sample: SearchCase) {
        #expect(NoteHandlesModelTestsSupport.ids(NoteBlockMenuModel.filter(searchable, query: sample.query)) == [sample.id])
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
        #expect(NoteHandlesModelTestsSupport.ids(NoteBlockMenuModel.filter(NoteHandlesModelTestsSupport.menu([code]), query: "pyth")) == ["language.python"])
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
}
