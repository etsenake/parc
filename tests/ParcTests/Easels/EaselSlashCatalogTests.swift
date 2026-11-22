import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct EaselSlashCatalogTests {
    private static let everything = EaselSlashContext(checklist: true, divider: true, mention: true, date: true, inlineEquation: true)

    private static func ids(_ query: String, _ context: EaselSlashContext = EaselSlashContext()) -> [String] {
        EaselSlashCatalog.results(for: query, in: context).map(\.id)
    }

    private static func ids(in section: NoteCatalogSection) -> [String] {
        EaselSlashCatalog.rows(in: everything).filter { $0.item.section == section }.map(\.id)
    }

    @Test func everyEaselSlashRowHasItsOwnID() {
        let all = EaselSlashCatalog.rows(in: Self.everything)
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func theMenuRunsTextRowsInlineRowsThenAddToTheEasel() {
        let sections = EaselSlashCatalog.rows(in: Self.everything).map(\.item.section)
            .reduce(into: [NoteCatalogSection]()) { if $0.last != $1 { $0.append($1) } }
        #expect(sections == [.basic, .inline, .easel])
    }

    @Test func textRowsFollowTheNotesOrder() {
        #expect(Self.ids(in: .basic) == ["text", "heading1", "heading2", "heading3", "bulleted", "numbered", "todo", "quote", "divider"])
    }

    @Test func inlineRowsFollowTheNotesOrder() {
        #expect(Self.ids(in: .inline) == ["mention", "date", "emoji", "inlineEquation"])
    }

    @Test func everyObjectTheEaselCanPlaceHasARow() {
        #expect(Self.ids(in: .easel) == EaselSlashObject.allCases.map { "easel." + $0.rawValue })
    }

    @Test func theObjectSectionHasItsOwnHeader() {
        #expect(NoteCatalogSection.easel.title == "Add to the Easel")
        #expect(!NoteCatalogSection.easel.needsQuery)
    }

    @Test(arguments: EaselSlashObject.allCases)
    func objectRowsHaveATitleAndASummaryAboutTheEasel(object: EaselSlashObject) throws {
        let row = try #require(EaselSlashCatalog.rows(in: Self.everything).first { $0.id == "easel." + object.rawValue })
        #expect(!row.item.title.isEmpty)
        #expect(!row.item.summary.isEmpty)
        #expect(!row.item.summary.contains("this note") && !row.item.summary.contains("the note"))
    }

    @Test(arguments: [("easel.equation", "Block equation"), ("easel.pdf", "PDF")])
    func objectRowsUseTheNotesNames(id: String, title: String) {
        #expect(EaselSlashCatalog.rows(in: Self.everything).first { $0.id == id }?.item.title == title)
    }

    @Test(arguments: [
        ("h1", "heading1"), ("#", "heading1"),
        ("img", "easel.image"), ("photo", "easel.image"),
        ("sticky", "easel.sticky"), ("post-it", "easel.sticky"),
        ("rect", "easel.shape"), ("circle", "easel.shape"),
        ("emoji", "emoji"), ("smiley", "emoji"),
    ])
    func rowsAnswerToTheirNamesAndNotesAliases(query: String, id: String) {
        #expect(Self.ids(query).first == id)
    }

    @Test func mathFindsTheBlockEquation() {
        #expect(Self.ids("math").first == "easel.equation" || Self.ids("tex").first == "easel.equation")
    }

    @Test func nonsenseFindsNothing() {
        #expect(Self.ids("zzzzzz").isEmpty)
    }

    @Test func anEmptyQueryListsEverything() {
        #expect(Self.ids("").count == EaselSlashCatalog.rows(in: EaselSlashContext()).count)
    }

    @Test(arguments: ["todo", "divider", "mention", "date", "inlineEquation"])
    func rowsWaitForTheirCommandsBeforeTheyAppear(id: String) {
        #expect(!Self.ids("").contains(id))
    }

    @Test(arguments: ["emoji", "text", "quote"])
    func rowsWithWorkingCommandsAppear(id: String) {
        #expect(Self.ids("").contains(id))
    }

    @Test func aToDoSearchFindsNoToDoUntilChecklistsExist() {
        #expect(Self.ids("todo").first != "todo")
    }

    @Test func checklistsAppearOnceTheyExist() {
        #expect(Self.ids("todo", EaselSlashContext(checklist: true)).first == "todo")
    }

    @Test func cellsAndLabelsOfferNoObjects() {
        #expect(!Self.ids("", EaselSlashContext(objects: false)).contains { $0.hasPrefix("easel.") })
    }
}
