import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteSlashApplyTests {
    typealias Blocks = NoteEditorBlocks

    func apply(_ effect: NoteCatalogEffect, _ page: NotePage, _ block: NoteBlockID, _ range: Range<Int>) throws -> NoteCatalogOutcome {
        try #require(NoteCatalogApplier.apply(effect, to: page, at: NotePosition(block, range.upperBound), removing: range))
    }

    func apply(_ effect: NoteCatalogEffect, _ blocks: [NoteBlock], _ block: NoteBlock, _ range: Range<Int>) throws -> NoteCatalogOutcome {
        try apply(effect, NotePage(blocks: blocks), block.id, range)
    }

    @Test func theQueryTextDisappearsAndTheWordsStay() throws {
        let hello = NoteBlock.paragraph("Hello /h1")
        let outcome = try apply(.block(.heading(1)), [hello], hello, 6..<9)
        #expect(outcome.page.blocks.count == 2)
        #expect(outcome.page.blocks[0].text.string == "Hello ")
    }

    @Test func aNonEmptyBlockGetsANewHeadingAfterIt() throws {
        let hello = NoteBlock.paragraph("Hello /h1")
        let heading = try apply(.block(.heading(1)), [hello], hello, 6..<9).page.blocks[1]
        #expect(heading.kind == .heading)
        #expect(heading.props.level == 1)
    }

    @Test func theCaretLandsInTheNewHeading() throws {
        let hello = NoteBlock.paragraph("Hello /h1")
        let outcome = try apply(.block(.heading(1)), [hello], hello, 6..<9)
        #expect(outcome.selection.caret == NotePosition(outcome.page.blocks[1].id, 0))
    }

    @Test func anEmptyBlockTurnsIntoTheHeadingItself() throws {
        let empty = NoteBlock.paragraph("/h2")
        let outcome = try apply(.block(.heading(2)), [empty], empty, 0..<3)
        #expect(outcome.page.blocks.count == 1)
        #expect(outcome.page.blocks[0].id == empty.id)
        #expect(outcome.page.blocks[0].kind == .heading)
        #expect(outcome.page.blocks[0].props.level == 2)
        #expect(outcome.page.blocks[0].text.isEmpty)
    }

    @Test func theCaretStaysPutInAnEmptyBlock() throws {
        let empty = NoteBlock.paragraph("/h2")
        #expect(try apply(.block(.heading(2)), [empty], empty, 0..<3).selection.caret == NotePosition(empty.id, 0))
    }

    struct Family {
        let child = NoteBlock(.bulletedItem, text: "inside")
        let parent: NoteBlock

        init() { parent = NoteBlock(.bulletedItem, text: "/todo", children: [child]) }
    }

    @Test func convertingAListItemIntoATodoKeepsItsChildren() throws {
        let family = Family()
        let outcome = try apply(.block(.todo), [family.parent], family.parent, 0..<5)
        #expect(outcome.page.blocks.count == 1)
        #expect(outcome.page.blocks[0].kind == .todo)
        #expect(outcome.page.blocks[0].children.map(\.id) == [family.child.id])
    }

    @Test func headingsKeepTheirChildrenNestedUnderThem() throws {
        let family = Family()
        let outcome = try apply(.block(.heading(1)), [family.parent], family.parent, 0..<5)
        #expect(outcome.page.blocks.map(\.id) == [family.parent.id])
        #expect(outcome.page.blocks[0].children.map(\.id) == [family.child.id])
    }

    @Test func toggleHeadingsKeepTheChildrenFoldedInside() throws {
        let family = Family()
        let outcome = try apply(.block(.toggleHeading(1)), [family.parent], family.parent, 0..<5)
        #expect(outcome.page.blocks[0].children.map(\.id) == [family.child.id])
        #expect(outcome.page.blocks[0].props.toggleable)
    }

    @Test func aDividerReplacesTheEmptyLineAndLeavesAFreshOne() throws {
        let divider = NoteBlock.paragraph("/div")
        let outcome = try apply(.block(.divider), [divider], divider, 0..<4)
        #expect(outcome.page.blocks.count == 2)
        #expect(outcome.page.blocks[0].kind == .divider)
        #expect(outcome.page.blocks[1].kind == .paragraph)
        #expect(outcome.selection.caret == NotePosition(outcome.page.blocks[1].id, 0))
    }

    @Test func anEmptyLineBelowADividerIsReused() throws {
        let divider = NoteBlock.paragraph("/div"), trailing = NoteBlock.paragraph()
        let outcome = try apply(.block(.divider), [divider, trailing], divider, 0..<4)
        #expect(outcome.page.blocks.count == 2)
        #expect(outcome.selection.caret == NotePosition(trailing.id, 0))
    }

    @Test func anImageLandsAfterTheWordsAndAsksForItsPicker() throws {
        let words = NoteBlock.paragraph("Look /img")
        let outcome = try apply(.block(.image), [words], words, 5..<9)
        let image = outcome.page.blocks[1]
        #expect(image.kind == .image)
        #expect(outcome.page.blocks[0].text.string == "Look ")
        #expect(outcome.selection == .blocks([image.id]))
        #expect(outcome.activate == image.id)
    }

    @Test func anEquationOpensItsEditor() throws {
        let math = NoteBlock.paragraph("/math")
        let outcome = try apply(.block(.equation), [math], math, 0..<5)
        #expect(outcome.page.blocks[0].kind == .equation)
        #expect(outcome.activate == math.id)
    }

    @Test func codePutsTheCaretStraightIntoTheCode() throws {
        let code = NoteBlock.paragraph("/code")
        let outcome = try apply(.block(.code), [code], code, 0..<5)
        #expect(outcome.page.blocks[0].kind == .code)
        #expect(outcome.selection.caret == NotePosition(code.id, 0))
        #expect(outcome.activate == nil)
    }

    @Test func aTableBlockAppearsWithTheCaretInTheFirstCell() throws {
        let table = NoteBlock.paragraph("/table")
        let outcome = try apply(.block(.table), [table], table, 0..<6)
        let grid = outcome.page.blocks[0]
        #expect(grid.kind == .table)
        #expect(grid.props.table != nil)
        #expect(outcome.selection.caret == NotePosition(grid.id, 0, field: .cell(row: 0, column: 0)))
    }

    @Test func twoColumnsAppearWithTheCaretInTheLeftColumn() throws {
        let columns = NoteBlock.paragraph("/2col")
        let outcome = try apply(.block(.columns(2)), [columns], columns, 0..<5)
        let split = outcome.page.blocks[0]
        #expect(split.kind == .columns)
        #expect(split.children.count == 2)
        #expect(outcome.selection.caret == NotePosition(split.children[0].children[0].id, 0))
    }

    @Test func coloursPaintTheBlockAndTheCaretStaysWhereTheSlashWas() throws {
        let red = NoteBlock.paragraph("Hot /red")
        let outcome = try apply(.color(.text(.red)), [red], red, 4..<8)
        #expect(outcome.page.blocks[0].color == .text(.red))
        #expect(outcome.page.blocks[0].text.string == "Hot ")
        #expect(outcome.selection.caret == NotePosition(red.id, 4))
    }

    @Test func defaultClearsTheColour() throws {
        var painted = NoteBlock.paragraph("Hot /red")
        painted.color = .background(.blue)
        #expect(try apply(.color(nil), [painted], painted, 4..<8).page.blocks[0].color == nil)
    }

    struct Three {
        let first = NoteBlock.paragraph("First"), second = NoteBlock.paragraph("Second /del"), third = NoteBlock.paragraph("Third")
        var page: NotePage { NotePage(blocks: [first, second, third]) }
    }

    @Test func deleteRemovesTheWholeBlock() throws {
        let three = Three()
        #expect(try apply(.action(.delete), three.page, three.second.id, 7..<11).page.blocks.map(\.id) == [three.first.id, three.third.id])
    }

    @Test func deleteLandsTheCaretAtTheEndOfTheBlockAbove() throws {
        let three = Three()
        #expect(try apply(.action(.delete), three.page, three.second.id, 7..<11).selection.caret == NotePosition(three.first.id, 5))
    }

    @Test func deletingTheLastBlockLeavesAnEmptyPage() throws {
        let only = NoteBlock.paragraph("/del")
        let outcome = try apply(.action(.delete), [only], only, 0..<4)
        #expect(outcome.page.blocks.count == 1)
        #expect(outcome.page.blocks[0].text.isEmpty)
        #expect(outcome.selection.caret?.offset == 0)
    }

    @Test func duplicateCopiesTheBlockWithoutTheQuery() throws {
        let three = Three()
        let outcome = try apply(.action(.duplicate), three.page, three.second.id, 7..<11)
        #expect(outcome.page.blocks.count == 4)
        #expect(outcome.page.blocks[2].text.string == "Second ")
        #expect(outcome.page.blocks[2].id != three.second.id)
        #expect(outcome.selection.caret == NotePosition(three.second.id, 7))
    }

    @Test func moveUpSwapsWithTheBlockAbove() throws {
        let three = Three()
        #expect(try apply(.action(.moveUp), three.page, three.second.id, 7..<11).page.blocks.map(\.id) == [three.second.id, three.first.id, three.third.id])
    }

    @Test func moveDownSwapsWithTheBlockBelow() throws {
        let three = Three()
        #expect(try apply(.action(.moveDown), three.page, three.second.id, 7..<11).page.blocks.map(\.id) == [three.first.id, three.third.id, three.second.id])
    }

    @Test func theTopBlockCannotMoveHigher() throws {
        let three = Three()
        let outcome = try apply(.action(.moveUp), [three.first, three.second], three.first, 0..<0)
        #expect(outcome.page.blocks.map(\.id) == [three.first.id, three.second.id])
    }

    @Test func theFirstChildMovesOutAboveItsParent() throws {
        let kid = NoteBlock(.bulletedItem, text: "kid")
        let mum = NoteBlock(.bulletedItem, text: "mum", children: [kid])
        #expect(try apply(.action(.moveUp), [mum], kid, 3..<3).page.blocks.map(\.id) == [kid.id, mum.id])
    }

    @Test func turnIntoConvertsTheBlockItselfWordsAndAll() throws {
        let turn = NoteBlock.paragraph("Hello /turn h1")
        let outcome = try apply(.turnInto(.heading(1)), [turn], turn, 6..<14)
        #expect(outcome.page.blocks.count == 1)
        #expect(outcome.page.blocks[0].kind == .heading)
        #expect(outcome.page.blocks[0].text.string == "Hello ")
        #expect(outcome.selection.caret == NotePosition(turn.id, 6))
    }

    let mention = NoteBlock.paragraph("Hi /men")

    @Test func mentionSwapsTheQueryForAnAt() throws {
        let outcome = try apply(.inline(.mention), [mention], mention, 3..<7)
        #expect(outcome.page.blocks[0].text.string == "Hi @")
        #expect(outcome.selection.caret?.offset == 4)
    }

    @Test func mentionOpensTheMentionMenuRightAfterIt() throws {
        #expect(try apply(.inline(.mention), [mention], mention, 3..<7).followUp == .mention(NotePosition(mention.id, 3), datesOnly: false))
    }

    @Test func dateOpensTheMentionMenuOnDates() throws {
        #expect(try apply(.inline(.date), [mention], mention, 3..<7).followUp == .mention(NotePosition(mention.id, 3), datesOnly: true))
    }

    @Test func emojiClearsTheQueryAndOpensThePickerWhereItWas() throws {
        let outcome = try apply(.inline(.emoji), [mention], mention, 3..<7)
        #expect(outcome.page.blocks[0].text.string == "Hi ")
        #expect(outcome.followUp == .emoji(NotePosition(mention.id, 3)))
    }

    @Test func anInlineEquationDropsInAndOpens() throws {
        let outcome = try apply(.inline(.equation), [mention], mention, 3..<7)
        #expect(outcome.page.blocks[0].text.marks(at: 3).atom == .equation(""))
        #expect(outcome.followUp == .editEquation(NotePosition(mention.id, 3)))
    }

    @Test func linkToNoteAsksWhichNote() throws {
        let link = NoteBlock.paragraph("/link")
        let outcome = try apply(.block(.linkToNote), [link], link, 0..<5)
        #expect(outcome.page.blocks[0].text.isEmpty)
        #expect(outcome.followUp == .pickNote(NotePosition(link.id, 0)))
    }

    @Test func newNoteIsTheControllersJobSinceItTouchesFiles() {
        let link = NoteBlock.paragraph("/link")
        #expect(NoteCatalogApplier.apply(.block(.newNote), to: NotePage(blocks: [link]), at: NotePosition(link.id, 5), removing: 0..<5) == nil)
    }

    @Test func aPageLinkReplacesTheEmptyLineAndGetsSelected() throws {
        var props = NoteBlockProps()
        props.target = "Other.md"
        let pageLink = NoteBlock(.pageLink, text: "Other", props: props)
        let host = NoteBlock.paragraph("/page")
        let placed = try #require(NoteCatalogApplier.place(pageLink, template: nil, into: NotePage(blocks: [host]), at: NotePosition(host.id, 5),
                                                           removing: 0..<5, name: "Link to Note"))
        #expect(placed.page.blocks.map(\.id) == [pageLink.id])
        #expect(placed.selection == .blocks([pageLink.id]))
    }

    @Test func codeBlocksNeverTakeSlashCommands() {
        let codeHost = NoteBlock(.code, text: "/h1")
        #expect(NoteCatalogApplier.place(NoteBlock.heading(1), template: .heading(1), into: NotePage(blocks: [codeHost]),
                                         at: NotePosition(codeHost.id, 3), removing: 0..<3, name: "Insert") == nil)
    }

    struct Reminders {
        var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }

        var plans: [NoteReminderPlan] {
            let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
            let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: Locale(identifier: "en_US"))
            let soon = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
            let allDay = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
            let past = NoteDateMention(year: 2026, month: 11, day: 19, hour: 8, minute: 0, remind: true)
            let plainDate = NoteDateMention(year: 2026, month: 12, day: 25)
            let reminderBlock = NoteBlock.paragraph(NoteText("Call Sam ") + NoteText.atom(.date(soon)))
            let laterBlock = NoteBlock(.todo, text: NoteText("Taxes ") + NoteText.atom(.date(allDay)) + NoteText.atom(.date(soon)))
            let quietBlock = NoteBlock.paragraph(NoteText.atom(.date(past)) + NoteText(" and ") + NoteText.atom(.date(plainDate)))
            return NoteReminderPlan.reminders(in: NotePage(blocks: [laterBlock, reminderBlock, quietBlock]), parser: parser)
        }
    }

    @Test func remindersAreFutureDeduplicatedAndInOrder() {
        #expect(Reminders().plans.map(\.key) == ["2026-11-21T15:30", "2026-12-03T09:00"])
    }

    @Test func theReminderBodyIsTheBlocksWords() {
        #expect(Reminders().plans.first?.body.hasPrefix("Taxes ") == true)
    }

    @Test func allDayRemindersFireAtNine() {
        let reminders = Reminders()
        #expect(reminders.plans.last?.fireDate == reminders.calendar.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 9)))
    }

    func newNotes() throws -> (NoteEditorTemporaryFolder, URL?, URL?, URL?) {
        let folder = try NoteEditorTemporaryFolder("slash")
        let environment = NoteDetachedEnvironment(documentURL: folder.url.appendingPathComponent("Home.md"),
                                                  files: IsolatedNoteFiles.make())
        return (folder, try? environment.createNote(titled: "Untitled"), try? environment.createNote(titled: "Untitled"),
                try? environment.createNote(titled: "a/b: c"))
    }

    @Test func newNotesNeverOverwriteEachOther() throws {
        let notes = try newNotes()
        #expect(notes.1?.lastPathComponent == "Untitled.md")
        #expect(notes.2?.lastPathComponent == "Untitled 2.md")
    }

    @Test func slashesAndColonsStayOutOfFileNames() throws {
        #expect(try newNotes().3?.lastPathComponent == "a-b- c.md")
    }

    @Test func theNewNoteExistsOnDisk() throws {
        let notes = try newNotes()
        #expect(notes.1.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }
}
