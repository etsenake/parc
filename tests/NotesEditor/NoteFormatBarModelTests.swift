import AppKit

@main @MainActor
struct NoteFormatBarModelTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        placement()
        dropdowns()
        activeState()
        contexts()
        turnInto()
        colors()
        links()
        chords()
        focus()
        print("NoteFormatBarModelTests passed")
    }

    static func placement() {
        let visible = NSRect(x: 0, y: 100, width: 800, height: 600)
        let size = NSSize(width: 300, height: 34)
        let oneLine = [NSRect(x: 200, y: 400, width: 120, height: 22)]
        let above = NoteFormatBarPlacement.compute(lineRects: oneLine, size: size, visible: visible)
        expect(above?.edge == .above, "a selection with room above gets the bar above it")
        expect(above?.frame.maxY == 400 - NoteFormatBarPlacement.gap, "the bar sits one gap above the top line")
        expect(above?.frame.midX == 260, "the bar centres on the selection's top line")

        let paragraph = [NSRect(x: 300, y: 400, width: 400, height: 22), NSRect(x: 40, y: 422, width: 660, height: 22),
                         NSRect(x: 40, y: 444, width: 80, height: 22)]
        let wrapped = NoteFormatBarPlacement.compute(lineRects: paragraph, size: size, visible: visible)
        expect(wrapped?.frame.midX == 500, "a wrapped selection centres on its first line, not the whole block")

        let nearTop = [NSRect(x: 200, y: 120, width: 120, height: 22), NSRect(x: 40, y: 142, width: 200, height: 22)]
        let flipped = NoteFormatBarPlacement.compute(lineRects: nearTop, size: size, visible: visible)
        expect(flipped?.edge == .below, "no room above flips the bar below")
        expect(flipped?.frame.minY == 164 + NoteFormatBarPlacement.gap, "the flipped bar hangs below the last line")
        expect(flipped?.frame.midX == 150 || flipped?.frame.minX == NoteFormatBarPlacement.margin,
               "the flipped bar centres on the last line, clamped")

        let tall = [NSRect(x: 100, y: 50, width: 500, height: 22), NSRect(x: 100, y: 900, width: 500, height: 22)]
        let pinned = NoteFormatBarPlacement.compute(lineRects: tall, size: size, visible: visible)
        expect(pinned?.edge == .pinned && pinned?.frame.minY == 108, "a selection taller than the view pins the bar to the top")

        let leftEdge = [NSRect(x: 2, y: 400, width: 30, height: 22)]
        let clampedLeft = NoteFormatBarPlacement.compute(lineRects: leftEdge, size: size, visible: visible)
        expect(clampedLeft?.frame.minX == NoteFormatBarPlacement.margin, "the bar never pokes past the left edge")
        let rightEdge = [NSRect(x: 770, y: 400, width: 28, height: 22)]
        let clampedRight = NoteFormatBarPlacement.compute(lineRects: rightEdge, size: size, visible: visible)
        expect(clampedRight?.frame.maxX == 800 - NoteFormatBarPlacement.margin, "the bar never pokes past the right edge")

        let offscreen = [NSRect(x: 100, y: 1200, width: 50, height: 22)]
        expect(NoteFormatBarPlacement.compute(lineRects: offscreen, size: size, visible: visible) == nil,
               "a selection scrolled out of view hides the bar")
        expect(NoteFormatBarPlacement.compute(lineRects: [], size: size, visible: visible) == nil, "no rects, no bar")

        let narrow = NSRect(x: 0, y: 0, width: 200, height: 400)
        let squeezed = NoteFormatBarPlacement.compute(lineRects: [NSRect(x: 50, y: 200, width: 40, height: 20)], size: size, visible: narrow)
        expect(squeezed?.frame.minX == NoteFormatBarPlacement.margin, "a bar wider than the view hugs the leading edge")
    }

    static func dropdowns() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: 240, height: 300)
        let below = NoteFormatBarPlacement.dropdown(anchor: NSRect(x: 100, y: 100, width: 80, height: 28), size: size, visible: visible)
        expect(below.edge == .below && below.frame.minY == 134 && below.frame.minX == 100, "dropdowns open below their button")
        let above = NoteFormatBarPlacement.dropdown(anchor: NSRect(x: 100, y: 500, width: 80, height: 28), size: size, visible: visible)
        expect(above.edge == .above && above.frame.maxY == 494, "dropdowns flip above when the bottom is tight")
        let right = NoteFormatBarPlacement.dropdown(anchor: NSRect(x: 700, y: 100, width: 80, height: 28), size: size, visible: visible)
        expect(right.frame.maxX == 792, "dropdowns stay inside the right edge")
        let cramped = NoteFormatBarPlacement.dropdown(anchor: NSRect(x: 100, y: 280, width: 80, height: 28),
                                                      size: NSSize(width: 240, height: 500), visible: visible)
        expect(cramped.frame.minY >= 8 && cramped.frame.maxY <= 600 || cramped.frame.minY == 8,
               "a dropdown too tall for either side stays on screen")
    }

    static func page() -> (NotePageSession, NoteBlock, NoteBlock, NoteBlock) {
        var bold = NoteMarks.plain
        bold.bold = true
        var linked = NoteMarks.plain
        linked.link = "https://parc.example"
        linked.color = .text(.red)
        let first = NoteBlock.paragraph(NoteText(pieces: [("Hello ", .plain), ("bold", bold), (" world", .plain)]))
        let second = NoteBlock(.heading, text: NoteText(pieces: [("Linked", linked), (" tail", .plain)]),
                               props: { var props = NoteBlockProps(); props.level = 2; return props }())
        let code = NoteBlock(.code, text: "let x = 1")
        return (NotePageSession(page: NotePage(blocks: [first, second, code])), first, second, code)
    }

    static func select(_ session: NotePageSession, _ a: NotePosition, _ b: NotePosition) -> NoteFormatState? {
        session.setSelection(.text(anchor: a, head: b))
        return NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false)
    }

    static func activeState() {
        let (session, first, second, code) = page()
        let boldOnly = select(session, NotePosition(first.id, 6), NotePosition(first.id, 10))
        expect(boldOnly?.isActive(.bold) == true, "a fully bold selection shows Bold checked")
        expect(boldOnly?.isActive(.italic) == false, "unused marks stay unchecked")
        expect(boldOnly?.turnIntoLabel == "Text" && boldOnly?.turnInto == .text, "Turn into names the block type")
        let mixed = select(session, NotePosition(first.id, 0), NotePosition(first.id, 10))
        expect(mixed?.isActive(.bold) == false, "a partly bold selection shows Bold unchecked")
        let backwards = select(session, NotePosition(first.id, 10), NotePosition(first.id, 6))
        expect(backwards?.isActive(.bold) == true, "a backwards selection reads the same marks")

        let linked = select(session, NotePosition(second.id, 0), NotePosition(second.id, 6))
        expect(linked?.link == "https://parc.example" && linked?.isActive(.link) == true, "a linked selection shows Link checked")
        expect(linked?.color.text == .red && linked?.color.uniform == .text(.red), "the colour glyph reads the span colour")
        expect(linked?.turnIntoLabel == "Heading 2", "headings name their level")
        let partly = select(session, NotePosition(second.id, 3), NotePosition(second.id, 9))
        expect(partly?.link == nil && partly?.firstLink == "https://parc.example", "a half-linked selection keeps the link to edit")
        expect(partly?.color.isTextMixed == true && partly?.color.uniform == nil, "mixed colours check nothing")

        let across = select(session, NotePosition(first.id, 6), NotePosition(second.id, 3))
        expect(across?.spansBlocks == true && across?.bodyBlocks == [first.id, second.id], "cross-block selections touch every block")
        expect(across?.isEnabled(.equation) == false && across?.isEnabled(.mention) == false,
               "equation and mention need a single block")
        expect(across?.isTurnIntoUniform == false && across?.turnIntoLabel == "Text", "mixed types show the first block's type")

        let intoCode = select(session, NotePosition(second.id, 2), NotePosition(code.id, 3))
        expect(intoCode?.bodyBlocks == [second.id], "code blocks drop out of a cross-block selection")
        expect(select(session, NotePosition(code.id, 0), NotePosition(code.id, 3)) == nil, "code blocks never show the bar")
        expect(select(session, NotePosition(first.id, 3), NotePosition(first.id, 3)) == nil, "a caret shows no bar")
        session.setSelection(.text(anchor: NotePosition(first.id, 0), head: NotePosition(first.id, 4)))
        expect(NoteFormatState.resolve(session: session, isPlainText: true, isReadOnly: false) == nil, "plain-text pages show no bar")
        expect(NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: true) == nil, "locked pages show no bar")
        session.setSelection(.blocks([first.id]))
        expect(NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false) == nil, "block selection shows no bar")

        session.toggleMark(.italic, in: .text(anchor: NotePosition(first.id, 0), head: NotePosition(first.id, 5)))
        let italic = select(session, NotePosition(first.id, 0), NotePosition(first.id, 5))
        expect(italic?.isActive(.italic) == true, "toggling a mark is reflected right away")

        let equation = NoteBlock.paragraph(NoteText.atom(.equation("e^{i\\pi}")) + NoteText(" done"))
        let math = NotePageSession(page: NotePage(blocks: [equation]))
        math.setSelection(.text(anchor: NotePosition(equation.id, 0), head: NotePosition(equation.id, 1)))
        let atom = NoteFormatState.resolve(session: math, isPlainText: false, isReadOnly: false)
        expect(atom?.isActive(.equation) == true && atom?.isEnabled(.mention) == false, "a selected equation shows Equation checked")
        expect(atom?.selectedText == "e^{i\\pi}", "selected text reads equation sources")
    }

    static func contexts() {
        var props = NoteBlockProps()
        props.caption = "A fine caption"
        let image = NoteBlock(.image, props: props)
        var tableProps = NoteBlockProps()
        tableProps.table = NoteTable(rows: [["Cell one", "Two"]])
        let table = NoteBlock(.table, props: tableProps)
        let session = NotePageSession(page: NotePage(blocks: [image, table]))
        let caption = select(session, NotePosition(image.id, 2, field: .caption), NotePosition(image.id, 6, field: .caption))
        expect(caption?.context == .caption && caption?.items.contains(.turnInto) == false, "captions get the reduced set")
        expect(caption?.items.contains(.bold) == true && caption?.items.contains(.link) == true, "captions keep marks and links")
        let cell = select(session, NotePosition(table.id, 0, field: .cell(row: 0, column: 0)),
                          NotePosition(table.id, 4, field: .cell(row: 0, column: 0)))
        expect(cell?.context == .cell && cell?.items.first == .link, "table cells start at Link")
        expect(NoteFormatItem.items(for: .body).first == .turnInto && NoteFormatItem.items(for: .body).count == 10,
               "body text gets every item, Turn into first")
        expect(NoteFormatItem.items(for: .body).map(\.group) == NoteFormatItem.items(for: .body).map(\.group).sorted(),
               "items stay grouped in Notion's order")
    }

    static func turnInto() {
        let (session, first, second, _) = page()
        for option in NoteTurnIntoOption.allCases where option.kind.hasRichText {
            session.turnInto([first.id], kind: option.kind, configure: option.configure)
            let block = session.page.block(first.id)!
            expect(NoteTurnIntoOption(block: block) == option, "\(option.title) round-trips through turnInto")
        }
        session.turnInto([first.id], kind: NoteTurnIntoOption.toggleHeading2.kind, configure: NoteTurnIntoOption.toggleHeading2.configure)
        let toggle = session.page.block(first.id)!
        expect(toggle.props.toggleable && toggle.props.level == 2 && toggle.props.expanded, "toggle headings open expanded")
        session.turnInto([first.id], kind: NoteTurnIntoOption.heading2.kind, configure: NoteTurnIntoOption.heading2.configure)
        expect(session.page.block(first.id)?.props.toggleable == false, "a toggle heading turns back into a plain one")
        expect(NoteTurnIntoOption(block: session.page.block(second.id)!) == .heading2, "existing headings map to options")
        let deep = NoteBlock.heading(5, "Small")
        expect(NoteTurnIntoOption(block: deep) == nil && NoteTurnIntoOption.label(for: deep) == "Heading 5",
               "deeper headings still get a name")
        expect(NoteTurnIntoOption.allCases.first == .text && NoteTurnIntoOption.allCases.count == 15, "the list starts at Text")
        expect(NoteTurnIntoOption.heading1.chord?.display == "⌥⌘1", "turn-into shortcuts read in Parc's modifier order")
    }

    static func colors() {
        let summary = NoteColorSummary(styles: [.text(.blue), .text(.blue)])
        let model = NoteColorMenuModel(recents: [.background(.yellow), .text(.blue), .background(.yellow)], summary: summary)
        expect(model.sections.map(\.title) == ["Last Used", "Text", "Background"], "Last used leads the colour menu")
        expect(model.sections[0].choices == [.background(.yellow), .text(.blue)], "recents drop duplicates")
        expect(model.sections[1].choices.count == 10 && model.sections[2].choices.count == 10, "default plus nine per section")
        expect(model.isChecked(.text(.blue)) && model.isChecked(.background(nil)) && !model.isChecked(.text(nil)),
               "the current text colour and default background are checked")
        expect(NoteColorMenuModel(recents: [], summary: .plain).sections.count == 2, "no recents, no Last used")
        let mixed = NoteColorSummary(styles: [.text(.blue), nil])
        expect(mixed.isTextMixed && !NoteColorMenuModel(recents: [], summary: mixed).isChecked(.text(nil)), "mixed colours check nothing")
        let background = NoteColorSummary(styles: [.background(.pink)])
        expect(background.background == .pink && background.text == nil && background.uniform == .background(.pink),
               "backgrounds summarise separately")

        var marks = NoteMarks.plain
        NoteColorChoice.text(.red).apply(to: &marks)
        expect(marks.color == .text(.red), "picking a text colour sets it")
        NoteColorChoice.background(nil).apply(to: &marks)
        expect(marks.color == .text(.red), "default background leaves a text colour alone")
        NoteColorChoice.text(nil).apply(to: &marks)
        expect(marks.color == nil, "default text clears a text colour")
        NoteColorChoice.background(.green).apply(to: &marks)
        NoteColorChoice.background(nil).apply(to: &marks)
        expect(marks.color == nil, "default background clears a background")

        for choice in NoteColorChoice.textChoices + NoteColorChoice.backgroundChoices {
            expect(NoteColorChoice(id: choice.id) == choice, "\(choice.id) survives an id round trip")
        }
        expect(NoteColorChoice.text(.gray).title == "Gray Text" && NoteColorChoice.background(nil).title == "Default Background",
               "colour names read like Notion's")

        let defaults = UserDefaults(suiteName: "NoteFormatBarModelTests.\(UUID().uuidString)")!
        for style in [NoteColorStyle.text(.red), .background(.blue), .text(.red), .text(.green), .text(.gray),
                      .text(.brown), .text(.orange)] {
            NoteColorRecents.record(style, in: defaults)
        }
        let recents = NoteColorRecents.load(from: defaults)
        expect(recents.first == .text(.orange) && recents.count == NoteColorRecents.limit, "recents keep the newest few")
        expect(Set(recents).count == recents.count, "recents never repeat")

        let grid = NoteColorMenuModel(recents: [.text(.red)], summary: .plain)
        expect(grid.move(from: nil, dx: 1, dy: 0)! == (0, 0), "keyboard entry starts at the first swatch")
        expect(grid.move(from: (0, 0), dx: 1, dy: 0)! == (1, 0), "right arrow walks into the next section")
        expect(grid.move(from: (1, 7), dx: 0, dy: 1)! == (2, 7), "down arrow keeps the column")
        expect(grid.move(from: (1, 7), dx: 0, dy: -1)! == (0, 0), "up into a short row clamps the column")
        expect(grid.move(from: (2, 9), dx: 1, dy: 0)! == (0, 0), "right arrow wraps around")
    }

    static func links() {
        let cases: [(String, String?)] = [
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
            ("hello world", nil),
            ("notalink", nil),
            ("http://", nil),
            ("", nil),
            ("   ", nil),
            ("example.c", nil),
            ("-bad-.com", nil),
            ("one\ntwo.com", nil),
        ]
        for (input, expected) in cases {
            let actual = NoteLinkInput.normalize(input)
            expect(actual == expected, "normalize(\(input.debugDescription)) gave \(actual.debugDescription), wanted \(expected.debugDescription)")
        }
        expect(NoteLinkInput.displayText("https://www.example.com/") == "www.example.com", "display drops the scheme and bare slash")
        expect(NoteLinkInput.displayText("https://example.com/a%20b?x=1") == "example.com/a b?x=1", "display decodes the path")
        expect(NoteLinkInput.displayText("mailto:hi@parc.example") == "hi@parc.example", "display drops mailto")
        expect(NoteLinkInput.displayText("./Other%20Note.md") == "./Other Note.md", "relative links display decoded")
        expect(NoteLinkInput.isRelative("Ideas.md") && !NoteLinkInput.isRelative("https://x.com") && !NoteLinkInput.isRelative("#a"),
               "relative links are told apart from web links and anchors")
        expect(NoteLinkInput.isNotePath("Plan%20B.md") && !NoteLinkInput.isNotePath("photo.png"), "note paths are .md or .txt")
    }

    static func chords() {
        expect(NoteFormatShortcut.bold.matches(characters: "b", flags: .command), "⌘B matches")
        expect(!NoteFormatShortcut.bold.matches(characters: "b", flags: [.command, .shift]), "⌘⇧B is not ⌘B")
        expect(NoteFormatShortcut.strikethrough.matches(characters: "S", flags: [.command, .shift]), "⌘⇧S matches the shifted letter")
        expect(NoteFormatShortcut.focusToolbar.matches(characters: "?", flags: [.command, .shift]), "⌘? focuses the toolbar")
        expect(NoteFormatShortcut.lastColor.matches(characters: "H", flags: [.command, .shift, .capsLock]), "caps lock never matters")
        expect(NoteFormatShortcut.strikethrough.display == "⇧⌘S" && NoteFormatShortcut.lastColor.glyphs == ["⇧", "⌘", "H"],
               "chords read in Parc's keycap order")
        expect(NoteFormatItem.shortcutItem(for: ("e", [.command, .shift])) == .equation, "⌘⇧E is the equation shortcut")
        expect(NoteFormatItem.shortcutItem(for: ("e", .command)) == .code, "⌘E is inline code")
        expect(NoteFormatItem.shortcutItem(for: ("k", .command)) == .link, "⌘K is the link editor")
        expect(NoteFormatItem.shortcutItem(for: ("x", .command)) == nil, "other chords pass through")
    }

    static func focus() {
        let enabled = [true, true, false, true]
        expect(NoteFormatBarFocus.move(from: nil, by: 1, enabled: enabled) == 0, "keyboard focus starts at the first item")
        expect(NoteFormatBarFocus.move(from: nil, by: -1, enabled: enabled) == 3, "left from nothing starts at the end")
        expect(NoteFormatBarFocus.move(from: 1, by: 1, enabled: enabled) == 3, "disabled items are skipped")
        expect(NoteFormatBarFocus.move(from: 3, by: 1, enabled: enabled) == 0, "focus wraps around")
        expect(NoteFormatBarFocus.move(from: 0, by: -1, enabled: enabled) == 3, "focus wraps backwards")
        expect(NoteFormatBarFocus.move(from: 0, by: 1, enabled: [false, false]) == nil, "nothing enabled, nothing focused")
    }
}
