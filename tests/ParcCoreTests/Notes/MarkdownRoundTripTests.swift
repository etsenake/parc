import Foundation
import Testing
@testable import ParcCore

struct MarkdownRoundTripTests {
    func anchored(_ blocks: [NoteBlock], _ random: inout MarkdownRandom) -> [NoteBlock] {
        blocks.map { original in
            var block = original
            if block.kind != .html, block.kind != .raw, block.kind != .column, random.chance(20) {
                block.props.anchor = random.pick(["k3x9qa", "intro", "step-2", "a_b", "Z9"]) + String(random.int(0...99))
                if block.kind == .code, block.props.fence == "    " { block.props.fence = nil }
            }
            block.children = anchored(block.children, &random)
            return block
        }
    }

    let sourcePieces = ["# ", "## ", "> ", "- ", "* ", "+ ", "1. ", "2) ", "- [ ] ", "- [x] ", "    ", "  ", "\t", "```", "~~~", "---", "***", "===",
                               "| a | b |", "| --- | :-: |", "<div>", "</div>", "<!-- c -->", "<details>", "<summary>S</summary>", "</details>",
                               ":::: columns", "::: column", ":::", "::: indent", ":::: indent", "$$", "$x$", "$5", "**", "*", "_", "__", "~~", "==", "`", "[", "]", "(", ")",
                               "[a](b)", "![i](p.png)", "[[W]]", "<u>", "</u>", "<span data-color=\"red\">", "</span>", "<b>", "&amp;", "&#32;",
                               "\\", "\\*", "text", "more words", "https://x.y/z", "www.a.bc", "m@x.io", "[^1]", "[^1]: note", "[r]: /url",
                               "> [!NOTE]", "> [!tip]- T", "<!-- parc color=\"red\" -->", "<!-- toc -->", "<time datetime=\"2026-01-02\">d</time>",
                               "<summary>B <!-- parc button --></summary>", "<!-- parc insert=\"top\" -->", "<!-- parc confirm=\"Sure?\" -->"]

    let readme = """
    <p align="center">
      <img src="docs/logo.svg" width="120" alt="Parc logo">
    </p>

    # Parc

    [![Build](https://github.com/example/parc/actions/workflows/ci.yml/badge.svg)](https://github.com/example/parc/actions) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

    A calm browser for people who keep too many tabs open. Parc puts your tabs in a
    sidebar, sorts them into Spaces and lets old ones quietly archive themselves.

    > [!IMPORTANT]
    > Parc needs macOS 15 or later.

    ## Install

    ```sh
    brew install --cask parc
    ```

    Or grab the latest `.dmg` from the [releases page](https://github.com/example/parc/releases).

    ## Features

    - **Spaces** for work, home and side projects
    - Split view with up to *four* pages
    - A command bar (`⌘T`) that searches tabs, history and bookmarks
      - Fuzzy matching
      - Recent first
    - Notes stored as plain Markdown files

    ## Building from source

    1. Install Xcode 17.
    2. Clone the repository:

       ```sh
       git clone https://github.com/example/parc.git
       ```

    3. Run `scripts/build.sh` and wait. It's a big engine.

    | Script                | What it does            |
    | :-------------------- | :---------------------- |
    | `scripts/build.sh`    | Builds the app          |
    | `scripts/test.sh`     | Runs every test         |
    | `scripts/release.sh`  | Signs and notarizes     |

    <details>
    <summary>Troubleshooting</summary>

    If the build stalls, delete `build/` and try again. Still stuck? Open an
    [issue][issues].

    </details>

    ## License

    MIT © 2026 The Parc authors. See [LICENSE](LICENSE).

    [issues]: https://github.com/example/parc/issues

    """

    let changelog = """
    # Changelog

    All notable changes to this project are documented here. The format follows
    [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
    [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

    ## [Unreleased]

    ### Added

    - Notes are now plain Markdown files you can open anywhere.
    - Drag a tab onto a note to drop in a bookmark.

    ## [2.11.0] - 2026-11-18

    ### Fixed

    - The sidebar no longer flickers when you switch Spaces (#1234).
    - Downloads keep their names when the server sends `Content-Disposition`.

    ### Changed

    - Bumped the engine to Chromium 157.

    ## [2.10.2] - 2026-10-30

    ### Security

    - Patched a crash in the PDF viewer. Thanks to @sec-researcher for the report.

    [Unreleased]: https://github.com/example/parc/compare/v2.11.0...HEAD
    [2.11.0]: https://github.com/example/parc/compare/v2.10.2...v2.11.0
    [2.10.2]: https://github.com/example/parc/releases/tag/v2.10.2

    """

    let meeting = """
    ---
    icon: 🗓️
    tags:
      - meetings
      - design
    attendees:
      - Ada
      - Grace
      - Linus
    date: 2026-11-20
    ---

    ## Design sync

    Present: [[Ada Lovelace]], [[Grace Hopper|Grace]] and Linus.

    ### Agenda

    1. Review the new toolbar
    2. Decide on the ==default font==
    3. Anything else

    ### Notes

    - Toolbar feels *much* lighter. Keep the springy hover.
    - Font: go with **Nunito** for body text, ~~Helvetica~~ is out.
    - Check contrast on dark Spaces <!-- parc color="orange" -->

    > [!TIP]
    > Record the next one so Linus can catch up.

    ### Action items

    - [ ] Ada: ship the toolbar behind a flag by <time datetime="2026-11-27">2026-11-27</time>
    - [x] Grace: share the font specimens
    - [ ] Linus: write up [the contrast rules](Design/Contrast.md)

    ---

    Next meeting: <time datetime="2026-11-27T10:00" data-remind>2026-11-27 10:00</time>

    """

    let obsidian = """
    ---
    aliases:
      - Zettel 42
    created: 2026-11-19T21:14
    rating: 4
    ---

    # On writing things down

    Writing is thinking made visible. See also [[Zettelkasten]] and [[Reading list#Books|my books]].

    > [!quote] Seneca
    > While we are postponing, life speeds by.

    > [!info]- Collapsed by default
    > Hidden details live here.
    >
    > - Even lists

    The energy of a photon is $E = h\\nu$, and in general

    $$
    E^2 = (pc)^2 + (mc^2)^2
    $$

    A thought with a footnote.[^seneca]

    ![[diagram.png]]

    [^seneca]: *Letters from a Stoic*, letter 1.

    """

    let docs = """
    # Configuration

    Parc reads its settings from `~/Library/Application Support/Parc/settings.json`.
    Most people never need to touch it.

    > [!WARNING]
    > Editing this file while Parc is running can lose your changes.

    ## Keys

    | Key | Type | Default |
    | --- | --- | --- |
    | `archiveAfter` | number | `12` |
    | `theme` | string | `"system"` |

    ### `archiveAfter`

    Hours before an idle tab archives itself. Set it to `0` to turn archiving off.

    ```json
    {
      "archiveAfter": 24
    }
    ```

    <details>
    <summary>Why hours, not days?</summary>

    Because a day is a long time on the internet.

    </details>

    :::: columns
    ::: column
    **Before**

    Tabs everywhere.
    :::
    ::: column
    **After**

    Calm.
    :::
    ::::

    """

    func checkRandomPages(seeds: Range<Int>) {
        var failures = 0
        for seed in seeds {
            var generator = MarkdownPageGenerator(random: MarkdownRandom(state: UInt64(seed) &* 2654435761 &+ 17))
            var page = NotePage(blocks: generator.blocks(depth: 0, count: generator.random.int(1...8), trailingEmpty: true))
            var anchors = MarkdownRandom(state: UInt64(seed) &* 40503 &+ 99)
            if anchors.chance(40) { page.blocks = anchored(page.blocks, &anchors) }
            if generator.random.chance(30) {
                page.settings.icon = generator.random.pick(["🍎", "Attachments/icon.png", "true", "- dash"])
                if generator.random.chance(50) { page.settings.cover = NoteCover(source: "cover.jpg", position: generator.random.chance(50) ? 0.5 : 0.125) }
                page.settings.font = generator.random.pick(NotePageFont.allCases)
                page.settings.smallText = generator.random.chance(30)
                page.settings.fullWidth = generator.random.chance(30)
                page.settings.locked = generator.random.chance(30)
                page.settings.properties = [NotePageProperty(key: "title", value: .text(generator.plainString(maxWords: 3))),
                                            NotePageProperty(key: "tags", value: .list(["a", generator.plainString(maxWords: 2)]))]
            }
            if !NoteMarkdownCheck.checkModelRoundTrip(page, "seed \(seed)") {
                failures += 1
                if failures >= 3 { return }
            }
        }
    }

    static let pageBatches = Array(stride(from: 0, to: 2000, by: 100))

    @Test(arguments: MarkdownRoundTripTests.pageBatches)
    func randomPagesSurviveAMarkdownRoundTrip(firstSeed: Int) { checkRandomPages(seeds: firstSeed..<(firstSeed + 100)) }

    func generateSource(_ random: inout MarkdownRandom) -> String {
        var lines: [String] = []
        for _ in 0..<random.int(1...12) {
            var line = ""
            for _ in 0..<random.int(0...5) { line += random.pick(sourcePieces) + (random.chance(60) ? " " : "") }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func checkRandomSources(indices: Range<Int>) {
        var random = MarkdownRandom(state: 99)
        for _ in 0..<indices.lowerBound { _ = generateSource(&random) }
        var failures = 0
        for index in indices {
            let source = generateSource(&random)
            if !NoteMarkdownCheck.checkStable(source, "source \(index)") {
                failures += 1
                if failures >= 3 { return }
            }
        }
    }

    static let sourceBatches = Array(stride(from: 0, to: 1500, by: 125))

    @Test(arguments: MarkdownRoundTripTests.sourceBatches)
    func randomSourcesSettleAfterOneSave(firstIndex: Int) { checkRandomSources(indices: firstIndex..<(firstIndex + 125)) }

    var samples: [String: String] {
        ["readme": readme, "changelog": changelog, "meeting": meeting, "obsidian": obsidian, "docs": docs]
    }

    @Test(arguments: ["readme", "changelog", "meeting", "obsidian", "docs"])
    func aRealWorldNoteIsStableAfterOneSave(label: String) throws {
        let sample = try #require(samples[label])
        #expect(NoteMarkdownCheck.checkStable(sample, label))
    }

    @Test(arguments: ["readme", "changelog", "meeting", "obsidian", "docs"])
    func aRealWorldNoteModelSurvivesARoundTrip(label: String) throws {
        let sample = try #require(samples[label])
        #expect(NoteMarkdownCheck.checkModelRoundTrip(NoteMarkdown.parse(sample), label))
    }

    @Test(arguments: ["changelog", "meeting", "obsidian"])
    func aRealWorldNoteSavesBackExactly(label: String) throws {
        let sample = try #require(samples[label])
        #expect(NoteMarkdownCheck.checkExact(sample, label + " exact"))
    }

    @Test func aReadmeLoadsItsHtmlCalloutToggleAndTable() {
        let page = NoteMarkdown.parse(readme)
        #expect(page.blocks.first?.kind == .html)
        #expect(page.blocks.contains { $0.kind == .callout && $0.props.alert == "IMPORTANT" })
        #expect(page.blocks.contains { $0.kind == .toggle })
        #expect(page.blocks.contains { $0.kind == .table })
    }

    @Test func aMeetingNoteLoadsItsIconAndThreeTodos() {
        let page = NoteMarkdown.parse(meeting)
        #expect(page.settings.icon == "🗓️")
        #expect(page.blocks.filter { $0.kind == .todo }.count == 3)
    }

    @Test func aBigDocumentParsesAndSaves() {
        var document = ""
        while document.split(separator: "\n", omittingEmptySubsequences: false).count < 5000 {
            document += readme + "\n" + changelog + "\n" + docs + "\n"
        }
        let page = NoteMarkdown.parse(document)
        #expect(!NoteMarkdown.serialize(page).isEmpty)
        #expect(page.blocks.count > 500)
    }


    struct MarkdownRandom {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            var value = state
            value ^= value >> 33
            value = value &* 0xff51afd7ed558ccd
            value ^= value >> 33
            return value
        }

        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }

        mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }

        mutating func pick<T>(_ values: [T]) -> T { values[int(0...(values.count - 1))] }
    }

    struct MarkdownPageGenerator {
        var random: MarkdownRandom
        var allowBreaks = true

        static let words = ["alpha", "beta", "note", "Parc", "file", "a", "1.", "2)", "#", "##", "-", "+", "*", "**", "_", "__", "~", "~~", "==", "`", "``",
                            "[", "]", "[x]", "](", "![", "<", ">", "<b>", "</b>", "<div>", "&", "&amp;", "&#32;", "$", "$5", "$x$", "\\", "|", ":::", "---",
                            "===", "```", "http://x.y", "www.a.bc", "me@x.io", "[[w]]", "[^1]", "!", "@", "{", "}", "(", ")", "\"", "'", "ü", "🎉", "中文",
                            "snake_case", "C#", "2*3", "x_y", ".", ",", ";", "?", "%", "^", "=", "<!--", "-->", "&copy;", "   ", "\t"]

        mutating func plainString(maxWords: Int = 6) -> String {
            var parts: [String] = []
            for _ in 0..<random.int(1...maxWords) { parts.append(random.pick(Self.words)) }
            return parts.joined(separator: random.chance(80) ? " " : "")
        }

        mutating func marks() -> NoteMarks {
            var marks = NoteMarks()
            if random.chance(20) { marks.bold = true }
            if random.chance(20) { marks.italic = true }
            if random.chance(10) { marks.underline = true }
            if random.chance(10) { marks.strikethrough = true }
            if random.chance(10) { marks.code = true }
            if random.chance(10) { marks.link = random.pick(["https://example.com/a", "Other.md", "https://x.org/(p)", "../up dir/n.md", "mailto:a@b.co", "#anchor"]) }
            if random.chance(10) {
                marks.color = random.chance(50) ? .text(random.pick(NoteColor.allCases)) : .background(random.pick(NoteColor.allCases))
            }
            return marks
        }

        mutating func atom() -> NoteAtom {
            switch random.int(0...4) {
            case 0: return .equation(random.pick(["x^2", "a_1 + b", "\\frac{1}{2}", "e^{i\\pi}", "$ odd", "trail ", "5"]))
            case 1:
                if random.chance(50) { return .page(target: "Folder/My Note.md", title: "My Note") }
                return .page(target: random.pick(["Ideas", "Daily/2026-11-20"]), title: random.pick(["Ideas", "Today", "A | B"]))
            case 2:
                var date = NoteDateMention(year: 2026, month: random.int(1...12), day: random.int(1...28), hour: random.chance(50) ? random.int(0...23) : nil,
                                           minute: nil, remind: random.chance(30)).withMinute(random.chance(50))
                if random.chance(30) {
                    date.end = NoteDateEnd(year: 2026, month: date.month, day: min(28, date.day + random.int(0...3)), hour: date.hour.map { min(23, $0 + 1) },
                                           minute: date.minute)
                }
                if date.remind, random.chance(50) { date.remindBefore = random.pick([5, 30, 60, 90, 1440, 10080]) }
                if date.hour != nil, random.chance(25) { date.timeZone = random.pick(["Europe/Paris", "America/New_York", "Asia/Kolkata"]) }
                if random.chance(20) { date.format = random.pick(NoteDateFormat.allCases) }
                if random.chance(20) { date.timeFormat = random.pick(NoteTimeFormat.allCases) }
                return .date(date)
            case 3: return .link(url: random.pick(["https://example.com", "https://a.b/c?d=e&f=g"]), title: plainString(maxWords: 3))
            default: return .raw(random.pick(["<kbd>", "</kbd>", "![img](pic.png)", "<sup>", "<wbr>"]))
            }
        }

        mutating func text(maxPieces: Int = 5, breaks: Bool = true) -> NoteText {
            var text = NoteText()
            for _ in 0..<random.int(1...maxPieces) {
                if random.chance(12) {
                    text.append(.atom(atom(), marks: random.chance(30) ? marks().withoutCode : .plain))
                } else if breaks, allowBreaks, random.chance(10) {
                    text.append(NoteText(random.chance(50) ? "\n" : "\u{2028}", marks: random.chance(20) ? marks().withoutCode : .plain))
                } else {
                    text.append(NoteText(plainString(), marks: random.chance(45) ? marks() : .plain))
                }
            }
            return text
        }

        mutating func leaf(depth: Int) -> NoteBlock {
            var block: NoteBlock
            switch random.int(0...16) {
            case 0, 1, 2:
                block = .paragraph(random.chance(8) ? NoteText() : text())
            case 3:
                block = .heading(random.int(1...6), random.chance(5) ? NoteText() : text(breaks: false))
                if block.props.level <= 2, !block.text.isEmpty, random.chance(40) { block.props.fence = block.props.level == 1 ? "=" : "-" }
            case 4:
                block = NoteBlock(.code, text: NoteText(random.pick(["let x = 1", "```\nfence inside\n```", "", "a\n\nb", "~~~", "  indented\n\tmore", "tail\n"])))
                block.props.language = random.pick(["", "swift", "c++", "js"])
                if random.chance(20), !block.props.language.isEmpty { block.props.info = "title=\"a b\"" }
                block.props.fence = random.pick([nil, "~~~", "````", "    "])
                if block.props.fence == "    ", !block.props.language.isEmpty || block.props.info != nil || block.text.isEmpty || block.text.string.hasSuffix("\n") {
                    block.props.fence = nil
                }
                if let fence = block.props.fence, fence != "    " {
                    let written = NoteMDWriter.fence(for: block.text.string, preferred: fence, info: block.props.language)
                    block.props.fence = written == NoteMDWriter.fence(for: block.text.string, preferred: nil, info: block.props.language) ? nil : written
                }
                if random.chance(15) { block.props.wrap = true }
                if random.chance(15) { block.props.caption = text(breaks: false) }
            case 5:
                block = NoteBlock(.equation, text: NoteText(random.pick(["E = mc^2", "a\n$$\nb", "", "\\sum_{i=1}^n i", "x $$"])))
                if random.chance(20), !NoteMDWriter.equationNeedsFence(block.text.string) { block.props.fence = "````" }
            case 6:
                block = NoteBlock(.divider)
                block.props.fence = random.pick([nil, "***", "___", "* * *"])
            case 7:
                block = NoteBlock(random.pick([.image, .video, .audio, .file, .embed]))
                block.props.source = random.pick(["Attachments/pic.png", "clip.MOV", "https://youtu.be/x", "a b/c(d).pdf", "song.mp3", "https://cdn.x/y", ""])
                if random.chance(50) { block.props.alt = plainString(maxWords: 3) }
                if random.chance(40) { block.props.caption = text(breaks: false) }
                if random.chance(30) { block.props.width = Double(random.int(40...900)) + (random.chance(50) ? 0.5 : 0) }
                if random.chance(30) { block.props.alignment = random.pick([.left, .right]) }
            case 8:
                block = NoteBlock(.bookmark)
                block.props.source = random.pick(["https://example.com/post", "https://a.b/c d"])
                var bookmark = NoteBookmark()
                if random.chance(70) { bookmark.title = plainString(maxWords: 4) }
                if random.chance(50) { bookmark.summary = plainString(maxWords: 5) }
                if random.chance(30) { bookmark.siteName = "Site" }
                if random.chance(30) { bookmark.iconURL = "https://example.com/i.ico" }
                if random.chance(30) { bookmark.imageURL = "https://example.com/i.png" }
                block.props.bookmark = bookmark
                if random.chance(30) { block.props.caption = text(breaks: false) }
            case 9:
                block = NoteBlock(.pageLink, text: random.chance(10) ? NoteText() : text(maxPieces: 2, breaks: false))
                block.text.updateMarks(in: 0..<block.text.length) { $0.link = nil }
                block.props.target = random.pick(["Other.md", "Folder/Some%20Note.md", "../Up.markdown"])
            case 10:
                var table = NoteTable(rows: (0..<random.int(1...4)).map { _ in (0..<random.int(1...3)).map { _ in random.chance(15) ? NoteText() : text(maxPieces: 3) } })
                table.normalize()
                table.alignments = table.alignments.map { _ in random.pick([nil, .left, .center, .right]) }
                if random.chance(20) { table.headerRow = false }
                if random.chance(20) { table.headerColumn = true }
                if random.chance(20) { table.columnWidths = table.columnWidths.map { _ in random.chance(50) ? Double(random.int(60...300)) : nil } }
                block = NoteBlock(.table)
                block.props.table = table
            case 11:
                block = NoteBlock(.tableOfContents)
            case 12:
                block = NoteBlock(.html, text: NoteText(random.pick(["<div align=\"center\">\n  <img src=\"a.png\">\n</div>", "<!-- note to self -->", "<table>\n<tr><td>x</td></tr>\n</table>"])))
                return block
            case 13:
                block = NoteBlock(.raw, text: NoteText(random.pick(["[docs]: https://example.com/docs", "[^n]: A footnote.\n    Continued."])))
                return block
            case 14:
                block = .paragraph()
                return block
            default:
                block = .paragraph(text())
            }
            if random.chance(12) { block.color = random.chance(50) ? .text(random.pick(NoteColor.allCases)) : .background(random.pick(NoteColor.allCases)) }
            if block.kind == .code, block.props.fence == "    ", block.color != nil || block.props.wrap || !block.props.caption.isEmpty { block.props.fence = nil }
            if block.kind == .paragraph || block.kind == .heading, depth < 3, random.chance(20) {
                block.children = blocks(depth: depth + 1, count: random.int(1...3), trailingEmpty: true)
            }
            return block
        }

        mutating func button(depth: Int) -> NoteBlock {
            var actions: [NoteButtonAction] = []
            for _ in 0..<random.int(0...3) {
                switch random.int(0...3) {
                case 0, 1:
                    actions.append(.insert(placement: random.pick(NoteButtonPlacement.allCases),
                                           blocks: blocks(depth: depth + 1, count: random.int(0...3), trailingEmpty: true)))
                case 2:
                    actions.append(.confirm(message: random.chance(20) ? "" : plainString(maxWords: 4)))
                default:
                    actions.append(.open(target: random.pick(["https://example.com/a?b=c&d", "Other%20Note.md", "../Up.md", ""])))
                }
            }
            let icon: String? = random.chance(40) ? random.pick(["✅", "🚀", "📓"]) : nil
            var block = NoteBlock.button(name: NoteButton.normalizedName(plainString(maxWords: 4)), icon: icon, actions: actions)
            if random.chance(20) { block.props.expanded = true }
            if random.chance(15) { block.color = random.chance(50) ? .text(.blue) : .background(.yellow) }
            return block
        }

        mutating func container(depth: Int) -> NoteBlock {
            switch random.int(0...5) {
            case 0:
                var block = NoteBlock(.toggle, text: text(breaks: false), children: blocks(depth: depth + 1, count: random.int(0...3), trailingEmpty: true))
                block.props.expanded = random.chance(50)
                if random.chance(30) { block.kind = .heading; block.props.level = random.int(1...6); block.props.toggleable = true }
                if random.chance(15) { block.color = .background(.yellow) }
                return block
            case 1:
                var block = NoteBlock(.quote, text: random.chance(15) ? NoteText() : text(), children: blocks(depth: depth + 1, count: random.int(0...2), trailingEmpty: true))
                if random.chance(15) { block.color = .text(.purple) }
                return block
            case 2:
                var block = NoteBlock(.callout, children: blocks(depth: depth + 1, count: random.int(0...2), trailingEmpty: true))
                block.props.alert = random.pick([nil, "TIP", "WARNING", "faq", "Danger"])
                block.text = random.chance(15) ? NoteText() : text(breaks: block.props.alert == nil || block.props.alert == "TIP" || block.props.alert == "WARNING")
                if random.chance(70) { block.props.icon = random.pick(["💡", "⚠️", "📌", "Attachments/icon.png"]) }
                if random.chance(20) { block.props.toggleable = true; block.props.expanded = random.chance(50) }
                if random.chance(30) { block.color = .background(random.pick(NoteColor.allCases)) }
                return block
            case 3:
                var columns = NoteBlock(.columns)
                for _ in 0..<random.int(1...3) {
                    var column = NoteBlock(.column, children: blocks(depth: depth + 1, count: random.int(1...3), trailingEmpty: true))
                    if random.chance(40) { column.props.width = Double(random.int(1...99)) / Double(random.pick([100, 3, 7])) }
                    columns.children.append(column)
                }
                return columns
            case 4:
                return button(depth: depth)
            default:
                return leaf(depth: depth)
            }
        }

        mutating func listRun(depth: Int) -> [NoteBlock] {
            let kind: NoteBlockKind = random.pick([.bulletedItem, .numberedItem, .todo])
            let loose = random.chance(25)
            let bullet: String? = random.pick([nil, "*", "+"])
            let ordered = kind == .numberedItem || (kind == .todo && random.chance(20))
            let delimiter: String? = kind == .todo ? (ordered ? random.pick([".", ")"]) : nil) : kind == .numberedItem ? random.pick([nil, ")"]) : nil
            var run: [NoteBlock] = []
            let count = random.int(1...4)
            for index in 0..<count {
                var item = NoteBlock(kind, text: random.chance(10) ? NoteText() : text())
                item.props.looseList = loose && count > 1
                if !ordered { item.props.bulletMarker = bullet }
                item.props.orderedDelimiter = delimiter
                if kind == .todo { item.props.checked = random.chance(50) }
                if ordered, index == 0, random.chance(30) { item.props.listStart = random.int(2...40) }
                if random.chance(20) { item.color = .text(.red) }
                if depth < 3, random.chance(30) { item.children = blocks(depth: depth + 1, count: random.int(1...2), trailingEmpty: false) }
                run.append(item)
            }
            return run
        }

        mutating func blocks(depth: Int, count: Int, trailingEmpty: Bool) -> [NoteBlock] {
            var result: [NoteBlock] = []
            var lastListKey: String?
            for _ in 0..<count {
                if random.chance(30) {
                    let run = listRun(depth: depth)
                    let key = Self.listKey(run[0])
                    if key == lastListKey { result.append(.paragraph("separator")) }
                    result.append(contentsOf: run)
                    lastListKey = key
                } else {
                    result.append(depth < 3 && random.chance(30) ? container(depth: depth) : leaf(depth: depth))
                    lastListKey = nil
                }
            }
            if !trailingEmpty {
                while let last = result.last, last.kind == .paragraph, last.text.isEmpty, last.color == nil { result.removeLast() }
            }
            for index in result.indices where result[index].kind == .code && result[index].props.fence == "    " {
                if let previous = result[..<index].last(where: { !NoteMDWriter.isBareEmptyParagraph($0) }), previous.kind.isListItem || previous.kind == .raw {
                    result[index].props.fence = nil
                }
            }
            var lastNumber: Int?
            for index in result.indices {
                let block = result[index]
                let ordered = block.kind == .numberedItem || (block.kind == .todo && block.props.orderedDelimiter != nil)
                guard ordered else { lastNumber = nil; continue }
                let expected = (lastNumber ?? 0) + 1
                if result[index].props.listStart == expected { result[index].props.listStart = nil }
                lastNumber = result[index].props.listStart ?? expected
            }
            return result
        }

        static func listKey(_ block: NoteBlock) -> String {
            if block.kind == .numberedItem { return "o" + (block.props.orderedDelimiter ?? ".") }
            if block.kind == .todo, let delimiter = block.props.orderedDelimiter { return "o" + delimiter }
            return "b" + (block.props.bulletMarker ?? "-")
        }
    }
}

private extension NoteMarks {
    var withoutCode: NoteMarks {
        var value = self
        value.code = false
        return value
    }
}

private extension NoteDateMention {
    func withMinute(_ include: Bool) -> NoteDateMention {
        var value = self
        if hour != nil { value.minute = include ? 30 : 0 }
        return value
    }
}
