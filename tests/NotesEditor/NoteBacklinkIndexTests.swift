import Combine
import Foundation

@main @MainActor
struct NoteBacklinkIndexTests {
    static let clock = ManualNoteClock()
    static var folder: URL!

    static func main() {
        exitOnFailure {
            NoteFileSession.clock = clock
            NoteFileSession.worker = .inline
            NoteLibrary.clock = clock
            NoteLibrary.worker = .inline
            NoteBacklinkIndex.clock = clock
            NoteBacklinkIndex.worker = .inline
            folder = NoteFileTestSupport.makeFolder("backlinks")
            defer { NoteFileTestSupport.remove(folder) }
            snippets()
            frontMatter()
            scanning()
            rewriting()
            headerGeometry()
            try indexing()
            print("NoteBacklinkIndexTests passed")
        }
    }

    static func snippets() {
        let plain = "We talked for ages about the weather and the rain before finally getting to the Roadmap which matters most, then lunch."
        let range = (plain as NSString).range(of: "Roadmap")
        let snippet = NoteBacklinkSnippet.around(range.location..<(range.location + range.length), in: plain)
        expect(snippet.text.hasPrefix("…"), "long lead-ins are clipped with an ellipsis")
        guard let highlight = snippet.highlight else { failTest("the link is highlighted") }
        expectEqual((snippet.text as NSString).substring(with: NSRange(location: highlight.lowerBound, length: highlight.count)), "Roadmap",
                    "the highlight covers the link text")
        expect(!snippet.text.contains("  "), "whitespace is collapsed")
        let short = NoteBacklinkSnippet.around(0..<3, in: "See\nthat")
        expectEqual(short.text, "See that", "line breaks read as spaces")
        expectEqual(short.highlight, 0..<3, "short snippets keep the link at the start")
        expectEqual(NoteBacklinkSnippet.around(0..<0, in: "").text, "", "empty text gives an empty snippet")
    }

    static func frontMatter() {
        for display in [NoteBacklinksDisplay.expanded, .off, .popup] {
            var page = NotePage(blocks: [.paragraph("Hi")])
            page.settings.backlinks = display
            let text = NoteMarkdown.serialize(page)
            expect(text.contains("backlinks: \(display.rawValue)"), "\(display) is written to front matter")
            expectEqual(NoteMarkdown.parse(text).settings.backlinks, display, "\(display) reads back")
        }
        var page = NotePage(blocks: [.paragraph("Hi")])
        page.settings.backlinksDisplay = .popup
        expectEqual(page.settings.backlinks, nil, "picking the default leaves front matter alone")
        expect(!NoteMarkdown.serialize(page).contains("backlinks"), "the default writes nothing")
        let odd = NoteMarkdown.parse("---\nbacklinks: sometimes\n---\nHi\n")
        expectEqual(odd.settings.backlinks, nil, "unknown values aren't a setting")
        expectEqual(odd.settings.properties.first?.key, "backlinks", "unknown values survive as a property")
    }

    static func scanning() {
        let base = folder.appendingPathComponent("Scan", isDirectory: true)
        let roadmap = NoteFileTestSupport.write("# Roadmap\n", to: base.appendingPathComponent("Roadmap.md"))
        let key = NoteFilePaths.key(for: roadmap)
        let page = NoteMarkdown.parse("""
        # Plans

        Read the [[Roadmap]] first.

        A [plain link](Roadmap.md#goals) and a mention [Roadmap](Roadmap.md).

        [The big plan](Roadmap.md)

        ```
        [ignored](Roadmap.md)
        ```

        Elsewhere [web](https://example.com) and [[Missing]].
        """)
        let links = NoteBacklinkScanner.outgoing(in: page, folder: base)
        let local = links.filter { $0.target == key }
        expectEqual(local.count, 4, "wiki links, link marks, mentions and page links all count, code doesn't")
        expectEqual(Set(local.map(\.kind)), [.mention, .link, .pageLink], "each kind is recognised")
        expect(local.allSatisfy { $0.anchor == "plans" }, "links remember the section they sit in")
        expect(local.contains { $0.kind == .pageLink && $0.snippet.text == "The big plan" }, "page links use their label")
        expect(local.contains { $0.snippet.text == "Read the Roadmap first." && $0.snippet.highlight == 9..<16 },
               "mentions show their sentence")
        expect(!links.contains { $0.target.hasSuffix("example.com") }, "web links are skipped")
        expectEqual(NoteBacklinkScanner.targetKey("Roadmap", from: base), key, "wiki targets find the .md file")
        expectEqual(NoteBacklinkScanner.targetKey("./Roadmap.md#x", from: base), key, "fragments are ignored")
        expectEqual(NoteBacklinkScanner.targetKey(roadmap.absoluteString, from: folder), key, "file URLs resolve")
        expectEqual(NoteBacklinkScanner.targetKey("#heading", from: base), nil, "same-page anchors aren't backlinks")
        expectEqual(NoteBacklinkScanner.targetKey("mailto:a@b.c", from: base), nil, "other schemes are skipped")
    }

    static func rewriting() {
        let base = folder.appendingPathComponent("Rewrite", isDirectory: true)
        let old = base.appendingPathComponent("Roadmap.md")
        let new = base.appendingPathComponent("Big Plan.md")
        NoteFileTestSupport.write("x\n", to: new)
        let move = NoteBacklinkMove(fromKey: NoteFilePaths.key(for: old), from: old, to: new)
        let source = """
        ---
        icon: 🍎
        ---
        Read the [[Roadmap]] and [[Roadmap|the map]] first.

        A [plain link](Roadmap.md#goals) and a mention [Roadmap](Roadmap.md), plus _style_ kept.

        [Roadmap](Roadmap.md)

        `[code](Roadmap.md)` and [other](Other.md).

        """
        guard let output = NoteBacklinkRewriter.rewritten(source, resolvingFrom: base, writingFrom: base, move: move) else {
            failTest("links to the moved note are rewritten")
        }
        expect(output.contains("[[Big Plan]]"), "bare wiki links follow and keep their form: \(output)")
        expect(output.contains("[[Big Plan|the map]]"), "aliases stay")
        expect(output.contains("[plain link](Big%20Plan.md#goals)"), "link marks keep their text and fragment")
        expect(output.contains("[Big Plan](Big%20Plan.md), plus _style_ kept."), "mentions take the new name and other text is untouched")
        expect(output.contains("\n[Big Plan](Big%20Plan.md)\n"), "page links follow")
        expect(output.contains("`[code](Roadmap.md)`"), "code is left alone")
        expect(output.contains("[other](Other.md)"), "unrelated links stay")
        expect(output.hasPrefix("---\nicon: 🍎\n---\n"), "front matter stays byte for byte")
        expectEqual(NoteBacklinkRewriter.rewritten("No links here.\n", resolvingFrom: base, writingFrom: base, move: move), nil,
                    "notes without links aren't touched")
        let crlf = "See [[Roadmap]].\r\nNext line\r\n"
        expectEqual(NoteBacklinkRewriter.rewritten(crlf, resolvingFrom: base, writingFrom: base, move: move), "See [[Big Plan]].\r\nNext line\r\n",
                    "line endings survive")

        var text = NoteText.atom(.page(target: "Roadmap.md", title: "Roadmap"))
        expect(NoteBacklinkRewriter.rewrite(&text, resolvingFrom: base, writingFrom: base, move: move), "atoms are rewritten in the model")
        expectEqual(text.marks(at: 0).atom, .page(target: "Big%20Plan.md", title: "Big Plan"), "mention atoms take the new target and title")
        let sub = base.appendingPathComponent("Sub", isDirectory: true)
        expectEqual(NoteBacklinkRewriter.replacement(for: "../Roadmap.md", writingFrom: sub, to: new, wiki: false), "../Big%20Plan.md",
                    "relative links stay relative to their note")
    }

    static func headerGeometry() {
        var geometry = NotePageHeaderGeometry(width: 1000, column: CGRect(x: 140, y: 0, width: 720, height: 0), titleHeight: 55)
        let bare = geometry.layout()
        expectEqual(bare.backlinks, nil, "no backlinks, no slot")
        geometry.backlinksHeight = 26
        geometry.backlinksGutter = 8
        let shown = geometry.layout()
        guard let frame = shown.backlinks else { failTest("backlinks get a slot") }
        expectEqual(frame, CGRect(x: 132, y: bare.title.maxY + NotePageHeaderGeometry.backlinksGap, width: 728, height: 26),
                    "the count sits under the title, hanging into the gutter")
        expectEqual(shown.height, bare.height + 26 + NotePageHeaderGeometry.backlinksGap, "the header grows to fit")
        geometry.propertiesHeight = 64
        let both = geometry.layout()
        expect((both.backlinks?.minY ?? 0) > (both.properties?.maxY ?? .infinity), "backlinks follow the properties")
    }

    static func indexing() throws {
        let root = folder.appendingPathComponent("Index", isDirectory: true)
        let target = NoteFileTestSupport.write("# Target\n", to: root.appendingPathComponent("Target.md"))
        let alpha = NoteFileTestSupport.write("See [[Target]] and [Target](Target.md).\n", to: root.appendingPathComponent("Alpha.md"))
        NoteFileTestSupport.write("---\nicon: 🐝\n---\n## Notes\n\nAbout [the target](../Target.md).\n",
                                  to: root.appendingPathComponent("Deep/Beta.md"))
        NoteFileTestSupport.write("Nothing to see.\n", to: root.appendingPathComponent("Gamma.md"))
        NoteFileTestSupport.write("[me](Target.md)\n", to: root.appendingPathComponent("Plain.txt"))
        NoteFileTestSupport.write("Self [[Target]]\n", to: target)
        let index = NoteBacklinkIndex.shared
        let library = NoteLibrary.shared(folder: root)
        var heard = 0
        let watch = index.changes.sink { heard += 1 }
        defer { watch.cancel() }
        index.include(library)
        settle()
        var found = index.backlinks(to: target)
        expectEqual(found.map(\.title), ["Alpha", "Beta"], "sources are listed by title, without the note itself or plain text")
        expectEqual(found.first?.links, 2, "several links from one note count once")
        expectEqual(found.last?.icon, "🐝", "sources carry their icon")
        expectEqual(found.last?.anchor, "notes", "sources open at the linking section")
        expectEqual(found.last?.destination.fragment, "notes", "the destination carries the anchor")
        expect(heard > 0, "the index announces changes")

        NoteFileTestSupport.write("Gone.\n", to: alpha)
        NoteLibrary.filesRewritten([alpha])
        settle()
        found = index.backlinks(to: target)
        expectEqual(found.map(\.title), ["Beta"], "removing a link updates the list")

        NoteFileTestSupport.write("Back to [[Target]].\n", to: alpha)
        NoteLibrary.filesRewritten([alpha])
        settle()
        expectEqual(index.backlinks(to: target).count, 2, "new links show up")

        let renamed = try NoteLibrary.rename(target, to: "Destination")
        expectEqual(index.backlinks(to: renamed).map(\.title), ["Alpha", "Beta"], "backlinks follow a renamed note right away")
        steadily(index, renamed, ["Alpha", "Beta"], "after a rename")
        expectEqual(NoteFileTestSupport.read(alpha), "Back to [[Destination]].\n", "links in other notes follow the rename")
        expect(NoteFileTestSupport.read(root.appendingPathComponent("Deep/Beta.md")).contains("[the target](../Destination.md)"),
               "relative links from other folders follow too")
        expect(NoteFileTestSupport.read(renamed).contains("[[Destination]]"), "a note's link to itself follows its new name")
        expectEqual(index.backlinks(to: target), [], "nothing points at the old name any more")

        let moved = root.appendingPathComponent("Moved/Final.md")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: renamed, to: moved)
        library.refresh()
        clock.advance(0.3)
        expectEqual(index.backlinks(to: moved).map(\.title), ["Alpha", "Beta"], "a Finder move of a closed note is recognised by file identity")
        expectEqual(index.backlinks(to: renamed), [], "the old place has no backlinks")
        steadily(index, moved, ["Alpha", "Beta"], "after a Finder move")
        expectEqual(NoteFileTestSupport.read(alpha), "Back to [[Moved/Final]].\n", "links in closed notes follow a Finder move")
        expect(NoteFileTestSupport.read(root.appendingPathComponent("Deep/Beta.md")).contains("[the target](../Moved/Final.md)"),
               "relative links follow a Finder move too")
        expect(NoteFileTestSupport.read(moved).contains("[[Final]]"), "the moved note's link to itself follows it into the new folder")

        let alphaTwo = root.appendingPathComponent("Alpha Two.md")
        try FileManager.default.moveItem(at: alpha, to: alphaTwo)
        library.refresh()
        clock.advance(0.3)
        expectEqual(index.backlinks(to: moved).map(\.title), ["Alpha Two", "Beta"], "a renamed source keeps its links and takes its new name at once")
        steadily(index, moved, ["Alpha Two", "Beta"], "after a source moves")

        NoteFileTestSupport.write("Copy of [[Moved/Final]].\n", to: root.appendingPathComponent("Copy.md"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Gamma.md"))
        library.refresh()
        settle()
        expectEqual(index.backlinks(to: moved).map(\.title), ["Alpha Two", "Beta", "Copy"], "a deleted note and a new one aren't mistaken for a move")
        expectEqual(NoteFileTestSupport.read(alphaTwo), "Back to [[Moved/Final]].\n", "unrelated arrivals rewrite nothing")
    }

    static func steadily(_ index: NoteBacklinkIndex, _ note: URL, _ titles: [String], _ context: String) {
        for step in 0..<80 {
            clock.advance(0.1)
            let now = index.backlinks(to: note).map(\.title)
            if now != titles { failTest("the count dipped \(context) at step \(step): \(now)") }
        }
        expect(index.isSettled, "the index settles \(context)")
    }

    static func settle() {
        for _ in 0..<20 { clock.advance(0.5) }
    }
}
