import Foundation

@main @MainActor
struct NoteTextInputRulesTests {
    static func typed(_ string: String, in kind: NoteBlockKind = .paragraph, caret: Int? = nil,
                      text: NoteText? = nil, configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteInputRule? {
        let value = text ?? NoteText(string)
        let source = block(kind, value.string, [], configure)
        let position = caret ?? value.length
        let inserted = (value.string as NSString).substring(with: NSRange(location: position - 1, length: 1))
        return NoteInputRules.afterTyping(inserted, text: value, caret: position, block: NoteBlock(kind, text: value, props: source.props))
    }

    static func shortcut(_ string: String, in kind: NoteBlockKind = .paragraph, caret: Int? = nil,
                         configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteBlockShortcut? {
        if case .block(let value) = typed(string, in: kind, caret: caret, configure: configure) { return value }
        return nil
    }

    static func inline(_ string: String, text: NoteText? = nil) -> NoteInlineConversion? {
        if case .inline(let value) = typed(string, text: text) { return value }
        return nil
    }

    static func main() {
        blockShortcuts()
        inlineMarks()
        equationsAndLinks()
        sessionApplication()
        print("NoteTextInputRulesTests passed")
    }

    static func blockShortcuts() {
        expectEqual(shortcut("# ")?.conversion, .heading(1), "# makes a heading 1")
        expectEqual(shortcut("### ")?.conversion, .heading(3), "### makes a heading 3")
        expectEqual(shortcut("#### ")?.conversion, .heading(4), "#### makes a heading 4")
        expect(shortcut("####### ") == nil, "seven hashes stay text")
        expectEqual(shortcut("# Title", caret: 2)?.prefixLength, 2, "a shortcut typed before existing text converts the block")
        expectEqual(shortcut("## ", in: .toggle)?.conversion, .toggleHeading(2), "## in a toggle makes a toggle heading")
        expect(shortcut("# ", in: .heading) == nil, "a heading 1 stays a heading 1")
        expectEqual(shortcut("- ")?.conversion, .bulletedList, "- makes a bullet")
        expectEqual(shortcut("* ")?.bulletMarker, "*", "* keeps its marker for the file")
        expectEqual(shortcut("+ ")?.conversion, .bulletedList, "+ makes a bullet")
        expect(shortcut("- ", in: .bulletedItem) == nil, "a bullet stays a bullet")
        expectEqual(shortcut("1. ")?.conversion, .numberedList, "1. makes a numbered item")
        expect(shortcut("1. ")?.listStart == nil, "1. starts at one")
        expectEqual(shortcut("7. ")?.listStart, 7, "7. starts at seven")
        expectEqual(shortcut("3) ")?.orderedDelimiter, ")", "3) keeps its parenthesis")
        expectEqual(shortcut("a. ")?.conversion, .numberedList, "a. makes a numbered item")
        expectEqual(shortcut("i. ")?.conversion, .numberedList, "i. makes a numbered item")
        expect(shortcut("b. ") == nil, "b. stays text")
        expectEqual(shortcut("[] ")?.conversion, .todo, "[] makes a to-do")
        expectEqual(shortcut("[ ] ")?.conversion, .todo, "[ ] makes a to-do")
        expect(shortcut("[x] ")?.checked == true, "[x] makes a done to-do")
        expect(shortcut("[] ")?.checked == false, "[] starts unchecked")
        expectEqual(shortcut("> ")?.conversion, .toggle, "> makes a toggle")
        expect(shortcut("> ", in: .toggle) == nil, "a toggle stays a toggle")
        expectEqual(shortcut("\" ")?.conversion, .quote, "\" makes a quote")
        expectEqual(shortcut("| ")?.conversion, .quote, "| makes a quote")
        expectEqual(shortcut("---")?.conversion, .divider, "--- makes a divider")
        expect(shortcut("---", caret: 3) != nil && shortcut("--- ") == nil, "--- fires on the third hyphen only")
        expect(typed("---x", caret: 3) == nil, "--- in front of text stays text")
        expectEqual(shortcut("$$")?.conversion, .equation, "$$ makes an equation block")
        expectEqual(shortcut("``` ")?.conversion, .code, "``` and a space make code")
        expectEqual(shortcut("```swift ")?.language, "swift", "```swift and a space make Swift code")
        if case .block(let fence) = NoteInputRules.onNewline(text: "```python", caret: 9, block: para("```python")) {
            expectEqual(fence.conversion, .code, "```python and Return make code")
            expectEqual(fence.language, "python", "the fence language sticks")
            expectEqual(fence.prefixLength, 9, "the whole fence is consumed")
        } else { failTest("```python and Return should make code") }
        expect(NoteInputRules.onNewline(text: "``` x y", caret: 7, block: para("``` x y")) == nil, "a fence with spaces stays text")
        expect(NoteInputRules.onNewline(text: "hello", caret: 5, block: para("hello")) == nil, "plain text splits normally")
        expect(shortcut("# ", in: .code) == nil, "code blocks never convert")
        expect(shortcut("x# ") == nil, "a hash after text stays text")
        let atomic = NoteText.atom(.equation("x")) + NoteText(" ")
        expect(NoteInputRules.afterTyping(" ", text: atomic, caret: 2, block: para()) == nil, "an atom never counts as a marker")
    }

    static func inlineMarks() {
        let bold = inline("hello **world**")
        expectEqual(bold?.text.string, "hello world", "bold delimiters disappear")
        expect(bold?.text.allHave(.bold, in: 6..<11) == true, "bold lands on the word")
        expect(bold?.text.marks(at: 5).bold == false, "the text before stays plain")
        expectEqual(bold?.caret, 11, "the caret sits after the bold run")
        expect(bold?.typingMarks.bold == false, "typing after the conversion is plain")
        expectEqual(bold?.name, "Bold", "the undo step is called Bold")
        expect(inline("hello **world*") == nil, "a half-closed bold waits")
        expect(inline("a **b** c **d*") == nil, "an earlier bold run doesn't confuse a half-closed one")
        let underscores = inline("__init__")
        expect(underscores?.text.allHave(.bold, in: 0..<4) == true, "__x__ makes bold")
        let italic = inline("say *hi*")
        expect(italic?.text.string == "say hi" && italic?.text.allHave(.italic, in: 4..<6) == true, "*x* makes italic")
        expect(inline("say _hi_")?.text.allHave(.italic, in: 4..<6) == true, "_x_ makes italic")
        expect(inline("snake_case_name") == nil, "snake_case stays text")
        expect(inline("😀_x_")?.text.allHave(.italic, in: 2..<3) == true, "_x_ right after an emoji makes italic")
        expect(inline("👩🏽‍💻*hi*")?.text.allHave(.italic, in: 7..<9) == true, "*x* right after a joined emoji makes italic")
        expect(inline("é_x_") == nil, "an accented letter before _ keeps snake case")
        expect(inline("٣_x_") == nil, "any decimal digit before _ keeps snake case")
        expect(!NoteInputRules.isWordCharacter(endingAt: 1, in: [0xD83D]), "a lone lead surrogate isn't a word character")
        expect(!NoteInputRules.isWordCharacter(endingAt: 1, in: [0xDE00]), "a lone trail surrogate isn't a word character")
        expect(NoteInputRules.isWordCharacter(endingAt: 2, in: Array("𝒜".utf16)), "an astral letter is a word character")
        expect(inline("2*3*") == nil, "multiplication stays text")
        expect(inline("a * b *") == nil, "spaced stars stay text")
        expect(inline("** **") == nil, "empty bold stays text")
        let code = inline("run `ls -la`")
        expect(code?.text.string == "run ls -la" && code?.text.allHave(.code, in: 4..<10) == true, "`x` makes inline code")
        expect(code?.typingMarks.code == false, "typing after inline code is plain")
        let strike = inline("~~gone~~")
        expect(strike?.text.string == "gone" && strike?.text.allHave(.strikethrough, in: 0..<4) == true, "~~x~~ strikes through")
        expect(inline("~gone~")?.text.allHave(.strikethrough, in: 0..<4) == true, "~x~ strikes through")
        let highlight = inline("==wow==")
        expect(highlight?.text.string == "wow" && highlight?.text.marks(at: 0).color == .background(.yellow), "==x== highlights")
        let styled = NoteText(pieces: [("**", .plain), ("hi", italicMarks), ("**", .plain)])
        let mixed = inline("", text: styled)
        expect(mixed?.text.marks(at: 0).bold == true && mixed?.text.marks(at: 0).italic == true, "bold keeps existing italic")
        let insideCode = NoteText("x **y**", marks: marks { $0.code = true })
        expect(inline("", text: insideCode) == nil, "inline code is left alone")
    }

    static func equationsAndLinks() {
        let math = inline("so $x^2$")
        expectEqual(math?.text.string, "so " + NoteAtom.character, "$x$ becomes one atom")
        expectEqual(math?.text.marks(at: 3).atom, .equation("x^2"), "the atom carries its TeX")
        expectEqual(math?.caret, 4, "the caret sits after the equation")
        expectEqual(inline("$$e=mc^2$$")?.text.marks(at: 0).atom, .equation("e=mc^2"), "$$x$$ makes an inline equation too")
        expect(inline("costs $5 and $") == nil, "prices stay text")
        expect(inline("a$b$") == nil, "dollars glued to a word stay text")
        let link = inline("see https://parc.app ")
        expectEqual(link?.text.marks(at: 4).link, "https://parc.app", "a bare URL links on space")
        expect(link?.text.marks(at: 20).link == nil, "the space after isn't linked")
        expectEqual(link?.name, "Link", "the undo step is called Link")
        expectEqual(inline("go to www.parc.app. ")?.text.marks(at: 6).link, "https://www.parc.app", "www links get https")
        expect(inline("go to www.parc.app. ")?.text.marks(at: 18).link == nil, "trailing punctuation stays outside the link")
        expect(inline("https:// ") == nil, "a bare scheme isn't a link")
        expect(inline("localhost ") == nil, "plain words aren't links")
        let linked = NoteText(pieces: [("https://a.com", marks { $0.link = "https://b.com" }), (" ", .plain)])
        expect(inline("", text: linked) == nil, "existing links are left alone")
    }

    static func sessionApplication() {
        let first = para("# Title")
        let session = NotePageSession(page: NotePage(blocks: [first]))
        session.setText("# Title", of: (first.id, .body))
        guard let rule = shortcut("# Title", caret: 2) else { failTest("expected a heading shortcut") }
        let position = session.applyBlockShortcut(rule, to: first.id)
        expectEqual(outline(session.page.blocks), "h1 Title", "the paragraph became a heading without its marker")
        expectEqual(position, NotePosition(first.id, 0), "the caret lands at the start of the heading")
        session.undo()
        expectEqual(outline(session.page.blocks), "p # Title", "undo brings back the literal marker")

        let item = para("[x] ")
        let todoSession = NotePageSession(page: NotePage(blocks: [item]))
        guard let checked = shortcut("[x] ") else { failTest("expected a to-do shortcut") }
        todoSession.applyBlockShortcut(checked, to: item.id)
        expectEqual(outline(todoSession.page.blocks), "done", "[x] makes a checked to-do in one go")
        todoSession.undo()
        expectEqual(outline(todoSession.page.blocks), "p [x] ", "one undo step undoes the whole conversion")

        let fence = para("```swift ")
        let codeSession = NotePageSession(page: NotePage(blocks: [fence]))
        guard let codeRule = shortcut("```swift ") else { failTest("expected a code shortcut") }
        codeSession.applyBlockShortcut(codeRule, to: fence.id)
        expect(codeSession.page.blocks[0].kind == .code && codeSession.page.blocks[0].props.language == "swift", "code keeps the language")

        let rule3 = para("---")
        let dividerSession = NotePageSession(page: NotePage(blocks: [rule3]))
        guard let dividerRule = shortcut("---") else { failTest("expected a divider shortcut") }
        let landing = dividerSession.applyBlockShortcut(dividerRule, to: rule3.id)
        expectEqual(outline(dividerSession.page.blocks), "divider\np", "--- leaves a divider and a fresh line")
        expectEqual(landing?.block, dividerSession.page.blocks[1].id, "the caret moves to the fresh line")

        let numberedSource = para("4. ")
        let numberedSession = NotePageSession(page: NotePage(blocks: [numberedSource]))
        numberedSession.applyBlockShortcut(shortcut("4. ")!, to: numberedSource.id)
        expectEqual(outline(numberedSession.page.blocks), "ol@4", "4. starts the list at four")

        let typedBold = para("a **b**")
        let inlineSession = NotePageSession(page: NotePage(blocks: [typedBold]))
        guard let conversion = inline("a **b**") else { failTest("expected bold") }
        inlineSession.applyInlineConversion(conversion, to: typedBold.id)
        expect(inlineSession.page.blocks[0].text.allHave(.bold, in: 2..<3), "bold reaches the session")
        expectEqual(inlineSession.selection.caret, NotePosition(typedBold.id, 3), "the caret follows the bold run")
        inlineSession.undo()
        expectEqual(inlineSession.page.blocks[0].text.string, "a **b**", "undo restores the asterisks")
    }
}
