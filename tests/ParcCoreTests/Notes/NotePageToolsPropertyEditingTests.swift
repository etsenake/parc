import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsPropertyEditingTests {
    private func properties() -> [NotePageProperty] {
        var list: [NotePageProperty] = []
        list = NotePropertyEditing.adding(.list, to: list)
        list = NotePropertyEditing.adding(.list, to: list)
        list = NotePropertyEditing.adding(.date, to: list)
        return list
    }

    struct InvalidName: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let name: String
    }

    private static let invalidNames = [
        InvalidName(testDescription: "case insensitive collision", name: "tags"),
        InvalidName(testDescription: "blank", name: "  "),
        InvalidName(testDescription: "reserved page setting", name: "Icon"),
        InvalidName(testDescription: "colon", name: "a: b"),
    ]

    @Test func propertyKindsHaveTheExpectedNames() {
        #expect(NotePropertyKind.allCases.map(\.displayName) == ["Text", "Number", "Checkbox", "Date", "List"], "five property kinds")
    }

    @Test(arguments: NotePropertyKind.allCases) func eachPropertyKindSuppliesADefaultOfItsKind(_ kind: NotePropertyKind) {
        #expect(kind.defaultValue.kind == kind)
    }

    @Test func newPropertiesGetUniqueNames() {
        let list = properties()
        #expect(list.map(\.key) == ["Tags", "Tags 2", "Date"], "new properties get unique names")
    }

    @Test(arguments: invalidNames) func invalidPropertyNamesAreRejected(_ example: InvalidName) {
        #expect(NotePropertyEditing.renaming(properties(), at: 1, to: example.name) == nil)
    }

    @Test func renamingAPropertyTrimsWhitespace() {
        let list = properties()
        #expect(NotePropertyEditing.renaming(list, at: 1, to: " Mood ")?[1].key == "Mood", "renames trim")
    }

    @Test func renamingToTheSamePropertyNameChangesNothing() {
        let list = properties()
        #expect(NotePropertyEditing.renaming(list, at: 0, to: "Tags") == list, "renaming to itself changes nothing")
    }

    @Test func aReservedDefaultPropertyNameGetsANumber() {
        #expect(NotePropertyEditing.uniqueKey("icon", among: []) == "icon 2", "a reserved base name gets a number")
    }

    @Test func movingAPropertyReordersIt() {
        let list = properties()
        let moved = NotePropertyEditing.moving(list, from: 2, to: 0)
        #expect(moved.map(\.key) == ["Date", "Tags", "Tags 2"], "drag reorder moves a row")
    }

    @Test func removingAPropertyDropsOnlyThatRow() {
        let list = properties()
        let moved = NotePropertyEditing.moving(list, from: 2, to: 0)
        #expect(NotePropertyEditing.removing(moved, at: 1).map(\.key) == ["Date", "Tags 2"], "delete removes a row")
    }

    @Test func changingAnEmptyListPropertyToTextGivesEmptyText() {
        let list = properties()
        #expect(NotePropertyEditing.changingKind(list, at: 0, to: .text)[0].value == .text(""), "an empty list becomes empty text")
    }
}
