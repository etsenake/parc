import Foundation
import Testing
@testable import ParcCore

struct NoteCodeEditingTestsExitTests {
    struct ReturnCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String
        let selection: Range<Int>
        let exits: Bool

        init(_ label: String, _ text: String, _ selection: Range<Int>, _ exits: Bool) {
            testDescription = label
            self.text = text
            self.selection = selection
            self.exits = exits
        }
    }

    @Test(arguments: [
        ReturnCase("Return on an empty last line exits", "echo hi\n", 8..<8, true),
        ReturnCase("Return after code stays inside", "echo hi", 7..<7, false),
        ReturnCase("Return away from the end stays inside", "echo hi\n", 2..<2, false),
        ReturnCase("an empty line in the middle stays inside", "a\n\nb", 2..<2, false),
        ReturnCase("one blank indented line stays inside", "  x\n  ", 6..<6, false),
        ReturnCase("a second blank indented line exits", "  x\n\n  ", 7..<7, true),
        ReturnCase("an empty block exits on the second Return", "\n", 1..<1, true),
        ReturnCase("the first Return in an empty block stays inside", "", 0..<0, false),
        ReturnCase("a selection never exits", "a\n", 1..<2, false),
    ])
    func returnExitsOnlyAtTheEndOfAnEmptyLastLine(fixture: ReturnCase) {
        #expect(NoteCodeEditing.exitsOnReturn(fixture.text, selection: fixture.selection) == fixture.exits)
    }

    struct TrimCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String
        let trimmed: String

        init(_ label: String, _ text: String, _ trimmed: String) {
            testDescription = label
            self.text = text
            self.trimmed = trimmed
        }
    }

    @Test(arguments: [
        TrimCase("exiting drops the empty line", "echo hi\n", "echo hi"),
        TrimCase("exiting drops trailing blank lines only", "  x  \n\n  ", "  x  "),
        TrimCase("an empty block stays empty", "\n", ""),
    ])
    func exitingTrimsOnlyTrailingBlankLines(fixture: TrimCase) {
        #expect(NoteCodeEditing.trimmedForExit(fixture.text) == fixture.trimmed)
    }
}
