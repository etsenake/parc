import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteCodeEditingTests {
    func check(_ edit: NoteCodeEdit?, on text: String, gives expected: String, caret: Range<Int>, _ message: String) {
        guard let edit else { Issue.record("\(message): no edit"); return }
        let result = edit.applied(to: text)
        if result != expected { Issue.record("\(message): got \(result.debugDescription), wanted \(expected.debugDescription)") }
        if edit.selection != caret { Issue.record("\(message): selection \(edit.selection), wanted \(caret)") }
    }

    @Test func widths() {
        #expect(NoteCodeEditing.indentWidth(forLanguage: "python") == 4, "Python indents by four")
        #expect(NoteCodeEditing.indentWidth(forLanguage: " Swift ") == 4, "language names are trimmed and case-insensitive")
        #expect(NoteCodeEditing.indentWidth(forLanguage: "javascript") == 2, "JavaScript indents by two")
        #expect(NoteCodeEditing.indentWidth(forLanguage: "") == 2, "plain text indents by two, like Notion")
        #expect(NoteCodeEditing.indent(forLanguage: "makefile") == .tab(4), "Makefiles need real tabs")
        #expect(NoteCodeEditing.indent(forLanguage: "go", text: "func a() {\n\treturn\n}") == .tab(4), "tab-indented code keeps tabs")
        #expect(NoteCodeEditing.indent(forLanguage: "go", text: "func a() {\n    return\n}") == .spaces(4), "space-indented code keeps spaces")
    }

    @Test func newlines() {
        let two = NoteCodeIndent.spaces(2), four = NoteCodeIndent.spaces(4)
        check(NoteCodeEditing.newline(in: "  foo", selection: 5..<5, indent: two), on: "  foo",
              gives: "  foo\n  ", caret: 8..<8, "Return keeps the leading whitespace")
        check(NoteCodeEditing.newline(in: "if (x) {", selection: 8..<8, indent: two, language: "javascript"), on: "if (x) {",
              gives: "if (x) {\n  ", caret: 11..<11, "Return indents after an opening brace")
        check(NoteCodeEditing.newline(in: "f() {}", selection: 5..<5, indent: two), on: "f() {}",
              gives: "f() {\n  \n}", caret: 8..<8, "Return between braces opens an indented line")
        check(NoteCodeEditing.newline(in: "def f():", selection: 8..<8, indent: four, language: "python"), on: "def f():",
              gives: "def f():\n    ", caret: 13..<13, "Return indents after a colon")
        check(NoteCodeEditing.newline(in: "    return x", selection: 12..<12, indent: four, language: "python"), on: "    return x",
              gives: "    return x\n", caret: 13..<13, "Python dedents after return")
        check(NoteCodeEditing.newline(in: "    returned = 1", selection: 16..<16, indent: four, language: "python"),
              on: "    returned = 1", gives: "    returned = 1\n    ", caret: 21..<21, "only the return keyword dedents")
        check(NoteCodeEditing.newline(in: "a\n  ", selection: 4..<4, indent: two), on: "a\n  ",
              gives: "a\n\n  ", caret: 5..<5, "a blank line loses its leftover indentation")
        check(NoteCodeEditing.newline(in: "  foo", selection: 2..<2, indent: two), on: "  foo",
              gives: "\n  foo", caret: 3..<3, "Return in the indentation pushes the line down intact")
        check(NoteCodeEditing.newline(in: "a = b   c", selection: 6..<6, indent: two), on: "a = b   c",
              gives: "a = b \nc", caret: 7..<7, "spaces after the caret don't follow it down")
        check(NoteCodeEditing.newline(in: "std::", selection: 5..<5, indent: two, language: "cpp"), on: "std::",
              gives: "std::\n", caret: 6..<6, "a scope operator isn't a block")
        check(NoteCodeEditing.newline(in: "<div>", selection: 5..<5, indent: two, language: "html"), on: "<div>",
              gives: "<div>\n  ", caret: 8..<8, "Return indents inside an opening tag")
        check(NoteCodeEditing.newline(in: "<br>", selection: 4..<4, indent: two, language: "html"), on: "<br>",
              gives: "<br>\n", caret: 5..<5, "void elements don't indent")
        check(NoteCodeEditing.newline(in: "<p></p>", selection: 3..<3, indent: two, language: "html"), on: "<p></p>",
              gives: "<p>\n  \n</p>", caret: 6..<6, "Return between tags opens an indented line")
        check(NoteCodeEditing.newline(in: "  x {y", selection: 5..<6, indent: two), on: "  x {y",
              gives: "  x {\n    ", caret: 10..<10, "Return replaces the selection")
        check(NoteCodeEditing.newline(in: "items.each do |item|", selection: 20..<20, indent: two, language: "ruby"),
              on: "items.each do |item|", gives: "items.each do |item|\n  ", caret: 23..<23, "Ruby blocks indent")
    }

    @Test func tabs() {
        let four = NoteCodeIndent.spaces(4), two = NoteCodeIndent.spaces(2)
        check(NoteCodeEditing.tab(in: "ab", selection: 2..<2, indent: four), on: "ab",
              gives: "ab  ", caret: 4..<4, "Tab pads to the next tab stop")
        check(NoteCodeEditing.tab(in: "", selection: 0..<0, indent: two), on: "",
              gives: "  ", caret: 2..<2, "Tab inserts the language's indent")
        check(NoteCodeEditing.tab(in: "x", selection: 1..<1, indent: .tab(4)), on: "x",
              gives: "x\t", caret: 2..<2, "tab-indented code gets a tab")
        check(NoteCodeEditing.tab(in: "a\nb", selection: 0..<3, indent: two), on: "a\nb",
              gives: "  a\n  b", caret: 0..<7, "Tab indents every selected line")
        check(NoteCodeEditing.tab(in: "a\n\nb", selection: 0..<4, indent: two), on: "a\n\nb",
              gives: "  a\n\n  b", caret: 0..<8, "empty lines stay empty")
        check(NoteCodeEditing.tab(in: "a\nb\nc", selection: 1..<4, indent: two), on: "a\nb\nc",
              gives: "  a\n  b\nc", caret: 3..<8, "a selection ending at a line start leaves that line alone")
        check(NoteCodeEditing.tab(in: "hello", selection: 0..<5, indent: two), on: "hello",
              gives: "  hello", caret: 0..<7, "a whole selected line indents")
        check(NoteCodeEditing.tab(in: "hello", selection: 1..<3, indent: two), on: "hello",
              gives: "h lo", caret: 2..<2, "a partial selection is replaced up to the next tab stop")
    }

    @Test func dedents() {
        let two = NoteCodeIndent.spaces(2), four = NoteCodeIndent.spaces(4)
        check(NoteCodeEditing.dedentLines(in: "    a\n  b", selection: 0..<9, indent: two), on: "    a\n  b",
              gives: "  a\nb", caret: 0..<5, "Shift-Tab dedents every selected line")
        check(NoteCodeEditing.dedentLines(in: "    x", selection: 5..<5, indent: four), on: "    x",
              gives: "x", caret: 1..<1, "Shift-Tab dedents the caret's line")
        check(NoteCodeEditing.dedentLines(in: "   x", selection: 1..<1, indent: four), on: "   x",
              gives: "x", caret: 0..<0, "a caret inside the indentation moves to the line start")
        check(NoteCodeEditing.dedentLines(in: "\t\tx", selection: 3..<3, indent: .tab(4)), on: "\t\tx",
              gives: "\tx", caret: 2..<2, "Shift-Tab removes one tab")
        #expect(NoteCodeEditing.dedentLines(in: "x\ny", selection: 0..<3, indent: two) == nil, "nothing to dedent gives no edit")
    }

    @Test func brackets() {
        let two = NoteCodeIndent.spaces(2)
        check(NoteCodeEditing.closingBracket("}", in: "if {\n    ", selection: 9..<9, indent: two), on: "if {\n    ",
              gives: "if {\n  }", caret: 8..<8, "a closing brace on an indented blank line dedents")
        #expect(NoteCodeEditing.closingBracket("}", in: "x = {", selection: 5..<5, indent: two) == nil, "braces after code type normally")
        #expect(NoteCodeEditing.closingBracket("}", in: "", selection: 0..<0, indent: two) == nil, "no indentation, nothing to dedent")
        #expect(NoteCodeEditing.closingBracket("a", in: "  ", selection: 2..<2, indent: two) == nil, "letters never dedent")
    }

    @Test func backspace() {
        let four = NoteCodeIndent.spaces(4)
        check(NoteCodeEditing.deleteBackward(in: "    ", selection: 4..<4, indent: four), on: "    ",
              gives: "", caret: 0..<0, "Backspace in indentation removes a whole step")
        check(NoteCodeEditing.deleteBackward(in: "      ", selection: 6..<6, indent: four), on: "      ",
              gives: "    ", caret: 4..<4, "Backspace returns to the previous tab stop")
        #expect(NoteCodeEditing.deleteBackward(in: "     ", selection: 5..<5, indent: four) == nil, "a single space deletes normally")
        #expect(NoteCodeEditing.deleteBackward(in: "  x ", selection: 4..<4, indent: four) == nil, "spaces after code delete normally")
        #expect(NoteCodeEditing.deleteBackward(in: "\t", selection: 1..<1, indent: .tab(4)) == nil, "tabs delete normally")
    }

    @Test func escape() {
        #expect(NoteCodeEditing.exitsOnReturn("echo hi\n", selection: 8..<8), "Return on an empty last line exits")
        #expect(!NoteCodeEditing.exitsOnReturn("echo hi", selection: 7..<7), "Return after code stays inside")
        #expect(!NoteCodeEditing.exitsOnReturn("echo hi\n", selection: 2..<2), "Return away from the end stays inside")
        #expect(!NoteCodeEditing.exitsOnReturn("a\n\nb", selection: 2..<2), "an empty line in the middle stays inside")
        #expect(!NoteCodeEditing.exitsOnReturn("  x\n  ", selection: 6..<6), "one blank indented line stays inside")
        #expect(NoteCodeEditing.exitsOnReturn("  x\n\n  ", selection: 7..<7), "a second blank indented line exits")
        #expect(NoteCodeEditing.exitsOnReturn("\n", selection: 1..<1), "an empty block exits on the second Return")
        #expect(!NoteCodeEditing.exitsOnReturn("", selection: 0..<0), "the first Return in an empty block stays inside")
        #expect(!NoteCodeEditing.exitsOnReturn("a\n", selection: 1..<2), "a selection never exits")
        #expect(NoteCodeEditing.trimmedForExit("echo hi\n") == "echo hi", "exiting drops the empty line")
        #expect(NoteCodeEditing.trimmedForExit("  x  \n\n  ") == "  x  ", "exiting drops trailing blank lines only")
        #expect(NoteCodeEditing.trimmedForExit("\n") == "", "an empty block stays empty")
    }
}
