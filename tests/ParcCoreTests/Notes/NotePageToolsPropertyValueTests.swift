import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsPropertyValueTests {
    struct Conversion: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let value: NotePropertyValue
        let kind: NotePropertyKind
        let expected: NotePropertyValue
    }

    private static let conversions = [
        Conversion(testDescription: "text turns into a number", value: .text("42"), kind: .number, expected: .number(42)),
        Conversion(testDescription: "grouped numbers parse", value: .text("1,250.5"), kind: .number, expected: .number(1250.5)),
        Conversion(testDescription: "nonsense numbers fall back to zero", value: .text("soon"), kind: .number, expected: .number(0)),
        Conversion(testDescription: "whole numbers print without decimals", value: .number(3), kind: .text, expected: .text("3")),
        Conversion(testDescription: "fractions keep their digits", value: .number(2.5), kind: .text, expected: .text("2.5")),
        Conversion(testDescription: "yes checks the box", value: .text("yes"), kind: .checkbox, expected: .checkbox(true)),
        Conversion(testDescription: "a checked box reads Yes", value: .checkbox(true), kind: .text, expected: .text("Yes")),
        Conversion(testDescription: "an unchecked box reads empty", value: .checkbox(false), kind: .text, expected: .text("")),
        Conversion(testDescription: "text splits into unique tags", value: .text("a, b, a, ,c"), kind: .list, expected: .list(["a", "b", "c"])),
        Conversion(testDescription: "tags join back into text", value: .list(["a", "b"]), kind: .text, expected: .text("a, b")),
        Conversion(testDescription: "an ISO date stays a date", value: .text("2026-11-20"), kind: .date, expected: .date("2026-11-20")),
        Conversion(testDescription: "unparseable dates go empty", value: .text("tomorrow"), kind: .date, expected: .date("")),
        Conversion(testDescription: "a filled date checks the box", value: .date("2026-02-30"), kind: .checkbox, expected: .checkbox(true)),
    ]

    @Test(arguments: conversions) func convertingAPropertyValueProducesTheExpectedValue(_ example: Conversion) {
        #expect(example.value.converted(to: example.kind) == example.expected)
    }

    @Test func anImpossibleDateCannotBeParsed() {
        #expect(NotePropertyEditing.date(from: "2026-02-30") == nil, "February 30th isn't a date")
    }

    @Test func aLeapDayRoundTripsThroughItsString() {
        let date = NotePropertyEditing.date(from: "2024-02-29")
        #expect(date != nil && NotePropertyEditing.dateString(from: date!) == "2024-02-29", "dates round-trip through strings")
    }

    @Test func aDateDisplaysItsYear() {
        #expect(NotePropertyValue.date("2024-02-29").displayText.contains("2024"), "dates display with their year")
    }

    @Test func addingATagSkipsCaseInsensitiveDuplicates() {
        #expect(NotePropertyEditing.addingTag(" Fun ", to: ["fun"]) == ["fun"], "duplicate tags are skipped")
    }

    @Test func commasInTagsBecomeSpaces() {
        #expect(NotePropertyEditing.addingTag("a,b", to: []) == ["a b"], "commas can't sneak into a tag")
    }

    @Test func emptinessDependsOnThePropertyKind() {
        #expect(NotePropertyValue.list([]).isEmpty && !NotePropertyValue.number(0).isEmpty, "emptiness depends on the kind")
    }
}
