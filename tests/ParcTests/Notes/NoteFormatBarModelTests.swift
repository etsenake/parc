import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteFormatBarModelTests {
    nonisolated static let richTextOptions = NoteTurnIntoOption.allCases.filter { $0.kind.hasRichText }

    let visible = NSRect(x: 0, y: 100, width: 800, height: 600)
    let size = NSSize(width: 300, height: 34)

    func place(_ rects: [NSRect], in area: NSRect? = nil) -> NoteFormatBarPlacement? {
        NoteFormatBarPlacement.compute(lineRects: rects, size: size, visible: area ?? visible)
    }

    @Test func aSelectionWithRoomAboveGetsTheBarAboveIt() {
        let above = place([NSRect(x: 200, y: 400, width: 120, height: 22)])
        #expect(above?.edge == .above)
        #expect(above?.frame.maxY == 400 - NoteFormatBarPlacement.gap)
    }

    @Test func theBarCentresOnTheSelectionsTopLine() {
        #expect(place([NSRect(x: 200, y: 400, width: 120, height: 22)])?.frame.midX == 260)
    }

    @Test func aWrappedSelectionCentresOnItsFirstLineNotTheWholeBlock() {
        let paragraph = [NSRect(x: 300, y: 400, width: 400, height: 22), NSRect(x: 40, y: 422, width: 660, height: 22),
                         NSRect(x: 40, y: 444, width: 80, height: 22)]
        #expect(place(paragraph)?.frame.midX == 500)
    }

    let nearTop = [NSRect(x: 200, y: 120, width: 120, height: 22), NSRect(x: 40, y: 142, width: 200, height: 22)]

    @Test func noRoomAboveFlipsTheBarBelow() {
        #expect(place(nearTop)?.edge == .below)
    }

    @Test func theFlippedBarHangsBelowTheLastLine() {
        #expect(place(nearTop)?.frame.minY == 164 + NoteFormatBarPlacement.gap)
    }

    @Test func theFlippedBarCentresOnTheLastLineClamped() {
        let flipped = place(nearTop)
        #expect(flipped?.frame.midX == 150 || flipped?.frame.minX == NoteFormatBarPlacement.margin)
    }

    @Test func aSelectionTallerThanTheViewPinsTheBarToTheTop() {
        let pinned = place([NSRect(x: 100, y: 50, width: 500, height: 22), NSRect(x: 100, y: 900, width: 500, height: 22)])
        #expect(pinned?.edge == .pinned)
        #expect(pinned?.frame.minY == 108)
    }

    @Test func theBarNeverPokesPastTheLeftEdge() {
        #expect(place([NSRect(x: 2, y: 400, width: 30, height: 22)])?.frame.minX == NoteFormatBarPlacement.margin)
    }

    @Test func theBarNeverPokesPastTheRightEdge() {
        #expect(place([NSRect(x: 770, y: 400, width: 28, height: 22)])?.frame.maxX == 800 - NoteFormatBarPlacement.margin)
    }

    @Test func aSelectionScrolledOutOfViewHidesTheBar() {
        #expect(place([NSRect(x: 100, y: 1200, width: 50, height: 22)]) == nil)
    }

    @Test func noRectsNoBar() {
        #expect(place([]) == nil)
    }

    @Test func aBarWiderThanTheViewHugsTheLeadingEdge() {
        let squeezed = place([NSRect(x: 50, y: 200, width: 40, height: 20)], in: NSRect(x: 0, y: 0, width: 200, height: 400))
        #expect(squeezed?.frame.minX == NoteFormatBarPlacement.margin)
    }

    func dropdown(anchor: NSRect, size: NSSize = NSSize(width: 240, height: 300)) -> NoteFormatBarPlacement {
        NoteFormatBarPlacement.dropdown(anchor: anchor, size: size, visible: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func dropdownsOpenBelowTheirButton() {
        let below = dropdown(anchor: NSRect(x: 100, y: 100, width: 80, height: 28))
        #expect(below.edge == .below)
        #expect(below.frame.minY == 134)
        #expect(below.frame.minX == 100)
    }

    @Test func dropdownsFlipAboveWhenTheBottomIsTight() {
        let above = dropdown(anchor: NSRect(x: 100, y: 500, width: 80, height: 28))
        #expect(above.edge == .above)
        #expect(above.frame.maxY == 494)
    }

    @Test func dropdownsStayInsideTheRightEdge() {
        #expect(dropdown(anchor: NSRect(x: 700, y: 100, width: 80, height: 28)).frame.maxX == 792)
    }

    @Test func aDropdownTooTallForEitherSideStaysOnScreen() {
        let cramped = dropdown(anchor: NSRect(x: 100, y: 280, width: 80, height: 28), size: NSSize(width: 240, height: 500))
        #expect(cramped.frame.minY >= 8 && cramped.frame.maxY <= 600 || cramped.frame.minY == 8)
    }

    @MainActor struct Page {
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

    @Test func aFullyBoldSelectionShowsBoldChecked() {
        #expect(Page().inFirst(6, 10)?.isActive(.bold) == true)
    }

    @Test func unusedMarksStayUnchecked() {
        #expect(Page().inFirst(6, 10)?.isActive(.italic) == false)
    }

    @Test func turnIntoNamesTheBlockType() {
        let state = Page().inFirst(6, 10)
        #expect(state?.turnIntoLabel == "Text")
        #expect(state?.turnInto == .text)
    }

    @Test func aPartlyBoldSelectionShowsBoldUnchecked() {
        #expect(Page().inFirst(0, 10)?.isActive(.bold) == false)
    }

    @Test func aBackwardsSelectionReadsTheSameMarks() {
        #expect(Page().inFirst(10, 6)?.isActive(.bold) == true)
    }

    @Test func aLinkedSelectionShowsLinkChecked() {
        let linked = Page().inSecond(0, 6)
        #expect(linked?.link == "https://parc.example")
        #expect(linked?.isActive(.link) == true)
    }

    @Test func theColourGlyphReadsTheSpanColour() {
        let linked = Page().inSecond(0, 6)
        #expect(linked?.color.text == .red)
        #expect(linked?.color.uniform == .text(.red))
    }

    @Test func headingsNameTheirLevel() {
        #expect(Page().inSecond(0, 6)?.turnIntoLabel == "Heading 2")
    }

    @Test func aHalfLinkedSelectionKeepsTheLinkToEdit() {
        let partly = Page().inSecond(3, 9)
        #expect(partly?.link == nil)
        #expect(partly?.firstLink == "https://parc.example")
    }

    @Test func mixedColoursCheckNothing() {
        let partly = Page().inSecond(3, 9)
        #expect(partly?.color.isTextMixed == true)
        #expect(partly?.color.uniform == nil)
    }

    func across() -> (Page, NoteFormatState?) {
        let page = Page()
        return (page, page.select(NotePosition(page.first.id, 6), NotePosition(page.second.id, 3)))
    }

    @Test func crossBlockSelectionsTouchEveryBlock() {
        let (page, state) = across()
        #expect(state?.spansBlocks == true)
        #expect(state?.bodyBlocks == [page.first.id, page.second.id])
    }

    @Test func equationAndMentionNeedASingleBlock() {
        let state = across().1
        #expect(state?.isEnabled(.equation) == false)
        #expect(state?.isEnabled(.mention) == false)
    }

    @Test func mixedTypesShowTheFirstBlocksType() {
        let state = across().1
        #expect(state?.isTurnIntoUniform == false)
        #expect(state?.turnIntoLabel == "Text")
    }

    @Test func codeBlocksDropOutOfACrossBlockSelection() {
        let page = Page()
        #expect(page.select(NotePosition(page.second.id, 2), NotePosition(page.code.id, 3))?.bodyBlocks == [page.second.id])
    }

    @Test func codeBlocksNeverShowTheBar() {
        let page = Page()
        #expect(page.select(NotePosition(page.code.id, 0), NotePosition(page.code.id, 3)) == nil)
    }

    @Test func aCaretShowsNoBar() {
        #expect(Page().inFirst(3, 3) == nil)
    }

    @Test func plainTextPagesShowNoBar() {
        let page = Page()
        page.session.setSelection(.text(anchor: NotePosition(page.first.id, 0), head: NotePosition(page.first.id, 4)))
        #expect(NoteFormatState.resolve(session: page.session, isPlainText: true, isReadOnly: false) == nil)
    }

    @Test func lockedPagesShowNoBar() {
        let page = Page()
        page.session.setSelection(.text(anchor: NotePosition(page.first.id, 0), head: NotePosition(page.first.id, 4)))
        #expect(NoteFormatState.resolve(session: page.session, isPlainText: false, isReadOnly: true) == nil)
    }

    @Test func blockSelectionShowsNoBar() {
        let page = Page()
        page.session.setSelection(.blocks([page.first.id]))
        #expect(NoteFormatState.resolve(session: page.session, isPlainText: false, isReadOnly: false) == nil)
    }

    @Test func togglingAMarkIsReflectedRightAway() {
        let page = Page()
        page.session.toggleMark(.italic, in: .text(anchor: NotePosition(page.first.id, 0), head: NotePosition(page.first.id, 5)))
        #expect(page.inFirst(0, 5)?.isActive(.italic) == true)
    }

    func selectedEquation() -> NoteFormatState? {
        let equation = NoteBlock.paragraph(NoteText.atom(.equation("e^{i\\pi}")) + NoteText(" done"))
        let math = NotePageSession(page: NotePage(blocks: [equation]))
        math.setSelection(.text(anchor: NotePosition(equation.id, 0), head: NotePosition(equation.id, 1)))
        return NoteFormatState.resolve(session: math, isPlainText: false, isReadOnly: false)
    }

    @Test func aSelectedEquationShowsEquationChecked() {
        let atom = selectedEquation()
        #expect(atom?.isActive(.equation) == true)
        #expect(atom?.isEnabled(.mention) == false)
    }

    @Test func selectedTextReadsEquationSources() {
        #expect(selectedEquation()?.selectedText == "e^{i\\pi}")
    }

    func captionAndTable() -> (NotePageSession, NoteBlock, NoteBlock) {
        var props = NoteBlockProps()
        props.caption = "A fine caption"
        let image = NoteBlock(.image, props: props)
        var tableProps = NoteBlockProps()
        tableProps.table = NoteTable(rows: [["Cell one", "Two"]])
        let table = NoteBlock(.table, props: tableProps)
        return (NotePageSession(page: NotePage(blocks: [image, table])), image, table)
    }

    func resolve(_ session: NotePageSession, _ a: NotePosition, _ b: NotePosition) -> NoteFormatState? {
        session.setSelection(.text(anchor: a, head: b))
        return NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false)
    }

    @Test func captionsGetTheReducedSet() {
        let (session, image, _) = captionAndTable()
        let caption = resolve(session, NotePosition(image.id, 2, field: .caption), NotePosition(image.id, 6, field: .caption))
        #expect(caption?.context == .caption)
        #expect(caption?.items.contains(.turnInto) == false)
    }

    @Test func captionsKeepMarksAndLinks() {
        let (session, image, _) = captionAndTable()
        let caption = resolve(session, NotePosition(image.id, 2, field: .caption), NotePosition(image.id, 6, field: .caption))
        #expect(caption?.items.contains(.bold) == true)
        #expect(caption?.items.contains(.link) == true)
    }

    @Test func tableCellsStartAtLink() {
        let (session, _, table) = captionAndTable()
        let cell = resolve(session, NotePosition(table.id, 0, field: .cell(row: 0, column: 0)), NotePosition(table.id, 4, field: .cell(row: 0, column: 0)))
        #expect(cell?.context == .cell)
        #expect(cell?.items.first == .link)
    }

    @Test func bodyTextGetsEveryItemTurnIntoFirst() {
        let items = NoteFormatItem.items(for: .body)
        #expect(items.first == .turnInto)
    }

    @Test func itemsStayGroupedInNotionsOrder() {
        let groups = NoteFormatItem.items(for: .body).map(\.group)
        #expect(groups == groups.sorted())
    }

    @Test(arguments: NoteFormatBarModelTests.richTextOptions)
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

    @Test func deeperHeadingsStillGetAName() {
        let deep = NoteBlock.heading(5, "Small")
        #expect(NoteTurnIntoOption(block: deep) == nil)
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

    func colorModel() -> NoteColorMenuModel {
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

    @Test func theCurrentTextColourAndDefaultBackgroundAreChecked() {
        let model = colorModel()
        #expect(model.isChecked(.text(.blue)))
        #expect(model.isChecked(.background(nil)))
        #expect(!model.isChecked(.text(nil)))
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

    func recentColours() -> [NoteColorStyle] {
        let defaults = UserDefaults(suiteName: "NoteFormatBarModelTests.\(UUID().uuidString)")!
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

    let grid = NoteColorMenuModel(recents: [.text(.red)], summary: .plain)

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

    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("  www.example.com/path?q=1#top \n", "https://www.example.com/path?q=1#top"),
        ("<https://parc.example/a>", "https://parc.example/a"),
        ("http://example.com", "http://example.com"),
        ("https://intranet:8080/x", "https://intranet:8080/x"),
        ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.10:8080/admin", "http://192.168.1.10:8080/admin"),
        ("sub.domain.co.uk", "https://sub.domain.co.uk"),
        ("someone@example.com", "mailto:someone@example.com"),
        ("mailto:someone@example.com", "mailto:someone@example.com"),
        ("tel:+15551234567", "tel:+15551234567"),
        ("./Other Note.md", "./Other%20Note.md"),
        ("Ideas.md", "Ideas.md"),
        ("../Projects/Plan.md#goals", "../Projects/Plan.md#goals"),
        ("#heading", "#heading"),
        ("/Users/me/Notes/Plan.md", "file:///Users/me/Notes/Plan.md"),
        ("obsidian://open?vault=x", "obsidian://open?vault=x"),
    ])
    func typedLinksNormalize(input: String, expected: String) {
        #expect(NoteLinkInput.normalize(input) == expected)
    }

    @Test(arguments: [
        "hello world", "notalink", "http://", "", "   ", "example.c", "-bad-.com", "one\ntwo.com", "javascript:alert(1)",
        "  JavaScript:alert(document.cookie)", "<javascript:void(0)>", "java\tscript:alert(1)", "vbscript:msgbox(1)",
        "data:text/html,<script>alert(1)</script>", "DATA:image/png;base64,AAAA",
    ])
    func typedTextThatIsNotASafeLinkIsRefused(input: String) {
        #expect(NoteLinkInput.normalize(input) == nil)
    }

    @Test(arguments: [
        ("https://www.example.com/", "www.example.com"), ("https://example.com/a%20b?x=1", "example.com/a b?x=1"),
        ("mailto:hi@parc.example", "hi@parc.example"), ("./Other%20Note.md", "./Other Note.md"),
    ])
    func linksDisplayWithoutTheirSchemeAndEscapes(link: String, shown: String) {
        #expect(NoteLinkInput.displayText(link) == shown)
    }

    @Test func relativeLinksAreToldApartFromWebLinksAndAnchors() {
        #expect(NoteLinkInput.isRelative("Ideas.md"))
        #expect(!NoteLinkInput.isRelative("https://x.com"))
        #expect(!NoteLinkInput.isRelative("#a"))
    }

    @Test func notePathsAreMarkdownOrText() {
        #expect(NoteLinkInput.isNotePath("Plan%20B.md"))
        #expect(!NoteLinkInput.isNotePath("photo.png"))
    }

    @Test(arguments: ["javascript:alert(1)", " \u{01}JAVASCRIPT:x", "java\nscript:x", "vbscript:x", "data:text/html,hi", "jav\u{00A0}ascript:x"])
    func unsafeSchemesAreRefusedAsLinks(link: String) {
        #expect(NoteLinkInput.isUnsafe(link))
    }

    @Test(arguments: ["https://example.com/javascript:x", "Ideas.md", "./data:notes.md", "mailto:hi@parc.example", "#data:x", "datas:x"])
    func ordinaryLinksAreNotUnsafe(link: String) {
        #expect(!NoteLinkInput.isUnsafe(link))
    }

    @Test func commandBMatches() {
        #expect(NoteFormatShortcut.bold.matches(characters: "b", flags: .command))
    }

    @Test func commandShiftBIsNotCommandB() {
        #expect(!NoteFormatShortcut.bold.matches(characters: "b", flags: [.command, .shift]))
    }

    @Test func strikethroughMatchesTheShiftedLetter() {
        #expect(NoteFormatShortcut.strikethrough.matches(characters: "S", flags: [.command, .shift]))
    }

    @Test func commandQuestionMarkFocusesTheToolbar() {
        #expect(NoteFormatShortcut.focusToolbar.matches(characters: "?", flags: [.command, .shift]))
    }

    @Test func capsLockNeverMatters() {
        #expect(NoteFormatShortcut.lastColor.matches(characters: "H", flags: [.command, .shift, .capsLock]))
    }

    @Test func chordsReadInParcsKeycapOrder() {
        #expect(NoteFormatShortcut.strikethrough.display == "⇧⌘S")
        #expect(NoteFormatShortcut.lastColor.glyphs == ["⇧", "⌘", "H"])
    }

    @Test(arguments: [("e", NSEvent.ModifierFlags([.command, .shift]), NoteFormatItem.equation), ("e", .command, .code), ("k", .command, .link)]
          as [(String, NSEvent.ModifierFlags, NoteFormatItem)])
    func chordsMapToTheirFormatItem(key: String, flags: NSEvent.ModifierFlags, item: NoteFormatItem) {
        #expect(NoteFormatItem.shortcutItem(for: (key, flags)) == item)
    }

    @Test func otherChordsPassThrough() {
        #expect(NoteFormatItem.shortcutItem(for: ("x", .command)) == nil)
    }

    func linkedText() -> NoteText {
        var link = NoteMarks.plain
        link.link = "https://parc.example"
        var bold = link
        bold.bold = true
        var other = NoteMarks.plain
        other.link = "Other.md"
        return NoteText(pieces: [("See ", .plain), ("the ", link), ("bold", bold), (" docs", link), (" and ", .plain), ("this", other)])
    }

    @Test func aLinkSpansEveryRunThatSharesIt() {
        let span = NoteLinkSpan.at(9, in: linkedText())
        #expect(span?.range == 4..<17)
        #expect(span?.link == "https://parc.example")
    }

    @Test func plainTextHasNoLinkSpan() {
        #expect(NoteLinkSpan.at(2, in: linkedText()) == nil)
    }

    @Test func neighbouringLinksStaySeparate() {
        let span = NoteLinkSpan.at(22, in: linkedText())
        #expect(span?.range == 22..<26)
        #expect(span?.link == "Other.md")
    }

    @Test func pastTheEndThereIsNoLink() {
        #expect(NoteLinkSpan.at(26, in: linkedText()) == nil)
    }

    func energy() -> NoteText {
        var bold = NoteMarks.plain
        bold.bold = true
        return NoteText(pieces: [("Energy ", .plain), (" E=mc^2 ", bold), ("rocks", .plain)])
    }

    @Test func spacesStayOutsideTheEquation() {
        #expect(NoteInlineEquation.wrap(energy(), range: 7..<15)?.text.string == "Energy  " + NoteAtom.character + " rocks")
    }

    @Test func theNewEquationIsReportedForSelecting() {
        #expect(NoteInlineEquation.wrap(energy(), range: 7..<15)?.atom == 8..<9)
    }

    @Test func theSourceBecomesAnEquationThatKeepsItsMarks() throws {
        let wrapped = try #require(NoteInlineEquation.wrap(energy(), range: 7..<15))
        let marks = wrapped.text.marks(at: wrapped.atom.lowerBound)
        #expect(marks.atom == .equation("E=mc^2"))
        #expect(marks.bold)
    }

    @Test func wrappingOnlySpacesDoesNothing() {
        #expect(NoteInlineEquation.wrap(energy(), range: 6..<7) == nil)
    }

    @Test func unwrappingRestoresTheSource() throws {
        let wrapped = try #require(NoteInlineEquation.wrap(energy(), range: 7..<15))
        let unwrapped = NoteInlineEquation.unwrap(wrapped.text, range: wrapped.atom)
        #expect(unwrapped.text.string == "Energy  E=mc^2 rocks")
        #expect(unwrapped.range == 8..<14)
    }

    @Test func unwrappedSourceKeepsItsMarks() throws {
        let wrapped = try #require(NoteInlineEquation.wrap(energy(), range: 7..<15))
        let unwrapped = NoteInlineEquation.unwrap(wrapped.text, range: wrapped.atom)
        #expect(unwrapped.text.marks(at: 9).bold)
        #expect(unwrapped.text.marks(at: 9).atom == nil)
    }

    @Test(arguments: [
        (nil, 1, 0), (nil, -1, 3), (1, 1, 3), (3, 1, 0), (0, -1, 3),
    ] as [(Int?, Int, Int?)])
    func keyboardFocusMovesPastDisabledItemsAndWraps(from: Int?, step: Int, expected: Int?) {
        #expect(NoteFormatBarFocus.move(from: from, by: step, enabled: [true, true, false, true]) == expected)
    }

    @Test func nothingEnabledNothingFocused() {
        #expect(NoteFormatBarFocus.move(from: 0, by: 1, enabled: [false, false]) == nil)
    }
}
