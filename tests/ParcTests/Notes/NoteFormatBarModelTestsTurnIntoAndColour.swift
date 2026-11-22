import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteFormatBarModelTestsTurnIntoAndColour {
    nonisolated private static let richTextOptions = NoteTurnIntoOption.allCases.filter { $0.kind.hasRichText }

    @MainActor private struct Page {
        let session: NotePageSession
        let first: NoteBlock
        let second: NoteBlock
        let code: NoteBlock

        init() {
            var bold = NoteMarks.plain
            bold.bold = true
            var linked = NoteMarks.plain
            linked.link = "https://parc.example"
            linked.color = .text(.red)
            first = NoteBlock.paragraph(NoteText(pieces: [("Hello ", .plain), ("bold", bold), (" world", .plain)]))
            second = NoteBlock(.heading, text: NoteText(pieces: [("Linked", linked), (" tail", .plain)]),
                               props: { var props = NoteBlockProps(); props.level = 2; return props }())
            code = NoteBlock(.code, text: "let x = 1")
            session = NotePageSession(page: NotePage(blocks: [first, second, code]))
        }

        func select(_ a: NotePosition, _ b: NotePosition) -> NoteFormatState? {
            session.setSelection(.text(anchor: a, head: b))
            return NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false)
        }

        func inFirst(_ from: Int, _ to: Int) -> NoteFormatState? { select(NotePosition(first.id, from), NotePosition(first.id, to)) }
        func inSecond(_ from: Int, _ to: Int) -> NoteFormatState? { select(NotePosition(second.id, from), NotePosition(second.id, to)) }
    }

    @Test func bodyTextGetsEveryItemTurnIntoFirst() {
        let items = NoteFormatItem.items(for: .body)
        #expect(items.first == .turnInto)
    }

    @Test func itemsStayGroupedInNotionsOrder() {
        let groups = NoteFormatItem.items(for: .body).map(\.group)
        #expect(groups == groups.sorted())
    }

    @Test(arguments: NoteFormatBarModelTestsTurnIntoAndColour.richTextOptions)
    func aTurnIntoOptionRoundTripsThroughTurnInto(option: NoteTurnIntoOption) {
        let page = Page()
        page.session.turnInto([page.first.id], kind: option.kind, configure: option.configure)
        #expect(NoteTurnIntoOption(block: page.session.page.block(page.first.id)!) == option)
    }

    @Test func toggleHeadingsOpenExpanded() {
        let page = Page()
        let option = NoteTurnIntoOption.toggleHeading2
        page.session.turnInto([page.first.id], kind: option.kind, configure: option.configure)
        let toggle = page.session.page.block(page.first.id)
        #expect(toggle?.props.toggleable == true)
        #expect(toggle?.props.level == 2)
        #expect(toggle?.props.expanded == true)
    }

    @Test func aToggleHeadingTurnsBackIntoAPlainOne() {
        let page = Page()
        let toggle = NoteTurnIntoOption.toggleHeading2, plain = NoteTurnIntoOption.heading2
        page.session.turnInto([page.first.id], kind: toggle.kind, configure: toggle.configure)
        page.session.turnInto([page.first.id], kind: plain.kind, configure: plain.configure)
        #expect(page.session.page.block(page.first.id)?.props.toggleable == false)
    }

    @Test func existingHeadingsMapToOptions() {
        let page = Page()
        #expect(NoteTurnIntoOption(block: page.session.page.block(page.second.id)!) == .heading2)
    }

    @Test func deepHeadingsHaveNoTurnIntoOption() {
        let deep = NoteBlock.heading(5, "Small")
        #expect(NoteTurnIntoOption(block: deep) == nil)
    }

    @Test func deepHeadingsStillGetAName() {
        let deep = NoteBlock.heading(5, "Small")
        #expect(NoteTurnIntoOption.label(for: deep) == "Heading 5")
    }

    @Test func theTurnIntoListStartsAtText() {
        #expect(NoteTurnIntoOption.allCases.first == .text)
    }

    @Test func heading4SitsInTheListLikeNotions() {
        #expect(NoteTurnIntoOption(block: NoteBlock.heading(4, "Four")) == .heading4)
    }

    @Test func turnIntoShortcutsReadInParcsModifierOrder() {
        #expect(NoteTurnIntoOption.heading1.chord?.display == "⌥⌘1")
    }

    private func colorModel() -> NoteColorMenuModel {
        NoteColorMenuModel(recents: [.background(.yellow), .text(.blue), .background(.yellow)],
                           summary: NoteColorSummary(styles: [.text(.blue), .text(.blue)]))
    }

    @Test func lastUsedLeadsTheColourMenu() {
        #expect(colorModel().sections.map(\.title) == ["Last Used", "Text", "Background"])
    }

    @Test func recentsDropDuplicates() {
        #expect(colorModel().sections[0].choices == [.background(.yellow), .text(.blue)])
    }

    @Test func eachColourSectionIsTheDefaultPlusNine() {
        let sections = colorModel().sections
        #expect(sections[1].choices.count == 10)
        #expect(sections[2].choices.count == 10)
    }

    @Test func theCurrentTextColourIsChecked() {
        let model = colorModel()
        #expect(model.isChecked(.text(.blue)))
        #expect(!model.isChecked(.text(nil)))
    }

    @Test func theDefaultBackgroundIsChecked() {
        let model = colorModel()
        #expect(model.isChecked(.background(nil)))
    }

    @Test func noRecentsNoLastUsed() {
        #expect(NoteColorMenuModel(recents: [], summary: .plain).sections.count == 2)
    }

    @Test func mixedColoursCheckNothingInTheMenu() {
        let mixed = NoteColorSummary(styles: [.text(.blue), nil])
        #expect(mixed.isTextMixed)
        #expect(!NoteColorMenuModel(recents: [], summary: mixed).isChecked(.text(nil)))
    }

    @Test func backgroundsSummariseSeparately() {
        let background = NoteColorSummary(styles: [.background(.pink)])
        #expect(background.background == .pink)
        #expect(background.text == nil)
        #expect(background.uniform == .background(.pink))
    }

    @Test func pickingATextColourSetsIt() {
        var marks = NoteMarks.plain
        NoteColorChoice.text(.red).apply(to: &marks)
        #expect(marks.color == .text(.red))
    }

    @Test func defaultBackgroundLeavesATextColourAlone() {
        var marks = NoteMarks.plain
        NoteColorChoice.text(.red).apply(to: &marks)
        NoteColorChoice.background(nil).apply(to: &marks)
        #expect(marks.color == .text(.red))
    }

    @Test func defaultTextClearsATextColour() {
        var marks = NoteMarks.plain
        NoteColorChoice.text(.red).apply(to: &marks)
        NoteColorChoice.text(nil).apply(to: &marks)
        #expect(marks.color == nil)
    }

    @Test func defaultBackgroundClearsABackground() {
        var marks = NoteMarks.plain
        NoteColorChoice.background(.green).apply(to: &marks)
        NoteColorChoice.background(nil).apply(to: &marks)
        #expect(marks.color == nil)
    }

    @Test(arguments: NoteColorChoice.textChoices + NoteColorChoice.backgroundChoices)
    func aColourChoiceSurvivesAnIDRoundTrip(choice: NoteColorChoice) {
        #expect(NoteColorChoice(id: choice.id) == choice)
    }

    @Test func colourNamesReadLikeNotions() {
        #expect(NoteColorChoice.text(.gray).title == "Gray Text")
        #expect(NoteColorChoice.background(nil).title == "Default Background")
    }

    private func recentColours() -> [NoteColorStyle] {
        let defaults = UserDefaults(suiteName: "NoteFormatBarModelTestsTurnIntoAndColour.\(UUID().uuidString)")!
        for style in [NoteColorStyle.text(.red), .background(.blue), .text(.red), .text(.green), .text(.gray), .text(.brown), .text(.orange)] {
            NoteColorRecents.record(style, in: defaults)
        }
        return NoteColorRecents.load(from: defaults)
    }

    @Test func recentsKeepTheNewestFew() {
        let recents = recentColours()
        #expect(recents.first == .text(.orange))
        #expect(recents.count == NoteColorRecents.limit)
    }

    @Test func recentsNeverRepeat() {
        let recents = recentColours()
        #expect(Set(recents).count == recents.count)
    }

    private let grid = NoteColorMenuModel(recents: [.text(.red)], summary: .plain)

    @Test func keyboardEntryStartsAtTheFirstSwatch() {
        #expect(grid.move(from: nil, dx: 1, dy: 0)! == (0, 0))
    }

    @Test func rightArrowWalksIntoTheNextSection() {
        #expect(grid.move(from: (0, 0), dx: 1, dy: 0)! == (1, 0))
    }

    @Test func downArrowKeepsTheColumn() {
        #expect(grid.move(from: (1, 7), dx: 0, dy: 1)! == (2, 7))
    }

    @Test func upIntoAShortRowClampsTheColumn() {
        #expect(grid.move(from: (1, 7), dx: 0, dy: -1)! == (0, 0))
    }

    @Test func rightArrowWrapsAround() {
        #expect(grid.move(from: (2, 9), dx: 1, dy: 0)! == (0, 0))
    }
}
