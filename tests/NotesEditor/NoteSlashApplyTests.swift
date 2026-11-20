import Foundation

@main @MainActor
struct NoteSlashApplyTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func apply(_ effect: NoteCatalogEffect, _ page: NotePage, _ block: NoteBlockID, _ range: Range<Int>) -> NoteCatalogOutcome {
        guard let outcome = NoteCatalogApplier.apply(effect, to: page, at: NotePosition(block, range.upperBound), removing: range) else {
            failTest("\(effect) produced nothing")
        }
        return outcome
    }

    static func main() {
        let hello = NoteBlock.paragraph("Hello /h1")
        var outcome = apply(.block(.heading(1)), NotePage(blocks: [hello]), hello.id, 6..<9)
        expect(outcome.page.blocks.count == 2 && outcome.page.blocks[0].text.string == "Hello ", "the query text disappears and the words stay")
        let heading = outcome.page.blocks[1]
        expect(heading.kind == .heading && heading.props.level == 1, "a non-empty block gets a new heading after it")
        expect(outcome.selection.caret == NotePosition(heading.id, 0), "the caret lands in the new heading")

        let empty = NoteBlock.paragraph("/h2")
        outcome = apply(.block(.heading(2)), NotePage(blocks: [empty]), empty.id, 0..<3)
        expect(outcome.page.blocks.count == 1 && outcome.page.blocks[0].id == empty.id && outcome.page.blocks[0].kind == .heading
               && outcome.page.blocks[0].props.level == 2 && outcome.page.blocks[0].text.isEmpty, "an empty block turns into the heading itself")
        expect(outcome.selection.caret == NotePosition(empty.id, 0), "the caret stays put")

        let child = NoteBlock(.bulletedItem, text: "inside")
        let parent = NoteBlock(.bulletedItem, text: "/todo", children: [child])
        outcome = apply(.block(.todo), NotePage(blocks: [parent]), parent.id, 0..<5)
        expect(outcome.page.blocks.count == 1 && outcome.page.blocks[0].kind == .todo && outcome.page.blocks[0].children.map(\.id) == [child.id],
               "converting a list item into a to-do keeps its children")
        outcome = apply(.block(.heading(1)), NotePage(blocks: [parent]), parent.id, 0..<5)
        expect(outcome.page.blocks.map(\.id) == [parent.id, child.id] && outcome.page.blocks[0].children.isEmpty,
               "headings can't hold children, so they step out after it")
        outcome = apply(.block(.toggleHeading(1)), NotePage(blocks: [parent]), parent.id, 0..<5)
        expect(outcome.page.blocks[0].children.map(\.id) == [child.id] && outcome.page.blocks[0].props.toggleable,
               "toggle headings keep the children folded inside")

        let divider = NoteBlock.paragraph("/div")
        outcome = apply(.block(.divider), NotePage(blocks: [divider]), divider.id, 0..<4)
        expect(outcome.page.blocks.count == 2 && outcome.page.blocks[0].kind == .divider && outcome.page.blocks[1].kind == .paragraph,
               "a divider replaces the empty line and leaves a fresh one below")
        expect(outcome.selection.caret == NotePosition(outcome.page.blocks[1].id, 0), "the caret moves past the divider")
        let trailing = NoteBlock.paragraph()
        outcome = apply(.block(.divider), NotePage(blocks: [divider, trailing]), divider.id, 0..<4)
        expect(outcome.page.blocks.count == 2 && outcome.selection.caret == NotePosition(trailing.id, 0), "an empty line below is reused")

        let words = NoteBlock.paragraph("Look /img")
        outcome = apply(.block(.image), NotePage(blocks: [words]), words.id, 5..<9)
        let image = outcome.page.blocks[1]
        expect(image.kind == .image && outcome.page.blocks[0].text.string == "Look ", "an image lands after the words")
        expect(outcome.selection == .blocks([image.id]) && outcome.activate == image.id, "the image asks for its picker")

        let math = NoteBlock.paragraph("/math")
        outcome = apply(.block(.equation), NotePage(blocks: [math]), math.id, 0..<5)
        expect(outcome.page.blocks[0].kind == .equation && outcome.activate == math.id, "an equation opens its editor")

        let code = NoteBlock.paragraph("/code")
        outcome = apply(.block(.code), NotePage(blocks: [code]), code.id, 0..<5)
        expect(outcome.page.blocks[0].kind == .code && outcome.selection.caret == NotePosition(code.id, 0) && outcome.activate == nil,
               "code puts the caret straight into the code")

        let table = NoteBlock.paragraph("/table")
        outcome = apply(.block(.table), NotePage(blocks: [table]), table.id, 0..<6)
        let grid = outcome.page.blocks[0]
        expect(grid.kind == .table && grid.props.table != nil, "a table block appears")
        expect(outcome.selection.caret == NotePosition(grid.id, 0, field: .cell(row: 0, column: 0)), "the caret lands in the first cell")

        let columns = NoteBlock.paragraph("/2col")
        outcome = apply(.block(.columns(2)), NotePage(blocks: [columns]), columns.id, 0..<5)
        let split = outcome.page.blocks[0]
        expect(split.kind == .columns && split.children.count == 2, "two columns appear")
        expect(outcome.selection.caret == NotePosition(split.children[0].children[0].id, 0), "the caret starts in the left column")

        let red = NoteBlock.paragraph("Hot /red")
        outcome = apply(.color(.text(.red)), NotePage(blocks: [red]), red.id, 4..<8)
        expect(outcome.page.blocks[0].color == .text(.red) && outcome.page.blocks[0].text.string == "Hot ", "colours paint the block")
        expect(outcome.selection.caret == NotePosition(red.id, 4), "and the caret stays where the slash was")
        var painted = red
        painted.color = .background(.blue)
        outcome = apply(.color(nil), NotePage(blocks: [painted]), painted.id, 4..<8)
        expect(outcome.page.blocks[0].color == nil, "Default clears the colour")

        let first = NoteBlock.paragraph("First")
        let second = NoteBlock.paragraph("Second /del")
        let third = NoteBlock.paragraph("Third")
        outcome = apply(.action(.delete), NotePage(blocks: [first, second, third]), second.id, 7..<11)
        expect(outcome.page.blocks.map(\.id) == [first.id, third.id], "delete removes the whole block")
        expect(outcome.selection.caret == NotePosition(first.id, 5), "and the caret lands at the end of the block above")
        let only = NoteBlock.paragraph("/del")
        outcome = apply(.action(.delete), NotePage(blocks: [only]), only.id, 0..<4)
        expect(outcome.page.blocks.count == 1 && outcome.page.blocks[0].text.isEmpty && outcome.selection.caret?.offset == 0,
               "deleting the last block leaves an empty page you can type on")
        outcome = apply(.action(.duplicate), NotePage(blocks: [first, second, third]), second.id, 7..<11)
        expect(outcome.page.blocks.count == 4 && outcome.page.blocks[2].text.string == "Second " && outcome.page.blocks[2].id != second.id,
               "duplicate copies the block without the query")
        expect(outcome.selection.caret == NotePosition(second.id, 7), "the caret stays in the original")
        outcome = apply(.action(.moveUp), NotePage(blocks: [first, second, third]), second.id, 7..<11)
        expect(outcome.page.blocks.map(\.id) == [second.id, first.id, third.id], "move up swaps with the block above")
        outcome = apply(.action(.moveDown), NotePage(blocks: [first, second, third]), second.id, 7..<11)
        expect(outcome.page.blocks.map(\.id) == [first.id, third.id, second.id], "move down swaps with the block below")
        outcome = apply(.action(.moveUp), NotePage(blocks: [first, second]), first.id, 0..<0)
        expect(outcome.page.blocks.map(\.id) == [first.id, second.id], "the top block can't move higher")
        let nestedChild = NoteBlock(.bulletedItem, text: "kid")
        let nestedParent = NoteBlock(.bulletedItem, text: "mum", children: [nestedChild])
        outcome = apply(.action(.moveUp), NotePage(blocks: [nestedParent]), nestedChild.id, 3..<3)
        expect(outcome.page.blocks.map(\.id) == [nestedChild.id, nestedParent.id], "the first child moves out above its parent")

        let turn = NoteBlock.paragraph("Hello /turn h1")
        outcome = apply(.turnInto(.heading(1)), NotePage(blocks: [turn]), turn.id, 6..<14)
        expect(outcome.page.blocks.count == 1 && outcome.page.blocks[0].kind == .heading && outcome.page.blocks[0].text.string == "Hello ",
               "Turn into converts the block itself, words and all")
        expect(outcome.selection.caret == NotePosition(turn.id, 6), "with the caret where the slash was")

        let mention = NoteBlock.paragraph("Hi /men")
        outcome = apply(.inline(.mention), NotePage(blocks: [mention]), mention.id, 3..<7)
        expect(outcome.page.blocks[0].text.string == "Hi @", "mention swaps the query for an @")
        expect(outcome.followUp == .mention(NotePosition(mention.id, 3), datesOnly: false) && outcome.selection.caret?.offset == 4,
               "and opens the mention menu right after it")
        outcome = apply(.inline(.date), NotePage(blocks: [mention]), mention.id, 3..<7)
        expect(outcome.followUp == .mention(NotePosition(mention.id, 3), datesOnly: true), "date opens the mention menu on dates")
        outcome = apply(.inline(.emoji), NotePage(blocks: [mention]), mention.id, 3..<7)
        expect(outcome.page.blocks[0].text.string == "Hi " && outcome.followUp == .emoji(NotePosition(mention.id, 3)),
               "emoji clears the query and opens the picker where it was")
        outcome = apply(.inline(.equation), NotePage(blocks: [mention]), mention.id, 3..<7)
        expect(outcome.page.blocks[0].text.marks(at: 3).atom == .equation("") && outcome.followUp == .editEquation(NotePosition(mention.id, 3)),
               "inline equation drops in an equation and opens it")

        let link = NoteBlock.paragraph("/link")
        outcome = apply(.block(.linkToNote), NotePage(blocks: [link]), link.id, 0..<5)
        expect(outcome.page.blocks[0].text.isEmpty && outcome.followUp == .pickNote(NotePosition(link.id, 0)), "Link to note asks which note")
        expect(NoteCatalogApplier.apply(.block(.newNote), to: NotePage(blocks: [link]), at: NotePosition(link.id, 5), removing: 0..<5) == nil,
               "New note is the controller's job, since it touches files")

        var props = NoteBlockProps()
        props.target = "Other.md"
        let pageLink = NoteBlock(.pageLink, text: "Other", props: props)
        let host = NoteBlock.paragraph("/page")
        if let placed = NoteCatalogApplier.place(pageLink, template: nil, into: NotePage(blocks: [host]), at: NotePosition(host.id, 5),
                                                 removing: 0..<5, name: "Link to Note") {
            expect(placed.page.blocks.map(\.id) == [pageLink.id] && placed.selection == .blocks([pageLink.id]),
                   "a page link replaces the empty line and gets selected")
        } else {
            failTest("placing a page link failed")
        }
        let codeHost = NoteBlock(.code, text: "/h1")
        expect(NoteCatalogApplier.place(NoteBlock.heading(1), template: .heading(1), into: NotePage(blocks: [codeHost]),
                                        at: NotePosition(codeHost.id, 3), removing: 0..<3, name: "Insert") == nil,
               "code blocks never take slash commands")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
        let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: Locale(identifier: "en_US"))
        let soon = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        let allDay = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
        let past = NoteDateMention(year: 2026, month: 11, day: 19, hour: 8, minute: 0, remind: true)
        let plainDate = NoteDateMention(year: 2026, month: 12, day: 25)
        let reminderBlock = NoteBlock.paragraph(NoteText("Call Sam ") + NoteText.atom(.date(soon)))
        let laterBlock = NoteBlock(.todo, text: NoteText("Taxes ") + NoteText.atom(.date(allDay)) + NoteText.atom(.date(soon)))
        let quietBlock = NoteBlock.paragraph(NoteText.atom(.date(past)) + NoteText(" and ") + NoteText.atom(.date(plainDate)))
        let plans = NoteReminderPlan.reminders(in: NotePage(blocks: [laterBlock, reminderBlock, quietBlock]), parser: parser)
        expect(plans.map(\.key) == ["2026-11-21T15:30", "2026-12-03T09:00"], "reminders are future, deduplicated and in order: \(plans.map(\.key))")
        expect(plans.first?.body.hasPrefix("Taxes ") == true, "the reminder body is the block's words")
        expect(plans.last?.fireDate == calendar.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 9)), "all-day reminders fire at 9")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("parc-slash-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let environment = NoteDetachedEnvironment(documentURL: folder.appendingPathComponent("Home.md"))
        let created = try? environment.createSiblingNote(titled: "Untitled")
        let again = try? environment.createSiblingNote(titled: "Untitled")
        let odd = try? environment.createSiblingNote(titled: "a/b: c")
        expect(created?.lastPathComponent == "Untitled.md" && again?.lastPathComponent == "Untitled 2.md", "new notes never overwrite each other")
        expect(odd?.lastPathComponent == "a-b- c.md", "slashes and colons stay out of file names")
        expect(created.map { FileManager.default.fileExists(atPath: $0.path) } == true, "the new note exists on disk")
        try? FileManager.default.removeItem(at: folder)
        print("NoteSlashApplyTests passed")
    }
}
