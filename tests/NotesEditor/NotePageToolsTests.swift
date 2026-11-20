import Foundation

@main @MainActor
struct NotePageToolsTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        finding()
        replacing()
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
