import Foundation
import Testing
@testable import ParcCore

struct NoteCodeEditingTestsNewlineTests {
    private typealias Edit = NoteCodeEditingTestsSupport

    struct NewlineCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String
        let selection: Range<Int>
        let indent: NoteCodeIndent
        let expected: String
        let caret: Range<Int>
        let language: String

        init(_ label: String, _ text: String, _ selection: Range<Int>, _ indent: NoteCodeIndent,
             _ expected: String, _ caret: Range<Int>, language: String = "") {
            testDescription = label
            self.text = text
            self.selection = selection
            self.indent = indent
            self.expected = expected
            self.caret = caret
            self.language = language
        }
    }

    @Test(arguments: [
        NewlineCase("Return keeps the leading whitespace",
                    "  foo", 5..<5, .spaces(2), "  foo\n  ", 8..<8),
        NewlineCase("Return indents after an opening brace",
                    "if (x) {", 8..<8, .spaces(2), "if (x) {\n  ", 11..<11, language: "javascript"),
        NewlineCase("Return between braces opens an indented line",
                    "f() {}", 5..<5, .spaces(2), "f() {\n  \n}", 8..<8),
        NewlineCase("Return indents after a colon",
                    "def f():", 8..<8, .spaces(4), "def f():\n    ", 13..<13, language: "python"),
        NewlineCase("Python dedents after return",
                    "    return x", 12..<12, .spaces(4), "    return x\n", 13..<13, language: "python"),
        NewlineCase("only the return keyword dedents",
                    "    returned = 1", 16..<16, .spaces(4), "    returned = 1\n    ", 21..<21, language: "python"),
        NewlineCase("a blank line loses its leftover indentation",
                    "a\n  ", 4..<4, .spaces(2), "a\n\n  ", 5..<5),
        NewlineCase("Return in the indentation pushes the line down intact",
                    "  foo", 2..<2, .spaces(2), "\n  foo", 3..<3),
        NewlineCase("spaces after the caret don't follow it down",
                    "a = b   c", 6..<6, .spaces(2), "a = b \nc", 7..<7),
        NewlineCase("a scope operator isn't a block",
                    "std::", 5..<5, .spaces(2), "std::\n", 6..<6, language: "cpp"),
        NewlineCase("Return indents inside an opening tag",
                    "<div>", 5..<5, .spaces(2), "<div>\n  ", 8..<8, language: "html"),
        NewlineCase("void elements don't indent",
                    "<br>", 4..<4, .spaces(2), "<br>\n", 5..<5, language: "html"),
        NewlineCase("Return between tags opens an indented line",
                    "<p></p>", 3..<3, .spaces(2), "<p>\n  \n</p>", 6..<6, language: "html"),
        NewlineCase("Return replaces the selection",
                    "  x {y", 5..<6, .spaces(2), "  x {\n    ", 10..<10),
        NewlineCase("Ruby blocks indent",
                    "items.each do |item|", 20..<20, .spaces(2), "items.each do |item|\n  ", 23..<23, language: "ruby"),
    ])
    func returnInsertsTheExpectedTextAndMovesTheCaret(fixture: NewlineCase) {
        let edit = NoteCodeEditing.newline(in: fixture.text, selection: fixture.selection,
                                           indent: fixture.indent, language: fixture.language)
        Edit.check(edit, on: fixture.text, gives: fixture.expected, caret: fixture.caret, fixture.testDescription)
    }
}
