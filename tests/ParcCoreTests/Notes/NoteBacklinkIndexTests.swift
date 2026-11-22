import Combine
import Foundation
import Testing
@testable import ParcCore

struct NoteBacklinkSnippetTests {
    static let plain = "We talked for ages about the weather and the rain before finally getting to the Roadmap which matters most, then lunch."

    func roadmapSnippet() -> NoteBacklinkSnippet {
        let range = (Self.plain as NSString).range(of: "Roadmap")
        return NoteBacklinkSnippet.around(range.location..<(range.location + range.length), in: Self.plain)
    }

    @Test func longLeadInsAreClippedWithAnEllipsis() {
        #expect(roadmapSnippet().text.hasPrefix("…"))
    }

    @Test func theHighlightCoversTheLinkText() throws {
        let snippet = roadmapSnippet()
        let highlight = try #require(snippet.highlight)
        #expect((snippet.text as NSString).substring(with: NSRange(location: highlight.lowerBound, length: highlight.count)) == "Roadmap")
    }

    @Test func whitespaceIsCollapsed() {
        #expect(!roadmapSnippet().text.contains("  "))
    }

    @Test func lineBreaksReadAsSpacesAndShortSnippetsKeepTheLinkAtTheStart() {
        let short = NoteBacklinkSnippet.around(0..<3, in: "See\nthat")
        #expect(short.text == "See that")
        #expect(short.highlight == 0..<3)
    }

    @Test func emptyTextGivesAnEmptySnippet() {
        #expect(NoteBacklinkSnippet.around(0..<0, in: "").text == "")
    }
}

struct NoteBacklinksSettingTests {
    @Test(arguments: [NoteBacklinksDisplay.expanded, .off, .popup])
    func anExplicitDisplayIsWrittenToFrontMatterAndReadsBack(display: NoteBacklinksDisplay) {
        var page = NotePage(blocks: [.paragraph("Hi")])
        page.settings.backlinks = display
        let text = NoteMarkdown.serialize(page)
        #expect(text.contains("backlinks: \(display.rawValue)"))
        #expect(NoteMarkdown.parse(text).settings.backlinks == display)
    }

    @Test func pickingTheDefaultLeavesFrontMatterAlone() {
        var page = NotePage(blocks: [.paragraph("Hi")])
        page.settings.backlinksDisplay = .popup
        #expect(page.settings.backlinks == nil)
        #expect(!NoteMarkdown.serialize(page).contains("backlinks"))
    }

    @Test func unknownValuesSurviveAsAProperty() {
        let odd = NoteMarkdown.parse("---\nbacklinks: sometimes\n---\nHi\n")
        #expect(odd.settings.backlinks == nil)
        #expect(odd.settings.properties.first?.key == "backlinks")
    }

    @Test func noBacklinksMeansNoHeaderSlot() {
        let geometry = NotePageHeaderGeometry(width: 1000, column: CGRect(x: 140, y: 0, width: 720, height: 0), titleHeight: 55)
        #expect(geometry.layout().backlinks == nil)
    }

    @Test func theBacklinkCountSitsUnderTheTitleHangingIntoTheGutter() throws {
        var geometry = NotePageHeaderGeometry(width: 1000, column: CGRect(x: 140, y: 0, width: 720, height: 0), titleHeight: 55)
        let bare = geometry.layout()
        geometry.backlinksHeight = 26
        geometry.backlinksGutter = 8
        let shown = geometry.layout()
        let frame = try #require(shown.backlinks)
        #expect(frame == CGRect(x: 132, y: bare.title.maxY + NotePageHeaderGeometry.backlinksGap, width: 728, height: 26))
        #expect(shown.height == bare.height + 26 + NotePageHeaderGeometry.backlinksGap)
    }

    @Test func backlinksFollowTheProperties() {
        var geometry = NotePageHeaderGeometry(width: 1000, column: CGRect(x: 140, y: 0, width: 720, height: 0), titleHeight: 55)
        geometry.backlinksHeight = 26
        geometry.propertiesHeight = 64
        let both = geometry.layout()
        #expect((both.backlinks?.minY ?? 0) > (both.properties?.maxY ?? .infinity))
    }
}

final class NoteBacklinkScannerTests {
    let folder = NoteFileTestSupport.makeFolder("backlink-scan")

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    var base: URL { folder.appendingPathComponent("Scan", isDirectory: true) }

    func roadmap() -> URL { NoteFileTestSupport.write("# Roadmap\n", to: base.appendingPathComponent("Roadmap.md")) }

    func outgoing() -> (key: String, links: [NoteOutgoingLink]) {
        let key = NoteFilePaths.key(for: roadmap())
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
        return (key, NoteBacklinkScanner.outgoing(in: page, folder: base))
    }

    @Test func wikiLinksLinkMarksMentionsAndPageLinksCountButCodeDoesNot() {
        let (key, links) = outgoing()
        let local = links.filter { $0.target == key }
        #expect(local.count == 4)
        #expect(Set(local.map(\.kind)) == [.mention, .link, .pageLink])
    }

    @Test func linksRememberTheSectionTheySitIn() {
        let (key, links) = outgoing()
        #expect(links.filter { $0.target == key }.allSatisfy { $0.anchor == "plans" })
    }

    @Test func pageLinksUseTheirLabelAndMentionsShowTheirSentence() {
        let (key, links) = outgoing()
        let local = links.filter { $0.target == key }
        #expect(local.contains { $0.kind == .pageLink && $0.snippet.text == "The big plan" })
        #expect(local.contains { $0.snippet.text == "Read the Roadmap first." && $0.snippet.highlight == 9..<16 })
    }

    @Test func webLinksAreSkipped() {
        #expect(!outgoing().links.contains { $0.target.hasSuffix("example.com") })
    }

    @Test(arguments: ["Roadmap", "./Roadmap.md#x"])
    func relativeTargetsFindTheMarkdownFile(raw: String) {
        let key = NoteFilePaths.key(for: roadmap())
        #expect(NoteBacklinkScanner.targetKey(raw, from: base) == key)
    }

    @Test func fileURLTargetsResolve() {
        let url = roadmap()
        #expect(NoteBacklinkScanner.targetKey(url.absoluteString, from: folder) == NoteFilePaths.key(for: url))
    }

    @Test(arguments: ["#heading", "mailto:a@b.c"])
    func sameNoteAnchorsAndOtherSchemesAreNotBacklinks(raw: String) {
        #expect(NoteBacklinkScanner.targetKey(raw, from: base) == nil)
    }
}

final class NoteBacklinkRewriterTests {
    let folder: URL
    let base: URL
    let new: URL
    let move: NoteBacklinkMove

    static let source = """
    ---
    icon: 🍎
    ---
    Read the [[Roadmap]] and [[Roadmap|the map]] first.

    A [plain link](Roadmap.md#goals) and a mention [Roadmap](Roadmap.md), plus _style_ kept.

    [Roadmap](Roadmap.md)

    `[code](Roadmap.md)` and [other](Other.md).

    """

    init() {
        folder = NoteFileTestSupport.makeFolder("backlink-rewrite")
        base = folder.appendingPathComponent("Rewrite", isDirectory: true)
        let old = base.appendingPathComponent("Roadmap.md")
        new = base.appendingPathComponent("Big Plan.md")
        NoteFileTestSupport.write("x\n", to: new)
        move = NoteBacklinkMove(fromKey: NoteFilePaths.key(for: old), from: old, to: new)
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    func rewritten() throws -> String {
        try #require(NoteBacklinkRewriter.rewritten(Self.source, resolvingFrom: base, writingFrom: base, move: move))
    }

    @Test(arguments: [
        "[[Big Plan]]", "[[Big Plan|the map]]", "[plain link](Big%20Plan.md#goals)", "[Big Plan](Big%20Plan.md), plus _style_ kept.",
        "\n[Big Plan](Big%20Plan.md)\n", "`[code](Roadmap.md)`", "[other](Other.md)",
    ])
    func linksToTheMovedNoteFollowWhileEverythingElseStays(expected: String) throws {
        #expect(try rewritten().contains(expected))
    }

    @Test func frontMatterStaysByteForByte() throws {
        #expect(try rewritten().hasPrefix("---\nicon: 🍎\n---\n"))
    }

    @Test func notesWithoutLinksAreNotTouched() {
        #expect(NoteBacklinkRewriter.rewritten("No links here.\n", resolvingFrom: base, writingFrom: base, move: move) == nil)
    }

    @Test func lineEndingsSurvive() {
        #expect(NoteBacklinkRewriter.rewritten("See [[Roadmap]].\r\nNext line\r\n", resolvingFrom: base, writingFrom: base, move: move)
                == "See [[Big Plan]].\r\nNext line\r\n")
    }

    @Test func mentionAtomsTakeTheNewTargetAndTitle() {
        var text = NoteText.atom(.page(target: "Roadmap.md", title: "Roadmap"))
        #expect(NoteBacklinkRewriter.rewrite(&text, resolvingFrom: base, writingFrom: base, move: move))
        #expect(text.marks(at: 0).atom == .page(target: "Big%20Plan.md", title: "Big Plan"))
    }

    @Test func relativeLinksStayRelativeToTheirNote() {
        let sub = base.appendingPathComponent("Sub", isDirectory: true)
        #expect(NoteBacklinkRewriter.replacement(for: "../Roadmap.md", writingFrom: sub, to: new, wiki: false) == "../Big%20Plan.md")
    }
}

@MainActor final class NoteBacklinkIndexTests {
    let clock = NoteManualClock()
    let folder: URL
    lazy var files = NoteFileTestSupport.files(clock: clock)
    let root: URL
    let target: URL
    let alpha: URL
    let beta: URL

    init() {
        folder = NoteFileTestSupport.makeFolder("backlinks")
        root = folder.appendingPathComponent("Index", isDirectory: true)
        target = NoteFileTestSupport.write("# Target\nSelf [[Target]]\n", to: root.appendingPathComponent("Target.md"))
        alpha = NoteFileTestSupport.write("See [[Target]] and [Target](Target.md).\n", to: root.appendingPathComponent("Alpha.md"))
        beta = NoteFileTestSupport.write("---\nicon: 🐝\n---\n## Notes\n\nAbout [the target](../Target.md).\n",
                                         to: root.appendingPathComponent("Deep/Beta.md"))
        NoteFileTestSupport.write("Nothing to see.\n", to: root.appendingPathComponent("Gamma.md"))
        NoteFileTestSupport.write("[me](Target.md)\n", to: root.appendingPathComponent("Plain.txt"))
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    var index: NoteBacklinkIndex { files.backlinks }
    var library: NoteLibrary { files.library(folder: root) }

    func settle() {
        for _ in 0..<20 { clock.advance(0.5) }
    }

    func indexed() {
        index.include(library)
        settle()
    }

    func titles(_ note: URL) -> [String] { index.backlinks(to: note).map(\.title) }

    func expectSteady(_ note: URL, _ expected: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        var seen: [[String]] = []
        for _ in 0..<80 {
            clock.advance(0.1)
            seen.append(titles(note))
        }
        #expect(seen.allSatisfy { $0 == expected }, sourceLocation: sourceLocation)
        #expect(index.isSettled, sourceLocation: sourceLocation)
    }

    func finderMove(_ from: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: from, to: destination)
        library.refresh()
        clock.advance(0.3)
    }

    @Test func sourcesAreListedByTitleWithoutTheNoteItselfOrPlainText() {
        indexed()
        #expect(titles(target) == ["Alpha", "Beta"])
    }

    @Test func severalLinksFromOneNoteCountOnce() {
        indexed()
        #expect(index.backlinks(to: target).first?.links == 2)
    }

    @Test func sourcesCarryTheirIconAndOpenAtTheLinkingSection() {
        indexed()
        let beta = index.backlinks(to: target).last
        #expect(beta?.icon == "🐝")
        #expect(beta?.anchor == "notes")
        #expect(beta?.destination.fragment == "notes")
    }

    @Test func theIndexAnnouncesChanges() {
        var heard = 0
        let watch = index.changes.sink { heard += 1 }
        defer { watch.cancel() }
        indexed()
        #expect(heard > 0)
    }

    @Test func eachFileEnvironmentKeepsItsOwnIndex() {
        indexed()
        #expect(NoteFileTestSupport.files(clock: clock).backlinks !== index)
    }

    @Test func removingALinkUpdatesTheList() {
        indexed()
        NoteFileTestSupport.write("Gone.\n", to: alpha)
        files.filesRewritten([alpha])
        settle()
        #expect(titles(target) == ["Beta"])
    }

    @Test func newLinksShowUp() {
        NoteFileTestSupport.write("Gone.\n", to: alpha)
        indexed()
        NoteFileTestSupport.write("Back to [[Target]].\n", to: alpha)
        files.filesRewritten([alpha])
        settle()
        #expect(titles(target) == ["Alpha", "Beta"])
    }

    @Test func backlinksFollowARenamedNoteRightAwayAndStaySteady() throws {
        indexed()
        let renamed = try files.rename(target, to: "Destination")
        #expect(titles(renamed) == ["Alpha", "Beta"])
        expectSteady(renamed, ["Alpha", "Beta"])
        #expect(index.backlinks(to: target) == [])
    }

    @Test func linksInOtherNotesFollowARename() throws {
        indexed()
        let renamed = try files.rename(target, to: "Destination")
        expectSteady(renamed, ["Alpha", "Beta"])
        #expect(NoteFileTestSupport.read(alpha).contains("[[Destination]]"))
        #expect(NoteFileTestSupport.read(beta).contains("[the target](../Destination.md)"))
    }

    @Test func aNotesLinkToItselfFollowsItsNewName() throws {
        indexed()
        let renamed = try files.rename(target, to: "Destination")
        expectSteady(renamed, ["Alpha", "Beta"])
        #expect(NoteFileTestSupport.read(renamed).contains("[[Destination]]"))
    }

    @Test func aFinderMoveOfAClosedNoteIsRecognisedByFileIdentity() throws {
        indexed()
        let moved = root.appendingPathComponent("Moved/Final.md")
        try finderMove(target, to: moved)
        #expect(titles(moved) == ["Alpha", "Beta"])
        #expect(index.backlinks(to: target) == [])
        expectSteady(moved, ["Alpha", "Beta"])
    }

    @Test func linksInClosedNotesFollowAFinderMove() throws {
        indexed()
        let moved = root.appendingPathComponent("Moved/Final.md")
        try finderMove(target, to: moved)
        expectSteady(moved, ["Alpha", "Beta"])
        #expect(NoteFileTestSupport.read(alpha).contains("[[Moved/Final]]"))
        #expect(NoteFileTestSupport.read(beta).contains("[the target](../Moved/Final.md)"))
        #expect(NoteFileTestSupport.read(moved).contains("[[Final]]"))
    }

    @Test func aRenamedSourceKeepsItsLinksAndTakesItsNewNameAtOnce() throws {
        indexed()
        try finderMove(alpha, to: root.appendingPathComponent("Alpha Two.md"))
        #expect(titles(target) == ["Alpha Two", "Beta"])
        expectSteady(target, ["Alpha Two", "Beta"])
    }

    @Test func aDeletedNoteAndANewOneAreNotMistakenForAMove() throws {
        indexed()
        NoteFileTestSupport.write("Copy of [[Target]].\n", to: root.appendingPathComponent("Copy.md"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Gamma.md"))
        library.refresh()
        settle()
        #expect(titles(target) == ["Alpha", "Beta", "Copy"])
        #expect(NoteFileTestSupport.read(alpha) == "See [[Target]] and [Target](Target.md).\n")
    }
}
