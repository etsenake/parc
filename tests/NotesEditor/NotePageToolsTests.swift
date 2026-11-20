import Foundation

@main @MainActor
struct NotePageToolsTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        finding()
        findingTitles()
        replacing()
        titleChecks()
        headerGeometry()
        calloutAlerts()
        stats()
        properties()
        history()
        relativeTime()
        exporting()
        print("NotePageToolsTests passed")
    }

    static func samplePage() -> (NotePage, [NoteBlockID]) {
        var bold = NoteMarks.plain
        bold.bold = true
        let intro = NoteBlock.paragraph(NoteText(pieces: [("Park parks ", .plain), ("PARK", bold), (" at the park.", .plain)]))
        var tableProps = NoteBlockProps()
        tableProps.table = NoteTable(rows: [["Park", "Ride"], ["Bench", "parked"]])
        let table = NoteBlock(.table, props: tableProps)
        var imageProps = NoteBlockProps()
        imageProps.source = "Attachments/park.png"
        imageProps.caption = "A park at dusk"
        let image = NoteBlock(.image, props: imageProps)
        var toggleProps = NoteBlockProps()
        toggleProps.expanded = false
        let hidden = NoteBlock.paragraph("Secret park")
        let toggle = NoteBlock(.toggle, text: "Folded", props: toggleProps, children: [hidden])
        let code = NoteBlock(.code, text: "let park = 1")
        let mention = NoteBlock.paragraph(NoteText.atom(.page(target: "park.md", title: "Park")) + NoteText(" park"))
        let divider = NoteBlock(.divider)
        let blocks = [intro, table, image, toggle, code, mention, divider]
        return (NotePage(blocks: blocks), [intro.id, table.id, image.id, toggle.id, hidden.id, code.id, mention.id])
    }

    static func finding() {
        let (page, ids) = samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page)
        let expected: [(NoteBlockID, NoteTextField, Int)] = [
            (ids[0], .body, 0), (ids[0], .body, 5), (ids[0], .body, 11), (ids[0], .body, 23),
            (ids[1], .cell(row: 0, column: 0), 0), (ids[1], .cell(row: 1, column: 1), 0),
            (ids[2], .caption, 2),
            (ids[4], .body, 7),
            (ids[5], .body, 4),
            (ids[6], .body, 2),
        ]
        expect(matches.count == expected.count, "finds every park across body, cells, caption, collapsed toggle, code and mention text (got \(matches.count))")
        for (match, want) in zip(matches, expected) {
            expect(match.block == want.0 && match.field == want.1 && match.position.offset == want.2 && match.length == 4,
                   "match \(want) lands in document order")
        }
        let cased = NotePageFinder.matches(of: "Park", in: page, options: NoteFindOptions(matchCase: true))
        expect(cased.count == 2, "match case keeps only the capitalised Parks (got \(cased.count))")
        expect(NotePageFinder.matches(of: "", in: page).isEmpty, "an empty query matches nothing")
        expect(NotePageFinder.matches(of: "zebra", in: page).isEmpty, "a missing word matches nothing")
        expect(NotePageFinder.ranges(of: "aa", in: "aaaa") == [0..<2, 2..<4], "matches never overlap")
        expect(NotePageFinder.ranges(of: "cafe", in: "Café cafe") == [0..<4, 5..<9], "diacritics fold when case is ignored")
        expect(NotePageFinder.ranges(of: "e\u{301}", in: "x\u{e9}y").count == 1, "composed and decomposed accents still meet")
        expect(NotePageFinder.matches(of: "\u{FFFC}", in: page).isEmpty == false, "the atom character itself is findable only literally")
        let caret = NotePosition(ids[2], 0, field: .body)
        expect(NotePageFinder.firstIndex(atOrAfter: caret, in: matches, page: page) == 6, "the first match after the caret is the caption")
        let end = NotePosition(ids[6], 99)
        expect(NotePageFinder.firstIndex(atOrAfter: end, in: matches, page: page) == 0, "searching past the end wraps to the top")
        expect(NotePageFinder.firstIndex(atOrAfter: nil, in: matches, page: page) == 0, "no caret starts at the top")
        let emoji = NotePage(blocks: [.paragraph("👋 park 👋 park")])
        let emojiMatches = NotePageFinder.matches(of: "park", in: emoji)
        expect(emojiMatches.map(\.position.offset) == [3, 11], "offsets are UTF-16, so emoji count twice")
    }

    static func findingTitles() {
        let (page, ids) = samplePage()
        let matches = NotePageFinder.matches(of: "park", in: page, title: "Park day at the park")
        expect(matches.count == 12, "the title adds its two parks to the ten in the body (got \(matches.count))")
        expect(matches[0].isTitle && matches[0].position.offset == 0 && matches[1].isTitle && matches[1].position.offset == 16,
               "title matches come first, in order")
        expect(!matches[2].isTitle && matches[2].block == ids[0], "the body follows the title")
        expect(matches.filter(\.isTitle).allSatisfy { $0.field == .body && $0.length == 4 }, "title matches carry plain ranges")
        expect(NotePageFinder.matches(of: "park", in: page, title: "").count == 10, "an empty title adds nothing")
        expect(NotePageFinder.matches(of: "park", in: page, title: nil).count == 10, "no title means body only")
        expect(NotePageFinder.firstIndex(atOrAfter: nil, in: matches, page: page) == 0, "no caret starts at the title")
        let inBody = NotePosition(ids[0], 0)
        expect(NotePageFinder.firstIndex(atOrAfter: inBody, in: matches, page: page) == 2, "a caret in the body skips the title")
        let titleCaret = NotePosition(NoteFindMatch.titleBlock, 5)
        expect(NotePageFinder.firstIndex(atOrAfter: titleCaret, in: matches, page: page) == 1, "a caret in the title finds the next title match")
        let end = NotePosition(ids[6], 99)
        expect(NotePageFinder.firstIndex(atOrAfter: end, in: matches, page: page) == 0, "wrapping past the end lands back on the title")
        var touched = page
        expect(NotePageFinder.replace(matches.filter(\.isTitle), with: "x", in: &touched).isEmpty && touched == page,
               "page replace leaves title matches to the header")
        expect(NotePageFinder.replacingTitle("Park day at the park", matches: matches, with: "Garden") == "Garden day at the Garden",
               "title replace rewrites every title match")
        expect(NotePageFinder.replacingTitle("Park day at the park", matches: [matches[1]], with: "beach") == "Park day at the beach",
               "title replace can swap just the current match")
        expect(NotePageFinder.replacingTitle("tiny", matches: [.title(offset: 2, length: 10)], with: "x") == "tiny",
               "a stale title match past the end is ignored")
        let cased = NotePageFinder.matches(of: "Park", in: page, title: "Park park", options: NoteFindOptions(matchCase: true))
        expect(cased.filter(\.isTitle).count == 1, "match case applies to the title too")
        let after = NotePageFinder.positionAfterReplacing(matches[0], with: "Garden")
        expect(after.block == NoteFindMatch.titleBlock && after.offset == 6, "the caret after a title replace stays in the title")
    }

    static func titleChecks() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("title-checks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Groceries.md")
        let neighbour = folder.appendingPathComponent("Errands.md")
        try? Data("a".utf8).write(to: note)
        try? Data("b".utf8).write(to: neighbour)
        expect(NotePageTitleCheck.problem(renaming: note, to: "Errands") == .nameTaken("Errands"), "a taken name is caught before renaming")
        expect(NotePageTitleCheck.problem(renaming: note, to: "Errands")?.errorDescription == "There’s already a note called “Errands” here.",
               "the collision reads in Parc's voice")
        expect(NotePageTitleCheck.problem(renaming: note, to: "Weekend plans") == nil, "a fresh name is fine")
        expect(NotePageTitleCheck.problem(renaming: note, to: "Groceries") == nil, "keeping the name is fine")
        expect(NotePageTitleCheck.problem(renaming: note, to: "groceries") == nil, "changing only the case of its own name is fine")
        expect(NotePageTitleCheck.problem(renaming: note, to: "...") == .invalidName, "a name made only of dots can't be a file")
        expect(NotePageTitleCheck.problem(renaming: note, to: "...")?.errorDescription == "Notes can’t be named that.", "invalid names explain themselves")
        expect(NotePageTitleCheck.problem(renaming: note, to: "   ") == nil, "a blank title just keeps the old name")
        expect(NotePageTitleCheck.problem(renaming: note, to: "a/b") == nil, "slashes become dashes instead of failing")
    }

    static func headerGeometry() {
        let column = CGRect(x: 140, y: 0, width: 720, height: 0)
        var base = NotePageHeaderGeometry(width: 1000, column: column, titleHeight: 55)
        base.titleCapInset = 12
        base.iconInkInset = 11
        base.affordanceHeight = 26

        var both = base
        both.coverHeight = 228
        both.hasIcon = true
        let full = both.layout()
        expect(full.cover == CGRect(x: 0, y: 0, width: 1000, height: 228), "the cover runs edge to edge")
        guard let icon = full.icon else { failTest("an icon is laid out") }
        expect(icon.minY == 228 - icon.height / 2 && icon.height == NotePageHeaderGeometry.iconSide, "the icon overlaps the cover by half")
        expect(icon.minX == column.minX - NotePageHeaderGeometry.iconLead, "the icon sits on the text column")
        let inkGap = (full.title.minY + 12) - (icon.maxY - 11)
        expect(inkGap >= 12 && inkGap <= 16, "the title's caps sit 12 to 16 pt under the icon's ink (got \(inkGap))")
        expect(full.title.minY - icon.maxY < 8, "the title hugs the icon box (gap \(full.title.minY - icon.maxY))")
        expect(full.affordances.minX >= icon.maxX && full.affordances.minY >= 228 && full.affordances.maxY <= icon.maxY,
               "the hover row sits beside the icon's foot, below the cover")
        expect(full.height == (full.title.maxY + NotePageHeaderGeometry.bottomPadding).rounded(.up), "the header ends just under the title")

        var iconOnly = base
        iconOnly.hasIcon = true
        let plainIcon = iconOnly.layout()
        expect(plainIcon.cover == nil && plainIcon.icon?.minY == NotePageHeaderGeometry.topPadding, "without a cover the icon starts at the top padding")
        expect(plainIcon.title.minY - (plainIcon.icon?.maxY ?? 0) == full.title.minY - icon.maxY, "the icon to title rhythm holds without a cover")

        var coverOnly = base
        coverOnly.coverHeight = 228
        let banner = coverOnly.layout()
        expect(banner.icon == nil && banner.affordances.minY > 228 && banner.affordances.maxY < banner.title.minY + 12,
               "with only a cover, the hover row rests between the cover and the title's caps")
        expect(banner.title.minY - 228 < 60, "the title stays close under a bare cover (gap \(banner.title.minY - 228))")

        let neither = base.layout()
        expect(neither.icon == nil && neither.cover == nil && neither.affordances.minY == NotePageHeaderGeometry.topPadding,
               "a bare page keeps its hover row in the top padding")
        expect(neither.title.minY + 12 - neither.affordances.maxY == NotePageHeaderGeometry.inkGap, "the bare title sits one ink gap under the row")

        var withError = both
        withError.errorHeight = 20
        let erring = withError.layout()
        expect(erring.title == full.title, "an error never moves the title")
        expect(erring.error == CGRect(x: column.minX, y: full.title.maxY + NotePageHeaderGeometry.errorGap, width: 720, height: 20),
               "the error sits right under the title")
        expect(erring.height == full.height + 20 + NotePageHeaderGeometry.errorGap, "the error makes room for itself")

        var withProperties = withError
        withProperties.propertiesHeight = 120
        withProperties.propertiesGutter = 24
        let listed = withProperties.layout()
        expect(listed.properties == CGRect(x: column.minX - 24, y: erring.error!.maxY + NotePageHeaderGeometry.propertiesGap, width: 744, height: 120),
               "properties follow the error, hanging into the gutter")

        var plain = base
        plain.isPlainText = true
        plain.coverHeight = 228
        plain.hasIcon = true
        let text = plain.layout()
        expect(text.cover == nil && text.icon == nil && text.title.minY == NotePageHeaderGeometry.plainTextTop,
               "plain text pages skip the cover and icon")
        var narrow = base
        narrow.column = .zero
        expect(narrow.layout().title.width == 1000, "a missing column falls back to the full width")
    }

    static func calloutAlerts() {
        func callout(alert: String?, icon: String? = nil, color: NoteColorStyle? = nil) -> NoteBlock {
            var block = NoteBlock(.callout, text: "Heads up")
            block.props.alert = alert
            block.props.icon = icon
            block.color = color
            return block
        }
        let expected: [(String, String, NoteColor)] = [
            ("TIP", "💡", .green), ("IMPORTANT", "❗️", .purple), ("WARNING", "⚠️", .yellow), ("CAUTION", "🛑", .red),
            ("note", "ℹ️", .blue), ("info", "ℹ️", .blue), ("success", "✅", .green), ("question", "❓", .orange),
            ("failure", "❌", .red), ("danger", "⚡️", .red), ("bug", "🐛", .red), ("example", "📝", .purple),
            ("quote", "💬", .gray), ("abstract", "📋", .blue), ("todo", "☑️", .blue),
        ]
        for (alert, icon, color) in expected {
            let block = callout(alert: alert)
            expect(block.calloutDisplayIcon == icon, "\(alert) shows \(icon) (got \(block.calloutDisplayIcon ?? "nothing"))")
            expect(block.calloutDisplayColor == .background(color), "\(alert) gets a \(color) box")
            expect(block.props.icon == nil && block.color == nil, "\(alert) defaults stay display only")
        }
        expect(callout(alert: "tip").calloutDisplayIcon == "💡", "alert names ignore case")
        expect(callout(alert: "mystery").calloutDisplayIcon == nil && callout(alert: "mystery").calloutDisplayColor == nil,
               "unknown alerts keep the plain grey box")
        expect(callout(alert: nil).calloutDisplayIcon == nil, "plain callouts without an icon stay iconless")
        expect(callout(alert: "TIP", icon: "🌳").calloutDisplayIcon == "🌳", "a picked icon wins")
        expect(callout(alert: "TIP", icon: "").calloutDisplayIcon == nil, "a removed icon stays removed")
        expect(callout(alert: "TIP", color: .background(.pink)).calloutDisplayColor == .background(.pink), "a picked colour wins")
        expect(callout(alert: "TIP", color: .text(.red)).calloutDisplayColor == .text(.red), "a picked text colour wins too")
        expect(callout(alert: "TIP").calloutIconRemoval == "" && callout(alert: nil).calloutIconRemoval == nil,
               "removing an alert's icon writes an explicit none, a plain callout just drops it")
        var paragraph = NoteBlock.paragraph("Hi")
        paragraph.props.alert = "TIP"
        expect(paragraph.calloutDisplayIcon == nil && paragraph.calloutDisplayColor == nil, "only callouts get alert defaults")

        let source = "> [!TIP]\n> Try the shortcut.\n"
        var page = NoteMarkdown.parse(source)
        expect(NoteMarkdown.serialize(page) == source, "showing an alert's defaults never rewrites the file")
        page.blocks[0].props.icon = page.blocks[0].calloutIconRemoval
        let reread = NoteMarkdown.parse(NoteMarkdown.serialize(page))
        expect(reread.blocks[0].props.alert == "TIP" && reread.blocks[0].calloutDisplayIcon == nil,
               "a removed alert icon survives the file round trip without losing the alert")
        let html = NotePageHTML.document(NotePage(blocks: [callout(alert: "WARNING")]), title: "T", assets: { _ in nil }, embedImages: false)
        expect(html.contains("⚠️") && html.contains("var(--yellow-bg)") && html.contains("<aside class=\"callout\" data-block"),
               "HTML export shows the alert's look without claiming a picked colour")
        let fragment = NotePageHTML.fragment([callout(alert: "WARNING")])
        expect(fragment.contains("data-default-icon") && !fragment.contains("data-color") && !fragment.contains("data-icon="),
               "copied callouts mark alert defaults so pasting doesn't adopt them")
    }

    static func replacing() {
        let (original, ids) = samplePage()
        var page = original
        let all = NotePageFinder.matches(of: "park", in: page)
        let touched = NotePageFinder.replace(all, with: "garden", in: &page)
        expect(touched == Set([ids[0], ids[1], ids[2], ids[4], ids[5], ids[6]]), "replace all touches every block with a match")
        expect(page.block(ids[0])?.text.string == "garden gardens garden at the garden.", "replace all rewrites the paragraph")
        expect(page.block(ids[0])?.text.marks(at: 15).bold == true, "a replaced bold word stays bold")
        expect(page.block(ids[0])?.text.marks(at: 7).bold == false, "plain words stay plain")
        expect(page.block(ids[1])?.props.table?.rows[1][1].string == "gardened", "table cells get replaced")
        expect(page.block(ids[2])?.props.caption.string == "A garden at dusk", "captions get replaced")
        expect(page.block(ids[4])?.text.string == "Secret garden", "collapsed toggle children get replaced")
        expect(page.block(ids[6])?.text.length == 8 && page.block(ids[6])?.text.marks(at: 0).atom != nil,
               "mentions survive while the text beside them changes")
        expect(NotePageFinder.matches(of: "park", in: page).isEmpty, "nothing left to find afterwards")

        var single = original
        let first = NotePageFinder.matches(of: "park", in: single)
        NotePageFinder.replace([first[1]], with: "strolls past", in: &single)
        expect(single.block(ids[0])?.text.string == "Park strolls pasts PARK at the park.", "replace swaps only the current match")
        let after = NotePageFinder.positionAfterReplacing(first[1], with: "strolls past")
        let next = NotePageFinder.matches(of: "park", in: single)
        let index = NotePageFinder.firstIndex(atOrAfter: after, in: next, page: single)
        expect(index.map { next[$0].position.offset } == 19 && index.map { next[$0].block } == ids[0],
               "the next match after a replace is the following PARK")

        var grow = NotePage(blocks: [.paragraph("a a a")])
        let growMatches = NotePageFinder.matches(of: "a", in: grow)
        NotePageFinder.replace([growMatches[0]], with: "aa", in: &grow)
        let growAfter = NotePageFinder.positionAfterReplacing(growMatches[0], with: "aa")
        let regrown = NotePageFinder.matches(of: "a", in: grow)
        let growIndex = NotePageFinder.firstIndex(atOrAfter: growAfter, in: regrown, page: grow)
        expect(grow.blocks[0].text.string == "aa a a" && growIndex.map { regrown[$0].position.offset } == 3,
               "a replacement containing the query never loops back onto itself")

        var stale = NotePage(blocks: [.paragraph("tiny")])
        let bogus = NoteFindMatch(stale.blocks[0].id, offset: 2, length: 10)
        expect(NotePageFinder.replace([bogus], with: "x", in: &stale).isEmpty && stale.blocks[0].text.string == "tiny",
               "a stale match past the end is ignored")
    }

    static func stats() {
        let empty = NotePageStats(page: NotePage(blocks: [.paragraph()]))
        expect(empty.words == 0 && empty.readingMinutes == 0 && empty.summary == "No words yet", "an empty page has nothing to read")
        let one = NotePageStats(page: NotePage(blocks: [.paragraph("Hello")]))
        expect(one.words == 1 && one.wordLabel == "1 word" && one.readingMinutes == 1 && one.summary == "1 word · 1 min read",
               "one word is a one-minute read")
        let (page, _) = samplePage()
        let sample = NotePageStats(page: page)
        expect(sample.words == 22, "words count body, cells, captions, code and mention titles (got \(sample.words))")
        let long = NotePage(blocks: [.paragraph(NoteText(Array(repeating: "word", count: 239).joined(separator: " ")))])
        let longStats = NotePageStats(page: long)
        expect(longStats.words == 239 && longStats.readingMinutes == 2, "239 words rounds up to two minutes")
        expect(NotePageStats(words: 1234, characters: 0).wordLabel.contains("234") && NotePageStats(words: 1234, characters: 0).wordLabel.hasSuffix(" words"),
               "big counts are grouped")
        let chars = NotePageStats(page: NotePage(blocks: [.paragraph("ab"), .paragraph("👋🏽")]))
        expect(chars.characters == 3, "characters count graphemes and skip line breaks (got \(chars.characters))")
    }

    static func properties() {
        expect(NotePropertyKind.allCases.map(\.displayName) == ["Text", "Number", "Checkbox", "Date", "List"], "five property kinds")
        for kind in NotePropertyKind.allCases {
            expect(kind.defaultValue.kind == kind, "\(kind) default has the right kind")
        }
        var list: [NotePageProperty] = []
        list = NotePropertyEditing.adding(.list, to: list)
        list = NotePropertyEditing.adding(.list, to: list)
        list = NotePropertyEditing.adding(.date, to: list)
        expect(list.map(\.key) == ["Tags", "Tags 2", "Date"], "new properties get unique names")
        expect(NotePropertyEditing.renaming(list, at: 1, to: "tags") == nil, "renames can't collide, ignoring case")
        expect(NotePropertyEditing.renaming(list, at: 1, to: "  ") == nil, "renames can't be blank")
        expect(NotePropertyEditing.renaming(list, at: 1, to: "Icon") == nil, "renames can't take a page setting's key")
        expect(NotePropertyEditing.renaming(list, at: 1, to: "a: b") == nil, "renames can't hold a colon")
        expect(NotePropertyEditing.renaming(list, at: 1, to: " Mood ")?[1].key == "Mood", "renames trim")
        expect(NotePropertyEditing.renaming(list, at: 0, to: "Tags") == list, "renaming to itself changes nothing")
        expect(NotePropertyEditing.uniqueKey("icon", among: []) == "icon 2", "a reserved base name gets a number")
        let moved = NotePropertyEditing.moving(list, from: 2, to: 0)
        expect(moved.map(\.key) == ["Date", "Tags", "Tags 2"], "drag reorder moves a row")
        expect(NotePropertyEditing.removing(moved, at: 1).map(\.key) == ["Date", "Tags 2"], "delete removes a row")
        expect(NotePropertyEditing.changingKind(list, at: 0, to: .text)[0].value == .text(""), "an empty list becomes empty text")

        expect(NotePropertyValue.text("42").converted(to: .number) == .number(42), "text turns into a number")
        expect(NotePropertyValue.text("1,250.5").converted(to: .number) == .number(1250.5), "grouped numbers parse")
        expect(NotePropertyValue.text("soon").converted(to: .number) == .number(0), "nonsense numbers fall back to zero")
        expect(NotePropertyValue.number(3).converted(to: .text) == .text("3"), "whole numbers print without decimals")
        expect(NotePropertyValue.number(2.5).converted(to: .text) == .text("2.5"), "fractions keep their digits")
        expect(NotePropertyValue.text("yes").converted(to: .checkbox) == .checkbox(true), "yes checks the box")
        expect(NotePropertyValue.checkbox(true).converted(to: .text) == .text("Yes"), "a checked box reads Yes")
        expect(NotePropertyValue.checkbox(false).converted(to: .text) == .text(""), "an unchecked box reads empty")
        expect(NotePropertyValue.text("a, b, a, ,c").converted(to: .list) == .list(["a", "b", "c"]), "text splits into unique tags")
        expect(NotePropertyValue.list(["a", "b"]).converted(to: .text) == .text("a, b"), "tags join back into text")
        expect(NotePropertyValue.text("2026-11-20").converted(to: .date) == .date("2026-11-20"), "an ISO date stays a date")
        expect(NotePropertyValue.text("tomorrow").converted(to: .date) == .date(""), "unparseable dates go empty")
        expect(NotePropertyValue.date("2026-02-30").converted(to: .checkbox) == .checkbox(true), "a filled date checks the box")
        expect(NotePropertyEditing.date(from: "2026-02-30") == nil, "February 30th isn't a date")
        let date = NotePropertyEditing.date(from: "2024-02-29")
        expect(date != nil && NotePropertyEditing.dateString(from: date!) == "2024-02-29", "dates round-trip through strings")
        expect(NotePropertyValue.date("2024-02-29").displayText.contains("2024"), "dates display with their year")
        expect(NotePropertyEditing.addingTag(" Fun ", to: ["fun"]) == ["fun"], "duplicate tags are skipped")
        expect(NotePropertyEditing.addingTag("a,b", to: []) == ["a b"], "commas can't sneak into a tag")
        expect(NotePropertyValue.list([]).isEmpty && !NotePropertyValue.number(0).isEmpty, "emptiness depends on the kind")
    }

    static func history() {
        let policy = NotePageHistoryPolicy()
        let start = Date(timeIntervalSince1970: 1_000_000)
        expect(policy.shouldRecord(.save, current: "a", lastRecorded: nil, lastRecordedAt: nil, now: start), "the first save is always worth keeping")
        expect(!policy.shouldRecord(.close, current: "a\n", lastRecorded: "a", lastRecordedAt: start, now: start),
               "trailing whitespace alone isn't a new version")
        expect(!policy.shouldRecord(.save, current: "ab", lastRecorded: "a", lastRecordedAt: start, now: start.addingTimeInterval(60)),
               "saves within a few minutes wait")
        expect(policy.shouldRecord(.save, current: "ab", lastRecorded: "a", lastRecordedAt: start, now: start.addingTimeInterval(301)),
               "a save after five minutes records")
        expect(policy.shouldRecord(.idle, current: "ab", lastRecorded: "a", lastRecordedAt: start, now: start.addingTimeInterval(10)),
               "going idle records right away")
        expect(policy.shouldRecord(.close, current: "ab", lastRecorded: "a", lastRecordedAt: start, now: start),
               "closing records any real change")
        expect(!policy.shouldRecord(.idle, current: "a", lastRecorded: "a", lastRecordedAt: start, now: start.addingTimeInterval(999)),
               "an unchanged page never records")
    }

    static func exporting() {
        expect(NotePageExport.markdownForCopy(body: "Hello\n\n", title: " Trip ") == "# Trip\n\nHello\n", "copied Markdown leads with the title")
        expect(NotePageExport.markdownForCopy(body: "Hello", title: "") == "Hello\n", "an untitled page copies just the body")
        expect(NotePageExport.markdownForCopy(body: "\n", title: "Empty") == "# Empty\n", "an empty body copies just the title")
        var settings = NotePageSettings()
        settings.cover = NoteCover(source: "Attachments/cover.jpg")
        settings.icon = "Attachments/icon.png"
        var image = NoteBlockProps(); image.source = "Attachments/photo%20one.png"
        var remote = NoteBlockProps(); remote.source = "https://example.com/a.png"
        var absolute = NoteBlockProps(); absolute.source = "/Users/somebody/b.png"
        var sneaky = NoteBlockProps(); sneaky.source = "../outside/c.png"
        var again = NoteBlockProps(); again.source = "Attachments/cover.jpg"
        let item = NoteBlock(.bulletedItem, text: "x", children: [NoteBlock(.image, props: image)])
        let page = NotePage(settings: settings, blocks: [item, NoteBlock(.image, props: remote), NoteBlock(.file, props: absolute),
                                                         NoteBlock(.video, props: sneaky), NoteBlock(.image, props: again)])
        expect(NotePageExport.relativeAssetSources(in: page) == ["Attachments/cover.jpg", "Attachments/icon.png", "Attachments/photo%20one.png"],
               "exports copy the cover, image icon and nested media, skipping links, absolute paths, escapes and repeats")
        var emojiSettings = NotePageSettings(); emojiSettings.icon = "🌳"
        expect(NotePageExport.relativeAssetSources(in: NotePage(settings: emojiSettings)).isEmpty, "an emoji icon isn't a file")
        let source = URL(fileURLWithPath: "/tmp/notes/Draft.txt")
        let taken: Set<String> = ["/tmp/notes/Draft.md", "/tmp/notes/Draft 2.md"]
        expect(NotePageExport.markdownCopyURL(for: source) { taken.contains($0.path) }.path == "/tmp/notes/Draft 3.md",
               "a Markdown copy never overwrites a neighbour")
        expect(NotePageExport.markdownCopyURL(for: source) { _ in false }.path == "/tmp/notes/Draft.md", "the copy keeps the name when it can")
        expect(NotePageExport.validatedLink(" https://example.com/cover.jpg ")?.host == "example.com", "image links trim and validate")
        expect(NotePageExport.validatedLink("ftp://example.com/a.png") == nil, "only web links count")
        expect(NotePageExport.validatedLink("https://nodot") == nil, "a host needs a dot")
        expect(NotePageExport.validatedLink("not a link") == nil, "words aren't links")
        expect(NotePageExport.flattenedTitle("One\ntwo\r\nthree\tfour") == "One two three four", "pasted titles flatten to one line")
        expect(NotePageExport.isImageSource("Attachments/a.HEIC") && !NotePageExport.isImageSource("🌳"), "image icons are told apart from emoji")
    }

    static func relativeTime() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        expect(NoteRelativeTime.edited(now.addingTimeInterval(-10), now: now) == "Edited just now", "seconds ago is just now")
        expect(NoteRelativeTime.edited(nil, now: now) == "Not saved yet", "no date means not saved")
        let minutes = NoteRelativeTime.edited(now.addingTimeInterval(-180), now: now)
        expect(minutes.hasPrefix("Edited ") && minutes.contains("3"), "minutes read as a relative phrase (got \(minutes))")
    }
}
