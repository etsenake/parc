import Foundation
import Testing
@testable import ParcCore

struct NoteCodeEditingTestsIndentationTests {
    private typealias Edit = NoteCodeEditingTestsSupport

    struct WidthCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let language: String
        let width: Int

        init(_ label: String, _ language: String, _ width: Int) {
            testDescription = label
            self.language = language
            self.width = width
        }
    }

    @Test(arguments: [
        WidthCase("Python indents by four", "python", 4),
        WidthCase("Swift names are trimmed and case-insensitive", " Swift ", 4),
        WidthCase("JavaScript indents by two", "javascript", 2),
        WidthCase("plain text indents by two", "", 2),
    ])
    func eachLanguageUsesItsIndentWidth(fixture: WidthCase) {
        #expect(NoteCodeEditing.indentWidth(forLanguage: fixture.language) == fixture.width)
    }

    @Test
    func makefilesIndentWithTabs() {
        #expect(NoteCodeEditing.indent(forLanguage: "makefile") == .tab(4), "Makefiles need real tabs")
    }

    @Test
    func tabIndentedGoKeepsTabs() {
        #expect(NoteCodeEditing.indent(forLanguage: "go", text: "func a() {\n\treturn\n}") == .tab(4), "tab-indented code keeps tabs")
    }

    @Test
    func spaceIndentedGoKeepsSpaces() {
        #expect(NoteCodeEditing.indent(forLanguage: "go", text: "func a() {\n    return\n}") == .spaces(4), "space-indented code keeps spaces")
    }

    @Test
    func tabPadsToTheNextStop() {
        Edit.check(NoteCodeEditing.tab(in: "ab", selection: 2..<2, indent: .spaces(4)), on: "ab",
              gives: "ab  ", caret: 4..<4, "Tab pads to the next tab stop")
    }

    @Test
    func tabInsertsTheLanguagesIndent() {
        Edit.check(NoteCodeEditing.tab(in: "", selection: 0..<0, indent: .spaces(2)), on: "",
              gives: "  ", caret: 2..<2, "Tab inserts the language's indent")
    }

    @Test
    func tabKeepsTheIndentAsATabCharacter() {
        Edit.check(NoteCodeEditing.tab(in: "x", selection: 1..<1, indent: .tab(4)), on: "x",
              gives: "x\t", caret: 2..<2, "tab-indented code gets a tab")
    }

    @Test
    func tabIndentsEachSelectedLine() {
        Edit.check(NoteCodeEditing.tab(in: "a\nb", selection: 0..<3, indent: .spaces(2)), on: "a\nb",
              gives: "  a\n  b", caret: 0..<7, "Tab indents every selected line")
    }

    @Test
    func tabLeavesSelectedEmptyLinesEmpty() {
        Edit.check(NoteCodeEditing.tab(in: "a\n\nb", selection: 0..<4, indent: .spaces(2)), on: "a\n\nb",
              gives: "  a\n\n  b", caret: 0..<8, "empty lines stay empty")
    }

    @Test
    func tabLeavesOutALineStartingAtTheEndOfTheSelection() {
        Edit.check(NoteCodeEditing.tab(in: "a\nb\nc", selection: 1..<4, indent: .spaces(2)), on: "a\nb\nc",
              gives: "  a\n  b\nc", caret: 3..<8, "a selection ending at a line start leaves that line alone")
    }

    @Test
    func tabIndentsAWholeSelectedLine() {
        Edit.check(NoteCodeEditing.tab(in: "hello", selection: 0..<5, indent: .spaces(2)), on: "hello",
              gives: "  hello", caret: 0..<7, "a whole selected line indents")
    }

    @Test
    func tabReplacesAPartialSelectionUpToTheNextStop() {
        Edit.check(NoteCodeEditing.tab(in: "hello", selection: 1..<3, indent: .spaces(2)), on: "hello",
              gives: "h lo", caret: 2..<2, "a partial selection is replaced up to the next tab stop")
    }

    @Test
    func shiftTabDedentsEverySelectedLine() {
        Edit.check(NoteCodeEditing.dedentLines(in: "    a\n  b", selection: 0..<9, indent: .spaces(2)), on: "    a\n  b",
              gives: "  a\nb", caret: 0..<5, "Shift-Tab dedents every selected line")
    }

    @Test
    func shiftTabDedentsTheCaretLine() {
        Edit.check(NoteCodeEditing.dedentLines(in: "    x", selection: 5..<5, indent: .spaces(4)), on: "    x",
              gives: "x", caret: 1..<1, "Shift-Tab dedents the caret's line")
    }

    @Test
    func shiftTabMovesACaretInTheIndentToTheStart() {
        Edit.check(NoteCodeEditing.dedentLines(in: "   x", selection: 1..<1, indent: .spaces(4)), on: "   x",
              gives: "x", caret: 0..<0, "a caret inside the indentation moves to the line start")
    }

    @Test
    func shiftTabRemovesOneTab() {
        Edit.check(NoteCodeEditing.dedentLines(in: "\t\tx", selection: 3..<3, indent: .tab(4)), on: "\t\tx",
              gives: "\tx", caret: 2..<2, "Shift-Tab removes one tab")
    }

    @Test
    func shiftTabDoesNothingWhenThereIsNoIndent() {
        #expect(NoteCodeEditing.dedentLines(in: "x\ny", selection: 0..<3, indent: .spaces(2)) == nil, "nothing to dedent gives no edit")
    }

    @Test
    func aClosingBraceDedentsAnIndentedBlankLine() {
        Edit.check(NoteCodeEditing.closingBracket("}", in: "if {\n    ", selection: 9..<9, indent: .spaces(2)), on: "if {\n    ",
              gives: "if {\n  }", caret: 8..<8, "a closing brace on an indented blank line dedents")
    }

    @Test
    func aClosingBraceAfterCodeTypesNormally() {
        #expect(NoteCodeEditing.closingBracket("}", in: "x = {", selection: 5..<5, indent: .spaces(2)) == nil, "braces after code type normally")
    }

    @Test
    func aClosingBraceDoesNotDedentAnUnindentedLine() {
        #expect(NoteCodeEditing.closingBracket("}", in: "", selection: 0..<0, indent: .spaces(2)) == nil, "no indentation, nothing to dedent")
    }

    @Test
    func aLetterNeverTriggersADedent() {
        #expect(NoteCodeEditing.closingBracket("a", in: "  ", selection: 2..<2, indent: .spaces(2)) == nil, "letters never dedent")
    }

    @Test
    func backspaceInIndentationRemovesAWholeStep() {
        Edit.check(NoteCodeEditing.deleteBackward(in: "    ", selection: 4..<4, indent: .spaces(4)), on: "    ",
              gives: "", caret: 0..<0, "Backspace in indentation removes a whole step")
    }

    @Test
    func backspaceMovesToThePreviousTabStop() {
        Edit.check(NoteCodeEditing.deleteBackward(in: "      ", selection: 6..<6, indent: .spaces(4)), on: "      ",
              gives: "    ", caret: 4..<4, "Backspace returns to the previous tab stop")
    }

    @Test
    func aSingleSpaceDeletesNormally() {
        #expect(NoteCodeEditing.deleteBackward(in: "     ", selection: 5..<5, indent: .spaces(4)) == nil, "a single space deletes normally")
    }

    @Test
    func spacesAfterCodeDeleteNormally() {
        #expect(NoteCodeEditing.deleteBackward(in: "  x ", selection: 4..<4, indent: .spaces(4)) == nil, "spaces after code delete normally")
    }

    @Test
    func tabsDeleteNormally() {
        #expect(NoteCodeEditing.deleteBackward(in: "\t", selection: 1..<1, indent: .tab(4)) == nil, "tabs delete normally")
    }
}
