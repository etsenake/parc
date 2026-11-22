import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingListNumberingTests: NoteFixtures {
    struct ListLabel: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String
        let expected: String?
    }

    private nonisolated static let listLabels = [
        ListLabel(testDescription: "first item starts at one", text: "one", expected: "1."),
        ListLabel(testDescription: "children leave the count intact", text: "three", expected: "3."),
        ListLabel(testDescription: "second level starts with letters", text: "a", expected: "a."),
        ListLabel(testDescription: "letters count on", text: "b", expected: "b."),
        ListLabel(testDescription: "third level starts with Roman numerals", text: "i", expected: "i."),
        ListLabel(testDescription: "Roman numerals count on", text: "ii", expected: "ii."),
        ListLabel(testDescription: "fourth level returns to digits", text: "deep", expected: "1."),
        ListLabel(testDescription: "a break restarts the count", text: "again", expected: "1."),
        ListLabel(testDescription: "custom start", text: "five", expected: "5."),
        ListLabel(testDescription: "counting from the custom start", text: "six", expected: "6."),
        ListLabel(testDescription: "unnumbered bullet", text: "dot", expected: nil),
    ]

    struct NumberLabel: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let value: Int
        let level: Int
        let expected: String
    }

    private nonisolated static let numberLabels = [
        NumberLabel(testDescription: "letters roll over", value: 27, level: 1, expected: "aa."),
        NumberLabel(testDescription: "large Roman numerals", value: 1994, level: 2, expected: "mcmxciv."),
        NumberLabel(testDescription: "letters fall back to digits below one", value: 0, level: 1, expected: "0."),
    ]

    @Test(arguments: listLabels) func numberedRunsUseTheirDepthAndStartingNumber(_ example: ListLabel) {
        let page = NotePage(blocks: [
            numbered("one"), numbered("two", [numbered("a", [numbered("i", [numbered("deep")]), numbered("ii")]), numbered("b")]),
            numbered("three"), para("break"), numbered("again"), bullet("dot"), numbered("five", start: 5), numbered("six"),
        ])
        func label(_ text: String) -> String? {
            page.numberLabel(for: page.allBlocks().first { $0.text.plainText == text }!.id)
        }
        #expect(label(example.text) == example.expected)
    }

    @Test(arguments: numberLabels) func listNumbersFormatTheirValueForTheLevel(_ example: NumberLabel) {
        #expect(NoteListNumber(value: example.value, level: example.level).label == example.expected)
    }
}
