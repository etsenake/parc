import Foundation

@main @MainActor
struct NoteButtonTests {
    static var failures = 0

    static func expect(_ value: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        guard !value else { return }
        failures += 1
        FileHandle.standardError.write(Data("NoteButtonTests.swift:\(line): \(message())\n".utf8))
    }

    static func main() {
        implicitInsertIsPlainDetails()
        explicitActionsKeepTheirOrder()
        emptyButtonsStayEmpty()
        iconColorAndAnchorSurvive()
        awkwardNamesSurvive()
        nestedButtonsAndContainers()
        blankLinesInTemplatesSurvive()
        handWrittenLeadingContentBecomesAnInsert()
        templateIDsDoNotMatter()
        pressInsertsBelowAndAbove()
        pressInsertsAtTopAndBottom()
        pressIsOneUndoStepAcrossConfirmation()
        cancelledConfirmationStops()
        openActionsReportTargets()
        readOnlyPressInsertsNothing()
        columnsTemplateLeavesColumns()
        turnIntoButtonAndBack()
        unwrapRestoresBlocks()
        htmlRoundTrip()
        plainTextUsesName()
        editingSessionIsOneUndoStep()
        if failures > 0 { failTest("NoteButtonTests: \(failures) failures") }
        print("NoteButtonTests passed")
    }

    static func roundTrip(_ source: String, _ label: String, line: UInt = #line) -> NotePage {
        let page = NoteMarkdown.parse(source)
        let written = NoteMarkdown.serialize(page)
        expect(written == source, "\(label): text changed\n--- source\n\(source)--- written\n\(written)", line: line)
        let again = NoteMarkdown.parse(written)
        expect(MarkdownCheck.same(page, again), "\(label): model changed\n\(MarkdownCheck.describe(page.blocks))\n---\n\(MarkdownCheck.describe(again.blocks))", line: line)
        return page
    }

    static func implicitInsertIsPlainDetails() {
        let source = """
        <details>
        <summary>✅ Add a task <!-- parc button icon="✅" --></summary>

        - [ ] New task
        - [ ] Ask Sam

        </details>

        """
        let page = roundTrip(source, "implicit")
        guard let block = page.blocks.first else { expect(false, "no block"); return }
        expect(block.kind == .button, "reads a button, got \(block.kind)")
        expect(block.props.icon == "✅", "icon")
        expect(block.buttonValue.name == "Add a task", "name strips the icon, got \(block.buttonValue.name)")
        expect(block.buttonValue.actions.count == 1, "one action")
        if case .insert(let placement, let blocks) = block.buttonValue.actions.first {
            expect(placement == .below, "below")
            expect(blocks.map(\.kind) == [.todo, .todo], "template is two to-dos")
            expect(blocks.map(\.text.plainText) == ["New task", "Ask Sam"], "template text")
        } else {
            expect(false, "first action inserts")
        }
        expect(!block.props.expanded, "closed on GitHub")
    }

    static func explicitActionsKeepTheirOrder() {
        let source = """
        <details>
        <summary>🚀 Launch <!-- parc button icon="🚀" --></summary>

        <!-- parc confirm="Ready to &quot;launch&quot;?" -->

        <!-- parc insert="top" -->

        ## Launch log

        Went well.

        <!-- parc open="https://example.com/status" -->

        <!-- parc insert="bottom" -->

        </details>

        """
        let page = roundTrip(source, "explicit")
        let actions = page.blocks.first?.buttonValue.actions ?? []
        expect(actions.map(\.kind) == [.confirm, .insert, .open, .insert], "order kept, got \(actions.map(\.kind))")
        if actions.count == 4 {
            expect(actions[0] == .confirm(message: "Ready to \"launch\"?"), "message unescaped")
            if case .insert(let placement, let blocks) = actions[1] {
                expect(placement == .top, "top")
                expect(blocks.map(\.kind) == [.heading, .paragraph], "heading and paragraph")
            }
            expect(actions[2] == .open(target: "https://example.com/status"), "open target")
            expect(actions[3] == .insert(placement: .bottom, blocks: []), "empty insert at the bottom")
        }
    }

    static func emptyButtonsStayEmpty() {
        let source = """
        <details>
        <summary>Nothing yet <!-- parc button --></summary>
        </details>

        """
        let page = roundTrip(source, "empty")
        expect(page.blocks.first?.buttonValue.actions.isEmpty == true, "no actions")
        let starter = NotePage(blocks: [.button()])
        let written = NoteMarkdown.serialize(starter)
        expect(written == "<details>\n<summary> <!-- parc button --></summary>\n\n<!-- parc insert=\"below\" -->\n\n</details>\n",
               "starter button writes an explicit empty insert, got \(written)")
        expect(MarkdownCheck.same(starter, NoteMarkdown.parse(written)), "starter round trip")
        var onlyBlank = NotePage(blocks: [.button(actions: [.insert(placement: .below, blocks: [.paragraph()])])])
        onlyBlank.blocks[0].props.icon = "🫥"
        expect(MarkdownCheck.same(onlyBlank, NoteMarkdown.parse(NoteMarkdown.serialize(onlyBlank))), "blank template round trip")
    }

    static func iconColorAndAnchorSurvive() {
        var block = NoteBlock.button(name: "Daily", icon: "📓", actions: [.insert(placement: .above, blocks: [.paragraph("Today")])])
        block.color = .background(.blue)
        block.props.anchor = "k3x9qa"
        block.props.expanded = true
        let page = NotePage(blocks: [block, .paragraph("After")])
        let written = NoteMarkdown.serialize(page)
        expect(written.hasPrefix("<details open>\n<summary>📓 Daily <!-- parc button icon=\"📓\" color=\"blue_background\" id=\"k3x9qa\" --></summary>"),
               "summary carries the settings, got \(written)")
        expect(MarkdownCheck.same(page, NoteMarkdown.parse(written)), "round trip")
    }

    static func awkwardNamesSurvive() {
        let names = ["**not bold**", "<b>tag</b>", "a & b", "[[Ideas]]", "$5 or $x$", "1. list", "# hash", "https://x.y", "</summary>",
                     "<!-- hidden -->", "😀", "😀 😀", "back\\slash", "a | b", "under_score"]
        for name in names {
            for icon in [nil, "😀"] as [String?] {
                let page = NotePage(blocks: [.button(name: name, icon: icon, actions: [.insert(placement: .below, blocks: [.paragraph("x")])])])
                let written = NoteMarkdown.serialize(page)
                let reread = NoteMarkdown.parse(written)
                expect(MarkdownCheck.same(page, reread), "name \(String(reflecting: name)) icon \(icon ?? "-") survives\n\(written)\(MarkdownCheck.describe(reread.blocks))")
            }
        }
    }

    static func nestedButtonsAndContainers() {
        let inner = NoteBlock.button(name: "Inner", actions: [.confirm(message: "Sure?"), .insert(placement: .below, blocks: [.paragraph("deep")])])
        let toggle = NoteBlock(.toggle, text: "Fold", children: [.paragraph("hidden")])
        let outer = NoteBlock.button(name: "Outer", actions: [.insert(placement: .below, blocks: [inner, toggle]), .open(target: "Other%20Note.md")])
        let list = NoteBlock(.bulletedItem, text: "Item", children: [outer])
        let columns = NoteBlock(.columns, children: [
            NoteBlock(.column, children: [.button(name: "Left", actions: [.insert(placement: .below, blocks: [NoteBlock(.paragraph, text: "p", children: [.paragraph("kid")])])])]),
            NoteBlock(.column, children: [.paragraph("Right")]),
        ])
        let page = NotePage(blocks: [list, columns, NoteBlock(.toggle, text: "T", children: [outer])])
        let written = NoteMarkdown.serialize(page)
        let reread = NoteMarkdown.parse(written)
        expect(MarkdownCheck.same(page, reread), "nested buttons survive\n\(written)\(MarkdownCheck.describe(reread.blocks))")
    }

    static func blankLinesInTemplatesSurvive() {
        let shapes: [[NoteBlock]] = [
            [.paragraph(), .paragraph("a")],
            [.paragraph("a"), .paragraph()],
            [.paragraph("a"), .paragraph(), .paragraph(), .paragraph("b")],
            [.paragraph(), .paragraph()],
        ]
        for shape in shapes {
            for second in [nil, NoteButtonAction.open(target: "https://a.b")] {
                let actions = [NoteButtonAction.insert(placement: .below, blocks: shape)] + (second.map { [$0] } ?? [])
                let page = NotePage(blocks: [.button(name: "B", actions: actions), .paragraph("after")])
                let written = NoteMarkdown.serialize(page)
                let reread = NoteMarkdown.parse(written)
                expect(MarkdownCheck.same(page, reread), "blank lines survive\n\(written)\(MarkdownCheck.describe(reread.blocks))")
            }
        }
    }

    static func handWrittenLeadingContentBecomesAnInsert() {
        let source = """
        <details>
        <summary>Hand made <!-- parc button --></summary>

        First

        <!-- parc open="Notes.md" -->

        </details>
        """
        let actions = NoteMarkdown.parse(source).blocks.first?.buttonValue.actions ?? []
        expect(actions.map(\.kind) == [.insert, .open], "leading blocks insert below, got \(actions.map(\.kind))")
        let toggle = NoteMarkdown.parse("<details>\n<summary>Plain <!-- parc color=\"red\" --></summary>\n\nBody\n\n</details>\n")
        expect(toggle.blocks.first?.kind == .toggle, "a summary without the button flag stays a toggle")
    }

    static func templateIDsDoNotMatter() {
        let one = NoteBlock.button(name: "A", actions: [.insert(placement: .below, blocks: [.paragraph("x")])])
        var two = one
        two.props.button = NoteButton(name: "A", actions: [.insert(placement: .below, blocks: [.paragraph("x")])])
        expect(one == two, "same template content compares equal")
        expect(one.hashValue == two.hashValue, "and hashes equal")
        var three = one
        three.props.button = NoteButton(name: "A", actions: [.insert(placement: .below, blocks: [.paragraph("y")])])
        expect(one != three, "different template content differs")
    }

    static func press(_ session: NotePageSession, _ id: NoteBlockID, confirm: Bool = true, opened: ((String) -> Void)? = nil) -> NoteButtonPress? {
        let press = NoteButtonPress(session: session, button: id, confirm: { _, decide in decide(confirm) }, open: { opened?($0) })
        press?.start()
        return press
    }

    static func pressInsertsBelowAndAbove() {
        let below = NoteBlock.button(name: "Below", actions: [.insert(placement: .below, blocks: [.paragraph("one"), .paragraph("two")])])
        let session = NotePageSession(page: NotePage(blocks: [.paragraph("start"), below, .paragraph("end")]))
        _ = press(session, below.id)
        _ = press(session, below.id)
        expect(session.page.blocks.map(\.text.plainText) == ["start", "", "one", "two", "one", "two", "end"], "below twice, got \(session.page.blocks.map(\.text.plainText))")
        let ids = Set(session.page.allBlocks().map(\.id))
        expect(ids.count == session.page.allBlocks().count, "every inserted copy has its own id")
        expect(session.undoDepth == 2, "one undo step per press, got \(session.undoDepth)")
        session.undo()
        expect(session.page.blocks.count == 5, "undo takes back one press")
        expect(session.undoActionName == NotePageSession.buttonPressName, "undo is named for the press")

        let above = NoteBlock.button(name: "Above", actions: [.insert(placement: .above, blocks: [.paragraph("x")])])
        let nested = NoteBlock(.toggle, text: "T", children: [.paragraph("a"), above])
        let other = NotePageSession(page: NotePage(blocks: [nested]))
        _ = press(other, above.id)
        expect(other.page.blocks[0].children.map(\.text.plainText) == ["a", "x", ""], "above stays inside the parent")
    }

    static func pressInsertsAtTopAndBottom() {
        let button = NoteBlock.button(name: "Both", actions: [.insert(placement: .top, blocks: [.paragraph("top")]),
                                                              .insert(placement: .bottom, blocks: [.heading(2, "bottom")])])
        let column = NoteBlock(.columns, children: [NoteBlock(.column, children: [button]), NoteBlock(.column, children: [.paragraph("r")])])
        let session = NotePageSession(page: NotePage(blocks: [.paragraph("first"), column, .paragraph("last")]))
        let run = press(session, button.id)
        expect(session.page.blocks.first?.text.plainText == "top", "top of the note")
        expect(session.page.blocks.last?.text.plainText == "bottom", "bottom of the note")
        expect(run?.inserted.count == 2, "reports what it added")
        expect(session.undoDepth == 1, "both inserts are one step")
        session.undo()
        expect(session.page.blocks.count == 3, "one undo takes both back")
    }

    static func pressIsOneUndoStepAcrossConfirmation() {
        let button = NoteBlock.button(name: "Ask", actions: [.insert(placement: .below, blocks: [.paragraph("before")]),
                                                             .confirm(message: "More?"),
                                                             .insert(placement: .below, blocks: [.paragraph("after")])])
        let session = NotePageSession(page: NotePage(blocks: [button]))
        var pending: ((Bool) -> Void)?
        var asked: [String] = []
        let run = NoteButtonPress(session: session, button: button.id, confirm: { message, decide in asked.append(message); pending = decide },
                                  open: { _ in })
        run?.start()
        expect(asked == ["More?"], "asks with the message")
        expect(session.page.blocks.map(\.text.plainText) == ["", "before"], "earlier actions already ran")
        expect(run?.isFinished == false, "waits for an answer")
        pending?(true)
        expect(session.page.blocks.map(\.text.plainText) == ["", "after", "before"], "carries on after yes, got \(session.page.blocks.map(\.text.plainText))")
        expect(run?.isFinished == true, "finishes")
        expect(session.undoDepth == 1, "the whole press is one step, got \(session.undoDepth)")
        session.undo()
        expect(session.page.blocks.count == 1, "undo takes back everything the press did")

        let interrupted = NotePageSession(page: NotePage(blocks: [button, .paragraph("typing")]))
        var later: ((Bool) -> Void)?
        let second = NoteButtonPress(session: interrupted, button: button.id, confirm: { _, decide in later = decide }, open: { _ in })
        second?.start()
        let typed = interrupted.page.blocks.last!.id
        interrupted.setText("typing more", of: (typed, .body))
        later?(true)
        expect(interrupted.undoDepth == 3, "an edit in between keeps its own step, got \(interrupted.undoDepth)")
    }

    static func cancelledConfirmationStops() {
        var opened: [String] = []
        let button = NoteBlock.button(name: "Stop", actions: [.confirm(message: ""), .insert(placement: .below, blocks: [.paragraph("x")]),
                                                              .open(target: "https://a.b")])
        let session = NotePageSession(page: NotePage(blocks: [button]))
        let run = press(session, button.id, confirm: false, opened: { opened.append($0) })
        expect(session.page.blocks.count == 1, "nothing inserted")
        expect(opened.isEmpty, "nothing opened")
        expect(run?.wasCancelled == true && run?.isFinished == true, "reports the cancel")
        expect(session.undoDepth == 0, "no undo step")
    }

    static func openActionsReportTargets() {
        var opened: [String] = []
        let button = NoteBlock.button(name: "Go", actions: [.open(target: " Projects/Plan.md "), .open(target: ""), .open(target: "https://example.com")])
        let session = NotePageSession(page: NotePage(blocks: [button]))
        _ = press(session, button.id, opened: { opened.append($0) })
        expect(opened == ["Projects/Plan.md", "https://example.com"], "opens trimmed targets in order, got \(opened)")
        expect(NoteButton.targetLabel("Projects/My%20Plan.md") == "My Plan", "note label")
        expect(NoteButton.targetLabel("https://example.com/a") == "example.com", "web label")
    }

    static func readOnlyPressInsertsNothing() {
        let button = NoteBlock.button(name: "Locked", actions: [.insert(placement: .below, blocks: [.paragraph("x")])])
        let session = NotePageSession(page: NotePage(blocks: [button]))
        session.isReadOnly = true
        _ = press(session, button.id)
        expect(session.page.blocks.count == 1, "read-only notes stay put")
    }

    static func columnsTemplateLeavesColumns() {
        let template = NoteBlock(.columns, children: [NoteBlock(.column, children: [.paragraph("a")]), NoteBlock(.column, children: [.paragraph("b")])])
        let button = NoteBlock.button(name: "Cols", actions: [.insert(placement: .below, blocks: [template])])
        let columns = NoteBlock(.columns, children: [NoteBlock(.column, children: [button]), NoteBlock(.column, children: [.paragraph("r")])])
        let session = NotePageSession(page: NotePage(blocks: [columns]))
        _ = press(session, button.id)
        expect(session.page.blocks.map(\.kind) == [.columns, .columns], "columns land after the outer columns, got \(session.page.blocks.map(\.kind))")
    }

    static func turnIntoButtonAndBack() {
        let paragraph = NoteBlock(.paragraph, text: "Start a journal entry\nsecond line", color: .text(.red), children: [.paragraph("Dear diary")])
        let session = NotePageSession(page: NotePage(blocks: [paragraph]))
        session.turnInto([paragraph.id], kind: .button)
        let button = session.page.blocks[0]
        expect(button.kind == .button, "became a button")
        expect(button.buttonValue.name == "Start a journal entry", "keeps the first line as its name")
        expect(button.children.isEmpty, "children move into the template")
        expect(button.buttonValue.templateBlocks.map(\.text.plainText) == ["Dear diary"], "template holds the children")
        expect(button.color == .text(.red), "keeps the colour")
        expect(!button.props.expanded, "closed on GitHub")
        session.turnInto([button.id], kind: .todo)
        let todo = session.page.blocks[0]
        expect(todo.kind == .todo && todo.text.plainText == "Start a journal entry", "back to text")
        expect(todo.children.map(\.text.plainText) == ["Dear diary"], "template comes back as children")
        expect(todo.props.button == nil, "no leftover button")
        session.turnInto([todo.id], kind: .code)
        expect(session.page.blocks.map(\.kind) == [.code, .paragraph], "children lift out of code")
        let callout = NoteBlock(.callout, text: "Tip", props: { var props = NoteBlockProps(); props.icon = "🌳"; return props }())
        expect(callout.converted(to: .button).props.icon == "🌳", "a callout's icon carries over")
        let fresh = NoteBlock.paragraph().converted(to: .button)
        expect(fresh.buttonValue == NoteButton.starter, "an empty block becomes a starter button")
    }

    static func unwrapRestoresBlocks() {
        let button = NoteBlock.button(name: "Wrap", actions: [.insert(placement: .below, blocks: [.paragraph("a")]), .confirm(message: "?"),
                                                              .insert(placement: .top, blocks: [.paragraph("b")])])
        let session = NotePageSession(page: NotePage(blocks: [.paragraph("x"), button]))
        let ids = session.unwrapButton(button.id)
        expect(session.page.blocks.map(\.text.plainText) == ["x", "a", "b"], "template blocks replace the button")
        expect(ids.count == 2, "returns the new blocks")
        session.undo()
        expect(session.page.blocks.last?.kind == .button, "undo brings the button back")
    }

    static func htmlRoundTrip() {
        var button = NoteBlock.button(name: "Ship it", icon: "🚢", actions: [.confirm(message: "Really?"),
                                                                           .insert(placement: .bottom, blocks: [.heading(2, "Shipped"), .paragraph("Notes")]),
                                                                           .open(target: "Release.md")])
        button.color = .background(.green)
        let html = NotePageHTML.fragment([button])
        expect(html.contains("<summary>🚢 Ship it</summary>"), "readable summary, got \(html)")
        let read = NoteHTMLReader.blocks(from: html, baseURL: nil)
        expect(read.count == 1 && read[0].kind == .button, "reads back one button, got \(read.map(\.kind))")
        expect(read.first?.props.button == button.props.button, "actions survive")
        expect(read.first?.props.icon == "🚢" && read.first?.color == .background(.green), "icon and colour survive")
        let foreign = NoteHTMLReader.blocks(from: "<details data-block=\"button\" data-icon=\"⭐\"><summary>⭐ Star</summary><p>Body</p></details>", baseURL: nil)
        expect(foreign.first?.buttonValue.name == "Star", "falls back to the summary")
        expect(foreign.first?.buttonValue.templateBlocks.map(\.text.plainText) == ["Body"], "and the body")
        let document = NotePageHTML.document(NotePage(blocks: [button]), title: "T", assets: { _ in nil }, embedImages: false)
        expect(document.contains("class=\"note-button") && document.contains("button-template"), "export styles the button")
    }

    static func plainTextUsesName() {
        let page = NotePage(blocks: [.paragraph("a"), .button(name: "Press me"), .button()])
        expect(page.plainText == "a\nPress me\n" + NoteButton.placeholderName, "plain text, got \(page.plainText)")
    }

    static func editingSessionIsOneUndoStep() {
        let button = NoteBlock.button(name: "Old")
        let session = NotePageSession(page: NotePage(blocks: [button]))
        let token = UUID()
        session.setButton(button.id, name: "N", coalescing: .lasting(button.id, token))
        session.setButton(button.id, name: "Ne", coalescing: .lasting(button.id, token))
        session.setButton(button.id, icon: .some("🧪"), coalescing: .lasting(button.id, token))
        session.setButton(button.id, actions: [.open(target: "https://a.b")], coalescing: .lasting(button.id, token))
        session.setButton(button.id, actions: [.open(target: "https://a.b")], coalescing: .lasting(button.id, token))
        expect(session.undoDepth == 1, "one editing session is one step, got \(session.undoDepth)")
        expect(session.page.blocks[0].buttonValue.name == "Ne" && session.page.blocks[0].props.icon == "🧪", "all changes land")
        session.undo()
        expect(session.page.blocks[0].buttonValue.name == "Old" && session.page.blocks[0].props.icon == nil, "undo restores the start")
        session.setButton(button.id, icon: .some(nil))
        expect(session.undoDepth == 0, "clearing a missing icon changes nothing")
    }
}
